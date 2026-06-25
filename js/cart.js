/* ===================================================
   REDACTR — cart.js
   Stores selected plan in localStorage
=================================================== */

const CART_KEY = 'redactr_selected_plan';

const PLANS = {
  starter: {
    id:       'starter',
    name:     'Starter',
    price:    9,
    currency: 'USD',
    period:   'month',
    seats:    'Up to 5 seats',
    features: [
      'API Key & Secret Detection',
      'Email & Phone Redaction',
      'Credit Card Protection',
      'Chrome Extension',
      'Basic Dashboard',
      '5 manager approvals/month',
      'Email Support'
    ]
  },
  professional: {
    id:       'professional',
    name:     'Professional',
    price:    29,
    currency: 'USD',
    period:   'month',
    seats:    'Up to 25 seats',
    features: [
      'Everything in Starter',
      'Source Code Detection',
      'Advanced Risk Scoring',
      'Manager Mobile App',
      'Unlimited Approvals',
      'Team Analytics',
      'Priority Support',
      'Slack Integration'
    ]
  },
  enterprise: {
    id:       'enterprise',
    name:     'Enterprise',
    price:    99,
    currency: 'USD',
    period:   'month',
    seats:    'Unlimited seats',
    features: [
      'Everything in Professional',
      'Custom Detection Rules',
      'SSO / SAML',
      'SIEM Integration',
      'Dedicated Account Manager',
      'SLA 99.9% Uptime',
      'Custom Contracts',
      'On-premise Option'
    ]
  }
};

/* ── Save plan to cart ──────────────────────────── */
function selectPlan(planId) {
  const plan = PLANS[planId];
  if (!plan) { console.warn('Unknown plan:', planId); return; }

  localStorage.setItem(CART_KEY, JSON.stringify({
    ...plan,
    selectedAt: new Date().toISOString()
  }));

  if (window.showToast) {
    showToast(`${plan.name} plan selected!`, 'success');
  }

  setTimeout(() => {
    window.location.href = '../pages/checkout.html';
  }, 800);
}

/* ── Get cart item ──────────────────────────────── */
function getCart() {
  try {
    const raw = localStorage.getItem(CART_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

/* ── Clear cart ─────────────────────────────────── */
function clearCart() {
  localStorage.removeItem(CART_KEY);
}

/* ── Expose globally ────────────────────────────── */
window.selectPlan = selectPlan;
window.getCart    = getCart;
window.clearCart  = clearCart;
window.PLANS      = PLANS;

/* ── Highlight active plan button on pricing page ── */
document.addEventListener('DOMContentLoaded', () => {
  const cart = getCart();
  if (!cart) return;

  document.querySelectorAll('[data-plan-id]').forEach(btn => {
    if (btn.dataset.planId === cart.id) {
      btn.textContent = '✓ Selected';
      btn.classList.add('btn-primary');
      btn.classList.remove('btn-outline');
    }
  });
});
