/**
 * Copies the ONNX Runtime Web WASM binaries out of node_modules so the
 * extension can self-host them (no jsDelivr CDN dependency for the runtime
 * itself — only the model weights come from the network, once, from
 * Hugging Face). Run automatically after `npm run build` (see package.json
 * "postbuild").
 */
const fs = require("fs");
const path = require("path");

const SRC_DIR = path.join(__dirname, "..", "node_modules", "onnxruntime-web", "dist");
const DEST_DIR = path.join(__dirname, "..", "offscreen", "ort");

const FILES = [
  "ort-wasm-simd-threaded.wasm",
  "ort-wasm-simd-threaded.mjs",
  "ort-wasm-simd-threaded.jsep.wasm",
  "ort-wasm-simd-threaded.jsep.mjs",
];

fs.mkdirSync(DEST_DIR, { recursive: true });

for (const file of FILES) {
  const src = path.join(SRC_DIR, file);
  if (!fs.existsSync(src)) {
    console.warn(`[copy-ort-assets] skipping missing file: ${file}`);
    continue;
  }
  fs.copyFileSync(src, path.join(DEST_DIR, file));
  console.log(`[copy-ort-assets] copied ${file}`);
}
