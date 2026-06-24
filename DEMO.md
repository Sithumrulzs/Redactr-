# Redactr Demo Script

Fixed test inputs used throughout — keep these consistent across every walkthrough so results are
reproducible.

| Type | Value | Expected result |
|---|---|---|
| Fake AWS key | `AKIAABCDEFGHIJKLMNOP` | Detected as `AWS_KEY`, high severity |
| Fake API key | `sk-abcdefghijklmnopqrstuvwx12345` | Detected as `API_KEY`, high severity |
| Luhn-valid test card | `4111-1111-1111-1111` | Detected as `CREDIT_CARD` (passes Luhn) |
| Luhn-invalid card shape | `4111-1111-1111-1112` | NOT detected (fails Luhn — false-positive guard) |
| Sample email | `test@example.com` | Detected as `EMAIL`, low severity |
| Sample IP | `10.0.0.5` | Detected as `IP_ADDRESS`, medium severity |
| Sample phone | `415-555-2671` | Detected as `PHONE`, medium severity |
| Combined test prompt | `My AWS key is AKIAABCDEFGHIJKLMNOP and my card is 4111-1111-1111-1111` | Score 75 → red |

## 1. Website (sells)

1. Open `redactr-website/index.html` with Live Server.
2. Go to **Pricing**, select the "Team" plan → confirm `redactr_selected_plan` is set in
   localStorage and the "Continue to checkout" link appears.
3. Go to **Checkout** → confirm the plan summary renders, then complete the PayPal **sandbox**
   button flow (use any sandbox buyer account) → confirm the on-page invoice renders with an
   invoice number, date, plan, amount, and order ID, and that localStorage is cleared afterward.
4. Visit **Contact** → confirm the ABN/ACN placeholder, the Google Maps embed, and the
   "class assignment, not for commercial purpose" disclaimer are all visible.

## 2. Browser extension (enforces)

1. `chrome://extensions` → enable Developer mode → **Load unpacked** → select `redactr-extension/`.
2. Open chatgpt.com (or claude.ai / gemini.google.com), paste the combined test prompt into the
   chat box, and press Enter.
3. Confirm: the send is blocked, an inline warning banner appears showing the risk score and
   detected types (`AWS_KEY, CREDIT_CARD`), and the message was never sent.
4. Click **Copy safe version** → confirm the input now contains
   `My AWS key is [AWS_KEY_1] and my card is [CREDIT_CARD_1]` and can be sent normally.
5. Open the extension popup → confirm the "leaks prevented" counter incremented by 1, then toggle
   protection off and confirm the same prompt now sends without interception.

## 3. Mobile app (oversees)

1. `cd redactr_app && flutter run` (emulator or device).
2. Dashboard tab → confirm the team risk score circle and "recent activity" list render from the
   hardcoded mock alerts (no network needed).
3. Alerts tab → tap the "Priya Nair / AWS access key" alert → confirm the detail screen shows the
   finding type, risk score, and timestamp.
4. Tap **Approve** → go back → confirm the alert's status badge and the dashboard's pending count
   update immediately.

## What's deliberately out of scope

- No backend, no database, no server-side LLM classification — all detection is on-device.
- Real-time laptop↔phone push (extension blocks → manager approves remotely) is a stretch goal
  layered on free Firebase Cloud Messaging, not implemented here.
- Tier-2 unstructured PII/NER detection (compromise.js/wink-nlp or Transformers.js ONNX) is an
  optional stretch module, not implemented here — Tier 1 (regex + Luhn) is the complete, working
  core.
