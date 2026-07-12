/**
 * Copies the ONNX Runtime Web WASM binaries out of node_modules so the
 * extension can self-host them (no jsDelivr CDN dependency for the runtime
 * itself — only model weights come from the network, once, from Hugging Face).
 * Run automatically after `npm run build` (see package.json "postbuild").
 *
 * Two separate ORT versions are copied to avoid WASM ABI mismatches:
 *
 *   offscreen/ort/         — ORT v1.22.0-dev used by @huggingface/transformers
 *                            (BERT fallback engine)
 *   offscreen/ort-gliner/  — ORT v1.19.2 used by the `gliner` npm package
 *                            (GLiNER primary engine)
 *
 * Each engine's wasmPaths is set to its own directory at runtime.
 */
const fs   = require("fs");
const path = require("path");

const EXT_DIR = path.join(__dirname, "..");

const TARGETS = [
  {
    srcDir:  path.join(EXT_DIR, "node_modules", "onnxruntime-web", "dist"),
    destDir: path.join(EXT_DIR, "offscreen", "ort"),
    label:   "ORT v1.22.0-dev (@huggingface/transformers / BERT fallback)",
  },
  {
    srcDir:  path.join(EXT_DIR, "node_modules", "gliner", "node_modules", "onnxruntime-web", "dist"),
    destDir: path.join(EXT_DIR, "offscreen", "ort-gliner"),
    label:   "ORT v1.19.2 (gliner / GLiNER primary)",
  },
];

const FILES = [
  "ort-wasm-simd-threaded.wasm",
  "ort-wasm-simd-threaded.mjs",
  "ort-wasm-simd-threaded.jsep.wasm",
  "ort-wasm-simd-threaded.jsep.mjs",
];

for (const { srcDir, destDir, label } of TARGETS) {
  fs.mkdirSync(destDir, { recursive: true });
  console.log(`[copy-ort-assets] → ${label}`);
  for (const file of FILES) {
    const src = path.join(srcDir, file);
    if (!fs.existsSync(src)) {
      console.warn(`[copy-ort-assets]   skipping missing file: ${file}`);
      continue;
    }
    fs.copyFileSync(src, path.join(destDir, file));
    console.log(`[copy-ort-assets]   copied ${file}`);
  }
}
