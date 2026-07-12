/**
 * MV3 service worker — bundled via esbuild (see ../package.json's
 * build:background script) because it now imports the Firebase modular
 * SDK, which can't be loaded as a plain classic script.
 *
 * Responsibilities:
 *  1. Cross-tab state — "leaks prevented" counter, Tier-1 on/off, Tier-2
 *     on/off + model status, and now auth state — all in
 *     chrome.storage.local so the popup and content scripts stay in sync.
 *  2. Bridge content scripts to the offscreen document hosting the Tier-2
 *     NER pipeline (unchanged from before).
 *  3. Google sign-in (via chrome.identity.launchWebAuthFlow + Firebase
 *     Auth — chosen over chrome.identity.getAuthToken because it behaves
 *     identically in Chrome and Edge, both required per the project spec)
 *     and syncing blocked-prompt METADATA (never the raw secret text) to
 *     Firestore via the Redactr API's /createAlert route.
 */
import { initializeApp } from "firebase/app";
import { getAuth, GoogleAuthProvider, signInWithCredential, signOut as firebaseSignOut } from "firebase/auth";

const FIREBASE_CONFIG = {
  apiKey: "AIzaSyBTg49GkhytsgHECw-_SagfU_TIV57ncck",
  authDomain: "redactr-ea568.firebaseapp.com",
  projectId: "redactr-ea568",
  appId: "1:116258256150:web:b407a3c35fabc82c0a4c37",
};

// Web-application OAuth Client ID (reused the one Firebase auto-created),
// with chrome.identity.getRedirectURL() registered as an authorized
// redirect URI for this extension's ID.
const GOOGLE_OAUTH_CLIENT_ID = "116258256150-bk6aec5oadquj8hioc1qac1092nbar50.apps.googleusercontent.com";

// See server/index.js — this replaced the Cloud Functions (which needed
// the Blaze billing plan), hosted on Render.
const API_BASE_URL = "https://redactr-ln5t.onrender.com";

const app = initializeApp(FIREBASE_CONFIG);
const auth = getAuth(app);

/** Calls a route on the Express API with a Firebase ID token attached. */
async function callApi(method, path, body) {
  if (!auth.currentUser) throw new Error("Not signed in.");
  const idToken = await auth.currentUser.getIdToken();
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${idToken}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || `Request failed (${response.status})`);
  }
  return data;
}

const DEFAULT_STATE = {
  enabled: true,
  leaksPrevented: 0,
  tier2Enabled: false,
  tier2Status: "idle", // idle | loading | ready | error
  authUser: null, // { uid, email, displayName, photoURL } | null
  tier2Allowed: false, // entitlement: only true on the Enterprise plan (see getEntitlement)
  plan: null,
  joinError: null, // set when signed in but no invite exists for this email yet
  customKeywords: [], // Enterprise-only, admin-managed (see getEntitlement)
  customEntities: [], // Enterprise-only GLiNER labels (see getEntitlement + addCustomEntity)
  trialDaysLeft: 0,
  trialExpired: false,
  // Enterprise file scanning
  fileInterceptEnabled: false,
  fileInterceptAllowed: false, // true when plan === "enterprise"
  filesBlocked: 0,
};

const OFFSCREEN_PATH = "offscreen/offscreen.html";
let creatingOffscreenDocument = null;

chrome.runtime.onInstalled.addListener(async () => {
  const current = await chrome.storage.local.get(DEFAULT_STATE);
  await chrome.storage.local.set(current);
});

auth.onAuthStateChanged((user) => {
  chrome.storage.local.set({
    authUser: user ? { uid: user.uid, email: user.email, displayName: user.displayName, photoURL: user.photoURL } : null,
  });

  if (user) {
    joinCompany();
  } else {
    chrome.storage.local.set({
      tier2Allowed: false,
      plan: null,
      joinError: null,
      leaksPrevented: 0,
      filesBlocked: 0,
      fileInterceptAllowed: false,
      trialDaysLeft: 0,
      trialExpired: false,
      customEntities: [],
    });
  }
});

/**
 * Called once after sign-in (and on every service-worker wake while signed
 * in — cheap, and the server already short-circuits once users/{uid}
 * exists). The extension only ever JOINS via an existing invite — it never
 * sends a companyName, unlike the app's CompanySetupScreen — so a random
 * sign-in here can't spin up a new company. If there's no invite waiting
 * yet, the server returns a clear 400 that gets surfaced in the popup
 * instead of silently leaving Tier-1/Tier-2 half-linked.
 */
async function joinCompany() {
  try {
    await callApi("POST", "/claimOrJoinCompany");
    await chrome.storage.local.set({ joinError: null });
  } catch (error) {
    // Trial users have no company invite — claimOrJoinCompany returns 400,
    // but we still need to fetch their entitlement (which will hit the
    // trials/{uid} path on the server). Non-trial 400s surface as joinError.
    await chrome.storage.local.set({ joinError: String(error.message || error) });
  }
  // Always fetch entitlement regardless — trial users bypass company join.
  await fetchEntitlement();
}

/**
 * Never trusts a long-lived client cache for something that gates a paid
 * feature.
 */
async function fetchEntitlement() {
  try {
    const data = await callApi("GET", "/getEntitlement");
    await chrome.storage.local.set({
      plan: data.plan,
      tier2Allowed: data.tier2Allowed,
      customKeywords: data.customKeywords ?? [],
      customEntities: data.customEntities ?? [],
      trialDaysLeft: data.trialDaysLeft ?? 0,
      trialExpired: data.trialExpired ?? false,
      // File-intercept is exclusive to Enterprise
      fileInterceptAllowed: data.plan === "enterprise",
    });
    // Clear joinError for trial users — their "no company" state is expected.
    if (data.plan === "trial" || data.plan === "trial_expired") {
      await chrome.storage.local.set({ joinError: null });
    }
  } catch (error) {
    console.warn("Redactr: failed to fetch entitlement", error);
  }
}

function buildGoogleAuthUrl(redirectUri, nonce) {
  const params = new URLSearchParams({
    client_id: GOOGLE_OAUTH_CLIENT_ID,
    response_type: "id_token",
    redirect_uri: redirectUri,
    scope: "openid email profile",
    prompt: "select_account",
    nonce,
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
}

async function signInWithGoogle() {
  const redirectUri = chrome.identity.getRedirectURL();
  const nonce = crypto.randomUUID();
  const authUrl = buildGoogleAuthUrl(redirectUri, nonce);

  const responseUrl = await chrome.identity.launchWebAuthFlow({ url: authUrl, interactive: true });
  if (!responseUrl) throw new Error("Sign-in was cancelled.");

  const fragment = new URL(responseUrl).hash.slice(1);
  const idToken = new URLSearchParams(fragment).get("id_token");
  if (!idToken) throw new Error("Google did not return an id_token.");

  const credential = GoogleAuthProvider.credential(idToken);
  const userCredential = await signInWithCredential(auth, credential);
  return userCredential.user;
}

async function signOutOfGoogle() {
  await firebaseSignOut(auth);
}

/**
 * Sends only metadata about a blocked prompt — finding types, the
 * aggregate score, and which site it happened on — never the matched
 * secret text. No-ops silently if not signed in (local counter already
 * covers the offline/signed-out case).
 */
/**
 * Creates an alert on the server and returns the alertId so the content
 * script can poll /alertStatus/:alertId for the manager's decision.
 * Returns null when not signed in or the call fails (fail-open).
 */
async function syncAlert({ findingTypes, riskScore, site, tier, source, overridden }) {
  if (!auth.currentUser) return null;
  try {
    const data = await callApi("POST", "/createAlert", {
      findingTypes, riskScore, site, tier,
      source: source ?? "prompt",
      overridden: overridden ?? false,
    });
    return data?.alertId ?? null;
  } catch (error) {
    console.warn("Redactr: failed to sync alert to backend", error);
    return null;
  }
}

async function ensureOffscreenDocument() {
  const existing = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"] });
  if (existing.length > 0) return;

  if (creatingOffscreenDocument) {
    await creatingOffscreenDocument;
    return;
  }

  creatingOffscreenDocument = chrome.offscreen.createDocument({
    url: OFFSCREEN_PATH,
    reasons: ["WORKERS"],
    justification: "Runs the on-device NER model for Tier-2 PII detection.",
  });

  try {
    await creatingOffscreenDocument;
  } finally {
    creatingOffscreenDocument = null;
  }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type === "LEAK_BLOCKED") {
    (async () => {
      const { leaksPrevented } = await chrome.storage.local.get({ leaksPrevented: 0 });
      const next = leaksPrevented + 1;
      await chrome.storage.local.set({ leaksPrevented: next });
      // Await alert creation so the alertId is available for approval polling.
      const alertId = message.metadata ? await syncAlert(message.metadata) : null;
      sendResponse({ leaksPrevented: next, alertId });
    })();
    return true;
  }

  /* ── Employee requested approval: poll its status ────────────────────── */
  if (message?.type === "POLL_ALERT_STATUS") {
    (async () => {
      if (!auth.currentUser) {
        sendResponse({ ok: false, error: "not_signed_in" });
        return;
      }
      try {
        const data = await callApi("GET", `/alertStatus/${message.alertId}`);
        sendResponse({ ok: true, status: data.status });
      } catch (error) {
        sendResponse({ ok: false, error: String(error) });
      }
    })();
    return true;
  }

  /* ── Enterprise file scanning — file/email blocked ──────────────────── */
  if (message?.type === "FILE_BLOCKED") {
    (async () => {
      const { filesBlocked } = await chrome.storage.local.get({ filesBlocked: 0 });
      const next = filesBlocked + 1;
      await chrome.storage.local.set({ filesBlocked: next });
      sendResponse({ filesBlocked: next });

      if (message.metadata) {
        syncAlert(message.metadata);
      }
    })();
    return true;
  }

  /* ── Employee overrode a file block — log separately for admin audit ── */
  if (message?.type === "FILE_OVERRIDE") {
    (async () => {
      if (message.metadata) {
        syncAlert({ ...message.metadata, overridden: true });
      }
      sendResponse({ ok: true });
    })();
    return true;
  }

  /* ── Enterprise file scanning — image analysis via offscreen canvas ──── */
  if (message?.type === "FILE_SCAN_IMAGE") {
    (async () => {
      const { fileInterceptAllowed } = await chrome.storage.local.get({ fileInterceptAllowed: false });
      if (!fileInterceptAllowed) {
        sendResponse({ ok: true, blocked: false });
        return;
      }
      try {
        await ensureOffscreenDocument();
        const response = await chrome.runtime.sendMessage({
          target  : "offscreen",
          type    : "FILE_SCAN_IMAGE",
          dataUrl : message.dataUrl,
        });
        sendResponse(response);
      } catch (error) {
        // Fail open — never block an image because the offscreen had an error
        sendResponse({ ok: true, blocked: false, error: String(error) });
      }
    })();
    return true;
  }

  if (message?.type === "GET_STATE") {
    chrome.storage.local.get(DEFAULT_STATE).then((state) => sendResponse(state));
    return true;
  }

  if (message?.type === "SIGN_IN") {
    signInWithGoogle()
      .then((user) => sendResponse({ ok: true, user: { email: user.email, displayName: user.displayName } }))
      .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  }

  if (message?.type === "SIGN_OUT") {
    signOutOfGoogle()
      .then(() => sendResponse({ ok: true }))
      .catch((error) => sendResponse({ ok: false, error: String(error) }));
    return true;
  }

  if (message?.target === "background" && message.type === "TIER2_PROGRESS") {
    const status = message.progress?.status === "ready" ? "ready" : "loading";
    chrome.storage.local.set({ tier2Status: status });
    return false;
  }

  if (message?.target === "background" && message.type === "TIER2_SCAN") {
    (async () => {
      const { tier2Enabled, tier2Allowed, customEntities } = await chrome.storage.local.get({
        tier2Enabled: false,
        tier2Allowed: false,
        customEntities: [],
      });
      if (!tier2Enabled || !tier2Allowed) {
        sendResponse({ ok: false, error: tier2Allowed ? "tier2_disabled" : "tier2_not_entitled" });
        return;
      }

      try {
        await chrome.storage.local.set({ tier2Status: "loading" });
        await ensureOffscreenDocument();
        // customEntities are Enterprise-only; the offscreen always prepends DEFAULT_LABELS.
        const response = await chrome.runtime.sendMessage({
          target: "offscreen",
          type: "TIER2_SCAN",
          text: message.text,
          labels: customEntities,
        });
        await chrome.storage.local.set({ tier2Status: response?.ok ? "ready" : "error" });
        sendResponse(response);
      } catch (error) {
        await chrome.storage.local.set({ tier2Status: "error" });
        sendResponse({ ok: false, error: String(error) });
      }
    })();
    return true;
  }

  if (message?.type === "TIER2_WARMUP") {
    (async () => {
      const { tier2Allowed } = await chrome.storage.local.get({ tier2Allowed: false });
      if (!tier2Allowed) {
        sendResponse({ ok: false, error: "tier2_not_entitled" });
        return;
      }

      try {
        await chrome.storage.local.set({ tier2Status: "loading" });
        await ensureOffscreenDocument();
        const response = await chrome.runtime.sendMessage({ target: "offscreen", type: "TIER2_WARMUP" });
        await chrome.storage.local.set({ tier2Status: response?.ok ? "ready" : "error" });
        sendResponse(response);
      } catch (error) {
        await chrome.storage.local.set({ tier2Status: "error" });
        sendResponse({ ok: false, error: String(error) });
      }
    })();
    return true;
  }
});
