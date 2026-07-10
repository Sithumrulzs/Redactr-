/**
 * content/email-watcher.js — Enterprise Email Compose Scanner
 *
 * Monitors compose areas in Gmail and Outlook Web. Scans both subject
 * and body text on keyup (debounced 800 ms) using the same Tier-1
 * RedactrDetector engine. Shows a non-blocking warning banner below
 * the compose window when PII is detected — doesn't hard-block sending,
 * but makes it very clear the message contains sensitive data.
 *
 * Gate: only active when plan === "enterprise" AND fileInterceptEnabled.
 *
 * Requires lib/detector.js to be loaded first (see manifest.json).
 */
(function () {
  "use strict";

  /* ── State ────────────────────────────────────────────────────────────── */
  let isEnterprise   = false;
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

  /* ── Site detection ───────────────────────────────────────────────────── */
  const isGmail   = location.hostname === "mail.google.com";
  const isOutlook = location.hostname === "outlook.live.com" ||
                    location.hostname === "outlook.office.com" ||
                    location.hostname === "outlook.office365.com";

  /* ── Compose-area selectors ───────────────────────────────────────────── */
  const BODY_SELECTORS = isGmail
    ? [
        'div[role="textbox"][aria-multiline="true"]',   // compose body
        ".Am.Al.editable",
      ]
    : [
        'div[contenteditable="true"][aria-label]',       // Outlook body
        'div[role="textbox"]',
      ];

  const SUBJECT_SELECTORS = isGmail
    ? ['input[name="subjectbox"]']
    : [
        'input[aria-label]',
        'div[aria-label][contenteditable="true"]',
      ];

  /* ── Warning banner ───────────────────────────────────────────────────── */
  const BANNER_ID  = "rdx-email-banner";
  const BANNER_KEY = "__rdxBanner";                   // stored on compose root

  function findComposeRoot(el) {
    // Walk up until we find a fixed-size compose container
    let node = el;
    for (let i = 0; i < 12; i++) {
      if (!node.parentElement) break;
      node = node.parentElement;
      // Gmail compose has class 'nH' or 'aSs'; Outlook has role="dialog"
      if (
        node.matches('[role="dialog"]') ||
        node.matches('[aria-label*="ompose" i]') ||
        node.classList.contains("nH") ||
        node.classList.contains("aSs") ||
        node.classList.contains("AD")
      ) return node;
    }
    return el.closest("[role='dialog']") || el.parentElement;
  }

  function renderBanner(root, findings) {
    // Remove existing banner on this root
    if (root[BANNER_KEY]) root[BANNER_KEY].remove();

    const types = [...new Set(findings.map((f) => f.type))];
    const score = Math.min(100, findings.reduce((s, f) =>
      s + ({ AWS_KEY:40, API_KEY:40, CREDIT_CARD:35, PHONE:15, EMAIL:5,
              IP_ADDRESS:10, PERSON:20, LOCATION:20, CUSTOM_KEYWORD:30 }[f.type] || 0), 0));

    const banner = document.createElement("div");
    banner.style.cssText = `
      position:relative;z-index:99999;
      display:flex;align-items:center;gap:10px;
      background:rgba(239,84,102,.1);border-top:1.5px solid rgba(239,84,102,.4);
      padding:8px 14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;
      font-size:12px;color:#ef5466;
    `;
    banner.innerHTML = `
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" flex-shrink="0"
        stroke="#ef5466" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
        <line x1="12" y1="9" x2="12" y2="13"/><circle cx="12" cy="17" r=".5" fill="#ef5466"/>
      </svg>
      <span style="flex:1;color:#ef5466;font-weight:600;">
        Redactr: sensitive data detected in this email (${types.map((t) => t.replace(/_/g," ")).join(", ")})
        — Risk score ${score}/100.
      </span>
      <button style="background:transparent;border:none;color:#8c95a6;font-size:12px;
        cursor:pointer;padding:0;white-space:nowrap;" data-rdx-dismiss>Dismiss</button>
    `;

    banner.querySelector("[data-rdx-dismiss]").addEventListener("click", () => {
      banner.remove();
      root[BANNER_KEY] = null;
    });

    // Insert at bottom of compose container, or append to root
    root.appendChild(banner);
    root[BANNER_KEY] = banner;

    // Report (metadata only, no content)
    chrome.runtime.sendMessage({
      type: "FILE_BLOCKED",
      metadata: {
        findingTypes: types,
        riskScore: score,
        site: location.hostname,
        tier: 3,
        context: "email_compose",
      },
    });
  }

  function clearBanner(root) {
    if (root?.[BANNER_KEY]) {
      root[BANNER_KEY].remove();
      root[BANNER_KEY] = null;
    }
  }

  /* ── Debounce ─────────────────────────────────────────────────────────── */
  const timers = new WeakMap();
  function debounce(el, fn, ms = 800) {
    if (timers.has(el)) clearTimeout(timers.get(el));
    timers.set(el, setTimeout(fn, ms));
  }

  /* ── Compose-area listener ────────────────────────────────────────────── */
  const attached = new WeakSet();

  function attachToCompose(bodyEl) {
    if (attached.has(bodyEl)) return;
    attached.add(bodyEl);

    const root = findComposeRoot(bodyEl);

    function onInput() {
      if (!isActive()) { clearBanner(root); return; }

      debounce(bodyEl, () => {
        // Gather text from body + subject
        const bodyText = bodyEl.tagName === "INPUT" ? bodyEl.value : bodyEl.innerText || "";

        // Try to find a subject field inside the same compose root
        let subjectText = "";
        for (const sel of SUBJECT_SELECTORS) {
          const el = root?.querySelector(sel);
          if (el) { subjectText = el.tagName === "INPUT" ? el.value : el.innerText || ""; break; }
        }

        const combined = [subjectText, bodyText].filter(Boolean).join("\n");
        if (!combined.trim()) { clearBanner(root); return; }

        const result = RedactrDetector.scan(combined, customKeywords);
        if (result.findings.length > 0) {
          renderBanner(root, result.findings);
        } else {
          clearBanner(root);
        }
      });
    }

    bodyEl.addEventListener("input", onInput);
    bodyEl.addEventListener("keyup", onInput);
    bodyEl.addEventListener("paste", () => setTimeout(onInput, 100));
  }

  /* ── MutationObserver to catch dynamically created compose windows ─────── */
  function scanForComposeAreas() {
    for (const sel of BODY_SELECTORS) {
      document.querySelectorAll(sel).forEach((el) => {
        // Skip elements that are probably not inside a compose dialog
        const inCompose =
          el.closest('[role="dialog"]') ||
          el.closest(".nH") || el.closest(".aSs") || el.closest(".AD") ||
          el.closest("[aria-label]");
        if (inCompose || isGmail) attachToCompose(el);
      });
    }
  }

  const observer = new MutationObserver(scanForComposeAreas);
  observer.observe(document.body, { childList: true, subtree: true });
  scanForComposeAreas();
})();
