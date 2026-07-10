/**
 * content/file-interceptor.js — Enterprise File & Attachment Scanner
 *
 * Intercepts file inputs and drag-drop uploads across ALL websites.
 * Extracts text from DOCX, ODT, TXT, CSV, PDF, and similar formats,
 * runs it through RedactrDetector (same engine as the AI prompt scanner),
 * and blocks the upload if sensitive data is found.
 *
 * Images are sent to the background for canvas-based text-density analysis.
 * Filename patterns (e.g. "passport.jpg", "ssn_scan.pdf") are flagged
 * immediately without reading content.
 *
 * Gate: only fires when plan === "enterprise" AND fileInterceptEnabled is
 * true. Silent for all other plans — no overhead at all.
 *
 * Requires lib/detector.js to be loaded first (see manifest.json).
 */
(function () {
  "use strict";

  /* ── State ────────────────────────────────────────────────────────────── */
  let isEnterprise = false;
  let featureEnabled = false;
  let customKeywords = [];

  chrome.storage.local.get(
    { plan: null, fileInterceptEnabled: false, customKeywords: [] },
    (s) => {
      isEnterprise   = s.plan === "enterprise";
      featureEnabled = s.fileInterceptEnabled;
      customKeywords = s.customKeywords || [];
    }
  );

  chrome.storage.onChanged.addListener((changes) => {
    if (changes.plan)                isEnterprise   = changes.plan.newValue === "enterprise";
    if (changes.fileInterceptEnabled) featureEnabled = changes.fileInterceptEnabled.newValue;
    if (changes.customKeywords)       customKeywords = changes.customKeywords.newValue || [];
  });

  function isActive() { return isEnterprise && featureEnabled; }

  /* ── File-type helpers ────────────────────────────────────────────────── */
  const TEXT_EXT   = new Set(["txt","md","csv","json","xml","html","htm","log","yaml","yml","ini","cfg","env","py","js","ts","sql"]);
  const DOCX_EXT   = new Set(["docx","odt"]);
  const IMAGE_EXT  = new Set(["png","jpg","jpeg","gif","bmp","webp","tiff","tif","heic","heif"]);

  function ext(filename) {
    const parts = filename.split(".");
    return parts.length > 1 ? parts.pop().toLowerCase() : "";
  }

  /* ── Sensitive filename heuristics ────────────────────────────────────── */
  const SENSITIVE_FILENAME_RX = [
    /passport/i, /\bssn\b/i, /social.?security/i, /driver.?licen/i,
    /\bid[-_]card/i, /\bnational[-_]?id/i, /credit[-_]?card/i,
    /\bpii\b/i, /tax[-_]?return/i, /\bw[-_]?[29]\b/i,
    /birth[-_]?cert/i, /medical[-_]?record/i, /health[-_]?record/i,
    /insurance[-_]?card/i, /bank[-_]?state?ment/i, /payslip/i,
    /salary/i, /\bein\b/i, /employees?[-_]?data/i,
  ];

  function isSensitiveFilename(name) {
    return SENSITIVE_FILENAME_RX.some((rx) => rx.test(name));
  }

  /* ── DOCX/ODT parser ─────────────────────────────────────────────────── */
  async function decompressDeflateRaw(data) {
    const ds     = new DecompressionStream("deflate-raw");
    const writer = ds.writable.getWriter();
    writer.write(data);
    writer.close();
    return new Uint8Array(await new Response(ds.readable).arrayBuffer());
  }

  async function extractDocxText(buffer) {
    const bytes = new Uint8Array(buffer);
    const view  = new DataView(buffer);
    const dec   = new TextDecoder("utf-8", { fatal: false });
    let offset  = 0;

    while (offset < bytes.length - 30) {
      // ZIP local file header: signature 0x04034b50 (little-endian)
      if (view.getUint32(offset, true) !== 0x04034b50) { offset++; continue; }

      const flags          = view.getUint16(offset + 6,  true);
      const compression    = view.getUint16(offset + 8,  true);
      const compressedSize = view.getUint32(offset + 18, true);
      const filenameLen    = view.getUint16(offset + 26, true);
      const extraLen       = view.getUint16(offset + 28, true);
      const filename       = dec.decode(bytes.slice(offset + 30, offset + 30 + filenameLen));
      const dataStart      = offset + 30 + filenameLen + extraLen;

      if (filename === "word/document.xml" || filename === "content.xml") {
        const compressed = bytes.slice(dataStart, dataStart + compressedSize);
        let xmlBytes;
        try {
          if (compression === 0)      xmlBytes = compressed;
          else if (compression === 8) xmlBytes = await decompressDeflateRaw(compressed);
          else break;
        } catch { break; }
        return xmlToText(dec.decode(xmlBytes));
      }

      // Bit 3 set: data descriptor follows compressed data — sizes may be 0
      if ((flags & 0x08) && compressedSize === 0) {
        // Scan forward to the next local file header or central directory
        offset = dataStart;
        while (offset < bytes.length - 4) {
          const sig = view.getUint32(offset, true);
          if (sig === 0x04034b50 || sig === 0x02014b50) break;
          offset++;
        }
      } else {
        offset = dataStart + compressedSize;
      }
    }
    return "";
  }

  function xmlToText(xml) {
    return xml
      .replace(/<w:p[\s/>]/g, "\n")           // Word paragraph breaks
      .replace(/<text:p[\s/>]/g, "\n")         // ODT paragraph breaks
      .replace(/<w:br[^>]*>/g, "\n")
      .replace(/<[^>]+>/g, "")                 // Strip all tags
      .replace(/&amp;/g,  "&")
      .replace(/&lt;/g,   "<")
      .replace(/&gt;/g,   ">")
      .replace(/&apos;/g, "'")
      .replace(/&quot;/g, '"')
      .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(+n))
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  }

  /* ── PDF text extractor ──────────────────────────────────────────────── */
  function extractPdfText(buffer) {
    // Attempt to pull readable text from BT…ET blocks (standard PDF content streams).
    // Not a full PDF parser — catches plain-text and most Office-generated PDFs.
    const raw    = new TextDecoder("latin1").decode(buffer);
    const chunks = [];
    const btEtRx = /BT([\s\S]*?)ET/g;
    const tjRx   = /\(([^)\\]*(?:\\.[^)\\]*)*)\)\s*(?:Tj|'|")/g;
    const tjArrRx = /\[((?:[^[\]]*|\[.*?\])*)\]\s*TJ/g;
    let block;
    while ((block = btEtRx.exec(raw)) !== null) {
      const content = block[1];
      let m;
      while ((m = tjRx.exec(content)) !== null) {
        chunks.push(
          m[1].replace(/\\n/g,"\n").replace(/\\r/g,"").replace(/\\t/g," ")
              .replace(/\\([0-7]{1,3})/g, (_, o) => String.fromCharCode(parseInt(o, 8)))
        );
      }
      tjRx.lastIndex = 0;
      while ((m = tjArrRx.exec(content)) !== null) {
        const arr = m[1].replace(/\(([^)]*)\)/g, (_, s) => s + " ").replace(/-?\d+\.?\d*/g, "");
        chunks.push(arr.trim());
      }
      tjArrRx.lastIndex = 0;
    }
    return chunks.join(" ").trim();
  }

  /* ── File reader helpers ─────────────────────────────────────────────── */
  function readAsText(file) {
    return new Promise((resolve) => {
      const r = new FileReader();
      r.onload  = () => resolve(r.result || "");
      r.onerror = () => resolve("");
      r.readAsText(file);
    });
  }

  function readAsArrayBuffer(file) {
    return new Promise((resolve) => {
      const r = new FileReader();
      r.onload  = () => resolve(r.result);
      r.onerror = () => resolve(null);
      r.readAsArrayBuffer(file);
    });
  }

  function readAsDataURL(file) {
    return new Promise((resolve) => {
      const r = new FileReader();
      r.onload  = () => resolve(r.result);
      r.onerror = () => resolve(null);
      r.readAsDataURL(file);
    });
  }

  async function extractText(file) {
    const e = ext(file.name);
    if (TEXT_EXT.has(e))  return readAsText(file);
    if (DOCX_EXT.has(e)) {
      const buf = await readAsArrayBuffer(file);
      return buf ? extractDocxText(buf) : "";
    }
    if (e === "pdf") {
      const buf = await readAsArrayBuffer(file);
      return buf ? extractPdfText(buf) : "";
    }
    if (e === "rtf") {
      // RTF: strip control words and extract readable text
      const raw = await readAsText(file);
      return raw.replace(/\{[^{}]*\}|\\[a-z]+\d*[ ]?|[{}\\]/g, " ").replace(/\s+/g," ").trim();
    }
    return null; // unknown type — skip text extraction
  }

  /* ── Blocking overlay UI ─────────────────────────────────────────────── */
  const HTML_ESCAPE = { "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;" };
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => HTML_ESCAPE[c]);

  function renderFindingPills(findings) {
    return [...new Set(findings.map((f) => f.type))].map((t) =>
      `<span style="background:rgba(239,84,102,.13);color:#ef5466;border:1px solid rgba(239,84,102,.28);
        border-radius:20px;font-size:11px;font-weight:700;padding:3px 10px;white-space:nowrap;">
        ${esc(t.replace(/_/g," "))}
      </span>`
    ).join("");
  }

  function showBlockOverlay({ filename, findings, riskScore, onRemove, onSendAnyway }) {
    document.getElementById("rdx-file-overlay")?.remove();

    const isSensitiveName = findings.length === 1 && findings[0].type === "SENSITIVE_FILENAME";
    const score = riskScore ?? Math.min(100, findings.reduce((s, f) =>
      s + ({ AWS_KEY:40, API_KEY:40, CREDIT_CARD:35, PHONE:15, EMAIL:5, IP_ADDRESS:10,
              PERSON:20, LOCATION:20, CUSTOM_KEYWORD:30, IMAGE_PII:50, SENSITIVE_FILENAME:25 }[f.type] || 0), 0));

    const overlay = document.createElement("div");
    overlay.id = "rdx-file-overlay";
    overlay.style.cssText = `
      position:fixed;inset:0;z-index:2147483647;
      background:rgba(8,12,18,.85);backdrop-filter:blur(5px);
      display:flex;align-items:center;justify-content:center;
      font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;
      animation:rdxFadeIn .18s ease both;
    `;

    overlay.innerHTML = `
      <style>
        @keyframes rdxFadeIn{from{opacity:0;transform:scale(.97)}to{opacity:1;transform:scale(1)}}
        #rdx-file-overlay button{cursor:pointer;font-family:inherit}
      </style>
      <div style="background:#13181f;border:1.5px solid #ef5466;border-radius:16px;
        padding:28px;max-width:420px;width:calc(100% - 48px);color:#fff;
        box-shadow:0 24px 64px rgba(0,0,0,.7);">

        <div style="display:flex;align-items:center;gap:12px;margin-bottom:18px;">
          <div style="width:44px;height:44px;border-radius:50%;flex-shrink:0;
            background:rgba(239,84,102,.14);display:flex;align-items:center;justify-content:center;">
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none"
              stroke="#ef5466" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
              <line x1="12" y1="9" x2="12" y2="13"/><circle cx="12" cy="17" r=".5" fill="#ef5466"/>
            </svg>
          </div>
          <div>
            <div style="font-size:15px;font-weight:700;color:#ef5466;letter-spacing:-.01em;">
              Redactr blocked this file
            </div>
            <div style="font-size:11px;color:#8c95a6;margin-top:2px;">Enterprise file scanning • Risk ${score}/100</div>
          </div>
        </div>

        <div style="background:rgba(239,84,102,.08);border:1px solid rgba(239,84,102,.22);
          border-radius:8px;padding:11px 14px;margin-bottom:16px;">
          <div style="font-size:11px;color:#8c95a6;margin-bottom:3px;">Detected in</div>
          <div style="font-size:13px;font-weight:600;word-break:break-all;line-height:1.3;">
            ${esc(filename)}
          </div>
        </div>

        <div style="margin-bottom:20px;">
          <div style="font-size:11px;color:#8c95a6;margin-bottom:7px;">Sensitive data detected</div>
          <div style="display:flex;flex-wrap:wrap;gap:6px;">
            ${isSensitiveName
              ? `<span style="background:rgba(239,84,102,.13);color:#ef5466;border:1px solid rgba(239,84,102,.28);
                   border-radius:20px;font-size:11px;font-weight:700;padding:3px 10px;">
                   SENSITIVE FILENAME</span>`
              : renderFindingPills(findings)}
          </div>
          ${!isSensitiveName ? `<div style="font-size:11px;color:#8c95a6;margin-top:8px;">
            ${findings.length} finding${findings.length !== 1 ? "s" : ""} detected
          </div>` : ""}
        </div>

        <div style="display:flex;gap:10px;align-items:stretch;">
          <button id="rdx-file-remove" style="flex:1;background:#14c8a6;color:#060e0b;
            font-weight:700;border:none;border-radius:8px;padding:10px;font-size:13px;">
            Remove file
          </button>
          <button id="rdx-file-allow" style="background:transparent;color:#8c95a6;
            border:1px solid #2e3744;border-radius:8px;padding:10px 14px;font-size:12px;">
            Send anyway
          </button>
        </div>

        <p style="font-size:10px;color:#8c95a6;margin:10px 0 0;text-align:center;line-height:1.4;">
          This file appears to contain sensitive company data.<br>
          Sending it may violate your organisation's data policy.
        </p>
      </div>
    `;

    document.documentElement.appendChild(overlay);

    overlay.querySelector("#rdx-file-remove").addEventListener("click", () => {
      overlay.remove();
      onRemove();
    });

    overlay.querySelector("#rdx-file-allow").addEventListener("click", () => {
      if (confirm("Send anyway? This file contains sensitive data and may violate your company policy.")) {
        overlay.remove();
        if (onSendAnyway) onSendAnyway();
      }
    });

    // Close on backdrop click
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) { overlay.remove(); onRemove(); }
    });
  }

  /* ── Core scanner ────────────────────────────────────────────────────── */
  const filesBlocked = new WeakSet();   // track file input elements that were blocked
  let formBlockedUntilClear = false;    // set when a non-input (drag-drop) file was blocked

  async function scanAndMaybeBlock({ file, inputEl, onBlock }) {
    const e = ext(file.name);

    /* 1 — Sensitive filename fast-path */
    if (isSensitiveFilename(file.name)) {
      onBlock({
        filename: file.name,
        findings: [{ type: "SENSITIVE_FILENAME" }],
        riskScore: 25,
      });
      return true;
    }

    /* 2 — Image: route through background → offscreen canvas analysis */
    if (IMAGE_EXT.has(e)) {
      const dataUrl = await readAsDataURL(file);
      if (!dataUrl) return false;

      return new Promise((resolve) => {
        chrome.runtime.sendMessage(
          { type: "FILE_SCAN_IMAGE", dataUrl, filename: file.name, site: location.hostname },
          (response) => {
            if (response?.blocked) {
              onBlock({
                filename : file.name,
                findings : response.findings || [{ type: "IMAGE_PII" }],
                riskScore: response.riskScore || 50,
              });
              resolve(true);
            } else {
              resolve(false);
            }
          }
        );
      });
    }

    /* 3 — Text-based file: extract + scan */
    const text = await extractText(file);
    if (!text) return false;

    const result = RedactrDetector.scan(text, customKeywords);
    if (result.findings.length === 0) return false;

    onBlock({ filename: file.name, findings: result.findings, riskScore: result.score });
    return true;
  }

  function notifyBlocked(filename, findings, riskScore) {
    chrome.runtime.sendMessage({
      type: "FILE_BLOCKED",
      metadata: {
        findingTypes: [...new Set(findings.map((f) => f.type))],
        riskScore,
        filename,
        site: location.hostname,
        tier: 3,
      },
    });
  }

  /* ── File-input change handler (main interception point) ─────────────── */
  document.addEventListener("change", (event) => {
    if (!isActive()) return;
    const input = event.target;
    if (input.type !== "file" || !input.files?.length) return;

    const files = Array.from(input.files);

    // Disable submit buttons while scanning to prevent racing
    const form       = input.closest("form");
    const submitBtns = form
      ? [...form.querySelectorAll("button[type=submit], input[type=submit], button:not([type])")]
      : [];
    submitBtns.forEach((b) => (b.disabled = true));

    (async () => {
      let blocked = false;
      for (const file of files) {
        const wasBlocked = await scanAndMaybeBlock({
          file,
          inputEl: input,
          onBlock({ filename, findings, riskScore }) {
            blocked = true;
            showBlockOverlay({
              filename,
              findings,
              riskScore,
              onRemove() {
                input.value = "";                      // clear the selection
                filesBlocked.delete(input);
                submitBtns.forEach((b) => (b.disabled = false));
              },
              onSendAnyway() {
                filesBlocked.delete(input);
                submitBtns.forEach((b) => (b.disabled = false));
              },
            });
            notifyBlocked(filename, findings, riskScore);
            filesBlocked.add(input);
          },
        });
        if (wasBlocked) break;
      }
      if (!blocked) {
        submitBtns.forEach((b) => (b.disabled = false));
      }
    })();
  }, true);

  /* ── Form submit guard ──────────────────────────────────────────────── */
  document.addEventListener("submit", (event) => {
    if (!isActive()) return;
    const form        = event.target;
    const fileInputs  = [...form.querySelectorAll("input[type=file]")];
    const anyBlocked  = fileInputs.some((i) => filesBlocked.has(i));
    if (anyBlocked || formBlockedUntilClear) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  /* ── Drag-and-drop interception ─────────────────────────────────────── */
  let dropScanPending = false;

  document.addEventListener("dragover", (event) => {
    if (!isActive()) return;
    if (event.dataTransfer?.types?.includes("Files")) {
      event.dataTransfer.dropEffect = "copy";
    }
  });

  document.addEventListener("drop", (event) => {
    if (!isActive()) return;
    const files = event.dataTransfer?.files;
    if (!files?.length) return;

    // We cannot prevent the drop synchronously and still read files.
    // Strategy: let the drop occur, scan immediately, show overlay if bad,
    // and block any subsequent form submit until the user removes the file.
    if (dropScanPending) return;
    dropScanPending = true;

    (async () => {
      for (const file of Array.from(files)) {
        const wasBlocked = await scanAndMaybeBlock({
          file,
          inputEl: null,
          onBlock({ filename, findings, riskScore }) {
            formBlockedUntilClear = true;
            showBlockOverlay({
              filename,
              findings,
              riskScore,
              onRemove() { formBlockedUntilClear = false; },
              onSendAnyway() { formBlockedUntilClear = false; },
            });
            notifyBlocked(filename, findings, riskScore);
          },
        });
        if (wasBlocked) break;
      }
      dropScanPending = false;
    })();
  });
})();
