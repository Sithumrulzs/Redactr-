/**
 * Redactr Tier-1 detection engine (deterministic regex + Luhn).
 * Spec: ../../shared/detection-rules.md
 *
 * Loaded as a classic script in the content script context (no ES modules),
 * and via module.exports when required from Node for testing.
 */
(function (root) {
  "use strict";

  const PATTERNS = [
    // ── AWS ────────────────────────────────────────────────────────────────

    // AWS Access Key ID
    { type: "AWS_KEY", severity: "high", weight: 40,
      regex: /\bAKIA[0-9A-Z]{16}\b/g },

    // AWS temporary session token (STS) — starts with ASIA, much longer
    { type: "AWS_KEY", severity: "high", weight: 40,
      regex: /\bASIA[0-9A-Z]{16}\b/g },

    // AWS Secret Access Key (40-char alphanumeric+/+) — only reliable with key-name context
    { type: "AWS_KEY", severity: "high", weight: 40,
      regex: /(?:aws_secret_access_key|AWS_SECRET_ACCESS_KEY|secret_access_key|SecretAccessKey)\s*[=:]\s*["']?([A-Za-z0-9/+]{40})["']?/g },

    // ── OpenAI ────────────────────────────────────────────────────────────

    // Legacy sk-XXX, project-scoped sk-proj-XXX, service sk-svcacct-XXX
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /sk-(?:proj-|svcacct-)[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}/g },

    // OpenAI organisation ID
    { type: "API_KEY", severity: "medium", weight: 30,
      regex: /\borg-[A-Za-z0-9]{24}\b/g },

    // ── Anthropic ─────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /sk-ant-(?:api03-)?[A-Za-z0-9_-]{20,}/g },

    // ── Google / GCP / Firebase ───────────────────────────────────────────

    // Google browser / server API key
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /AIza[0-9A-Za-z_-]{35}/g },

    // Google OAuth client secret embedded in JSON
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /"client_secret"\s*:\s*"GOCSPX-[A-Za-z0-9_-]{28}"/g },

    // Firebase service-account JSON block (private_key + client_email together)
    { type: "PRIVATE_KEY", severity: "high", weight: 50,
      regex: /"private_key"\s*:\s*"-----BEGIN [A-Z]+ PRIVATE KEY-----/g },

    // ── GitHub ────────────────────────────────────────────────────────────
    // Classic PAT (ghp_), OAuth app (gho_), Actions (ghs_), Refresh (ghr_), User (ghu_), fine-grained
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,82}/g },

    // ── Stripe ────────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /(?:sk|pk|rk)_(?:live|test)_[0-9a-zA-Z]{24,}|whsec_[A-Za-z0-9]{32,}/g },

    // ── Slack ─────────────────────────────────────────────────────────────
    // Bot/user/app/socket tokens + incoming webhook URL
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /xox[bpsoar]-[0-9A-Za-z_-]{10,}|https:\/\/hooks\.slack\.com\/services\/T[A-Za-z0-9_]+\/B[A-Za-z0-9_]+\/[A-Za-z0-9_]+/g },

    // ── SendGrid ──────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}/g },

    // ── HuggingFace ───────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /hf_[a-zA-Z0-9]{34,}/g },

    // ── npm ───────────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /npm_[A-Za-z0-9]{36}/g },

    // ── GitLab ────────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /glpat-[A-Za-z0-9_-]{20}/g },

    // ── Twilio ────────────────────────────────────────────────────────────
    // Account SID (AC...) and Auth Token in variable context
    { type: "API_KEY", severity: "medium", weight: 35,
      regex: /\bAC[a-f0-9]{32}\b/g },

    { type: "API_KEY", severity: "high", weight: 40,
      regex: /(?:auth_?token|TWILIO_AUTH_TOKEN)\s*[=:]\s*["']?[a-f0-9]{32}["']?/g },

    // ── Notion ────────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /secret_[A-Za-z0-9]{43}/g },

    // ── Shopify ───────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /shp(?:at|ss|ca|pa)_[a-fA-F0-9]{32}/g },

    // ── Groq ──────────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /gsk_[A-Za-z0-9]{52}/g },

    // ── Replicate ─────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /r8_[A-Za-z0-9]{40}/g },

    // ── Cohere ────────────────────────────────────────────────────────────
    // Key format: CO- prefix or raw alphanumeric when named in context
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /\bCO-[a-zA-Z0-9_-]{36,48}\b/g },

    // ── Mistral AI ────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /\bmistral-[A-Za-z0-9]{32,}\b/g },

    // ── Discord ───────────────────────────────────────────────────────────
    // Bot token: base64(user_id).base64(timestamp).hmac  — three fixed-length segments
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /[A-Za-z0-9_-]{23,28}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27,38}/g },

    // ── Telegram ──────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /\b\d{8,10}:[A-Za-z0-9_-]{35}\b/g },

    // ── New Relic ─────────────────────────────────────────────────────────
    // User API key (NRAK), Admin (NRAA), Browser (NRJS), Insights Insert (NRII)
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /NR(?:AK|AA|JS|II)-[A-Za-z0-9]{20,40}/g },

    // ── Square ────────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /sq0(?:atp|atb|csp|ath)-[A-Za-z0-9_-]{22,43}/g },

    // ── Databricks ────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /dapi[a-f0-9]{32}/g },

    // ── DigitalOcean ──────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /dop_v1_[a-f0-9]{64}/g },

    // ── Mailchimp ─────────────────────────────────────────────────────────
    // 32 hex chars + datacenter suffix e.g. abc123...-us12
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /[0-9a-f]{32}-us\d{1,2}\b/g },

    // ── Mailgun ───────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /key-[0-9a-f]{32}/g },

    // ── Braintree ─────────────────────────────────────────────────────────
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /access_token\$(?:production|sandbox)\$[a-z0-9]{16}\$[a-f0-9]{32}/g },

    // ── Mapbox ────────────────────────────────────────────────────────────
    // Secret tokens start with sk.eyJ (public pk.eyJ caught by JWT rule below)
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /sk\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}/g },

    // ── Cloudinary ────────────────────────────────────────────────────────
    { type: "CONNECTION_STRING", severity: "high", weight: 45,
      regex: /cloudinary:\/\/[0-9]+:[A-Za-z0-9_-]{27}@[a-z0-9]+/g },

    // ── Azure ─────────────────────────────────────────────────────────────
    // Storage account connection string
    { type: "AZURE_SECRET", severity: "high", weight: 45,
      regex: /DefaultEndpointsProtocol=https;AccountName=[^;\s]+;AccountKey=[^;\s]+/g },

    // Service Bus / Event Hubs connection string
    { type: "AZURE_SECRET", severity: "high", weight: 45,
      regex: /Endpoint=sb:\/\/[^;\s]+;SharedAccessKeyName=[^;\s]+;SharedAccessKey=[^;\s]+/g },

    // ── Database / service connection strings with embedded credentials ────
    // MongoDB Atlas  (mongodb+srv://user:pass@cluster...)
    { type: "CONNECTION_STRING", severity: "high", weight: 45,
      regex: /mongodb(?:\+srv)?:\/\/[^:@\s]{1,128}:[^@\s]{4,}@[a-zA-Z0-9][^\s]*/g },

    // PostgreSQL, MySQL, Redis, AMQP, CockroachDB, SQL Server
    { type: "CONNECTION_STRING", severity: "high", weight: 45,
      regex: /(?:postgres(?:ql)?|mysql(?:2)?|redis|amqps?|cockroachdb|sqlserver|mssql):\/\/[^:@\s]{1,128}:[^@\s]{4,}@[a-zA-Z0-9][^\s]*/g },

    // HTTPS URLs with long embedded tokens (e.g. git clone https://user:ghp_TOKEN@github.com)
    { type: "API_KEY", severity: "high", weight: 40,
      regex: /https?:\/\/[^:@\s]{1,64}:[^@\s]{20,}@[a-zA-Z0-9][^\s]*/g },

    // ── Private keys & certificates ───────────────────────────────────────
    // PEM private-key block header (RSA, EC, OPENSSH, PKCS8, generic)
    { type: "PRIVATE_KEY", severity: "high", weight: 50,
      regex: /-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----/g },

    // PEM certificate (sometimes contains embedded keys or is itself sensitive)
    { type: "PRIVATE_KEY", severity: "medium", weight: 35,
      regex: /-----BEGIN CERTIFICATE-----/g },

    // JWT (three base64url segments — catches bearer tokens, Firebase JWTs, etc.)
    // Listed after Mapbox sk.eyJ so Mapbox secret tokens get the higher-weight rule.
    { type: "API_KEY", severity: "medium", weight: 30,
      regex: /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g },

    // ── Identity numbers ───────────────────────────────────────────────────
    // US Social Security Number: 123-45-6789 or 123 45 6789
    { type: "SSN", severity: "high", weight: 40,
      regex: /\b\d{3}[-\s]\d{2}[-\s]\d{4}\b/g },

    // UK National Insurance Number: AB 12 34 56 C (or no spaces, case-insensitive)
    { type: "NI_NUMBER", severity: "high", weight: 35,
      regex: /\b[A-CEGHJ-PR-TW-Z][A-CEGHJ-NPR-TW-Z][ ]?\d{2}[ ]?\d{2}[ ]?\d{2}[ ]?[A-D]\b/gi },

    // ── Banking ────────────────────────────────────────────────────────────
    // IBAN: CC## then 2–7 groups of 4 alphanumeric (spaces optional), optional short tail
    { type: "IBAN", severity: "high", weight: 35,
      regex: /\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,6}(?:[ ]?[A-Z0-9]{1,4})?\b/g },

    // ── Contact / network ──────────────────────────────────────────────────
    { type: "EMAIL", severity: "low", weight: 5,
      regex: /[\w.+-]+@[\w-]+\.[\w.-]+/g },

    // Phone numbers: +1 800-555-1234, 077 123 4567, (212) 555-0100
    { type: "PHONE", severity: "medium", weight: 15,
      regex: /(\+?\d{1,2}[ -]?)?\(?\d{3}\)?[ -]?\d{3}[ -]?\d{4}\b/g },

    { type: "IP_ADDRESS", severity: "medium", weight: 10,
      regex: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g },
  ];

  const CREDIT_CARD_CANDIDATE = /\b(?:\d[ \-.\/]?){13,19}\b/g;

  // Weight per finding type, used for both Tier-1 regex findings and Tier-2
  // NER findings merged in by scanTier2() — see mergeTier2Findings().
  // GLiNER Tier-2 types and their weights are documented in
  // shared/detection-rules.md § "Tier 2 (GLiNER)".
  const WEIGHTS = {
    AWS_KEY: 40,
    API_KEY: 40,
    PRIVATE_KEY: 50,
    CONNECTION_STRING: 45,
    AZURE_SECRET: 45,
    CREDIT_CARD: 35,
    SSN: 40,
    IBAN: 35,
    NI_NUMBER: 35,
    EMAIL: 5,
    PHONE: 15,
    IP_ADDRESS: 10,
    PERSON: 20,
    LOCATION: 20,
    CUSTOM_KEYWORD: 30,
    PERSON_NAME: 15,
    ADDRESS: 15,
  };

  // Manager-defined GLiNER entities (CUSTOM_<LABEL>) are not in the static
  // table because their type strings are dynamic. getWeight() handles them.
  function getWeight(type) {
    if (WEIGHTS[type] !== undefined) return WEIGHTS[type];
    if (type.startsWith("CUSTOM_")) return 25; // manager-defined GLiNER entity
    return 0;
  }

  /** Escapes regex metacharacters so a literal keyword can't be misread as a pattern. */
  function escapeRegExp(string) {
    return string.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  /**
   * Enterprise-only custom keywords (see server/index.js's
   * addCustomKeyword) — deliberately literal substrings, not arbitrary
   * regex, so an admin-supplied pattern can never cause catastrophic
   * backtracking in every employee's browser.
   */
  function findCustomKeywords(text, keywords) {
    if (!Array.isArray(keywords) || keywords.length === 0) return [];
    const findings = [];
    for (const keyword of keywords) {
      if (!keyword) continue;
      const regex = new RegExp(escapeRegExp(keyword), "gi");
      let match;
      while ((match = regex.exec(text)) !== null) {
        findings.push({
          type: "CUSTOM_KEYWORD",
          match: match[0],
          start: match.index,
          end: match.index + match[0].length,
          severity: "high",
        });
        if (match[0].length === 0) regex.lastIndex++;
      }
    }
    return findings;
  }

  /** Luhn checksum: true if the digit string passes. */
  function luhnCheck(digits) {
    let sum = 0;
    let alternate = false;
    for (let i = digits.length - 1; i >= 0; i--) {
      let n = parseInt(digits[i], 10);
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 === 0;
  }

  // Explicit card formats — always blocked regardless of Luhn, because the
  // 4-4-4-4 / 4-6-5 grouping is so specific to payment cards that false
  // positives are negligible compared to the security risk of letting them through.
  const CARD_FORMAT_PATTERNS = [
    /\b\d{4}[ \-.]\d{4}[ \-.]\d{4}[ \-.]\d{4}\b/g,          // standard 16-digit (Visa/MC/etc.)
    /\b\d{4}[ \-.]\d{6}[ \-.]\d{5}\b/g,                      // Amex 15-digit
    /\b\d{4}[ \-.]\d{4}[ \-.]\d{4}[ \-.]\d{4}[ \-.]\d{3}\b/g, // 19-digit (some prepaid/gift)
    /\b3[47]\d{13}\b/g,                                        // Amex 15-digit no separator
  ];

  function findCreditCards(text) {
    const findings = [];
    const seen = new Set(); // deduplicate by start position

    // Pass 1: explicit format — block on sight, no Luhn required.
    for (const fmtRegex of CARD_FORMAT_PATTERNS) {
      fmtRegex.lastIndex = 0;
      let match;
      while ((match = fmtRegex.exec(text)) !== null) {
        if (!seen.has(match.index)) {
          seen.add(match.index);
          findings.push({ type: "CREDIT_CARD", match: match[0], start: match.index, end: match.index + match[0].length, severity: "high" });
        }
      }
    }

    // Pass 2: loose digit run — require Luhn to keep false-positive rate low for
    // unseparated sequences (e.g. order IDs, phone extensions, timestamps).
    CREDIT_CARD_CANDIDATE.lastIndex = 0;
    let match;
    while ((match = CREDIT_CARD_CANDIDATE.exec(text)) !== null) {
      if (seen.has(match.index)) continue;
      const raw = match[0];
      const digits = raw.replace(/[ \-.\/]/g, "");
      if (digits.length >= 13 && digits.length <= 19 && luhnCheck(digits)) {
        seen.add(match.index);
        findings.push({ type: "CREDIT_CARD", match: raw, start: match.index, end: match.index + raw.length, severity: "high" });
      }
    }

    return findings;
  }

  /**
   * Scan text and return Tier-1 findings plus an aggregate 0-100 risk score.
   * @param {string} text
   * @param {string[]} [customKeywords] - Enterprise-only literal phrases (see getEntitlement)
   * @returns {{findings: Array, score: number, level: "green"|"amber"|"red"}}
   */
  function scan(text, customKeywords) {
    const findings = [];

    for (const pattern of PATTERNS) {
      pattern.regex.lastIndex = 0;
      let match;
      while ((match = pattern.regex.exec(text)) !== null) {
        findings.push({
          type: pattern.type,
          match: match[0],
          start: match.index,
          end: match.index + match[0].length,
          severity: pattern.severity,
        });
      }
    }

    findings.push(...findCreditCards(text));
    findings.push(...findCustomKeywords(text, customKeywords));
    findings.sort((a, b) => a.start - b.start);

    return scoreFindings(findings);
  }

  /** Sums finding weights into a 0-100 score and a green/amber/red level. */
  function scoreFindings(findings) {
    const rawScore = findings.reduce((sum, f) => sum + getWeight(f.type), 0);
    const score = Math.min(100, rawScore);
    const level = score >= 70 ? "red" : score >= 30 ? "amber" : "green";
    return { findings, score, level };
  }

  /**
   * Merge Tier-2 NER entities (already in the {type, match, start, end,
   * severity} shape — see offscreen/offscreen.src.js) into a Tier-1 result,
   * dropping any entity that overlaps a span Tier-1 already found, and
   * recomputing the aggregate score. Tier-1's own logic is untouched.
   */
  function mergeTier2Findings(tier1Result, tier2Entities) {
    const overlaps = (a, b) => a.start < b.end && b.start < a.end;
    const additions = tier2Entities.filter(
      (entity) => !tier1Result.findings.some((f) => overlaps(f, entity))
    );
    const findings = [...tier1Result.findings, ...additions].sort(
      (a, b) => a.start - b.start
    );
    return scoreFindings(findings);
  }

  /**
   * Ask the background service worker (which proxies to the offscreen NER
   * document) to run Tier-2 detection on top of an existing Tier-1 result.
   * Browser-only: no-ops (returns the Tier-1 result unchanged) outside an
   * extension context, e.g. when this file is required from Node.
   */
  function scanTier2(text, tier1Result) {
    if (typeof chrome === "undefined" || !chrome.runtime?.sendMessage) {
      return Promise.resolve(tier1Result);
    }
    // Wrap in try/catch: chrome.runtime.sendMessage throws synchronously when
    // the extension is reloaded while this content script is still alive
    // ("Extension context invalidated"). Fall back to Tier-1 result silently.
    return new Promise((resolve) => {
      try {
        chrome.runtime.sendMessage(
          { target: "background", type: "TIER2_SCAN", text },
          (response) => {
            if (chrome.runtime.lastError || !response?.ok) {
              resolve(tier1Result);
              return;
            }
            resolve(mergeTier2Findings(tier1Result, response.entities));
          }
        );
      } catch (_) {
        // sendMessage throws synchronously when the extension is reloaded
        // while this content script is still alive ("Extension context
        // invalidated"). Resolve with Tier-1 result so the caller never sees
        // a rejection and no "Uncaught (in promise)" appears in DevTools.
        resolve(tier1Result);
      }
    });
  }

  /**
   * Replace each finding's span with an incrementing typed token.
   * @param {string} text
   * @param {Array} findings - must be the array returned by scan() (or a compatible shape)
   * @returns {{redacted: string, map: Object}} map is token -> original text
   */
  function redact(text, findings) {
    const sorted = [...findings].sort((a, b) => a.start - b.start);
    const counters = {};
    const map = {};
    let result = "";
    let cursor = 0;

    for (const finding of sorted) {
      if (finding.start < cursor) continue; // skip overlapping spans
      counters[finding.type] = (counters[finding.type] || 0) + 1;
      const token = `[${finding.type}_${counters[finding.type]}]`;
      result += text.slice(cursor, finding.start) + token;
      map[token] = text.slice(finding.start, finding.end);
      cursor = finding.end;
    }
    result += text.slice(cursor);

    return { redacted: result, map };
  }

  const RedactrDetector = { scan, redact, luhnCheck, scanTier2, mergeTier2Findings };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = RedactrDetector;
  } else {
    root.RedactrDetector = RedactrDetector;
  }
})(typeof window !== "undefined" ? window : globalThis);
