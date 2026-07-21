/**
 * Injected into chatgpt.com / claude.ai / gemini.google.com. Watches the
 * prompt input, intercepts the send action, and runs the text through
 * RedactrDetector (lib/detector.js) before it leaves the page.
 *
 * Tier-1 (regex/Luhn) is synchronous and is always the blocking gate.
 * Tier-2 (on-device NER, see ../offscreen/) is async and optional:
 *  - If Tier-1 already blocked, Tier-2 runs afterwards and escalates the
 *    same banner in place if it finds additional names/addresses.
 *  - If Tier-1 found nothing but Tier-2 is enabled, the send is held
 *    pending the (short) NER pass, then either let through unchanged or
 *    blocked with a banner — never sent twice.
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

  let enabled = true;
  let tier2Enabled = false;
  let customKeywords = [];
  let userRole = null; // "admin" | "employee" | null
  let banner = null;
  let attachedInput = null;
  let attachedButton = null;
  let bypassOnce = false;

  // Manager-approval state
  let currentAlertId    = null;  // set when LEAK_BLOCKED callback fires
  let approvalInterval  = null;  // setInterval ID for status polling
  let pendingInputEl    = null;  // input that triggered the approval request
  let pendingOrigText   = null;  // original (un-redacted) text to restore on approve
  let pendingFindings   = null;  // findings array (needed for "Send Redacted" in denied state)

  chrome.runtime.sendMessage({ type: "GET_STATE" }, (state) => {
    enabled = state?.enabled ?? true;
    tier2Enabled = state?.tier2Enabled ?? false;
    customKeywords = state?.customKeywords ?? [];
    userRole = state?.role ?? null;
  });

  chrome.storage.onChanged.addListener((changes) => {
    if (changes.enabled) enabled = changes.enabled.newValue;
    if (changes.tier2Enabled) tier2Enabled = changes.tier2Enabled.newValue;
    if (changes.customKeywords) customKeywords = changes.customKeywords.newValue ?? [];
    if (changes.role) userRole = changes.role.newValue ?? null;
  });

  function getInputElement() {
    for (const selector of INPUT_SELECTORS) {
      const el = document.querySelector(selector);
      if (el) return el;
    }
    return null;
  }

  function getText(el) {
    return el.tagName === "TEXTAREA" ? el.value : el.innerText;
  }

  function setText(el, text) {
    if (el.tagName === "TEXTAREA") {
      el.value = text;
      el.dispatchEvent(new Event("input", { bubbles: true }));
    } else {
      el.innerText = text;
      el.dispatchEvent(new InputEvent("input", { bubbles: true }));
    }
  }

  // ── Banner helpers ──────────────────────────────────────────────────────────

  const ICON = () => chrome.runtime.getURL("icons/icon32.png");
  const BASE_STYLE = `
    position:fixed; bottom:90px; right:24px; z-index:999999;
    max-width:360px; background:#1b212b; border-radius:12px; padding:16px 18px;
    color:#e2e8f0; font-family:Segoe UI,Arial,sans-serif; font-size:13px;
    box-shadow:0 8px 32px rgba(0,0,0,0.5); transition:border-color 0.3s;
  `;

  function clearApprovalState() {
    if (approvalInterval) { clearInterval(approvalInterval); approvalInterval = null; }
    pendingInputEl  = null;
    pendingOrigText = null;
    pendingFindings = null;
  }

  function removeBanner() {
    clearApprovalState();
    if (banner) { banner.remove(); banner = null; }
  }

  function makeBanner(borderColor) {
    removeBanner();
    banner = document.createElement("div");
    banner.setAttribute("data-redactr-banner", "true");
    banner.style.cssText = BASE_STYLE + `border:1.5px solid ${borderColor};`;
    document.body.appendChild(banner);
    return banner;
  }

  function ensurePulseAnim() {
    if (!document.getElementById("rdx-pulse-kf")) {
      const s = document.createElement("style");
      s.id = "rdx-pulse-kf";
      s.textContent = "@keyframes rdxDot{0%,100%{opacity:1}50%{opacity:0.25}}";
      document.head.appendChild(s);
    }
  }

  // Performs the actual send after text has been set in the input.
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
    triggerSend(inputEl);
  }

  // ── Banner: BLOCKED (initial) ───────────────────────────────────────────────
  function showBlockedBanner(inputEl, text, result) {
    const types = [...new Set(result.findings.map((f) => f.type))].join(", ");
    const el = makeBanner("#ef5466");
    const isAdminUser = userRole === "admin";

    // Build the secondary button separately to avoid nested template literals,
    // which can confuse Chrome's content-script parser.
    const secondaryBtn = isAdminUser
      ? "<button data-a=\"override\" style=\"background:#1e2a3a;color:#f59e0b;border:1.5px solid rgba(245,158,11,0.3);border-radius:6px;padding:10px 14px;cursor:pointer;font-size:13px;width:100%;\">&#9889; Override &amp; send original (you are the manager)</button>"
      : "<button data-a=\"approve\" style=\"background:#1e2a3a;color:#94a3b8;border:1.5px solid #2d3f52;border-radius:6px;padding:10px 14px;cursor:pointer;font-size:13px;width:100%;\">&#8987; Request manager approval to send original</button>";

    el.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <img src="${ICON()}" width="16" height="16" alt="">
        <strong style="color:#ef5466;font-size:13px;">Prompt blocked by Redactr</strong>
      </div>
      <p style="margin:0 0 12px;color:#94a3b8;line-height:1.5;">
        Risk <b style="color:#e2e8f0">${result.score}/100</b> &middot; Detected: <b style="color:#e2e8f0">${types}</b>
      </p>
      <div style="display:flex;flex-direction:column;gap:8px;">
        <button data-a="redact"
          style="background:#14c8a6;color:#0d1117;font-weight:700;border:none;
                 border-radius:6px;padding:10px 14px;cursor:pointer;font-size:13px;width:100%;">
          &#10003; Send redacted version
        </button>
        ${secondaryBtn}
        <button data-a="dismiss"
          style="background:none;color:#64748b;border:none;padding:6px;
                 cursor:pointer;font-size:12px;width:100%;">
          Dismiss
        </button>
      </div>
    `;
    el.querySelector("[data-a=\"redact\"]").addEventListener("click", () => doSendRedacted(inputEl, text, result.findings));
    if (isAdminUser) {
      el.querySelector("[data-a=\"override\"]").addEventListener("click", () => {
        removeBanner();
        setText(inputEl, text);
        triggerSend(inputEl);
      });
    } else {
      el.querySelector("[data-a=\"approve\"]").addEventListener("click", () => requestManagerApproval(inputEl, text, result));
    }
    el.querySelector("[data-a=\"dismiss\"]").addEventListener("click", removeBanner);
  }

  // ── Banner: AWAITING manager decision ──────────────────────────────────────
  function paintAwaitingBanner() {
    if (!banner) return;
    ensurePulseAnim();
    banner.style.borderColor = "#f59e0b";
    banner.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
        <img src="${ICON()}" width="16" height="16" alt="">
        <strong style="color:#f59e0b;font-size:13px;">Awaiting manager approval</strong>
      </div>
      <p style="margin:0 0 10px;color:#94a3b8;line-height:1.5;">
        Your manager has been notified. If approved, the original prompt will send automatically — no action needed from you.
      </p>
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px;">
        <span style="width:7px;height:7px;border-radius:50%;background:#f59e0b;display:inline-block;
                     animation:rdxDot 1.4s ease-in-out infinite;"></span>
        <span style="color:#64748b;font-size:12px;">Checking for response every 5 seconds…</span>
      </div>
      <button data-a="cancel"
        style="background:none;color:#64748b;border:1.5px solid #2d3f52;border-radius:6px;
               padding:8px 14px;cursor:pointer;font-size:12px;width:100%;">
        Cancel request
      </button>
    `;
    banner.querySelector('[data-a="cancel"]').addEventListener("click", removeBanner);
  }

  // ── Banner: DENIED by manager ──────────────────────────────────────────────
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
        Your manager has reviewed and blocked this content from being sent as-is.
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

  // ── Approval request & polling ─────────────────────────────────────────────
  function requestManagerApproval(inputEl, text, result) {
    pendingInputEl  = inputEl;
    pendingOrigText = text;
    pendingFindings = result.findings;

    paintAwaitingBanner();

    // alertId arrives asynchronously (LEAK_BLOCKED callback). Spin-wait for it.
    let waited = 0;
    const waitForId = setInterval(() => {
      if (!banner) { clearInterval(waitForId); return; }   // user cancelled
      if (currentAlertId) {
        clearInterval(waitForId);
        startPolling(currentAlertId);
        return;
      }
      waited += 250;
      if (waited >= 5000) {
        clearInterval(waitForId);
        // Not signed in or API error — can't get an alertId
        if (banner) {
          banner.style.borderColor = "#ef5466";
          banner.innerHTML = `
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:8px;">
              <img src="${ICON()}" width="16" height="16" alt="">
              <strong style="color:#ef5466;font-size:13px;">Could not request approval</strong>
            </div>
            <p style="margin:0 0 12px;color:#94a3b8;">Sign in to Redactr to use manager approval.</p>
            <button data-a="dismiss"
              style="background:none;color:#64748b;border:none;padding:6px;cursor:pointer;font-size:12px;width:100%;">
              Dismiss
            </button>
          `;
          banner.querySelector('[data-a="dismiss"]').addEventListener("click", removeBanner);
        }
      }
    }, 250);
  }

  function startPolling(alertId) {
    const deadline = Date.now() + 5 * 60 * 1000; // 5-minute timeout

    approvalInterval = setInterval(() => {
      // Manager took too long — show timeout state
      if (Date.now() > deadline) {
        clearApprovalState();
        if (banner) {
          banner.style.borderColor = "#475569";
          const _inputEl  = pendingInputEl  || null;
          const _text     = pendingOrigText  || null;
          const _findings = pendingFindings  || [];
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

      chrome.runtime.sendMessage({ type: "POLL_ALERT_STATUS", alertId }, (resp) => {
        if (!resp?.ok) return; // network error — keep polling

        if (resp.status === "approved") {
          clearInterval(approvalInterval);
          approvalInterval = null;

          // Capture pending state before clearing
          const inputEl      = pendingInputEl;
          const originalText = pendingOrigText;
          clearApprovalState();
          if (banner) { banner.remove(); banner = null; }

          // Auto-send the original prompt — employee needs to do nothing
          if (inputEl && originalText) {
            setText(inputEl, originalText);
            triggerSend(inputEl);
          }

        } else if (resp.status === "denied") {
          clearInterval(approvalInterval);
          approvalInterval = null;
          paintDeniedBanner();
        }
        // "pending" → keep polling
      });
    }, 5000);
  }

  /** Upgrades a still-blocked banner when Tier-2 finds additional findings. */
  function showWarning(inputEl, text, result) {
    showBlockedBanner(inputEl, text, result);
  }

  function escalateWarning(inputEl, text, mergedResult) {
    // Only update if still in the initial blocked state (not awaiting/denied)
    if (approvalInterval !== null || pendingOrigText !== null) return;
    showBlockedBanner(inputEl, text, mergedResult);
  }

  function resend(inputEl) {
    triggerSend(inputEl);
  }

  function handleSendAttempt(event, inputEl) {
    if (!enabled) return;
    if (bypassOnce) {
      bypassOnce = false;
      return;
    }

    const text = getText(inputEl);
    if (!text || !text.trim()) return;

    const tier1Result = RedactrDetector.scan(text, customKeywords);

    if (tier1Result.findings.length > 0) {
      event.preventDefault();
      event.stopImmediatePropagation();
      currentAlertId = null; // clear stale id before the fresh LEAK_BLOCKED callback arrives
      chrome.runtime.sendMessage(
        { type: "LEAK_BLOCKED", metadata: buildAlertMetadata(tier1Result) },
        (resp) => { currentAlertId = resp?.alertId ?? null; }
      );
      showWarning(inputEl, text, tier1Result);

      if (tier2Enabled) {
        RedactrDetector.scanTier2(text, tier1Result).then((merged) => {
          if (merged.findings.length > tier1Result.findings.length) {
            escalateWarning(inputEl, text, merged);
          }
        });
      }
      return;
    }

    if (tier2Enabled) {
      // Hold the send until the (short) NER pass completes, since Tier-1
      // alone can't see unstructured names/addresses.
      event.preventDefault();
      event.stopImmediatePropagation();

      RedactrDetector.scanTier2(text, tier1Result).then((merged) => {
        if (merged.findings.length === 0) {
          resend(inputEl);
          return;
        }
        currentAlertId = null;
        chrome.runtime.sendMessage(
          { type: "LEAK_BLOCKED", metadata: buildAlertMetadata(merged) },
          (resp) => { currentAlertId = resp?.alertId ?? null; }
        );
        showWarning(inputEl, text, merged);
      });
    }
  }

  /**
   * Only ever metadata — finding types, aggregate score, which site — never
   * the matched secret text itself. This is what (optionally) leaves the
   * machine once the user is signed in; see background/background.src.js.
   */
  function buildAlertMetadata(result) {
    const findingTypes = [...new Set(result.findings.map((f) => f.type))];
    const TIER2_TYPES = new Set(["PERSON", "LOCATION", "PERSON_NAME", "ADDRESS"]);
    const tier = findingTypes.some(
      t => TIER2_TYPES.has(t) || (t.startsWith("CUSTOM_") && t !== "CUSTOM_KEYWORD")
    ) ? 2 : 1;
    return { findingTypes, riskScore: result.score, site: location.hostname, tier };
  }

  function attachListeners(inputEl) {
    if (attachedInput !== inputEl) {
      attachedInput = inputEl;
      inputEl.addEventListener(
        "keydown",
        (event) => {
          if (event.key === "Enter" && !event.shiftKey) {
            handleSendAttempt(event, inputEl);
          }
        },
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
