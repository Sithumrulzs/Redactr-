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
});
