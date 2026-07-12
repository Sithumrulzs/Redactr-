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

## Tier 2 (GLiNER)

Zero-shot NER running entirely on-device in the offscreen document via the `gliner` npm package
on top of ONNX Runtime Web.

**Model**: `onnx-community/gliner_multi-v2.1` (quantized ONNX, Apache-2.0)
**Confidence threshold**: 0.5 (named constant `GLINER_CONFIDENCE_THRESHOLD` in `offscreen.src.js`)
**Context window**: ~384 tokens — longer inputs are chunked at ~300 words with 30-word overlap;
span offsets are mapped back into the original string and overlapping findings are deduplicated
by keeping the higher-confidence span.
**Fallback**: if GLiNER fails to load, the existing `Xenova/bert-base-NER` Transformers.js
pipeline is used; if both fail, `{entities: []}` is returned and Tier-1 blocking is unaffected.

### Label → finding-type mapping

| GLiNER label | `type` field | Severity | Weight |
|---|---|---|---|
| `person name` | `PERSON_NAME` | medium | 15 |
| `street address` | `ADDRESS` | medium | 15 |
| any manager-defined label | `CUSTOM_<LABEL_UPPERCASED>` | high | 25 |

Manager-defined labels are stored lowercase-trimmed on the company Firestore document
(`customEntities[]`) and delivered to the extension via `getEntitlement`. The extension prepends
the two default labels (`person name`, `street address`) and caps the total at 15 (GLiNER
latency scales with label count). Any `CUSTOM_*` type that is not `CUSTOM_KEYWORD` is treated as
a Tier-2 finding for alert-metadata purposes.

### Tier-2 finding shape

```
{
  type: "PERSON_NAME" | "ADDRESS" | "CUSTOM_<LABEL>",
  match: string,   // matched substring from the original text
  start: number,   // index into the original (pre-chunking) string
  end: number,     // exclusive
  severity: "medium" | "high"
}
```

Findings are merged into the Tier-1 array via `mergeTier2Findings()` in `detector.js`, which
drops any Tier-2 span that overlaps a Tier-1 span and recomputes the aggregate score. Scoring,
redaction, and the approve/deny pipeline require no changes.
