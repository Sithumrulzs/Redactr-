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
      'AWS & OpenAI API Key Detection',
      'Email & Phone Redaction',
      'Credit Card Protection (Luhn-validated)',
      'Chrome & Edge Extension',
      'Manager Mobile App (Dashboard, Alerts, Insights)',
      'Up to 5 employee seats',
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
      'Up to 25 employee seats',
      'Priority Support'
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
      'Unlimited employee seats',
      'AI Name & Address Detection (on-device)',
      'Custom Keyword Detection',
      'Dedicated Account Manager',
      'Custom Contracts'
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
