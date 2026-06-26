/* ===================================================
   REDACTR — checkout.js
   PayPal Sandbox + Invoice Generation
=================================================== */

document.addEventListener('DOMContentLoaded', () => {

  const cart = (window.getCart && getCart()) || null;
  const API_BASE_URL = (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1' || window.location.hostname === '0.0.0.0' || window.location.protocol === 'file:')
    ? 'http://localhost:3000'
    : 'https://redactr-ln5t.onrender.com';
  let businessDownloadUrl = null;

  // ── Populate order summary ────────────────────────
  const planDisplay   = document.getElementById('summaryPlanName');
  const priceDisplay  = document.getElementById('summaryPrice');
  const totalDisplay  = document.getElementById('summaryTotal');
  const planBadge     = document.getElementById('orderPlanBadge');
  const planPriceBig  = document.getElementById('orderPlanPrice');

  if (!cart) {
    if (planDisplay) planDisplay.textContent = 'No plan selected';
    if (priceDisplay) priceDisplay.textContent = '$0.00';
    if (totalDisplay) totalDisplay.textContent = '$0.00';
    showNoPlanMessage();
    return;
  }

  const tax   = +(cart.price * 0.1).toFixed(2);
  const total = +(cart.price + tax).toFixed(2);

  if (planDisplay)  planDisplay.textContent  = `${cart.name} Plan`;
  if (priceDisplay) priceDisplay.textContent = `$${cart.price}.00`;
  if (totalDisplay) totalDisplay.textContent = `$${total.toFixed(2)}`;
  if (planBadge)    planBadge.textContent    = cart.name;
  if (planPriceBig) planPriceBig.textContent = `$${cart.price}/mo`;

  // ── PayPal Sandbox Button ─────────────────────────
  const ppContainer = document.getElementById('paypal-button-container');

  if (ppContainer && typeof paypal !== 'undefined') {
    paypal.Buttons({
      style: {
        layout: 'vertical',
        color:  'blue',
        shape:  'rect',
        label:  'pay'
      },

      // Validates before PayPal's popup even opens — without this, someone
      // could pay with no business email/company name, /createSubscription
      // would fail server-side, and they'd see a "Payment successful"
      // invoice with a download button that silently never works.
      onClick: (data, actions) => {
        const email = document.getElementById('billingEmail')?.value.trim();
        const company = document.getElementById('billingCompany')?.value.trim();
        if (!email || !company) {
          showToast('Enter your business email and company name before paying.', 'warning');
          return actions.reject();
        }
        return actions.resolve();
      },

      createOrder: (data, actions) => {
        return actions.order.create({
          purchase_units: [{
            amount: {
              value: total.toFixed(2),
              currency_code: 'USD',
              breakdown: {
                item_total: { value: cart.price.toFixed(2), currency_code: 'USD' },
                tax_total:  { value: tax.toFixed(2), currency_code: 'USD' }
              }
            },
            description: `Redactr ${cart.name} Plan — Monthly Subscription`,
            items: [{
              name:     `Redactr ${cart.name}`,
              quantity: '1',
              unit_amount: { value: cart.price.toFixed(2), currency_code: 'USD' },
              category: 'DIGITAL_GOODS'
            }]
          }]
        });
      },

      onApprove: (data, actions) => {
        return actions.order.capture().then(async details => {
          const txId = details.id || 'RDCTR-' + Date.now();
          await submitSubscription(txId);
          generateInvoice(cart, details, txId, total, tax);
          clearCart();
        });
      },

      onError: (err) => {
        console.error('PayPal error:', err);
        showToast('Payment failed. Please try again.', 'error');
      },

      onCancel: () => {
        showToast('Payment cancelled.', 'warning');
      }

    }).render('#paypal-button-container');

  } else if (ppContainer) {
    // PayPal's SDK script didn't load (ad blocker, network issue, etc.) —
    // still provisions a real company/admin invite via /createSubscription,
    // it just can't take a card payment without the SDK present.
    ppContainer.innerHTML = `
      <button class="btn btn-primary btn-block btn-lg" onclick="continueWithoutPayPal()">
        Continue — Set Up My Account
      </button>
      <p style="text-align:center;font-size:0.8rem;color:#8C95A6;margin-top:10px;">
        PayPal isn't available right now — we'll email an invoice instead.
      </p>
    `;
  }

  // ── Submits the subscription to the backend; shared by the real
  //    PayPal approval handler and the no-SDK fallback below. ──
  async function submitSubscription(txId) {
    const billingEmail = document.getElementById('billingEmail')?.value || '';
    const billingCompany = document.getElementById('billingCompany')?.value || '';
    try {
      const response = await fetch(`${API_BASE_URL}/createSubscription`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          companyId: billingCompany || `company-${txId}`,
          plan: cart.id,
          email: billingEmail,
          companyName: billingCompany,
          txId,
        }),
      });
      const payload = await response.json().catch(() => null);
      businessDownloadUrl = payload?.subscription?.downloadUrl
        ? `${API_BASE_URL}${payload.subscription.downloadUrl}`
        : null;
    } catch (error) {
      console.error('subscription sync failed', error);
    }
  }

  // ── No-PayPal fallback: still creates the real company/invite ────
  window.continueWithoutPayPal = async function() {
    const firstName = document.getElementById('billingFirst')?.value.trim() || '';
    const lastName = document.getElementById('billingLast')?.value.trim() || '';
    const email = document.getElementById('billingEmail')?.value.trim() || '';
    const company = document.getElementById('billingCompany')?.value.trim() || '';
    if (!email || !company) {
      showToast('Enter your business email and company name first.', 'warning');
      return;
    }

    const txId = 'RDCTR-' + Date.now();
    await submitSubscription(txId);
    const details = {
      id: txId,
      payer: { name: { given_name: firstName, surname: lastName }, email_address: email },
      status: 'COMPLETED',
    };
    generateInvoice(cart, details, txId, total, tax);
    clearCart();
  };

  // ── Invoice generator ─────────────────────────────
  function generateInvoice(plan, details, txId, total, tax) {
    const now      = new Date();
    const invoiceNum = 'INV-' + now.getFullYear() + '-' + String(now.getMonth()+1).padStart(2,'0') + '-' + Math.floor(Math.random()*9000+1000);
    const dateStr  = now.toLocaleDateString('en-AU', { day:'2-digit', month:'long', year:'numeric' });
    const nextDate = new Date(now); nextDate.setMonth(nextDate.getMonth()+1);
    const nextStr  = nextDate.toLocaleDateString('en-AU', { day:'2-digit', month:'long', year:'numeric' });
    const buyerName= (details?.payer?.name?.given_name || '') + ' ' + (details?.payer?.name?.surname || 'Customer');
    const buyerEmail = details?.payer?.email_address || 'customer@example.com';

    const invoiceEl = document.getElementById('invoiceContainer');
    if (!invoiceEl) return;

    invoiceEl.innerHTML = `
      <div class="invoice-header">
        <div>
          <div class="invoice-title">INVOICE</div>
          <div class="invoice-number">${invoiceNum}</div>
          <div style="font-size:0.85rem;color:#8C95A6;margin-top:4px;">Date: ${dateStr}</div>
        </div>
        <div style="text-align:right;">
          <div style="font-size:1.4rem;font-weight:800;color:#14C8A6;font-family:'Poppins',sans-serif;">Redactr</div>
          <div style="font-size:0.8rem;color:#8C95A6;">security@redactr.io</div>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:1fr 1fr;gap:32px;margin-bottom:28px;">
        <div>
          <div style="font-size:0.75rem;text-transform:uppercase;letter-spacing:.08em;color:#8C95A6;margin-bottom:8px;">Bill To</div>
          <div style="font-weight:600;">${buyerName.trim()}</div>
          <div style="font-size:0.88rem;color:#8C95A6;">${buyerEmail}</div>
        </div>
        <div>
          <div style="font-size:0.75rem;text-transform:uppercase;letter-spacing:.08em;color:#8C95A6;margin-bottom:8px;">Transaction</div>
          <div style="font-size:0.85rem;font-family:monospace;color:#14C8A6;">${txId}</div>
          <div style="font-size:0.85rem;color:#14C8A6;margin-top:4px;">✓ Payment Confirmed</div>
        </div>
      </div>

      <table class="invoice-table">
        <thead>
          <tr>
            <th>Description</th>
            <th style="text-align:right;">Qty</th>
            <th style="text-align:right;">Unit Price</th>
            <th style="text-align:right;">Amount</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>
              <div style="font-weight:600;">Redactr ${plan.name} Plan</div>
              <div style="font-size:0.8rem;color:#8C95A6;">${plan.seats} · Monthly subscription · Renewal ${nextStr}</div>
            </td>
            <td style="text-align:right;">1</td>
            <td style="text-align:right;">$${plan.price}.00</td>
            <td style="text-align:right;">$${plan.price}.00</td>
          </tr>
        </tbody>
      </table>

      <div style="max-width:280px;margin-left:auto;">
        <div class="order-line"><span style="color:#8C95A6;">Subtotal</span><span>$${plan.price}.00</span></div>
        <div class="order-line"><span style="color:#8C95A6;">GST (10%)</span><span>$${tax.toFixed(2)}</span></div>
        <div class="order-line total"><span>Total Paid</span><span style="color:#14C8A6;">$${total.toFixed(2)}</span></div>
      </div>

      <div style="margin-top:32px;text-align:center;padding:20px;background:rgba(20,200,166,0.08);border:1px solid rgba(20,200,166,0.2);border-radius:12px;">
        <div style="color:#14C8A6;margin-bottom:8px;display:flex;justify-content:center;"><svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/></svg></div>
        <div style="font-weight:700;color:#14C8A6;margin-bottom:4px;">Thank you for subscribing to Redactr!</div>
        <div style="font-size:0.85rem;color:#8C95A6;">Your team is now protected. Download the extension package below to install Redactr and unlock the features included with your ${plan.name} plan.</div>
      </div>

      <div style="margin-top:24px;display:flex;gap:12px;justify-content:center;flex-wrap:wrap;">
        <button class="btn btn-primary" onclick="printInvoice()"><svg class="icon-inline" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 6 2 18 2 18 9"/><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="8"/></svg> &nbsp;Print Invoice</button>
        <button type="button" class="btn btn-outline" onclick="window.downloadBusinessExtension()"><svg class="icon-inline" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg> Download Extension</button>
        <button class="btn btn-outline" onclick="window.location.href='../index.html'">← Back to Home</button>
      </div>
    `;

    invoiceEl.classList.add('show');

    // Hide checkout form, show invoice
    const checkoutForm = document.getElementById('checkoutFormSection');
    if (checkoutForm) checkoutForm.style.display = 'none';

    invoiceEl.scrollIntoView({ behavior: 'smooth' });
    showToast('Payment successful! Invoice generated.', 'success');
  }

  window.downloadBusinessExtension = function() {
    if (!businessDownloadUrl) {
      showToast('Business extension download is not ready yet. Please wait a moment and try again.', 'warning');
      return;
    }

    const link = document.createElement('a');
    link.href = businessDownloadUrl;
    link.target = '_blank';
    link.rel = 'noopener';
    link.download = 'redactr-business-extension.zip';
    document.body.appendChild(link);
    link.click();
    link.remove();
  };

  window.printInvoice = function() {
    window.print();
  };

  function showNoPlanMessage() {
    const container = document.getElementById('paypal-button-container');
    if (container) {
      container.innerHTML = `
        <div style="text-align:center;padding:32px;color:#8C95A6;">
          <div style="margin-bottom:12px;display:flex;justify-content:center;"><svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg></div>
          <p>No plan selected. <a href="pricing.html" style="color:#14C8A6;">Choose a plan</a> first.</p>
        </div>
      `;
    }
  }
});
