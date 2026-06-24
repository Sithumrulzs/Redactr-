/**
 * Firebase Auth (Google sign-in) for the marketing site. Loaded as an ES
 * module — no build step, consistent with the rest of the site's plain
 * HTML/CSS/JS, the same way the PayPal SDK is loaded via a CDN <script>
 * in checkout.html.
 *
 * This account is currently informational only — it doesn't gate pricing
 * or checkout yet (that's Phase 3's entitlement work). It exists so a
 * visitor's identity is consistent across the site and the app/extension,
 * all backed by the same Firebase project.
 */
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js";
import {
  getAuth,
  GoogleAuthProvider,
  signInWithPopup,
  signOut,
  onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js";
import { getFirestore, doc, getDoc } from "https://www.gstatic.com/firebasejs/11.0.2/firebase-firestore.js";

// TODO(checkpoint): replace with the real Firebase Web app config from
// Firebase console -> Project settings -> General -> Your apps -> Web app.
const FIREBASE_CONFIG = {
  apiKey: "REPLACE_ME",
  authDomain: "REPLACE_ME.firebaseapp.com",
  projectId: "REPLACE_ME",
  appId: "REPLACE_ME",
};

const app = initializeApp(FIREBASE_CONFIG);
const auth = getAuth(app);
const firestore = getFirestore(app);
const provider = new GoogleAuthProvider();

export function signInWithGoogle() {
  return signInWithPopup(auth, provider);
}

export function signOutUser() {
  return signOut(auth);
}

export function onAuthChange(callback) {
  return onAuthStateChanged(auth, callback);
}

export function getCurrentUser() {
  return auth.currentUser;
}

/**
 * Used by checkout.js to attach a custom_id (companyId) to the PayPal
 * order so the paypalWebhook Cloud Function knows which company to
 * credit. Returns null if this user hasn't completed company setup in
 * the app yet (claimOrJoinCompany hasn't run for them).
 */
export async function getCompanyId(uid) {
  const snapshot = await getDoc(doc(firestore, "users", uid));
  return snapshot.exists() ? snapshot.data().companyId ?? null : null;
}

/**
 * Renders the "Sign in" link / signed-in name+avatar in the page header.
 * Call once per page after the DOM is ready — see the inline <script>
 * at the bottom of each page's <body>.
 */
export function mountAuthUI() {
  const container = document.getElementById("auth-area");
  if (!container) return;

  function render(user) {
    if (user) {
      container.innerHTML = `
        <div class="auth-chip">
          <img src="${user.photoURL ?? ""}" alt="" class="auth-avatar" />
          <span>${user.displayName ?? user.email}</span>
          <button id="auth-sign-out" class="auth-link">Sign out</button>
        </div>
      `;
      document.getElementById("auth-sign-out").addEventListener("click", () => signOutUser());
    } else {
      container.innerHTML = `<button id="auth-sign-in" class="auth-link">Sign in</button>`;
      document.getElementById("auth-sign-in").addEventListener("click", () => {
        signInWithGoogle().catch((error) => console.error("Sign-in failed", error));
      });
    }
  }

  onAuthChange(render);
}
