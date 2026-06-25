/**
 * Plain Express port of firebase/functions/index.js — same firebase-admin
 * logic, same trust boundary (every route verifies a Firebase ID token
 * before touching Firestore), just hosted on Render's free tier instead of
 * Firebase Cloud Functions (which require the Blaze billing plan). See
 * the project plan for why this exists.
 *
 * Firebase Auth, Firestore, and FCM are unaffected — this server only
 * replaces claimOrJoinCompany / inviteEmployee / getEntitlement /
 * createAlert / paypalWebhook.
 */
const path = require("path");
const express = require("express");
const cors = require("cors");
const admin = require("firebase-admin");

const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const TIER2_PLANS = new Set(["enterprise"]);
const SEAT_LIMITS = { starter: 5, professional: 25, enterprise: 999999 };

const app = express();
app.use(cors());
app.use(express.json());
// Serves server/public/redactr-extension.zip at /download/redactr-extension.zip
// — the file the website's post-purchase page links to.
app.use("/download", express.static(path.join(__dirname, "public")));

/**
 * Counts the seats a company has already used — every joined user plus
 * every invite still pending — so a burst of invites sent before any of
 * them are accepted can't blow past seatLimit.
 */
async function countUsedSeats(companyId) {
  const [users, invites] = await Promise.all([
    db.collection("users").where("companyId", "==", companyId).get(),
    db.collection("invites").where("companyId", "==", companyId).get(),
  ]);
  return users.size + invites.size;
}

/** Verifies the Firebase ID token in Authorization: Bearer <token>. */
async function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const idToken = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!idToken) {
    res.status(401).json({ error: "Sign in required." });
    return;
  }
  try {
    req.auth = await admin.auth().verifyIdToken(idToken);
    next();
  } catch (error) {
    res.status(401).json({ error: "Invalid or expired token." });
  }
}

app.get("/", (req, res) => res.send("Redactr API is running."));

/**
 * Called once, right after a user's first sign-in (see
 * redactr_app/lib/screens/company_setup_screen.dart). Joins an existing
 * company if an invite is waiting for this email, otherwise creates a new
 * company with the caller as admin.
 */
app.post("/claimOrJoinCompany", requireAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;
    const email = req.auth.email;
    if (!email) {
      res.status(400).json({ error: "Account has no email." });
      return;
    }

    const existingUser = await db.collection("users").doc(uid).get();
    if (existingUser.exists) {
      res.json({ companyId: existingUser.data().companyId, role: existingUser.data().role });
      return;
    }

    const inviteRef = db.collection("invites").doc(email);
    const invite = await inviteRef.get();

    if (invite.exists) {
      const { companyId, role } = invite.data();
      await db.collection("users").doc(uid).set({
        email,
        displayName: req.auth.name ?? null,
        photoURL: req.auth.picture ?? null,
        role,
        companyId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await inviteRef.delete();
      res.json({ companyId, role });
      return;
    }

    const companyName = (req.body?.companyName ?? "").trim();
    if (!companyName) {
      res.status(400).json({
        error: "No invite found for this email — provide companyName to create a new company.",
      });
      return;
    }

    const companyRef = db.collection("companies").doc();
    await companyRef.set({
      name: companyName,
      plan: "starter",
      seatLimit: SEAT_LIMITS.starter,
      ownerUid: uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await db.collection("users").doc(uid).set({
      email,
      displayName: req.auth.name ?? null,
      photoURL: req.auth.picture ?? null,
      role: "admin",
      companyId: companyRef.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ companyId: companyRef.id, role: "admin" });
  } catch (error) {
    console.error("claimOrJoinCompany failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Admin-only. Writes an invites/{email} doc so the next matching sign-in
 * joins this admin's company instead of creating a new one.
 */
app.post("/inviteEmployee", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "admin") {
      res.status(403).json({ error: "Only admins can invite employees." });
      return;
    }

    const email = (req.body?.email ?? "").trim().toLowerCase();
    if (!email) {
      res.status(400).json({ error: "email is required." });
      return;
    }

    const companyId = callerDoc.data().companyId;
    const companyDoc = await db.collection("companies").doc(companyId).get();
    const seatLimit = companyDoc.data()?.seatLimit ?? SEAT_LIMITS.starter;
    const usedSeats = await countUsedSeats(companyId);
    if (usedSeats >= seatLimit) {
      res.status(403).json({
        error: `Seat limit reached (${seatLimit}). Upgrade your plan to invite more employees.`,
      });
      return;
    }

    await db.collection("invites").doc(email).set({
      companyId,
      role: "employee",
      invitedBy: req.auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({ ok: true });
  } catch (error) {
    console.error("inviteEmployee failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Public checkout endpoint — called by redactr-website/js/checkout.js once
 * the PayPal sandbox payment captures. No auth required (the website never
 * signs in); the purchaser is identified by the billing email they typed
 * in, not a Firebase session. Creates the company AND an invites/{email}
 * doc with role "admin" — the exact shape claimOrJoinCompany already
 * reads, so when the purchaser later signs into the app or extension with
 * a Google account matching that billing email, they join this company
 * automatically instead of creating a new one.
 *
 * Accepted limitation: like the not-yet-deployed /paypalWebhook below,
 * this trusts the client's PayPal capture result rather than
 * independently re-verifying it server-side — fine for this assignment,
 * not something to ship as-is for real payments.
 */
app.post("/createSubscription", async (req, res) => {
  try {
    const email = (req.body?.email ?? "").trim().toLowerCase();
    const companyName = (req.body?.companyName ?? "").trim();
    const plan = SEAT_LIMITS[req.body?.plan] ? req.body.plan : "starter";
    const txId = req.body?.txId ?? null;

    if (!email || !companyName) {
      res.status(400).json({ error: "email and companyName are required." });
      return;
    }

    const companyRef = db.collection("companies").doc();
    await companyRef.set({
      name: companyName,
      plan,
      seatLimit: SEAT_LIMITS[plan],
      status: "active",
      paypalOrderId: txId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Overwrites any earlier pending invite for this email with this new
    // company — the most recent purchase wins.
    await db.collection("invites").doc(email).set({
      companyId: companyRef.id,
      role: "admin",
      invitedBy: "system:purchase",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      ok: true,
      subscription: { companyId: companyRef.id, downloadUrl: "/download/redactr-extension.zip" },
    });
  } catch (error) {
    console.error("createSubscription failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Called once after sign-in by both the extension and the app. Tier-2 NER
 * and custom keywords are both gated to the Enterprise plan, per the
 * pricing copy already on the website (redactr-website/pages/pricing.html).
 * customKeywords goes out to every signed-in user of an Enterprise company
 * (not just admins) — it's the employees' browsers that actually need the
 * list to scan against.
 */
app.get("/getEntitlement", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists) {
      res.status(400).json({ error: "Complete company setup first." });
      return;
    }

    const companyDoc = await db.collection("companies").doc(callerDoc.data().companyId).get();
    const plan = companyDoc.data()?.plan ?? "starter";
    const tier2Allowed = TIER2_PLANS.has(plan);

    res.json({
      plan,
      tier2Allowed,
      customKeywords: tier2Allowed ? companyDoc.data()?.customKeywords ?? [] : [],
    });
  } catch (error) {
    console.error("getEntitlement failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

const MAX_CUSTOM_KEYWORDS = 50;
const MAX_KEYWORD_LENGTH = 100;

/**
 * Enterprise-only, admin-only. Custom keywords are literal phrases, not
 * regex — admin-supplied regex running in every employee's browser on
 * every keystroke would be a real ReDoS risk (e.g. catastrophic
 * backtracking patterns), so this deliberately doesn't accept arbitrary
 * patterns.
 */
app.post("/addCustomKeyword", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "admin") {
      res.status(403).json({ error: "Only admins can manage custom keywords." });
      return;
    }

    const companyId = callerDoc.data().companyId;
    const companyRef = db.collection("companies").doc(companyId);
    const companyDoc = await companyRef.get();
    if (companyDoc.data()?.plan !== "enterprise") {
      res.status(403).json({ error: "Custom keyword detection requires the Enterprise plan." });
      return;
    }

    const keyword = (req.body?.keyword ?? "").trim().toLowerCase();
    if (!keyword || keyword.length > MAX_KEYWORD_LENGTH) {
      res.status(400).json({ error: `keyword must be 1-${MAX_KEYWORD_LENGTH} characters.` });
      return;
    }

    const existing = companyDoc.data()?.customKeywords ?? [];
    if (existing.includes(keyword)) {
      res.json({ ok: true, customKeywords: existing });
      return;
    }
    if (existing.length >= MAX_CUSTOM_KEYWORDS) {
      res.status(400).json({ error: `Limit of ${MAX_CUSTOM_KEYWORDS} custom keywords reached.` });
      return;
    }

    await companyRef.update({
      customKeywords: admin.firestore.FieldValue.arrayUnion(keyword),
    });
    res.json({ ok: true, customKeywords: [...existing, keyword] });
  } catch (error) {
    console.error("addCustomKeyword failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

app.post("/removeCustomKeyword", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "admin") {
      res.status(403).json({ error: "Only admins can manage custom keywords." });
      return;
    }

    const companyId = callerDoc.data().companyId;
    const keyword = (req.body?.keyword ?? "").trim().toLowerCase();
    if (!keyword) {
      res.status(400).json({ error: "keyword is required." });
      return;
    }

    await db.collection("companies").doc(companyId).update({
      customKeywords: admin.firestore.FieldValue.arrayRemove(keyword),
    });
    res.json({ ok: true });
  } catch (error) {
    console.error("removeCustomKeyword failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Called by the extension whenever Tier-1/Tier-2 blocks a prompt and the
 * user is signed in. Only ever receives METADATA — finding types/score,
 * never the matched secret text.
 */
app.post("/createAlert", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists) {
      res.status(400).json({ error: "Complete company setup first." });
      return;
    }
    const { companyId, displayName } = callerDoc.data();

    const findingTypes = Array.isArray(req.body?.findingTypes) ? req.body.findingTypes : [];
    const riskScore = Number(req.body?.riskScore) || 0;
    const site = typeof req.body?.site === "string" ? req.body.site : "unknown";
    const tier = req.body?.tier === 2 ? 2 : 1;

    if (findingTypes.length === 0) {
      res.status(400).json({ error: "findingTypes is required." });
      return;
    }

    const alertRef = db.collection("companies").doc(companyId).collection("alerts").doc();
    const employeeName = displayName ?? req.auth.email ?? "Unknown";
    const whatWasBlocked = `Blocked a prompt containing ${findingTypes.join(", ")} on ${site}`;

    await alertRef.set({
      employeeUid: req.auth.uid,
      employeeName,
      whatWasBlocked,
      findingType: findingTypes[0],
      riskScore,
      tier,
      status: "pending",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    await notifyAdmins(companyId, employeeName, whatWasBlocked);

    res.json({ alertId: alertRef.id });
  } catch (error) {
    console.error("createAlert failed", error);
    res.status(500).json({ error: "Internal error." });
  }
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

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title: `New alert from ${employeeName}`, body },
    });
  } catch (error) {
    console.warn("notifyAdmins failed", error);
  }
}

// --- PayPal webhook (Phase 3, optional) ---
// Ported for completeness. Needs PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET /
// PAYPAL_WEBHOOK_ID set as Render environment variables, and the webhook
// actually registered in the PayPal Developer Dashboard against this
// server's /paypalWebhook URL, before it does anything.
const PAYPAL_API_BASE = "https://api-m.sandbox.paypal.com";

async function getPayPalAccessToken() {
  const credentials = Buffer.from(
    `${process.env.PAYPAL_CLIENT_ID}:${process.env.PAYPAL_CLIENT_SECRET}`
  ).toString("base64");
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
      webhook_id: process.env.PAYPAL_WEBHOOK_ID,
      webhook_event: req.body,
    }),
  });
  const data = await response.json();
  return data.verification_status === "SUCCESS";
}

app.post("/paypalWebhook", async (req, res) => {
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
        currentPeriodEnd: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    res.status(200).send("ok");
  } catch (error) {
    console.error("paypalWebhook failed", error);
    res.status(500).send("error");
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`Redactr API listening on port ${port}`));
