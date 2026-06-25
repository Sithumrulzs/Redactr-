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
  let banner = null;
  let attachedInput = null;
  let attachedButton = null;
  let bypassOnce = false;

  chrome.runtime.sendMessage({ type: "GET_STATE" }, (state) => {
    enabled = state?.enabled ?? true;
    tier2Enabled = state?.tier2Enabled ?? false;
    customKeywords = state?.customKeywords ?? [];
  });

  chrome.storage.onChanged.addListener((changes) => {
    if (changes.enabled) enabled = changes.enabled.newValue;
    if (changes.tier2Enabled) tier2Enabled = changes.tier2Enabled.newValue;
    if (changes.customKeywords) customKeywords = changes.customKeywords.newValue ?? [];
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

  function removeBanner() {
    if (banner) {
      banner.remove();
      banner = null;
    }
  }

  function renderBanner({ title, body, showCopySafe, inputEl, text, findings }) {
    removeBanner();

    banner = document.createElement("div");
    banner.setAttribute("data-redactr-banner", "true");
    banner.style.cssText = `
      position: fixed; bottom: 90px; right: 24px; z-index: 999999;
      max-width: 360px; background: #1b212b; border: 1px solid #ef5466;
      border-radius: 10px; padding: 16px; color: #ffffff;
      font-family: Segoe UI, Arial, sans-serif; font-size: 13px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    `;

    banner.innerHTML = `
      <div style="display:flex; align-items:center; gap:8px;">
        <img src="${chrome.runtime.getURL("icons/icon32.png")}" width="18" height="18" alt="" />
        <strong style="color:#ef5466;">${title}</strong>
      </div>
      <p style="margin:8px 0;">${body}</p>
      <div style="display:flex; gap:8px; margin-top:10px;">
        ${showCopySafe ? '<button data-action="copy-safe" style="flex:1; background:#14c8a6; color:#14181f; font-weight:600; border:none; border-radius:6px; padding:8px; cursor:pointer;">Copy safe version</button>' : ""}
        <button data-action="dismiss" style="background:transparent; color:#8c95a6; border:1px solid #2e3744; border-radius:6px; padding:8px; cursor:pointer;">Dismiss</button>
      </div>
    `;

    if (showCopySafe) {
      banner.querySelector('[data-action="copy-safe"]').addEventListener("click", () => {
        const { redacted } = RedactrDetector.redact(text, findings);
        setText(inputEl, redacted);
        removeBanner();
      });
    }

    banner.querySelector('[data-action="dismiss"]').addEventListener("click", removeBanner);
    document.body.appendChild(banner);
  }

  function showWarning(inputEl, text, result) {
    const types = [...new Set(result.findings.map((f) => f.type))].join(", ");
    renderBanner({
      title: "Redactr blocked this prompt",
      body: `Risk score ${result.score}/100 (${result.level}). Detected: ${types}.`,
      showCopySafe: true,
      inputEl,
      text,
      findings: result.findings,
    });
  }

  /** Upgrades an already-shown Tier-1 banner if Tier-2 found more. */
  function escalateWarning(inputEl, text, mergedResult) {
    if (!banner) {
      showWarning(inputEl, text, mergedResult);
      return;
    }
    const types = [...new Set(mergedResult.findings.map((f) => f.type))].join(", ");
    const body = banner.querySelector("p");
    if (body) {
      body.textContent = `Risk score ${mergedResult.score}/100 (${mergedResult.level}). Detected: ${types}. (updated after on-device name/address scan)`;
    }
  }

  function resend(inputEl) {
    bypassOnce = true;
    const button = document.querySelector(SEND_BUTTON_SELECTORS.join(", "));
    if (button) {
      button.click();
    } else {
      inputEl.dispatchEvent(
        new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true })
      );
    }
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
      chrome.runtime.sendMessage({ type: "LEAK_BLOCKED", metadata: buildAlertMetadata(tier1Result) });
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
        chrome.runtime.sendMessage({ type: "LEAK_BLOCKED", metadata: buildAlertMetadata(merged) });
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
    const tier = findingTypes.some((t) => t === "PERSON" || t === "LOCATION") ? 2 : 1;
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
