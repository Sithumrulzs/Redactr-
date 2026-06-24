/**
 * Mounts a PayPal sandbox Smart Button for the plan stored by cart.js and
 * renders an on-page invoice once the sandbox order is approved.
 *
 * Phase 3: the order now carries custom_id = the signed-in user's
 * companyId, so the paypalWebhook Cloud Function (firebase/functions/
 * index.js) knows which company to credit when the payment is captured.
 * Without a signed-in account that's already completed company setup in
 * the app, there's nothing to credit, so checkout is gated behind sign-in.
 */
import { onAuthChange, getCompanyId, signInWithGoogle } from "./auth.js";

document.addEventListener("DOMContentLoaded", () => {
  const plan = RedactrCart.getPlan();
  const noPlanNotice = document.getElementById("no-plan-notice");
  const planSummary = document.getElementById("plan-summary");
  const invoiceEl = document.getElementById("invoice");
  const buttonContainer = document.getElementById("paypal-button-container");
  const signInNotice = document.getElementById("sign-in-notice");

  if (!plan) {
    noPlanNotice.classList.remove("hidden");
    return;
  }

  planSummary.classList.remove("hidden");
  document.getElementById("summary-name").textContent = `${plan.name} plan`;
  document.getElementById("summary-price").textContent = `$${plan.price.toFixed(2)} / mo`;

  function renderInvoice(orderDetails) {
    const invoiceNumber = `RDX-${Date.now()}`;
    const date = new Date().toLocaleString();
    const payer = orderDetails?.payer?.name?.given_name || "Sandbox Customer";

    invoiceEl.innerHTML = `
      <h2>Payment confirmed</h2>
      <p>Thanks, ${payer}. Your subscription is active.</p>
      <table>
        <tr><td>Invoice #</td><td>${invoiceNumber}</td></tr>
        <tr><td>Date</td><td>${date}</td></tr>
        <tr><td>Plan</td><td>${plan.name}</td></tr>
        <tr><td>Amount</td><td>$${plan.price.toFixed(2)} USD / mo</td></tr>
        <tr><td>Order ID</td><td>${orderDetails?.id || "N/A"}</td></tr>
        <tr><td>Status</td><td>${orderDetails?.status || "COMPLETED"}</td></tr>
      </table>
      <p class="bodySmall">Your plan unlocks once PayPal's webhook confirms the payment — usually within a few seconds.</p>
    `;
    invoiceEl.classList.remove("hidden");
    buttonContainer.classList.add("hidden");
    RedactrCart.clearPlan();
  }

  function renderPayPalButtons(companyId) {
    if (typeof paypal === "undefined") {
      console.error("PayPal SDK failed to load.");
      return;
    }

    paypal
      .Buttons({
        style: { layout: "vertical", color: "blue", shape: "rect", label: "paypal" },
        createOrder: (data, actions) =>
          actions.order.create({
            purchase_units: [
              {
                description: `Redactr ${plan.name} plan subscription`,
                amount: { value: plan.price.toFixed(2) },
                custom_id: companyId,
              },
            ],
          }),
        onApprove: (data, actions) =>
          actions.order.capture().then((orderDetails) => renderInvoice(orderDetails)),
        onError: (err) => {
          console.error("PayPal checkout error:", err);
          alert("Sandbox checkout failed. Please try again.");
        },
      })
      .render("#paypal-button-container");
  }

  function showSignInPrompt() {
    buttonContainer.classList.add("hidden");
    signInNotice.classList.remove("hidden");
    document.getElementById("checkout-sign-in").addEventListener("click", () => {
      signInWithGoogle().catch((error) => console.error("Sign-in failed", error));
    });
  }

  onAuthChange(async (user) => {
    if (!user) {
      showSignInPrompt();
      return;
    }

    const companyId = await getCompanyId(user.uid);
    if (!companyId) {
      showSignInPrompt();
      return;
    }

    signInNotice?.classList.add("hidden");
    buttonContainer.classList.remove("hidden");
    buttonContainer.innerHTML = "";
    renderPayPalButtons(companyId);
  });
});
