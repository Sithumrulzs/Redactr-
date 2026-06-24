# Redactr Detection Spec (Tier 1)

Single source of truth for the regex/Luhn/scoring rules implemented twice:
`redactr-extension/lib/detector.js` (JS) and `redactr_app` (no detector needed — mobile app only
consumes mock alert data, it does not scan).

## Finding shape

```
{
  type: "AWS_KEY" | "API_KEY" | "CREDIT_CARD" | "EMAIL" | "PHONE" | "IP_ADDRESS",
  match: string,        // the matched substring
  start: number,        // index into the original text
  end: number,           // exclusive
  severity: "high" | "medium" | "low"
}
```

## Patterns

| Type | Pattern | Severity | Weight |
|---|---|---|---|
| AWS_KEY | `AKIA[0-9A-Z]{16}` | high | 40 |
| API_KEY | `sk-[A-Za-z0-9]{20,}` | high | 40 |
| CREDIT_CARD | `\b(?:\d[ -]?){13,19}\b` then Luhn-validated | high | 35 |
| EMAIL | `[\w.+-]+@[\w-]+\.[\w.-]+` | low | 5 |
| PHONE | `(\+?\d{1,2}[ -]?)?(\(?\d{3}\)?[ -]?)\d{3}[ -]?\d{4}` | medium | 15 |
| IP_ADDRESS | `\b(?:\d{1,3}\.){3}\d{1,3}\b` | medium | 10 |

Credit card candidates that fail the Luhn checksum are discarded (not returned as findings) to
avoid false positives on arbitrary digit runs.

## Risk score

`score = min(100, sum(weight for each finding))`, then bucketed:

- `0–29` → green
- `30–69` → amber
- `70–100` → red

## Redaction

Findings are sorted by `start` ascending. Walking left to right, each span is replaced with an
incrementing typed token: `[AWS_KEY_1]`, `[API_KEY_1]`, `[CREDIT_CARD_1]`, `[EMAIL_1]`, `[PHONE_1]`,
`[IP_ADDRESS_1]` (counter increments per type, not globally). The original→token mapping is
returned alongside the redacted string so the caller can hold it in memory.

## Tier 2 (stretch, not implemented)

Optional unstructured PII (names/addresses) via compromise.js/wink-nlp or Transformers.js ONNX
NER, exposed behind the same `{type, match, start, end, severity}` finding shape so it can be
merged into the Tier-1 findings array without changing scoring/redaction code.
