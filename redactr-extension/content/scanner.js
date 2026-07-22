/**
 * Injected into chatgpt.com / claude.ai / gemini.google.com. Watches the
 * prompt input, intercepts the send action, and runs the text through
 * RedactrDetector (lib/detector.js) before it leaves the page.
 *
 * Tier-1 (regex/Luhn) is synchronous and is always the blocking gate.
 * Tier-2 (on-device NER, see ../offscreen/) is async and optional.
 *
 * Manager-approval flow is fully automated:
 *  - When a block fires, the alert is created server-side immediately
 *    (no employee button click needed).
 *  - The block banner shows a pulsing "Awaiting manager review" status.
 *  - On approval the banner plays a premium animation then auto-sends.
 */
(function () {
  "use strict";

  const INPUT_SELECTORS = [
    "#prompt-textarea",
    'div[contenteditable="true"]',
    "textarea",
  ];

  const SEND_BUTTON_SELECTORS = [
    'button[data-testid="send-button"]',
    'button[aria-label*="Send" i]',
    'button[aria-label*="submit" i]',
  ];

  function sendMsg(msg, cb) {
    try { chrome.runtime.sendMessage(msg, cb); } catch (_) { if (cb) cb(null); }
  }

  let enabled        = true;
  let tier2Enabled   = false;
  let customKeywords = [];
  let userRole       = null;
  let banner         = null;
  let attachedInput  = null;
  let attachedButton = null;
  let bypassOnce     = false;

  // Approval state — set immediately when a block fires, cleared on dismiss/send/approve
  let currentAlertId   = null;
  let approvalInterval = null;
  let pendingInputEl   = null;
  let pendingOrigText  = null;
  let pendingFindings  = null;

  sendMsg({ type: "GET_STATE" }, (state) => {
    enabled        = state?.enabled        ?? true;
    tier2Enabled   = state?.tier2Enabled   ?? false;
    customKeywords = state?.customKeywords ?? [];
    userRole       = state?.role           ?? null;
  });

  chrome.storage.onChanged.addListener((changes) => {
    if (changes.enabled)        enabled        = changes.enabled.newValue;
    if (changes.tier2Enabled)   tier2Enabled   = changes.tier2Enabled.newValue;
    if (changes.customKeywords) customKeywords = changes.customKeywords.newValue ?? [];
    if (changes.role)           userRole       = changes.role.newValue ?? null;
  });

  // ── DOM helpers ─────────────────────────────────────────────────────────────

  function getInputElement() {
    for (const s of INPUT_SELECTORS) {
      const el = document.querySelector(s);
      if (el) return el;
    }
    return null;
  }

  function getText(el) {
    return el.tagName === "TEXTAREA" ? el.value : el.innerText;
  }

  function setText(el, text) {
    if (el.tagName === "TEXTAREA") {
      // Native setter bypasses React's synthetic value tracking so the
      // framework sees the new value when the send button fires.
      const nativeSetter = Object.getOwnPropertyDescriptor(
        window.HTMLTextAreaElement.prototype, "value"
      ).set;
      nativeSetter.call(el, text);
      el.dispatchEvent(new Event("input", { bubbles: true }));
    } else {
      // execCommand updates contenteditable state synchronously inside the
      // editor's own event pipeline (React, ProseMirror, Quill, etc.),
      // so the framework reads the updated value on the very next click.
      el.focus();
      try {
        document.execCommand("selectAll", false, null);
        document.execCommand("insertText", false, text);
      } catch (_) {
        el.innerText = text;
        el.dispatchEvent(new InputEvent("input", { bubbles: true }));
      }
    }
  }

  const ICON = () => chrome.runtime.getURL("icons/icon32.png");

  const BASE_STYLE = [
    "position:fixed", "bottom:90px", "right:24px", "z-index:999999",
    "max-width:360px", "background:#1b212b", "border-radius:12px",
    "padding:16px 18px", "color:#e2e8f0",
    "font-family:Segoe UI,Arial,sans-serif", "font-size:13px",
    "box-shadow:0 8px 32px rgba(0,0,0,0.5)",
    "transition:border-color 0.35s,box-shadow 0.35s",
    "transform-origin:bottom right",
  ].join(";") + ";";

  // ── CSS animations (injected once) ──────────────────────────────────────────

  function ensureStyles() {
    if (document.getElementById("rdx-styles")) return;
    const s = document.createElement("style");
    s.id = "rdx-styles";
    s.textContent = `
      @keyframes rdxDot {
        0%,100%{ opacity:1; transform:scale(1); }
        50%    { opacity:0.3; transform:scale(0.6); }
      }
      @keyframes rdxGlow {
        0%  { box-shadow:0 8px 32px rgba(0,0,0,0.5); }
        50% { box-shadow:0 0 0 5px rgba(20,200,166,.22),0 0 52px rgba(20,200,166,.55); }
        100%{ box-shadow:0 0 0 3px rgba(20,200,166,.15),0 0 40px rgba(20,200,166,.35); }
      }
      @keyframes rdxCheckPop {
        0%  { transform:scale(0.3) rotate(-15deg); opacity:0; }
        55% { transform:scale(1.25) rotate(4deg);  opacity:1; }
        75% { transform:scale(0.92) rotate(-2deg); opacity:1; }
        100%{ transform:scale(1)   rotate(0deg);   opacity:1; }
      }
      @keyframes rdxFadeUp {
        0%  { opacity:0; transform:translateY(7px); }
        100%{ opacity:1; transform:translateY(0);   }
      }
      @keyframes rdxBannerOut {
        0%  { opacity:1; transform:scale(1)    translateY(0);   }
        100%{ opacity:0; transform:scale(0.86) translateY(14px); }
      }
      @keyframes rdxShimmer {
        0%  { background-position:200% center; }
        100%{ background-position:-200% center; }
      }
    `;
    document.head.appendChild(s);
  }

  // ── Approval state management ────────────────────────────────────────────────

  function clearApprovalState() {
    if (approvalInterval) { clearInterval(approvalInterval); approvalInterval = null; }
    pendingInputEl  = null;
    pendingOrigText = null;
    pendingFindings = null;
    currentAlertId  = null;
  }

  // Removes only the DOM element — does NOT clear approval state.
  function removeBannerDom() {
    if (banner) { banner.remove(); banner = null; }
  }

  // Full teardown: state + DOM.
  function removeBanner() {
    clearApprovalState();
    removeBannerDom();
  }

  function makeBanner(borderColor) {
    removeBannerDom();
    banner = document.createElement("div");
    banner.setAttribute("data-redactr-banner", "true");
    banner.style.cssText = BASE_STYLE + `border:1.5px solid ${borderColor};`;
    document.body.appendChild(banner);
    return banner;
  }

  function triggerSend(inputEl) {
    bypassOnce = true;
    const btn = document.querySelector(SEND_BUTTON_SELECTORS.join(", "));
    if (btn) btn.click();
    else inputEl.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
  }

  function doSendRedacted(inputEl, text, findings) {
    const { redacted } = RedactrDetector.redact(text, findings);
    setText(inputEl, redacted);
    removeBanner();
    // 50 ms lets the editor framework finish reconciling the new text
    // before the send button fires — prevents submitting stale state.
    setTimeout(() => triggerSend(inputEl), 50);
  }

  // ── Banner: BLOCKED ──────────────────────────────────────────────────────────

  function showBlockedBanner(inputEl, text, result) {
    ensureStyles();
    // Full reset for a new block event.
    clearApprovalState();
    const types = [...new Set(result.findings.map((f) => f.type))].join(", ");
    const el = makeBanner("#ef5466");
    const isAdmin = userRole === "admin";

    const headerDiv = document.createElement("div");
    headerDiv.style.cssText = "display:flex;align-items:center;gap:8px;margin-bottom:8px;";
    const img = document.createElement("img");
    img.src = ICON(); img.width = 16; img.height = 16; img.alt = "";
    const heading = document.createElement("strong");
    heading.style.cssText = "color:#ef5466;font-size:13px;";
    heading.textContent = "Prompt blocked by Redactr";
    headerDiv.appendChild(img);
    headerDiv.appendChild(heading);

    const infoP = document.createElement("p");
    infoP.id = "rdx-info";
    infoP.style.cssText = "margin:0 0 12px;color:#94a3b8;line-height:1.5;";
    infoP.innerHTML =
      "Risk <b style='color:#e2e8f0'>" + result.score + "/100</b>" +
      " &middot; Detected: <b style='color:#e2e8f0'>" + types + "</b>";

    const buttonsDiv = document.createElement("div");
    buttonsDiv.style.cssText = "display:flex;flex-direction:column;gap:8px;";

    const redactBtn = document.createElement("button");
    redactBtn.setAttribute("data-a", "redact");
    redactBtn.style.cssText = [
      "background:#14c8a6", "color:#0d1117", "font-weight:700",
      "border:none", "border-radius:6px", "padding:10px 14px",
      "cursor:pointer", "font-size:13px", "width:100%",
    ].join(";") + ";";
    redactBtn.textContent = "✓ Send redacted version";
    redactBtn.addEventListener("click", () => doSendRedacted(inputEl, text, result.findings));
    buttonsDiv.appendChild(redactBtn);

    if (isAdmin) {
      const overrideBtn = document.createElement("button");
      overrideBtn.setAttribute("data-a", "override");
      overrideBtn.style.cssText = [
        "background:#1e2a3a", "color:#f59e0b",
        "border:1.5px solid rgba(245,158,11,0.3)",
        "border-radius:6px", "padding:10px 14px",
        "cursor:pointer", "font-size:13px", "width:100%",
      ].join(";") + ";";
      overrideBtn.textContent = "⚡ Override & send original (you are the manager)";
      overrideBtn.addEventListener("click", () => {
        removeBanner();
        setText(inputEl, text);
        setTimeout(() => triggerSend(inputEl), 50);
      });
      buttonsDiv.appendChild(overrideBtn);
    } else {
      // Auto-notify status pill — replaces the old "Request approval" button
      const statusPill = document.createElement("div");
      statusPill.id = "rdx-status-pill";
      statusPill.style.cssText = [
        "display:flex", "align-items:center", "gap:9px",
        "padding:9px 13px", "background:#1e2a3a",
        "border:1.5px solid #2d3f52", "border-radius:6px",
      ].join(";") + ";";

      const dot = document.createElement("span");
      dot.id = "rdx-status-dot";
      dot.style.cssText = [
        "width:7px", "height:7px", "border-radius:50%",
        "background:#f59e0b", "flex-shrink:0",
        "animation:rdxDot 1.4s ease-in-out infinite",
      ].join(";") + ";";

      const statusTxt = document.createElement("span");
      statusTxt.id = "rdx-status-txt";
      statusTxt.style.cssText = "color:#94a3b8;font-size:12px;line-height:1.4;";
      statusTxt.textContent = "Notifying manager…";

      statusPill.appendChild(dot);
      statusPill.appendChild(statusTxt);
      buttonsDiv.appendChild(statusPill);
    }

    const dismissBtn = document.createElement("button");
    dismissBtn.setAttribute("data-a", "dismiss");
    dismissBtn.style.cssText = [
      "background:none", "color:#64748b", "border:none",
      "padding:6px", "cursor:pointer", "font-size:12px", "width:100%",
    ].join(";") + ";";
    dismissBtn.textContent = "Dismiss";
    dismissBtn.addEventListener("click", removeBanner);
    buttonsDiv.appendChild(dismissBtn);

    el.appendChild(headerDiv);
    el.appendChild(infoP);
    el.appendChild(buttonsDiv);
  }

  // Update the inline status pill once the alertId is confirmed.
  function setStatusConfirmed(confirmed) {
    const dot = document.getElementById("rdx-status-dot");
    const txt = document.getElementById("rdx-status-txt");
    if (!dot || !txt) return;
    if (confirmed) {
      dot.style.background = "#14c8a6";
      txt.textContent = "Awaiting manager review — will auto-send if approved";
    } else {
      txt.textContent = "Sign in to Redactr for manager approval";
      dot.style.background = "#64748b";
      dot.style.animation   = "none";
    }
  }

  // Update just the risk line when Tier-2 escalates findings (no banner re-create).
  function updateBannerInfo(result) {
    const infoP = document.getElementById("rdx-info");
    if (!infoP) return;
    const types = [...new Set(result.findings.map((f) => f.type))].join(", ");
    infoP.innerHTML =
      "Risk <b style='color:#e2e8f0'>" + result.score + "/100</b>" +
      " &middot; Detected: <b style='color:#e2e8f0'>" + types + "</b>";
  }

  // ── Premium approval animation ───────────────────────────────────────────────

  function playApprovalAnimation(cb) {
    if (!banner) { cb(); return; }
    ensureStyles();

    // Phase 1 — border turns teal + glow ring (0.5 s)
    banner.style.borderColor = "#14c8a6";
    banner.style.animation   = "rdxGlow 0.5s ease-out forwards";

    // Swap inner content to the approval card
    banner.innerHTML = `
      <div style="text-align:center;padding:12px 0 6px;">
        <div style="
          font-size:44px;line-height:1;margin-bottom:12px;
          color:#14c8a6;
          animation:rdxCheckPop 0.55s cubic-bezier(0.34,1.56,0.64,1) forwards;
          display:block;
        ">✓</div>
        <strong style="
          color:#14c8a6;font-size:15px;display:block;letter-spacing:0.01em;
          background:linear-gradient(90deg,#0fa98c,#14c8a6,#5eead4,#14c8a6,#0fa98c);
          background-size:200% auto;
          -webkit-background-clip:text;-webkit-text-fill-color:transparent;
          animation:rdxShimmer 1.8s linear infinite, rdxFadeUp 0.35s 0.1s ease-out both;
          opacity:0;
        ">Approved — sending now</strong>
        <p style="
          color:#64748b;font-size:12px;margin:7px 0 0;
          animation:rdxFadeUp 0.35s 0.22s ease-out both;
          opacity:0;
        ">Your original message is on its way</p>
      </div>
    `;

    // Phase 2 — hold 950 ms then slide-shrink out
    setTimeout(() => {
      if (!banner) { cb(); return; }
      banner.style.animation = "rdxBannerOut 0.42s cubic-bezier(0.4,0,1,1) forwards";
      setTimeout(() => {
        removeBannerDom();
        cb();
      }, 420);
    }, 950);
  }

  // ── Banner: DENIED ───────────────────────────────────────────────────────────

  function paintDeniedBanner() {
    if (!banner) return;
    const inputEl  = pendingInputEl;
    const text     = pendingOrigText;
    const findings = pendingFindings || [];
    banner.style.borderColor = "#ef5466";
    banner.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <img src="${ICON()}" width="16" height="16" alt="">
        <strong style="color:#ef5466;font-size:13px;">Manager denied this prompt</strong>
      </div>
      <p style="margin:0 0 12px;color:#94a3b8;line-height:1.5;">
        Your manager reviewed and blocked this content from being sent as-is.
      </p>
      <div style="display:flex;flex-direction:column;gap:8px;">
        <button data-a="redact"
          style="background:#14c8a6;color:#0d1117;font-weight:700;border:none;
                 border-radius:6px;padding:10px 14px;cursor:pointer;font-size:13px;width:100%;">
          ✓ Send redacted version instead
        </button>
        <button data-a="dismiss"
          style="background:none;color:#64748b;border:none;padding:6px;
                 cursor:pointer;font-size:12px;width:100%;">
          Dismiss
        </button>
      </div>
    `;
    banner.querySelector('[data-a="redact"]').addEventListener("click", () => {
      clearApprovalState();
      doSendRedacted(inputEl, text, findings);
    });
    banner.querySelector('[data-a="dismiss"]').addEventListener("click", removeBanner);
  }

  // ── Auto-polling (starts immediately after alertId is returned) ──────────────

  function startPolling(alertId) {
    setStatusConfirmed(true);
    const deadline = Date.now() + 5 * 60 * 1000; // 5-minute window

    approvalInterval = setInterval(() => {
      if (Date.now() > deadline) {
        clearApprovalState();
        if (banner) {
          banner.style.borderColor = "#475569";
          banner.innerHTML = `
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
              <strong style="color:#94a3b8;font-size:13px;">Approval request timed out</strong>
            </div>
            <p style="margin:0 0 12px;color:#64748b;">Manager hasn't responded in 5 minutes.</p>
            <button data-a="dismiss"
              style="background:none;color:#64748b;border:none;padding:6px;
                     cursor:pointer;font-size:12px;width:100%;">
              Dismiss
            </button>
          `;
          banner.querySelector('[data-a="dismiss"]').addEventListener("click", removeBanner);
        }
        return;
      }

      sendMsg({ type: "POLL_ALERT_STATUS", alertId }, (resp) => {
        if (!resp?.ok) return; // network error — keep polling

        if (resp.status === "approved") {
          clearInterval(approvalInterval);
          approvalInterval = null;

          // Capture before clearing
          const inputEl      = pendingInputEl;
          const originalText = pendingOrigText;
          pendingInputEl  = null;
          pendingOrigText = null;
          pendingFindings = null;
          currentAlertId  = null;

          playApprovalAnimation(() => {
            if (inputEl && originalText) {
              setText(inputEl, originalText);
              setTimeout(() => triggerSend(inputEl), 50);
            }
          });

        } else if (resp.status === "denied") {
          clearInterval(approvalInterval);
          approvalInterval = null;
          paintDeniedBanner();
        }
        // "pending" → keep polling
      });
    }, 5000);
  }

  // ── Main interception ────────────────────────────────────────────────────────

  function handleSendAttempt(event, inputEl) {
    if (!enabled) return;
    if (bypassOnce) { bypassOnce = false; return; }

    const text = getText(inputEl);
    if (!text || !text.trim()) return;

    const tier1Result = RedactrDetector.scan(text, customKeywords);

    if (tier1Result.findings.length > 0) {
      event.preventDefault();
      event.stopImmediatePropagation();

      // Set pending state immediately — polling needs this on approval.
      pendingInputEl  = inputEl;
      pendingOrigText = text;
      pendingFindings = tier1Result.findings;
      currentAlertId  = null;

      // Fire-and-forget the alert to the server; auto-start polling on success.
      sendMsg(
        { type: "LEAK_BLOCKED", metadata: buildAlertMetadata(tier1Result) },
        (resp) => {
          currentAlertId = resp?.alertId ?? null;
          if (currentAlertId && banner) {
            startPolling(currentAlertId);
          } else {
            setStatusConfirmed(false); // not signed in — grey out status
          }
        }
      );

      showBlockedBanner(inputEl, text, tier1Result);
      // Restore pending state that showBlockedBanner's clearApprovalState wiped.
      pendingInputEl  = inputEl;
      pendingOrigText = text;
      pendingFindings = tier1Result.findings;

      if (tier2Enabled) {
        RedactrDetector.scanTier2(text, tier1Result).then((merged) => {
          // Only escalate the displayed findings — don't re-create the banner.
          if (merged.findings.length > tier1Result.findings.length && approvalInterval === null) {
            updateBannerInfo(merged);
            pendingFindings = merged.findings;
          }
        }).catch(() => {});
      }
      return;
    }

    if (tier2Enabled) {
      event.preventDefault();
      event.stopImmediatePropagation();

      RedactrDetector.scanTier2(text, tier1Result).then((merged) => {
        if (merged.findings.length === 0) { bypassOnce = true; triggerSend(inputEl); return; }

        pendingInputEl  = inputEl;
        pendingOrigText = text;
        pendingFindings = merged.findings;
        currentAlertId  = null;

        sendMsg(
          { type: "LEAK_BLOCKED", metadata: buildAlertMetadata(merged) },
          (resp) => {
            currentAlertId = resp?.alertId ?? null;
            if (currentAlertId && banner) startPolling(currentAlertId);
            else setStatusConfirmed(false);
          }
        );
        showBlockedBanner(inputEl, text, merged);
        pendingInputEl  = inputEl;
        pendingOrigText = text;
        pendingFindings = merged.findings;
      }).catch(() => { bypassOnce = true; triggerSend(inputEl); });
    }
  }

  function buildAlertMetadata(result) {
    const findingTypes = [...new Set(result.findings.map((f) => f.type))];
    const TIER2_TYPES  = new Set(["PERSON", "LOCATION", "PERSON_NAME", "ADDRESS"]);
    const tier = findingTypes.some(
      (t) => TIER2_TYPES.has(t) || (t.startsWith("CUSTOM_") && t !== "CUSTOM_KEYWORD")
    ) ? 2 : 1;
    return { findingTypes, riskScore: result.score, site: location.hostname, tier };
  }

  // ── Input attachment ─────────────────────────────────────────────────────────

  function attachListeners(inputEl) {
    if (attachedInput !== inputEl) {
      attachedInput = inputEl;
      inputEl.addEventListener(
        "keydown",
        (event) => { if (event.key === "Enter" && !event.shiftKey) handleSendAttempt(event, inputEl); },
        true
      );
    }
    const button = document.querySelector(SEND_BUTTON_SELECTORS.join(", "));
    if (button && attachedButton !== button) {
      attachedButton = button;
      button.addEventListener("click", (event) => handleSendAttempt(event, inputEl), true);
    }
  }

  function scanForInput() {
    const inputEl = getInputElement();
    if (inputEl) attachListeners(inputEl);
  }

  const observer = new MutationObserver(scanForInput);
  observer.observe(document.body, { childList: true, subtree: true });
  scanForInput();
})();
