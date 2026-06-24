# Redactr extension

## Load it (Tier-1 only, no build needed)

1. `chrome://extensions` → enable **Developer mode** → **Load unpacked** → select this folder.
2. Reload the extension after any change to `manifest.json`, `background.js`, `content/scanner.js`,
   or `lib/detector.js`.

Tier-1 (regex + Luhn detection) works immediately with no build step — it's plain scripts loaded
straight from `manifest.json`.

## Tier-2 (on-device NER) — requires a one-time build

Tier-2 adds optional detection of unstructured PII (names/addresses) using a small BERT NER model
running fully in-browser via Transformers.js + ONNX Runtime Web. It's isolated behind the same
`{type, match, start, end, severity}` finding shape Tier-1 uses (see `lib/detector.js` →
`mergeTier2Findings`), so Tier-1 keeps working unmodified even if Tier-2 is off or fails to load.

It needs Node.js because `@huggingface/transformers` is an npm package with a WASM runtime that
can't be loaded as a plain `<script>` tag.

```bash
cd redactr-extension
npm install
npm run build      # bundles offscreen/offscreen.src.js -> offscreen/offscreen.bundle.js
```

Then reload the unpacked extension in Chrome. In the popup, flip on **"AI name/address
detection"** — this triggers a one-time model download (a few MB, needs internet) cached by the
browser; after that it works fully offline. The status line shows
`Off / Downloading… / Ready / Failed to load`.

### How it fits together

```
content/scanner.js  --(chrome.runtime.sendMessage)-->  background.js  --(creates + messages)-->  offscreen/offscreen.html
   (Tier-1, sync)              bridge only              (offscreen.bundle.js: Transformers.js pipeline)
```

- MV3 forbids running remotely-loaded/WASM-heavy code directly in a content script's page
  context, so the NER pipeline lives in an **offscreen document** (`chrome.offscreen`), not the
  content script or the service worker.
- `background.js` lazily creates the offscreen document on first use and relays
  `TIER2_SCAN` / `TIER2_WARMUP` messages to it, plus persists `tier2Status` to
  `chrome.storage.local` so the popup can show progress.
- `content/scanner.js` always runs Tier-1 synchronously first (the blocking gate). If Tier-2 is
  enabled, it either escalates an existing Tier-1 banner with extra findings, or — if Tier-1 found
  nothing — holds the send briefly for the NER pass before letting it through or blocking.

### Re-bundling

Run `npm run build` again after editing `offscreen/offscreen.src.js`. `npm run watch` rebuilds on
save.
