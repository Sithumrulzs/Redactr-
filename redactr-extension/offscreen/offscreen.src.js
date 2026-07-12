/**
 * Tier-2 NER worker — offscreen document (Manifest V3).
 *
 * Primary engine : GLiNER zero-shot NER via the `gliner` npm package.
 *   Model  : onnx-community/gliner_multi-v2.1
 *   Licence: Apache-2.0 (commercial use permitted; see README.md).
 *   Weights are fetched from Hugging Face on first enable and cached
 *   by the browser — no per-prompt network calls after that.
 *
 * Fallback engine : Xenova/bert-base-NER (standard BERT NER).
 *   Engages automatically if GLiNER fails to load or throws during
 *   inference. If both engines fail, scan() returns {entities:[]} so
 *   Tier-1 blocking is completely unaffected — we never hold, throw
 *   into the scanner, or indefinitely delay a send because of a model
 *   error.
 *
 * Message protocol (unchanged from original BERT implementation):
 *   TIER2_SCAN    { target:"offscreen", type, text, labels? }
 *                 → { ok:bool, entities:[] }
 *   TIER2_WARMUP  { target:"offscreen", type }
 *                 → { ok:bool }
 *   FILE_SCAN_IMAGE { target:"offscreen", type, dataUrl }
 *                 → { ok, blocked, ... }
 *
 * The labels field carries ["person name","street address",...customEntities].
 * If omitted, DEFAULT_LABELS are used. The offscreen always adds DEFAULT_LABELS
 * as a safety net; the background sends the full list for explicitness.
 */
import { Gliner } from "gliner";
import { pipeline, env } from "@huggingface/transformers";

// ── Constants ─────────────────────────────────────────────────────────────────

// Model: onnx-community/gliner_multi-v2.1 (Apache-2.0, quantized int8)
// Recorded in README.md — do not change without updating the licence note there.
const GLINER_MODEL_ID  = "onnx-community/gliner_multi-v2.1";
const GLINER_MODEL_URL =
  "https://huggingface.co/onnx-community/gliner_multi-v2.1/resolve/main/onnx/model_quantized.onnx";
const BERT_MODEL_ID = "Xenova/bert-base-NER";

// GLiNER latency scales linearly with the number of labels evaluated per span.
// Cap at 15 so a large customEntities list doesn't make prompts noticeably slow.
const MAX_LABELS = 15;
const GLINER_CONFIDENCE_THRESHOLD = 0.5;

// Chunking: GLiNER's context window is ~384 tokens (~300 words). Texts longer
// than WORDS_PER_CHUNK are split with OVERLAP_WORDS overlap so entities near
// a chunk boundary are not silently dropped.
const WORDS_PER_CHUNK = 300;
const OVERLAP_WORDS   = 30;

// Default entity types always scanned when Tier-2 is active.
const DEFAULT_LABELS = ["person name", "street address"];

// ── Label → canonical finding type ───────────────────────────────────────────
//
// Mapping table — single source of truth is shared/detection-rules.md
// § "Tier 2 (GLiNER)":
//
//   GLiNER label      type          severity   weight
//   ──────────────    ───────────   ────────   ──────
//   "person name"     PERSON_NAME   medium     15
//   "street address"  ADDRESS       medium     15
//   any other         CUSTOM_<…>    high       25
//
// For manager-defined labels the type is CUSTOM_ followed by the label
// uppercased with every run of non-alphanumeric characters collapsed to
// a single underscore (leading/trailing underscores stripped).

function labelToFinding(label, spanText, start, end) {
  const lower = label.toLowerCase().trim();
  if (lower === "person name") {
    return { type: "PERSON_NAME", match: spanText, start, end, severity: "medium" };
  }
  if (lower === "street address") {
    return { type: "ADDRESS", match: spanText, start, end, severity: "medium" };
  }
  const safeName = label.toUpperCase()
    .replace(/[^A-Z0-9]+/g, "_")
    .replace(/^_+|_+$/, "");
  return { type: `CUSTOM_${safeName}`, match: spanText, start, end, severity: "high" };
}

// ── BERT fallback env setup (@huggingface/transformers, v3) ──────────────────
// Uses the top-level onnxruntime-web v1.22.0-dev WASM files (offscreen/ort/).
env.allowLocalModels = false;
env.backends.onnx.wasm.wasmPaths = chrome.runtime.getURL("offscreen/ort/");
env.backends.onnx.wasm.numThreads = 1;

// ── GLiNER engine ─────────────────────────────────────────────────────────────

let glinerInstance    = null;
let glinerLoadPromise = null;
let glinerFailed      = false; // latched true on any load/inference error

function initGliner() {
  if (glinerLoadPromise) return glinerLoadPromise;
  glinerLoadPromise = (async () => {
    const inst = new Gliner({
      tokenizerPath: GLINER_MODEL_ID,
      onnxSettings: {
        modelPath: GLINER_MODEL_URL,
        executionProvider: "wasm",
        // Use the ORT v1.19.2 WASM binaries bundled for gliner — separate from
        // the v1.22.0-dev files @huggingface/transformers uses so there is no
        // WASM ABI mismatch between the two engines.
        wasmPaths: chrome.runtime.getURL("offscreen/ort-gliner/"),
        multiThread: false, // SharedArrayBuffer unavailable in offscreen docs
        fetchBinary: false,
      },
      transformersSettings: {
        allowLocalModels: false,
        useBrowserCache: true, // tokenizer files are cached in the browser
      },
      maxWidth: 12,
      modelType: "span-level",
    });
    await inst.initialize();
    glinerInstance = inst;
    return inst;
  })().catch((err) => {
    console.warn("Redactr: GLiNER failed to load — BERT fallback engaged", err);
    glinerFailed = true;
    glinerLoadPromise = null;
    throw err;
  });
  return glinerLoadPromise;
}

// ── Chunking helpers ──────────────────────────────────────────────────────────

function wordBoundaries(text) {
  const bounds = [];
  const re = /\S+/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    bounds.push({ start: m.index, end: m.index + m[0].length });
  }
  return bounds;
}

/**
 * Split text into overlapping character-range chunks.
 * Returns [{ text, charOffset }] where charOffset maps chunk-local character
 * positions back to positions in the original string: origPos = local + charOffset.
 */
function chunkText(text, wordsPerChunk, overlapWords) {
  const words = wordBoundaries(text);
  if (words.length === 0) return [{ text, charOffset: 0 }];
  const chunks = [];
  const step = wordsPerChunk - overlapWords;
  for (let i = 0; i < words.length; i += step) {
    const endIdx   = Math.min(i + wordsPerChunk, words.length);
    const charStart = words[i].start;
    const charEnd   = words[endIdx - 1].end;
    chunks.push({ text: text.slice(charStart, charEnd), charOffset: charStart });
    if (endIdx >= words.length) break;
  }
  return chunks;
}

/**
 * When chunks overlap, the same entity may appear in both. Keep the
 * higher-confidence instance; discard the lower.
 */
function deduplicateByScore(findings) {
  const byScore = [...findings].sort((a, b) => b._score - a._score);
  const kept = [];
  for (const f of byScore) {
    if (!kept.some(k => k.start < f.end && f.start < k.end)) {
      kept.push(f);
    }
  }
  return kept
    .map(({ _score, ...rest }) => rest)
    .sort((a, b) => a.start - b.start);
}

// ── GLiNER scan ───────────────────────────────────────────────────────────────

async function scanGliner(text, labels) {
  const inst  = await initGliner();
  const words = wordBoundaries(text);

  const runChunk = async (chunkText, charOffset) => {
    const results = await inst.inference({
      texts: [chunkText],
      entities: labels,
      flatNer: true,
      threshold: GLINER_CONFIDENCE_THRESHOLD,
    });
    return (results[0] || []).map(e => ({
      ...labelToFinding(e.label, e.spanText, e.start + charOffset, e.end + charOffset),
      _score: e.score,
    }));
  };

  if (words.length <= WORDS_PER_CHUNK) {
    const findings = await runChunk(text, 0);
    return deduplicateByScore(findings);
  }

  // Long text: chunk with overlap and merge
  const chunks   = chunkText(text, WORDS_PER_CHUNK, OVERLAP_WORDS);
  const allRaw   = [];
  for (const chunk of chunks) {
    allRaw.push(...(await runChunk(chunk.text, chunk.charOffset)));
  }
  return deduplicateByScore(allRaw);
}

// ── BERT fallback engine (original implementation, preserved intact) ───────────

const BERT_RELEVANT_GROUPS = new Set(["PER", "LOC"]);
let bertPipelinePromise = null;

function getBertPipeline() {
  if (!bertPipelinePromise) {
    bertPipelinePromise = pipeline("token-classification", BERT_MODEL_ID, {
      progress_callback: (progress) => {
        chrome.runtime.sendMessage({ target: "background", type: "TIER2_PROGRESS", progress });
      },
    });
  }
  return bertPipelinePromise;
}

async function scanBert(text) {
  const ner = await getBertPipeline();
  const raw = await ner(text, { aggregation_strategy: "simple" });
  return raw
    .filter(e => BERT_RELEVANT_GROUPS.has(e.entity_group) && e.score > 0.6)
    .map(e => ({
      type: e.entity_group === "PER" ? "PERSON" : "LOCATION",
      match: e.word,
      start: e.start,
      end: e.end,
      severity: "medium",
    }));
}

// ── Unified scan: GLiNER primary, BERT fallback ───────────────────────────────

async function scan(text, labels) {
  if (!glinerFailed) {
    try {
      return await scanGliner(text, labels);
    } catch (err) {
      console.warn("Redactr: GLiNER inference error — activating BERT fallback", err);
      glinerFailed = true;
    }
  }
  try {
    return await scanBert(text);
  } catch (err) {
    console.warn("Redactr: BERT fallback also failed — returning empty findings", err);
    return [];
  }
}

async function warmup() {
  if (!glinerFailed) {
    try { await initGliner(); return; } catch (_) { /* glinerFailed now latched */ }
  }
  await getBertPipeline();
}

// ── Image text-density analysis — Enterprise file scanning (unchanged) ─────────

async function analyzeImageForText(dataUrl) {
  try {
    const response = await fetch(dataUrl);
    const blob     = await response.blob();
    const bitmap   = await createImageBitmap(blob);

    const scale  = Math.min(1, 400 / bitmap.width);
    const width  = Math.round(bitmap.width  * scale);
    const height = Math.round(bitmap.height * scale);

    const canvas = new OffscreenCanvas(width, height);
    const ctx    = canvas.getContext("2d");
    ctx.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();

    const { data } = ctx.getImageData(0, 0, width, height);
    let edgeCount = 0, darkPixels = 0;
    const totalPx = width * height;

    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        const i  = (y * width + x) * 4;
        const iL = (y * width + (x - 1)) * 4;
        const iR = (y * width + (x + 1)) * 4;
        const gL = data[iL] * 0.299 + data[iL + 1] * 0.587 + data[iL + 2] * 0.114;
        const gR = data[iR] * 0.299 + data[iR + 1] * 0.587 + data[iR + 2] * 0.114;
        if (Math.abs(gL - gR) > 35) edgeCount++;
        const gray = data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;
        if (gray < 100) darkPixels++;
      }
    }

    const edgeDensity = edgeCount / totalPx;
    const darkRatio   = darkPixels / totalPx;
    const looksLikeDocument =
      edgeDensity > 0.03 && edgeDensity < 0.42 &&
      darkRatio   > 0.01 && darkRatio   < 0.65;
    const confidence = edgeDensity > 0.08 && edgeDensity < 0.35
      ? "high"
      : looksLikeDocument ? "medium" : "low";

    return {
      hasText    : looksLikeDocument,
      edgeDensity: Math.round(edgeDensity * 1000) / 1000,
      confidence,
    };
  } catch (err) {
    return { hasText: false, edgeDensity: 0, confidence: "low", error: String(err) };
  }
}

// ── Message listener ──────────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.target !== "offscreen") return;

  if (message.type === "TIER2_SCAN") {
    // Merge incoming labels with DEFAULT_LABELS (deduped), then cap at MAX_LABELS.
    const incoming = Array.isArray(message.labels) ? message.labels : [];
    const merged   = [...new Set([...DEFAULT_LABELS, ...incoming])];
    if (merged.length > MAX_LABELS) {
      console.warn(
        `Redactr: ${merged.length} entity labels exceed the ${MAX_LABELS}-label cap — using first ${MAX_LABELS}`
      );
    }
    const effectiveLabels = merged.slice(0, MAX_LABELS);

    scan(message.text, effectiveLabels)
      .then(entities => sendResponse({ ok: true, entities }))
      .catch(err     => sendResponse({ ok: false, error: String(err) }));
    return true;
  }

  if (message.type === "TIER2_WARMUP") {
    warmup()
      .then(() => sendResponse({ ok: true }))
      .catch(err => sendResponse({ ok: false, error: String(err) }));
    return true;
  }

  if (message.type === "FILE_SCAN_IMAGE") {
    analyzeImageForText(message.dataUrl)
      .then(result => {
        const blocked = result.hasText && result.confidence !== "low";
        sendResponse({
          ok        : true,
          blocked,
          hasText   : result.hasText,
          confidence: result.confidence,
          edgeDensity: result.edgeDensity,
          findings  : blocked
            ? [{ type: "IMAGE_PII", match: "(image)", start: 0, end: 0, severity: "high" }]
            : [],
          riskScore : blocked ? (result.confidence === "high" ? 65 : 40) : 0,
        });
      })
      .catch(err => sendResponse({ ok: true, blocked: false, error: String(err) }));
    return true;
  }
});
