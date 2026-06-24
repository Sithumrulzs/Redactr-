/**
 * NOT CURRENTLY DEPLOYED. Cloud Functions require the Firebase Blaze
 * (pay-as-you-go) billing plan, which this project isn't on. The same
 * logic now lives in ../../server/index.js, a plain Express app hosted on
 * Render's free tier instead — firebase-admin works identically there,
 * it's just a different host for the same trust boundary (verify a
 * Firebase ID token, then use the Admin SDK).
 *
 * Kept here, unmodified, as the reference implementation and the path
 * back to Cloud Functions if this project ever moves to Blaze (gets you
 * Firestore-triggered functions, tighter Firebase project integration,
 * etc. — advantages Render's plain HTTP server doesn't have).
 */
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

const PAYPAL_CLIENT_ID = defineSecret("PAYPAL_CLIENT_ID");
const PAYPAL_CLIENT_SECRET = defineSecret("PAYPAL_CLIENT_SECRET");
const PAYPAL_WEBHOOK_ID = defineSecret("PAYPAL_WEBHOOK_ID");

// Sandbox endpoint — matches the sandbox PayPal Buttons already used in
// redactr-website/js/checkout.js. Switch to api-m.paypal.com for a real
// production deployment.
const PAYPAL_API_BASE = "https://api-m.sandbox.paypal.com";

const TIER2_PLANS = new Set(["enterprise"]);

/**
 * Called once, right after a user's first sign-in (see
 * redactr_app/lib/screens/company_setup_screen.dart). Joins an existing
 * company if an invite is waiting for this email, otherwise creates a new
 * company with the caller as admin. Runs as Admin SDK — bypasses
 * firestore.rules entirely, which is exactly why role/companyId
 * assignment is only ever done here, never by a client write.
 */
exports.claimOrJoinCompany = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const uid = request.auth.uid;
  const email = request.auth.token.email;
  if (!email) {
    throw new HttpsError("failed-precondition", "Account has no email.");
  }

  const existingUser = await db.collection("users").doc(uid).get();
  if (existingUser.exists) {
    return { companyId: existingUser.data().companyId, role: existingUser.data().role };
  }

  const inviteRef = db.collection("invites").doc(email);
  const invite = await inviteRef.get();

  if (invite.exists) {
    const { companyId, role } = invite.data();
    await db.collection("users").doc(uid).set({
      email,
      displayName: request.auth.token.name ?? null,
      photoURL: request.auth.token.picture ?? null,
      role,
      companyId,
      createdAt: FieldValue.serverTimestamp(),
    });
    await inviteRef.delete();
    return { companyId, role };
  }

  const companyName = (request.data?.companyName ?? "").trim();
  if (!companyName) {
    throw new HttpsError(
      "invalid-argument",
      "No invite found for this email — provide companyName to create a new company."
    );
  }

  const companyRef = db.collection("companies").doc();
  await companyRef.set({
    name: companyName,
    plan: "starter",
    seatLimit: 1,
    ownerUid: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await db.collection("users").doc(uid).set({
    email,
    displayName: request.auth.token.name ?? null,
    photoURL: request.auth.token.picture ?? null,
    role: "admin",
    companyId: companyRef.id,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { companyId: companyRef.id, role: "admin" };
});

/**
 * Admin-only. Writes an invites/{email} doc so the next matching sign-in
 * joins this admin's company instead of creating a new one. Stub for
 * Phase 1 — no UI calls this yet (that's Phase 2's employee management).
 */
exports.inviteEmployee = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== "admin") {
    throw new HttpsError("permission-denied", "Only admins can invite employees.");
  }

  const email = (request.data?.email ?? "").trim().toLowerCase();
  if (!email) {
    throw new HttpsError("invalid-argument", "email is required.");
  }

  await db.collection("invites").doc(email).set({
    companyId: callerDoc.data().companyId,
    role: "employee",
    invitedBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

/**
 * Called once after sign-in by both the extension and the app (never
 * trusting a client-cached value indefinitely). Tier-2 NER is gated to the
 * Enterprise plan, per the pricing copy already on the website
 * (redactr-website/pages/pricing.html) — this is just enforcing what's
 * already advertised, not a new business rule.
 */
exports.getEntitlement = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists) {
    throw new HttpsError("failed-precondition", "Complete company setup first.");
  }

  const companyDoc = await db.collection("companies").doc(callerDoc.data().companyId).get();
  const plan = companyDoc.data()?.plan ?? "starter";

  return { plan, tier2Allowed: TIER2_PLANS.has(plan) };
});

/**
 * Called by the extension (background/background.src.js) whenever Tier-1/
 * Tier-2 blocks a prompt and the user is signed in. Only ever receives
 * METADATA from the client — finding types/severities/score, never the
 * actual matched secret text, so the raw leak never reaches the backend
 * even though we're "online" now. companyId/employeeName come from the
 * caller's own users/{uid} doc (looked up here), never trusted from the
 * request body, so one company can't write alerts into another's data.
 */
exports.createAlert = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (!callerDoc.exists) {
    throw new HttpsError("failed-precondition", "Complete company setup first.");
  }
  const { companyId, displayName } = callerDoc.data();

  const findingTypes = Array.isArray(request.data?.findingTypes) ? request.data.findingTypes : [];
  const riskScore = Number(request.data?.riskScore) || 0;
  const site = typeof request.data?.site === "string" ? request.data.site : "unknown";
  const tier = request.data?.tier === 2 ? 2 : 1;

  if (findingTypes.length === 0) {
    throw new HttpsError("invalid-argument", "findingTypes is required.");
  }

  const alertRef = db.collection("companies").doc(companyId).collection("alerts").doc();
  const employeeName = displayName ?? request.auth.token.email ?? "Unknown";
  const whatWasBlocked = `Blocked a prompt containing ${findingTypes.join(", ")} on ${site}`;

  await alertRef.set({
    employeeUid: request.auth.uid,
    employeeName,
    whatWasBlocked,
    findingType: findingTypes[0],
    riskScore,
    tier,
    status: "pending",
    timestamp: FieldValue.serverTimestamp(),
  });

  await notifyAdmins(companyId, employeeName, whatWasBlocked);

  return { alertId: alertRef.id };
});

/**
 * Best-effort push to every admin's registered device for this company.
 * Never throws — a notification failure shouldn't fail the alert write
 * that already succeeded.
 */
async function notifyAdmins(companyId, employeeName, body) {
  try {
    const admins = await db
      .collection("users")
      .where("companyId", "==", companyId)
      .where("role", "==", "admin")
      .get();

    const tokens = admins.docs.map((doc) => doc.data().fcmToken).filter(Boolean);
    if (tokens.length === 0) return;

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: `New alert from ${employeeName}`, body },
    });
  } catch (error) {
    console.warn("notifyAdmins failed", error);
  }
}

async function getPayPalAccessToken() {
  const credentials = Buffer.from(`${PAYPAL_CLIENT_ID.value()}:${PAYPAL_CLIENT_SECRET.value()}`).toString(
    "base64"
  );
  const response = await fetch(`${PAYPAL_API_BASE}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  const data = await response.json();
  return data.access_token;
}

async function verifyPayPalWebhook(req, accessToken) {
  const response = await fetch(`${PAYPAL_API_BASE}/v1/notifications/verify-webhook-signature`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      transmission_id: req.headers["paypal-transmission-id"],
      transmission_time: req.headers["paypal-transmission-time"],
      cert_url: req.headers["paypal-cert-url"],
      auth_algo: req.headers["paypal-auth-algo"],
      transmission_sig: req.headers["paypal-transmission-sig"],
      webhook_id: PAYPAL_WEBHOOK_ID.value(),
      webhook_event: req.body,
    }),
  });
  const data = await response.json();
  return data.verification_status === "SUCCESS";
}

/**
 * Registered in the PayPal Developer Dashboard (sandbox) against this
 * Function's deployed URL. Verifies the signature before trusting
 * anything in the payload, then writes companies/{id}.plan +
 * companies/{id}/subscription — the doc firestore.rules locks to
 * Cloud-Function-only writes. companyId comes from the order's custom_id,
 * set client-side in redactr-website/js/checkout.js when the order is
 * created by a signed-in user.
 */
exports.paypalWebhook = onRequest(
  { secrets: [PAYPAL_CLIENT_ID, PAYPAL_CLIENT_SECRET, PAYPAL_WEBHOOK_ID] },
  async (req, res) => {
    try {
      const accessToken = await getPayPalAccessToken();
      const verified = await verifyPayPalWebhook(req, accessToken);
      if (!verified) {
        res.status(400).send("invalid signature");
        return;
      }

      const event = req.body;
      if (event.event_type !== "PAYMENT.CAPTURE.COMPLETED") {
        res.status(200).send("ignored");
        return;
      }

      const purchaseUnit = event.resource?.supplementary_data?.related_ids ?? {};
      const companyId = event.resource?.custom_id ?? purchaseUnit.custom_id;
      const planName = (event.resource?.description ?? "").toLowerCase().includes("enterprise")
        ? "enterprise"
        : (event.resource?.description ?? "").toLowerCase().includes("team")
          ? "team"
          : "starter";

      if (!companyId) {
        console.warn("paypalWebhook: no companyId (custom_id) on event", event.resource?.id);
        res.status(200).send("no companyId");
        return;
      }

      await db.collection("companies").doc(companyId).set({ plan: planName }, { merge: true });
      await db
        .collection("companies")
        .doc(companyId)
        .collection("subscription")
        .doc("current")
        .set({
          planId: planName,
          status: "active",
          paypalOrderId: event.resource?.id ?? null,
          currentPeriodEnd: null, // sandbox capture events don't include a renewal date
          updatedAt: FieldValue.serverTimestamp(),
        });

      res.status(200).send("ok");
    } catch (error) {
      console.error("paypalWebhook failed", error);
      res.status(500).send("error");
    }
  }
);
