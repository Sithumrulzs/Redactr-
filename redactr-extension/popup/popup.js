document.addEventListener("DOMContentLoaded", async () => {
  const counterEl = document.getElementById("counter-value");
  const toggleEl = document.getElementById("enabled-toggle");
  const statusEl = document.getElementById("status-text");
  const tier2ToggleEl = document.getElementById("tier2-toggle");
  const tier2StatusEl = document.getElementById("tier2-status");
  const signedOutEl = document.getElementById("auth-signed-out");
  const signedInEl = document.getElementById("auth-signed-in");
  const signInButton = document.getElementById("sign-in-button");
  const signOutButton = document.getElementById("sign-out-button");
  const authErrorEl = document.getElementById("auth-error");
  const authNameEl = document.getElementById("auth-name");
  const authEmailEl = document.getElementById("auth-email");
  const authAvatarEl = document.getElementById("auth-avatar");
  const joinErrorEl = document.getElementById("join-error");

  function renderAuth(authUser, joinError) {
    signedOutEl.classList.toggle("hidden", !!authUser);
    signedInEl.classList.toggle("hidden", !authUser);
    if (authUser) {
      const name = authUser.displayName || authUser.email || "Signed in";
      authNameEl.textContent = name;
      authEmailEl.textContent = authUser.email || "";
      authAvatarEl.textContent = name.charAt(0).toUpperCase();
    }
    renderJoinError(joinError);
  }

  function renderJoinError(joinError) {
    const message = joinError
      ? "No company found for this email — ask your admin to invite you, then sign out and back in."
      : "";
    joinErrorEl.textContent = message;
    joinErrorEl.classList.toggle("hidden", !message);
  }

  signInButton.addEventListener("click", async () => {
    signInButton.disabled = true;
    authErrorEl.textContent = "";
    const response = await chrome.runtime.sendMessage({ type: "SIGN_IN" });
    signInButton.disabled = false;
    if (!response?.ok) {
      authErrorEl.textContent = "Sign-in failed. Please try again.";
      return;
    }
    // joinCompany() runs in the background off the auth-state listener and
    // reports via the joinError storage key picked up below — render the
    // signed-in card now, the join-error line (if any) follows shortly.
    renderAuth(response.user, null);
  });

  signOutButton.addEventListener("click", async () => {
    await chrome.runtime.sendMessage({ type: "SIGN_OUT" });
    renderAuth(null, null);
  });

  const STATUS_LABEL = {
    idle: "Off",
    loading: "Downloading/loading model…",
    ready: "Ready",
    error: "Failed to load — Tier-1 still active",
  };

  function renderTier2Status(status, tier2Enabled, tier2Allowed) {
    if (!tier2Allowed) {
      tier2StatusEl.textContent = "Enterprise plan required";
      tier2StatusEl.className = "tier2-sub";
      return;
    }
    if (!tier2Enabled) {
      tier2StatusEl.textContent = "Off";
      tier2StatusEl.className = "tier2-sub";
      return;
    }
    tier2StatusEl.textContent = STATUS_LABEL[status] || "Off";
    tier2StatusEl.className = `tier2-sub ${status}`;
  }

  const state = await chrome.storage.local.get({
    enabled: true,
    leaksPrevented: 0,
    tier2Enabled: false,
    tier2Status: "idle",
    authUser: null,
    tier2Allowed: false,
    joinError: null,
  });

  renderAuth(state.authUser, state.joinError);
  counterEl.textContent = state.leaksPrevented;
  toggleEl.checked = state.enabled;
  statusEl.textContent = state.enabled
    ? "Protection is active on ChatGPT, Claude, and Gemini."
    : "Protection is paused.";

  let tier2Allowed = state.tier2Allowed;
  tier2ToggleEl.checked = state.tier2Enabled;
  tier2ToggleEl.disabled = !tier2Allowed;
  renderTier2Status(state.tier2Status, state.tier2Enabled, tier2Allowed);

  toggleEl.addEventListener("change", async () => {
    await chrome.storage.local.set({ enabled: toggleEl.checked });
    statusEl.textContent = toggleEl.checked
      ? "Protection is active on ChatGPT, Claude, and Gemini."
      : "Protection is paused.";
  });

  tier2ToggleEl.addEventListener("change", async () => {
    await chrome.storage.local.set({ tier2Enabled: tier2ToggleEl.checked });
    if (tier2ToggleEl.checked) {
      renderTier2Status("loading", true, tier2Allowed);
      chrome.runtime.sendMessage({ type: "TIER2_WARMUP" });
    } else {
      renderTier2Status("idle", false, tier2Allowed);
    }
  });

  chrome.storage.onChanged.addListener((changes) => {
    if (changes.leaksPrevented) {
      counterEl.textContent = changes.leaksPrevented.newValue;
    }
    if (changes.tier2Allowed) {
      tier2Allowed = changes.tier2Allowed.newValue;
      tier2ToggleEl.disabled = !tier2Allowed;
    }
    if (changes.tier2Status || changes.tier2Allowed) {
      renderTier2Status(
        changes.tier2Status ? changes.tier2Status.newValue : "idle",
        tier2ToggleEl.checked,
        tier2Allowed
      );
    }
    if (changes.authUser) {
      renderAuth(changes.authUser.newValue, changes.joinError ? changes.joinError.newValue : null);
    } else if (changes.joinError) {
      renderJoinError(changes.joinError.newValue);
    }
  });
});
