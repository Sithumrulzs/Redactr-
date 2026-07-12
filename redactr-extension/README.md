# Redactr extension

## Load it (Tier-1 only, no build needed)

1. `chrome://extensions` → enable **Developer mode** → **Load unpacked** → select this folder.
2. Reload the extension after any change to `manifest.json`, `background.js`, `content/scanner.js`,
   or `lib/detector.js`.

Tier-1 (regex + Luhn detection) works immediately with no build step — it's plain scripts loaded
straight from `manifest.json`.

## Tier-2 (on-device NER) — requires a one-time build

Tier-2 adds optional detection of unstructured PII (names, addresses, and manager-defined custom
entity types) using GLiNER zero-shot NER running fully in-browser via ONNX Runtime Web. It's
isolated behind the same `{type, match, start, end, severity}` finding shape Tier-1 uses (see
`lib/detector.js` → `mergeTier2Findings`), so Tier-1 keeps working unmodified even if Tier-2 is
off or fails to load.

### Model licence record

| Model ID | Licence | Source |
|---|---|---|
| `onnx-community/gliner_multi-v2.1` | Apache-2.0 | https://huggingface.co/onnx-community/gliner_multi-v2.1 |

The quantized ONNX checkpoint is fetched at runtime on first enable and cached by the browser
(no model files are committed to this repo). Redactr is commercial software; Apache-2.0 permits
commercial use with attribution — this table is that attribution record.

**Fallback**: if GLiNER fails to initialise, the extension falls back to `Xenova/bert-base-NER`
(the previous Tier-2 engine). If both fail, `{entities:[]}` is returned and Tier-1 is unaffected.

### Build

It needs Node.js because both `gliner` and `@huggingface/transformers` are npm packages with WASM
runtimes that can't be loaded as plain `<script>` tags.

```bash
cd redactr-extension
npm install
npm run build      # bundles offscreen/offscreen.src.js -> offscreen/offscreen.bundle.js
```

Then reload the unpacked extension in Chrome. In the popup, flip on **"AI detection (names,
addresses & custom types)"** — this triggers a one-time model download (a few MB, needs internet)
cached by the browser; after that it works fully offline. The status line shows
`Off / Downloading… / Ready / Failed to load`.

### How it fits together

```
content/scanner.js  --(chrome.runtime.sendMessage)-->  background.js  --(creates + messages)-->  offscreen/offscreen.html
   (Tier-1, sync)              bridge only              (offscreen.bundle.js: gliner + BERT fallback)
```

- MV3 forbids running remotely-loaded/WASM-heavy code directly in a content script's page
  context, so the NER pipeline lives in an **offscreen document** (`chrome.offscreen`), not the
  content script or the service worker.
- `background.js` lazily creates the offscreen document on first use and relays
  `TIER2_SCAN` / `TIER2_WARMUP` messages to it (with an optional `labels` array for custom entity
  types), plus persists `tier2Status` to `chrome.storage.local` so the popup can show progress.
- `content/scanner.js` always runs Tier-1 synchronously first (the blocking gate). If Tier-2 is
  enabled, it either escalates an existing Tier-1 banner with extra findings, or — if Tier-1 found
  nothing — holds the send briefly for the NER pass before letting it through or blocking.
- Two WASM directories exist to avoid ABI conflicts: `offscreen/ort/` for `@huggingface/transformers`
  (ORT v1.22.0-dev, BERT fallback) and `offscreen/ort-gliner/` for `gliner`'s bundled ORT
  v1.19.2 (GLiNER primary). Both are populated by `npm run build` via `scripts/copy-ort-assets.js`.

### Re-bundling

Run `npm run build` again after editing `offscreen/offscreen.src.js`. `npm run watch` rebuilds on
save.
