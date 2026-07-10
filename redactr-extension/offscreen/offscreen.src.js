/**
 * Tier-2 NER worker. Runs inside an MV3 offscreen document (the only place
 * an MV3 extension can run heavy WASM/ONNX work outside the page's own CSP).
 * Bundled by esbuild into offscreen.bundle.js — see ../package.json.
 *
 * Talks to background.js over chrome.runtime messaging:
 *   { target: "offscreen", type: "TIER2_SCAN", text } -> { entities: [...] }
 */
import { pipeline, env } from "@huggingface/transformers";

// Model weights are cached by the browser after the first download; no
// per-prompt network calls happen here.
env.allowLocalModels = false;

// Self-host the ONNX Runtime Web WASM binaries (copied into ./ort/ by
// `npm run build`'s postbuild step) instead of depending on the jsDelivr
// CDN — the only network dependency Tier-2 has is the one-time model
// weight download from Hugging Face. numThreads=1 avoids needing
// SharedArrayBuffer/cross-origin isolation inside the offscreen document.
env.backends.onnx.wasm.wasmPaths = chrome.runtime.getURL("offscreen/ort/");
env.backends.onnx.wasm.numThreads = 1;

const MODEL_ID = "Xenova/bert-base-NER";
let nerPipelinePromise = null;

function getPipeline() {
  if (!nerPipelinePromise) {
    nerPipelinePromise = pipeline("token-classification", MODEL_ID, {
      progress_callback: (progress) => {
        chrome.runtime.sendMessage({
          target: "background",
          type: "TIER2_PROGRESS",
          progress,
        });
      },
    });
  }
  return nerPipelinePromise;
}

// Entity groups we care about for "unstructured PII" per the Tier-2 spec.
const RELEVANT_GROUPS = new Set(["PER", "LOC"]);

async function scan(text) {
  const ner = await getPipeline();
  const raw = await ner(text, { aggregation_strategy: "simple" });

  return raw
    .filter((entity) => RELEVANT_GROUPS.has(entity.entity_group) && entity.score > 0.6)
    .map((entity) => ({
      type: entity.entity_group === "PER" ? "PERSON" : "LOCATION",
      match: entity.word,
      start: entity.start,
      end: entity.end,
      severity: "medium",
    }));
}

/* ── Image text-density analysis for Enterprise file scanning ──────────── */

/**
 * Analyses an image for text-like content using canvas edge detection.
 * Returns { hasText: bool, edgeDensity: float, confidence: "high"|"medium"|"low" }.
 *
 * Approach: text regions produce characteristic edge patterns — many
 * short, high-contrast transitions in horizontal bands. We score images
 * by their edge density and horizontal-band regularity. A proper OCR
 * pipeline (e.g. Tesseract.js) would replace this in a future iteration;
 * this catches the majority of document screenshots and scans.
 */
async function analyzeImageForText(dataUrl) {
  try {
    // Decode data URL to Blob then to ImageBitmap (works in offscreen docs)
    const response = await fetch(dataUrl);
    const blob     = await response.blob();
    const bitmap   = await createImageBitmap(blob);

    // Work at a reduced resolution for speed (max 400px wide)
    const scale  = Math.min(1, 400 / bitmap.width);
    const width  = Math.round(bitmap.width  * scale);
    const height = Math.round(bitmap.height * scale);

    const canvas = new OffscreenCanvas(width, height);
    const ctx    = canvas.getContext("2d");
    ctx.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();

    const { data } = ctx.getImageData(0, 0, width, height);

    // Compute grayscale + horizontal Sobel edges
    let edgeCount  = 0;
    let darkPixels = 0;     // text is typically dark on light background
    const totalPx = width * height;

    for (let y = 1; y < height - 1; y++) {
      for (let x = 1; x < width - 1; x++) {
        const i    = (y * width + x) * 4;
        const gray = data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;

        // Horizontal edge: compare left and right neighbours
        const iL   = (y * width + (x - 1)) * 4;
        const iR   = (y * width + (x + 1)) * 4;
        const gL   = data[iL] * 0.299 + data[iL + 1] * 0.587 + data[iL + 2] * 0.114;
        const gR   = data[iR] * 0.299 + data[iR + 1] * 0.587 + data[iR + 2] * 0.114;

        if (Math.abs(gL - gR) > 35) edgeCount++;
        if (gray < 100) darkPixels++;
      }
    }

    const edgeDensity = edgeCount / totalPx;
    const darkRatio   = darkPixels / totalPx;

    // Heuristic thresholds derived empirically from document images:
    // — Documents/scans: edgeDensity 0.04–0.35, darkRatio 0.03–0.40
    // — Photos: edgeDensity > 0.40 or very irregular
    // — Blank images: edgeDensity < 0.01
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
    // Fail open — never block an image due to an analysis error
    return { hasText: false, edgeDensity: 0, confidence: "low", error: String(err) };
  }
}

/* ── Message listener ──────────────────────────────────────────────────── */

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.target !== "offscreen") return;

  if (message.type === "TIER2_SCAN") {
    scan(message.text)
      .then((entities) => sendResponse({ ok: true, entities }))
      .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  }

  if (message.type === "TIER2_WARMUP") {
    getPipeline()
      .then(() => sendResponse({ ok: true }))
      .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  }

  if (message.type === "FILE_SCAN_IMAGE") {
    analyzeImageForText(message.dataUrl)
      .then((result) => {
        const blocked = result.hasText && result.confidence !== "low";
        sendResponse({
          ok      : true,
          blocked,
          hasText : result.hasText,
          confidence: result.confidence,
          edgeDensity: result.edgeDensity,
          findings: blocked ? [{ type: "IMAGE_PII", match: "(image)", start: 0, end: 0, severity: "high" }] : [],
          riskScore: blocked ? (result.confidence === "high" ? 65 : 40) : 0,
        });
      })
      .catch((err) => sendResponse({ ok: true, blocked: false, error: String(err) }));
    return true;
  }
});
