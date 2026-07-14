/**
 * Offscreen document — Enterprise image analysis only.
 *
 * On-device NER (GLiNER / BERT) has been removed to comply with Chrome
 * Web Store MV3 policy which treats runtime-fetched ONNX model weights as
 * remotely-hosted code. Server-side NER is planned for a future release.
 *
 * Message protocol:
 *   FILE_SCAN_IMAGE { target:"offscreen", type, dataUrl }
 *                   → { ok, blocked, hasText, confidence, edgeDensity, findings, riskScore }
 */

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

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.target !== "offscreen") return;

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
