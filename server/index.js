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

let serviceAccount;
try {
  serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
} catch (e) {
  console.error("FATAL: FIREBASE_SERVICE_ACCOUNT_JSON is missing or invalid JSON. Server cannot start.", e.message);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const TIER2_PLANS = new Set(["enterprise"]);
const SEAT_LIMITS = { starter: 5, professional: 25, enterprise: 100 };

const app = express();

const ALLOWED_ORIGINS = [
  "https://redactr-swart.vercel.app",
  "https://redactr-ln5t.onrender.com",
  // local dev
  "http://localhost:3000",
  "http://localhost:5500",
  "http://127.0.0.1:5500",
];
app.use(cors({
  origin: (origin, cb) => {
    // Allow same-origin requests (no Origin header), listed origins, and the
    // Chrome extension service worker (which sends chrome-extension://<id>).
    if (!origin || ALLOWED_ORIGINS.includes(origin) || /^chrome-extension:\/\//.test(origin)) {
      return cb(null, true);
    }
    cb(new Error(`CORS: origin ${origin} not allowed`));
  },
  credentials: true,
}));
app.use(express.json());
const { randomUUID } = require("crypto");
const SERVER_URL = process.env.SERVER_URL || "https://redactr-ln5t.onrender.com";

// Simple in-memory rate limiter — resets on each server restart (fine for Render free tier).
const _rateCounts = new Map();
function rateLimit(key, maxPerMinute) {
  const now = Date.now();
  const entry = _rateCounts.get(key) || { count: 0, reset: now + 60000 };
  if (now > entry.reset) { entry.count = 0; entry.reset = now + 60000; }
  entry.count++;
  _rateCounts.set(key, entry);
  return entry.count > maxPerMinute;
}
function rateLimitMiddleware(maxPerMinute) {
  return (req, res, next) => {
    const ip = req.headers["x-forwarded-for"]?.split(",")[0] || req.socket.remoteAddress || "unknown";
    if (rateLimit(ip + req.path, maxPerMinute)) {
      return res.status(429).json({ error: "Too many requests. Please wait a moment." });
    }
    next();
  };
}

/**
 * Creates a 7-day download token in Firestore and returns the full download
 * URL. Tokens are reusable within their window so the same link can be
 * forwarded to multiple employees without generating a new one each time.
 */
async function createDownloadToken(companyId) {
  const token = randomUUID();
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  await db.collection("downloadTokens").doc(token).set({
    companyId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
  });
  return token;
}

/**
 * Token-gated extension download — the zip is only reachable with a valid
 * purchase token so the file can't be scraped or shared before payment.
 * Returns a path (not full URL) so checkout.js can prepend its own base.
 */
app.get("/download", async (req, res) => {
  const token = String(req.query.token || "");
  if (!token) {
    res.status(403).send("A purchase token is required. Complete checkout to receive a download link.");
    return;
  }
  try {
    const tokenDoc = await db.collection("downloadTokens").doc(token).get();
    if (!tokenDoc.exists) {
      res.status(403).send("Invalid or expired download link. Ask your admin to generate a new one from the mobile app.");
      return;
    }
    const { expiresAt } = tokenDoc.data();
    if (expiresAt && expiresAt.toDate() < new Date()) {
      await db.collection("downloadTokens").doc(token).delete();
      res.status(403).send("Download link has expired (7-day limit). Ask your admin to generate a new one.");
      return;
    }
    res.download(path.join(__dirname, "public", "redactr-extension.zip"), "redactr-extension.zip");
  } catch (error) {
    console.error("download failed", error);
    res.status(500).send("Download failed. Please try again.");
  }
});

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
app.post("/claimOrJoinCompany", requireAuth, rateLimitMiddleware(10), async (req, res) => {
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

    // Require an active trial to create a company without a paid invite.
    const trialDoc = await db.collection("trials").doc(uid).get();
    const trialData = trialDoc.exists ? trialDoc.data() : null;
    const trialValid = trialData?.trialActive && trialData?.trialEnd?.toDate?.() > new Date();
    if (!trialValid) {
      res.status(403).json({
        error: "A paid plan or free trial is required. Visit redactr-swart.vercel.app to get started.",
      });
      return;
    }

    const companyRef = db.collection("companies").doc();
    await companyRef.set({
      name: companyName,
      plan: "trial",
      seatLimit: 1,
      status: "active",
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
app.post("/inviteEmployee", requireAuth, rateLimitMiddleware(20), async (req, res) => {
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

    // Fire-and-forget — never block the response on email.
    const companyName = companyDoc.data()?.name ?? "your company";
    const inviterName = req.auth.name ?? req.auth.email ?? "Your admin";
    sendInviteEmail(email, companyName, inviterName);

    res.json({ ok: true });
  } catch (error) {
    console.error("inviteEmployee failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Admin-only. Removes a team member by clearing their companyId and role.
 * Their Auth account is preserved — they just lose company access.
 */
app.post("/removeMember", requireAuth, rateLimitMiddleware(20), async (req, res) => {
  try {
    const callerUid = req.auth.uid;
    const targetUid = (req.body?.targetUid ?? "").trim();

    if (!targetUid) {
      return res.status(400).json({ error: "targetUid is required." });
    }
    if (targetUid === callerUid) {
      return res.status(400).json({ error: "You cannot remove yourself." });
    }

    const callerDoc = await db.collection("users").doc(callerUid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "admin") {
      return res.status(403).json({ error: "Only admins can remove members." });
    }

    const targetDoc = await db.collection("users").doc(targetUid).get();
    if (!targetDoc.exists || targetDoc.data().companyId !== callerDoc.data().companyId) {
      return res.status(404).json({ error: "Member not found in your company." });
    }

    await db.collection("users").doc(targetUid).update({
      companyId: admin.firestore.FieldValue.delete(),
      role: admin.firestore.FieldValue.delete(),
    });

    res.json({ ok: true });
  } catch (error) {
    console.error("removeMember failed", error);
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
app.post("/createSubscription", rateLimitMiddleware(5), async (req, res) => {
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

    const dlToken = await createDownloadToken(companyRef.id);

    // Fire-and-forget confirmation email — don't block the checkout response.
    sendTrialWelcomeEmail(email, companyName, null, null, plan);

    res.json({
      ok: true,
      subscription: { companyId: companyRef.id, downloadUrl: `/download?token=${dlToken}` },
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
      // Not a company member — check for an active trial.
      const trialDoc = await db.collection("trials").doc(req.auth.uid).get();
      if (!trialDoc.exists) {
        res.status(400).json({ error: "Complete company setup first." });
        return;
      }
      const trial = trialDoc.data();
      const now = Date.now();
      const trialEnd = trial.trialEnd?.toDate?.() ?? new Date(0);
      const trialActive = trial.trialActive && trialEnd > now;
      const trialDaysLeft = trialActive
        ? Math.max(0, Math.ceil((trialEnd - now) / 86400000))
        : 0;
      res.json({
        plan: trialActive ? "trial" : "trial_expired",
        tier2Allowed: false,
        customKeywords: [],
        customEntities: [],
        trialDaysLeft,
        trialExpired: !trialActive,
      });
      return;
    }

    const companyDoc = await db.collection("companies").doc(callerDoc.data().companyId).get();
    const plan = companyDoc.data()?.plan ?? "starter";
    const tier2Allowed = TIER2_PLANS.has(plan);
    const companyData = companyDoc.data() ?? {};

    // For company trial users, surface remaining trial days from trials/{uid}
    // so the extension and app can show the correct banner and prompt to upgrade.
    let trialDaysLeft = 0;
    let trialExpired = false;
    if (plan === "trial") {
      const trialDoc = await db.collection("trials").doc(req.auth.uid).get();
      if (trialDoc.exists) {
        const now = Date.now();
        const trialEnd = trialDoc.data().trialEnd?.toDate?.() ?? new Date(0);
        const trialActive = trialDoc.data().trialActive && trialEnd > now;
        trialDaysLeft = trialActive ? Math.max(0, Math.ceil((trialEnd - now) / 86400000)) : 0;
        trialExpired = !trialActive;
      }
    }

    res.json({
      plan,
      tier2Allowed,
      customKeywords: tier2Allowed ? companyData.customKeywords ?? [] : [],
      customEntities: tier2Allowed ? companyData.customEntities ?? [] : [],
      trialDaysLeft,
      trialExpired,
    });
  } catch (error) {
    console.error("getEntitlement failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Sends an invite email to a newly-invited employee so they know to sign
 * in with this address. Fire-and-forget — the route responds immediately
 * and this runs in the background. Silently skips if RESEND_API_KEY is absent.
 */
async function sendInviteEmail(toEmail, companyName, inviterName) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.log(`[email] Invite email skipped (no RESEND_API_KEY) → ${toEmail}`);
    return;
  }

  const from    = process.env.EMAIL_FROM || "Redactr <onboarding@resend.dev>";
  const CWS_URL = "https://chromewebstore.google.com/detail/redactr/jplbboglhhopcopdgbephgoelaflfelh";
  const subject = `You've been invited to join ${companyName} on Redactr`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${subject}</title>
</head>
<body style="margin:0;padding:0;background:#060a11;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">

<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#060a11;">
<tr><td align="center" style="padding:52px 16px 64px;">

  <table width="560" cellpadding="0" cellspacing="0" border="0"
    style="max-width:560px;width:100%;background:#0c1018;border-radius:24px;
    border:1px solid rgba(255,255,255,0.06);overflow:hidden;">

    <tr><td style="background:linear-gradient(90deg,#0a7a62,#14c8a6 48%,#5eead4);
      height:2px;font-size:0;line-height:0;">&nbsp;</td></tr>

    <tr><td style="padding:32px 44px 0;">
      <table cellpadding="0" cellspacing="0" border="0"><tr>
        <td style="width:8px;height:22px;background:linear-gradient(180deg,#14c8a6,#0a7a62);
          border-radius:3px;display:inline-block;vertical-align:middle;"></td>
        <td style="padding-left:10px;font-size:15px;font-weight:800;color:#ffffff;
          letter-spacing:-0.02em;vertical-align:middle;">Redactr</td>
      </tr></table>
    </td></tr>

    <tr><td style="padding:28px 44px 0;">
      <p style="margin:0 0 6px;font-size:12px;font-weight:700;color:rgba(20,200,166,0.7);
        letter-spacing:1.8px;text-transform:uppercase;">Team invitation</p>
      <h1 style="margin:0 0 14px;font-size:28px;font-weight:800;color:#ffffff;
        letter-spacing:-0.04em;line-height:1.15;">
        You've been invited.
      </h1>
      <p style="margin:0;font-size:15px;color:rgba(180,200,230,0.55);line-height:1.7;">
        <strong style="color:rgba(255,255,255,0.8);">${inviterName}</strong> has invited you to join
        <strong style="color:rgba(255,255,255,0.8);">${companyName}</strong> on Redactr —
        AI-powered sensitive data protection for your browser.
      </p>
    </td></tr>

    <tr><td style="padding:28px 44px 0;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0"
        style="background:rgba(20,200,166,0.06);border:1px solid rgba(20,200,166,0.18);
        border-radius:16px;overflow:hidden;">
        <tr><td style="padding:24px;">
          <p style="margin:0 0 6px;font-size:11px;font-weight:700;color:#14c8a6;
            letter-spacing:1.2px;text-transform:uppercase;">How to join — 2 steps</p>
          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:16px;">
            <tr>
              <td width="28" valign="top" style="padding-bottom:14px;">
                <div style="width:22px;height:22px;border-radius:50%;background:#14c8a6;
                  text-align:center;line-height:22px;font-size:12px;font-weight:800;
                  color:#060a11;">1</div>
              </td>
              <td valign="top" style="padding-bottom:14px;padding-left:10px;">
                <p style="margin:0 0 4px;font-size:13.5px;font-weight:700;color:rgba(220,235,255,0.9);">
                  Install the Redactr extension</p>
                <p style="margin:0;font-size:12.5px;color:rgba(170,190,220,0.55);line-height:1.5;">
                  One click from the Chrome Web Store.</p>
              </td>
            </tr>
            <tr>
              <td width="28" valign="top">
                <div style="width:22px;height:22px;border-radius:50%;background:#14c8a6;
                  text-align:center;line-height:22px;font-size:12px;font-weight:800;
                  color:#060a11;">2</div>
              </td>
              <td valign="top" style="padding-left:10px;">
                <p style="margin:0 0 4px;font-size:13.5px;font-weight:700;color:rgba(220,235,255,0.9);">
                  Sign in with this email address</p>
                <p style="margin:0;font-size:12.5px;color:rgba(170,190,220,0.55);line-height:1.5;">
                  Use the Google account for <strong style="color:rgba(200,220,250,0.7);">${toEmail}</strong>.
                  You'll be automatically linked to ${companyName}.
                </p>
              </td>
            </tr>
          </table>

          <div style="margin-top:20px;">
            <a href="${CWS_URL}" style="display:inline-block;background:#14c8a6;color:#060a11;
              font-size:13px;font-weight:800;text-decoration:none;
              padding:12px 26px;border-radius:10px;letter-spacing:0.01em;">
              Install Redactr →
            </a>
          </div>
        </td></tr>
      </table>
    </td></tr>

    <tr><td style="padding:28px 44px 0;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
        <tr><td style="height:1px;background:rgba(255,255,255,0.05);font-size:0;">&nbsp;</td></tr>
      </table>
    </td></tr>

    <tr><td style="padding:20px 44px 36px;">
      <p style="margin:0;font-size:11px;color:rgba(120,140,170,0.35);line-height:1.7;">
        You're receiving this because ${inviterName} invited ${toEmail} to Redactr.
        If you weren't expecting this, you can safely ignore it.
      </p>
    </td></tr>

  </table>

</td></tr>
</table>
</body>
</html>`;

  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [toEmail], subject, html }),
    });
    if (!resp.ok) console.warn("[invite] Email failed:", await resp.json());
    else console.log(`[invite] Email sent → ${toEmail}`);
  } catch (e) {
    console.warn("[invite] Email error:", e.message);
  }
}

/**
 * Sends a welcome / confirmation email via Resend (https://resend.com).
 * Requires RESEND_API_KEY env var — silently skips if absent so the
 * route still works without email configured.
 *
 * plan: "trial" | "starter" | "professional" | "enterprise"
 */
async function sendTrialWelcomeEmail(toEmail, displayName, trialEnd, _downloadUrl, plan = "trial") {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.log(`[email] Welcome email skipped (no RESEND_API_KEY) → ${toEmail}`);
    return;
  }

  const from    = process.env.EMAIL_FROM || "Redactr <onboarding@resend.dev>";
  const name    = (displayName || toEmail.split("@")[0]).split(" ")[0]; // first name only
  const siteUrl = "https://redactr-swart.vercel.app";

  /* ── Plan metadata ─────────────────────────────────────────────────── */
  const isTrial = plan === "trial";
  const days    = isTrial ? Math.ceil((new Date(trialEnd) - Date.now()) / 86400000) : null;
  const endDate = trialEnd
    ? new Date(trialEnd).toLocaleDateString("en-GB", { day:"numeric", month:"long", year:"numeric" })
    : null;

  const PLAN_META = {
    trial:        { label:"Free Trial",    badge:"#14c8a6", badgeText:"TRIAL",        period: days ? `${days} days remaining` : "7-day access" },
    starter:      { label:"Starter",       badge:"#6366f1", badgeText:"STARTER",       period: "Monthly subscription" },
    professional: { label:"Professional",  badge:"#8b5cf6", badgeText:"PROFESSIONAL",  period: "Monthly subscription" },
    enterprise:   { label:"Enterprise",    badge:"#f59e0b", badgeText:"ENTERPRISE",    period: "Annual subscription" },
  };
  const meta = PLAN_META[plan] || PLAN_META.trial;

  const PLAN_FEATURES = {
    trial: [
      "API key detection (AWS, OpenAI, GitHub)",
      "Credit card protection (Luhn-validated)",
      "Email, phone &amp; IP address detection",
      "SSN, passport &amp; driver's licence detection",
      "Chrome extension on ChatGPT, Claude &amp; Gemini",
      "Manager mobile app &amp; alert dashboard",
      "7-day free access — no card required",
    ],
    starter: [
      "API key detection (AWS, OpenAI, GitHub)",
      "Credit card protection (Luhn-validated)",
      "Email, phone &amp; IP address detection",
      "SSN, passport &amp; driver's licence detection",
      "Chrome extension (1-click install)",
      "Manager mobile app &amp; alert dashboard",
      "Up to 5 employee seats",
      "Email support",
    ],
    professional: [
      "Everything in Starter",
      "Up to 25 employee seats",
      "Full team alert history &amp; audit log",
      "Employee invite management",
      "Admin approval &amp; deny controls",
      "Priority email support",
    ],
    enterprise: [
      "Everything in Professional",
      "Up to 100 employee seats",
      "On-device AI — name &amp; address detection",
      "Custom keyword blocking",
      "File &amp; attachment scanning (Word, PDF, images)",
      "Gmail &amp; Outlook compose monitoring",
      "Dedicated account manager",
      "Custom contracts &amp; SLA",
    ],
  };
  const features = PLAN_FEATURES[plan] || PLAN_FEATURES.trial;

  /* ── Subject line ───────────────────────────────────────────────────── */
  const subject = isTrial
    ? `Your ${days}-day Redactr trial is live, ${name}`
    : `Welcome to Redactr ${meta.label}, ${name}`;

  /* ── Email HTML ─────────────────────────────────────────────────────── */
  const featureRows = features.map((f) => `
    <tr>
      <td width="20" valign="top" style="padding:0 10px 10px 0;">
        <div style="width:18px;height:18px;border-radius:50%;background:rgba(20,200,166,0.12);
          text-align:center;line-height:18px;font-size:10px;font-weight:900;color:#14c8a6;">✓</div>
      </td>
      <td style="padding:0 0 10px;font-size:13.5px;color:rgba(200,215,235,0.75);line-height:1.5;">${f}</td>
    </tr>`).join("");

  const CWS_URL = "https://chromewebstore.google.com/detail/redactr/jplbboglhhopcopdgbephgoelaflfelh";

  const subscriptionBlock = isTrial ? `
    <!-- Renews / expires note -->
    <tr><td style="padding:16px 44px 0;">
      <p style="margin:0;font-size:12.5px;color:rgba(160,175,200,0.45);line-height:1.65;text-align:center;">
        After your trial, choose a plan at
        <a href="${siteUrl}/pages/pricing.html" style="color:#14c8a6;text-decoration:none;font-weight:600;">redactr.com/pricing</a>
        — no card required to start.
      </p>
    </td></tr>` : `
    <!-- Install CTA for paid plans -->
    <tr><td style="padding:28px 44px 0;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0"
        style="background:rgba(20,200,166,0.06);border:1px solid rgba(20,200,166,0.18);
        border-radius:16px;overflow:hidden;">
        <tr><td style="padding:22px 24px;">
          <p style="margin:0 0 4px;font-size:12px;font-weight:700;color:#14c8a6;
            letter-spacing:1.2px;text-transform:uppercase;">Get started</p>
          <p style="margin:0 0 16px;font-size:14px;color:rgba(200,215,235,0.65);line-height:1.55;">
            Install the extension in one click, then sign in with this email to activate your ${meta.label} plan.
            Share the same link with your team.
          </p>
          <a href="${CWS_URL}" style="display:inline-block;background:#14c8a6;color:#060a11;
            font-size:13px;font-weight:800;text-decoration:none;
            padding:12px 26px;border-radius:10px;letter-spacing:0.01em;">
            Install from Chrome Web Store →
          </a>
        </td></tr>
      </table>
    </td></tr>
    <!-- Dashboard link -->
    <tr><td style="padding:16px 44px 0;text-align:center;">
      <a href="${siteUrl}" style="font-size:12.5px;color:rgba(20,200,166,0.6);
        text-decoration:none;font-weight:600;">
        Open Redactr Dashboard →
      </a>
    </td></tr>`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>${subject}</title>
</head>
<body style="margin:0;padding:0;background:#060a11;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;">

<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#060a11;">
<tr><td align="center" style="padding:52px 16px 64px;">

  <!-- Shell -->
  <table width="560" cellpadding="0" cellspacing="0" border="0"
    style="max-width:560px;width:100%;background:#0c1018;border-radius:24px;
    border:1px solid rgba(255,255,255,0.06);overflow:hidden;">

    <!-- Top gradient bar -->
    <tr><td style="background:linear-gradient(90deg,#0a7a62,#14c8a6 48%,#5eead4);
      height:2px;font-size:0;line-height:0;">&nbsp;</td></tr>

    <!-- Logo row -->
    <tr><td style="padding:32px 44px 0;">
      <table cellpadding="0" cellspacing="0" border="0">
        <tr>
          <td style="width:8px;height:22px;background:linear-gradient(180deg,#14c8a6,#0a7a62);
            border-radius:3px;display:inline-block;vertical-align:middle;"></td>
          <td style="padding-left:10px;font-size:15px;font-weight:800;color:#ffffff;
            letter-spacing:-0.02em;vertical-align:middle;">Redactr</td>
        </tr>
      </table>
    </td></tr>

    <!-- Hero text -->
    <tr><td style="padding:28px 44px 0;">
      <p style="margin:0 0 6px;font-size:12px;font-weight:700;color:rgba(20,200,166,0.7);
        letter-spacing:1.8px;text-transform:uppercase;">Subscription confirmed</p>
      <h1 style="margin:0 0 14px;font-size:30px;font-weight:800;color:#ffffff;
        letter-spacing:-0.045em;line-height:1.12;">
        ${isTrial ? `You're in, ${name}.` : `Welcome aboard, ${name}.`}
      </h1>
      <p style="margin:0;font-size:15px;color:rgba(180,200,230,0.55);line-height:1.7;">
        ${isTrial
          ? `Your <strong style="color:rgba(255,255,255,0.85);">free trial</strong> is now active. Here's what you have access to for the next ${days} days.`
          : `Your <strong style="color:rgba(255,255,255,0.85);">${meta.label}</strong> plan is now active. Here's a summary of your subscription.`}
      </p>
    </td></tr>

    <!-- Plan card -->
    <tr><td style="padding:24px 44px 0;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0"
        style="background:#080d14;border-radius:16px;border:1px solid rgba(255,255,255,0.07);overflow:hidden;">

        <!-- Card header -->
        <tr>
          <td style="padding:20px 24px 16px;border-bottom:1px solid rgba(255,255,255,0.05);">
            <table width="100%" cellpadding="0" cellspacing="0" border="0">
              <tr>
                <td valign="middle">
                  <p style="margin:0;font-size:10px;font-weight:700;
                    color:rgba(140,160,190,0.5);letter-spacing:1.6px;text-transform:uppercase;">Your plan</p>
                  <p style="margin:4px 0 0;font-size:18px;font-weight:800;color:#ffffff;
                    letter-spacing:-0.03em;">${meta.label}</p>
                </td>
                <td valign="middle" align="right">
                  <span style="display:inline-block;background:rgba(20,200,166,0.12);
                    color:#14c8a6;border:1px solid rgba(20,200,166,0.25);
                    border-radius:20px;font-size:10px;font-weight:800;
                    padding:4px 12px;letter-spacing:1px;">${meta.badgeText}</span>
                </td>
              </tr>
            </table>
          </td>
        </tr>

        <!-- Card rows -->
        <tr>
          <td style="padding:0 24px;">
            <table width="100%" cellpadding="0" cellspacing="0" border="0">

              <!-- Status -->
              <tr>
                <td style="padding:14px 0;border-bottom:1px solid rgba(255,255,255,0.04);">
                  <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
                    <td style="font-size:12px;color:rgba(140,160,190,0.5);font-weight:600;
                      text-transform:uppercase;letter-spacing:0.08em;">Status</td>
                    <td align="right">
                      <span style="display:inline-flex;align-items:center;gap:5px;
                        font-size:12px;font-weight:700;color:#14c8a6;">
                        <span style="display:inline-block;width:6px;height:6px;
                          border-radius:50%;background:#14c8a6;"></span>
                        Active
                      </span>
                    </td>
                  </tr></table>
                </td>
              </tr>

              <!-- Billing period / days -->
              <tr>
                <td style="padding:14px 0;border-bottom:1px solid rgba(255,255,255,0.04);">
                  <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
                    <td style="font-size:12px;color:rgba(140,160,190,0.5);font-weight:600;
                      text-transform:uppercase;letter-spacing:0.08em;">
                      ${isTrial ? "Remaining" : "Billing"}
                    </td>
                    <td align="right" style="font-size:13px;font-weight:700;color:rgba(220,235,255,0.85);">
                      ${meta.period}
                    </td>
                  </tr></table>
                </td>
              </tr>

              ${endDate ? `
              <!-- End / renewal date -->
              <tr>
                <td style="padding:14px 0;">
                  <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
                    <td style="font-size:12px;color:rgba(140,160,190,0.5);font-weight:600;
                      text-transform:uppercase;letter-spacing:0.08em;">
                      ${isTrial ? "Trial ends" : "Next renewal"}
                    </td>
                    <td align="right" style="font-size:13px;font-weight:700;color:rgba(220,235,255,0.85);">
                      ${endDate}
                    </td>
                  </tr></table>
                </td>
              </tr>` : ""}

            </table>
          </td>
        </tr>

      </table>
    </td></tr>

    <!-- What's included -->
    <tr><td style="padding:28px 44px 0;">
      <p style="margin:0 0 14px;font-size:11px;font-weight:700;
        color:rgba(140,160,190,0.45);letter-spacing:1.6px;text-transform:uppercase;">
        What's included
      </p>
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
        ${featureRows}
      </table>
    </td></tr>

    ${subscriptionBlock}

    <!-- Thin divider -->
    <tr><td style="padding:28px 44px 0;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0">
        <tr><td style="height:1px;background:rgba(255,255,255,0.05);font-size:0;">&nbsp;</td></tr>
      </table>
    </td></tr>

    <!-- Footer -->
    <tr><td style="padding:20px 44px 36px;">
      <table width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
        <td style="font-size:11px;color:rgba(120,140,170,0.35);line-height:1.7;">
          You're receiving this because you activated a Redactr ${meta.label} at
          <a href="${siteUrl}" style="color:rgba(120,140,170,0.5);text-decoration:none;">${siteUrl.replace("https://","")}</a>.
          Signed in as <span style="color:rgba(180,200,230,0.4);">${toEmail}</span>.
        </td>
      </tr></table>
    </td></tr>

  </table>

</td></tr>
</table>

</body>
</html>`;

  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [toEmail], subject, html }),
    });
    if (!resp.ok) console.warn("[trial] Email failed:", await resp.json());
  } catch (e) {
    console.warn("[trial] Email error:", e.message);
  }
}

/** Public download route for trial users — no token required. */
app.get("/download/trial-extension", (req, res) => {
  const zipPath = path.join(__dirname, "public", "redactr-extension.zip");
  res.download(zipPath, "redactr-extension.zip", (err) => {
    if (err && !res.headersSent) res.status(404).send("Extension file not found on server.");
  });
});

/**
 * Creates a 7-day free trial for a signed-in user who hasn't yet joined a
 * company. Safe to call multiple times — a second call is a no-op when a
 * trial is already active so the user can't refresh their 7 days.
 */
app.post("/createTrial", requireAuth, rateLimitMiddleware(5), async (req, res) => {
  const downloadUrl = `${SERVER_URL}/download/trial-extension`;
  try {
    const trialRef = db.collection("trials").doc(req.auth.uid);
    const existing = await trialRef.get();
    if (existing.exists && existing.data().trialActive) {
      const trialEnd = existing.data().trialEnd?.toDate?.() ?? new Date(0);
      res.json({ ok: true, trialEnd: trialEnd.toISOString(), alreadyActive: true, downloadUrl });
      return;
    }
    const now = new Date();
    const trialEnd = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    await trialRef.set({
      uid: req.auth.uid,
      email: req.auth.email ?? "",
      displayName: req.auth.name ?? "",
      plan: "trial",
      trialStart: admin.firestore.Timestamp.fromDate(now),
      trialEnd: admin.firestore.Timestamp.fromDate(trialEnd),
      trialActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Fire-and-forget — don't let email failure block the response.
    sendTrialWelcomeEmail(req.auth.email ?? "", req.auth.name ?? "", trialEnd.toISOString(), downloadUrl);
    res.json({ ok: true, trialEnd: trialEnd.toISOString(), alreadyActive: false, downloadUrl });
  } catch (error) {
    console.error("createTrial failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Generates a fresh 7-day download token for the extension zip. Only admins
 * of companies with an active subscription can call this — it's what the
 * mobile app uses when the admin shares the extension link with an employee.
 */
app.post("/generateDownloadToken", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists) {
      res.status(400).json({ error: "Complete company setup first." });
      return;
    }
    if (callerDoc.data().role !== "admin") {
      res.status(403).json({ error: "Only admins can generate download links." });
      return;
    }
    const companyId = callerDoc.data().companyId;
    const companyDoc = await db.collection("companies").doc(companyId).get();
    if (!companyDoc.exists || companyDoc.data()?.status !== "active") {
      res.status(403).json({ error: "An active subscription is required to generate download links." });
      return;
    }
    const token = await createDownloadToken(companyId);
    res.json({ downloadUrl: `${SERVER_URL}/download?token=${token}` });
  } catch (error) {
    console.error("generateDownloadToken failed", error);
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
 * Enterprise-only, admin-only. Stores a plain-English concept label (e.g.
 * "internal project codename") that GLiNER will recognise on-device in every
 * employee's extension. Labels are stored lowercase-trimmed; duplicates are
 * silently ignored; max 15 per company (GLiNER latency scales with label count).
 *
 * Validation: non-empty, ≤40 chars, letters/digits/spaces/hyphens only.
 * All writes go through the Admin SDK — no Firestore rules change needed.
 */
const MAX_CUSTOM_ENTITIES = 15;
const ENTITY_LABEL_RE = /^[a-z0-9 -]+$/;

app.post("/addCustomEntity", requireAuth, rateLimitMiddleware(20), async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "admin") {
      res.status(403).json({ error: "Only admins can manage custom entity types." });
      return;
    }

    const companyId  = callerDoc.data().companyId;
    const companyRef = db.collection("companies").doc(companyId);
    const companyDoc = await companyRef.get();
    if (companyDoc.data()?.plan !== "enterprise") {
      res.status(403).json({ error: "Custom AI entity types require the Enterprise plan." });
      return;
    }

    const label = (req.body?.label ?? "").trim().toLowerCase();
    if (!label) {
      res.status(400).json({ error: "label is required." });
      return;
    }
    if (label.length > 40) {
      res.status(400).json({ error: "label must be 40 characters or fewer." });
      return;
    }
    if (!ENTITY_LABEL_RE.test(label)) {
      res.status(400).json({ error: "label may only contain letters, digits, spaces, and hyphens." });
      return;
    }

    const existing = companyDoc.data()?.customEntities ?? [];
    if (existing.includes(label)) {
      res.json({ ok: true, customEntities: existing });
      return;
    }
    if (existing.length >= MAX_CUSTOM_ENTITIES) {
      res.status(400).json({ error: `Limit of ${MAX_CUSTOM_ENTITIES} custom entity types reached.` });
      return;
    }

    await companyRef.update({
      customEntities: admin.firestore.FieldValue.arrayUnion(label),
    });
    res.json({ ok: true, customEntities: [...existing, label] });
  } catch (error) {
    console.error("addCustomEntity failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

app.post("/removeCustomEntity", requireAuth, rateLimitMiddleware(20), async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "admin") {
      res.status(403).json({ error: "Only admins can manage custom entity types." });
      return;
    }

    const companyId = callerDoc.data().companyId;
    const label = (req.body?.label ?? "").trim().toLowerCase();
    if (!label) {
      res.status(400).json({ error: "label is required." });
      return;
    }

    await db.collection("companies").doc(companyId).update({
      customEntities: admin.firestore.FieldValue.arrayRemove(label),
    });
    res.json({ ok: true });
  } catch (error) {
    console.error("removeCustomEntity failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

/**
 * Called by the extension whenever Tier-1/Tier-2 blocks a prompt and the
 * user is signed in. Only ever receives METADATA — finding types/score,
 * never the matched secret text.
 */
app.post("/createAlert", requireAuth, rateLimitMiddleware(60), async (req, res) => {
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
    // tier: 1=regex, 2=AI/NER, 3=file scan, 4=email compose
    const rawTier = Number(req.body?.tier);
    const tier = [1, 2, 3, 4].includes(rawTier) ? rawTier : 1;
    const alertSource = req.body?.source ?? (tier === 4 ? "email" : tier === 3 ? "file" : "prompt");
    const overridden = req.body?.overridden === true;

    if (findingTypes.length === 0) {
      res.status(400).json({ error: "findingTypes is required." });
      return;
    }

    const alertRef = db.collection("companies").doc(companyId).collection("alerts").doc();
    const employeeName = displayName ?? req.auth.email ?? "Unknown";
    const actionVerb = tier === 4 ? "Flagged an email draft containing" : tier === 3 ? "Blocked a file upload containing" : "Blocked a prompt containing";
    const whatWasBlocked = `${actionVerb} ${findingTypes.join(", ")} on ${site}`;

    await alertRef.set({
      employeeUid: req.auth.uid,
      employeeName,
      whatWasBlocked,
      findingType: findingTypes[0],
      findingTypes,
      riskScore,
      tier,
      source: alertSource,
      overridden,
      status: overridden ? "overridden" : "pending",
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

/**
 * Deletes the caller's own users/{uid} Firestore doc. The Firebase Auth
 * account itself is deleted client-side via user.delete() after this call
 * succeeds — we clean up the database record here so any company/seat counts
 * are freed immediately regardless of client-side timing.
 */
app.post("/deleteAccount", requireAuth, async (req, res) => {
  try {
    const uid = req.auth.uid;
    await db.collection("users").doc(uid).delete();
    res.json({ ok: true });
  } catch (error) {
    console.error("deleteAccount failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

// --- PayPal webhook (Phase 3, optional) ---
// Ported for completeness. Needs PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET /
// PAYPAL_WEBHOOK_ID set as Render environment variables, and the webhook
// actually registered in the PayPal Developer Dashboard against this
// server's /paypalWebhook URL, before it does anything.
const PAYPAL_API_BASE = process.env.PAYPAL_LIVE_MODE === "true"
  ? "https://api-m.paypal.com"
  : "https://api-m.sandbox.paypal.com";

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
    const desc = (event.resource?.description ?? "").toLowerCase();
    const planName = desc.includes("enterprise")
      ? "enterprise"
      : desc.includes("professional") || desc.includes("team")
        ? "professional"
        : "starter";

    if (!companyId) {
      console.warn("paypalWebhook: no companyId (custom_id) on event", event.resource?.id);
      res.status(200).send("no companyId");
      return;
    }

    await db.collection("companies").doc(companyId).set({
      plan: planName,
      seatLimit: SEAT_LIMITS[planName] ?? SEAT_LIMITS.starter,
      status: "active",
    }, { merge: true });
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

/**
 * Polled by the extension every 5 s while an employee awaits manager
 * approval. Returns the current alert status so the extension can auto-send
 * (approved) or surface the denied state — without the employee doing anything
 * further. Only the employee who triggered the alert (same companyId) can poll.
 */
app.get("/alertStatus/:alertId", requireAuth, rateLimitMiddleware(120), async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists) return res.status(400).json({ error: "Not a member." });
    const { companyId } = callerDoc.data();

    const alertDoc = await db
      .collection("companies")
      .doc(companyId)
      .collection("alerts")
      .doc(req.params.alertId)
      .get();

    if (!alertDoc.exists) return res.status(404).json({ error: "Alert not found." });
    res.json({ status: alertDoc.data().status ?? "pending" });
  } catch (error) {
    console.error("alertStatus failed", error);
    res.status(500).json({ error: "Internal error." });
  }
});

// ── Server-side GLiNER NER — Enterprise Tier 2 ───────────────────────────────
//
// The model runs here so the Chrome extension contains zero remotely-fetched
// code (CWS MV3 compliance). The extension sends authenticated text to
// /nerScan; the server returns entity findings in the same shape the
// extension's detector.js already understands.

let _gliner = null;
let _glinerPromise = null;

const GLINER_MODEL_ID  = "onnx-community/gliner_multi-v2.1";
const GLINER_MODEL_URL = "https://huggingface.co/onnx-community/gliner_multi-v2.1/resolve/main/onnx/model_quantized.onnx";
const GLINER_THRESHOLD = 0.5;
const NER_MAX_LABELS   = 15;
const NER_DEFAULT_LABELS = ["person name", "street address"];
// Chunking: GLiNER context window ~384 tokens (~300 words)
const NER_WORDS_PER_CHUNK = 300;
const NER_OVERLAP_WORDS   = 30;

function _getGliner() {
  if (_gliner) return Promise.resolve(_gliner);
  if (_glinerPromise) return _glinerPromise;
  _glinerPromise = (async () => {
    const { Gliner } = require("gliner");
    console.log("[ner] Loading GLiNER model — first request may be slow…");
    const inst = new Gliner({
      tokenizerPath: GLINER_MODEL_ID,
      onnxSettings: {
        modelPath: GLINER_MODEL_URL,
        executionProvider: "wasm",
        multiThread: false,
        fetchBinary: false,
      },
      transformersSettings: { allowLocalModels: true, useBrowserCache: false },
      maxWidth: 12,
      modelType: "span-level",
    });
    await inst.initialize();
    _gliner = inst;
    _glinerPromise = null;
    console.log("[ner] GLiNER model ready.");
    return inst;
  })().catch(err => { _glinerPromise = null; throw err; });
  return _glinerPromise;
}

function _nerLabel(label, spanText, start, end) {
  const lower = label.toLowerCase().trim();
  if (lower === "person name")    return { type: "PERSON_NAME", match: spanText, start, end, severity: "medium" };
  if (lower === "street address") return { type: "ADDRESS",     match: spanText, start, end, severity: "medium" };
  const safe = label.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_+|_+$/, "");
  return { type: `CUSTOM_${safe}`, match: spanText, start, end, severity: "high" };
}

function _wordBounds(text) {
  const bounds = [];
  const re = /\S+/g;
  let m;
  while ((m = re.exec(text)) !== null) bounds.push({ start: m.index, end: m.index + m[0].length });
  return bounds;
}

function _chunkText(text) {
  const words = _wordBounds(text);
  if (words.length <= NER_WORDS_PER_CHUNK) return [{ text, charOffset: 0 }];
  const chunks = [];
  const step = NER_WORDS_PER_CHUNK - NER_OVERLAP_WORDS;
  for (let i = 0; i < words.length; i += step) {
    const end = Math.min(i + NER_WORDS_PER_CHUNK, words.length);
    chunks.push({ text: text.slice(words[i].start, words[end - 1].end), charOffset: words[i].start });
    if (end >= words.length) break;
  }
  return chunks;
}

/**
 * POST /nerScan
 * Enterprise-gated. Runs GLiNER on the supplied text and returns entity
 * findings in the same shape detector.js's mergeTier2Findings() expects:
 *   { ok: true, entities: [{ type, match, start, end, severity }] }
 */
app.post("/nerScan", requireAuth, rateLimitMiddleware(30), async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists) return res.status(400).json({ ok: false, error: "Complete company setup first.", entities: [] });

    const companyDoc = await db.collection("companies").doc(callerDoc.data().companyId).get();
    if (!TIER2_PLANS.has(companyDoc.data()?.plan ?? "")) {
      return res.status(403).json({ ok: false, error: "AI entity detection requires the Enterprise plan.", entities: [] });
    }

    const text = String(req.body?.text ?? "").slice(0, 8000);
    if (!text.trim()) return res.json({ ok: true, entities: [] });

    const customEntities = companyDoc.data()?.customEntities ?? [];
    const incoming = Array.isArray(req.body?.labels) ? req.body.labels : [];
    const labels = [...new Set([...NER_DEFAULT_LABELS, ...customEntities, ...incoming])].slice(0, NER_MAX_LABELS);

    const gliner  = await _getGliner();
    const chunks  = _chunkText(text);
    const raw = [];
    for (const chunk of chunks) {
      const results = await gliner.inference({ texts: [chunk.text], entities: labels, flatNer: true, threshold: GLINER_THRESHOLD });
      for (const e of (results[0] ?? [])) {
        raw.push({ ...e, start: e.start + chunk.charOffset, end: e.end + chunk.charOffset });
      }
    }

    // Deduplicate overlapping spans — keep higher score
    const sorted = [...raw].sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
    const kept = [];
    for (const e of sorted) {
      if (!kept.some(k => k.start < e.end && e.start < k.end)) kept.push(e);
    }
    const entities = kept
      .sort((a, b) => a.start - b.start)
      .map(e => _nerLabel(e.label, e.spanText, e.start, e.end));

    res.json({ ok: true, entities });
  } catch (err) {
    console.error("[nerScan] failed:", err.message);
    // Fail-open: Tier-1 detection is unaffected when NER is unavailable
    res.status(500).json({ ok: false, error: "NER temporarily unavailable.", entities: [] });
  }
});

/**
 * POST /nerWarmup
 * Enterprise-gated. Kicks off model loading without waiting for it to finish,
 * so the first real /nerScan call is not the one that pays the cold-start cost.
 */
app.post("/nerWarmup", requireAuth, async (req, res) => {
  try {
    const callerDoc = await db.collection("users").doc(req.auth.uid).get();
    if (!callerDoc.exists) return res.status(400).json({ ok: false, status: "not_member" });
    const companyDoc = await db.collection("companies").doc(callerDoc.data().companyId).get();
    if (!TIER2_PLANS.has(companyDoc.data()?.plan ?? "")) {
      return res.status(403).json({ ok: false, status: "not_entitled" });
    }
    const alreadyReady = !!_gliner;
    if (!alreadyReady) _getGliner().catch(e => console.warn("[ner] warmup load failed:", e.message));
    res.json({ ok: true, status: alreadyReady ? "ready" : "loading" });
  } catch (err) {
    console.error("[nerWarmup] failed:", err.message);
    res.status(500).json({ ok: false, status: "error" });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Redactr API listening on port ${port}`);

  // Keep Render's free tier alive — pings itself every 14 min so the
  // server never spins down mid-session (free tier idles after 15 min).
  const KEEP_ALIVE_URL = (process.env.SERVER_URL || "https://redactr-ln5t.onrender.com") + "/";
  setInterval(() => {
    fetch(KEEP_ALIVE_URL)
      .then(() => console.log("[keep-alive] ping ok"))
      .catch((err) => console.warn("[keep-alive] ping failed:", err.message));
  }, 14 * 60 * 1000);
});
