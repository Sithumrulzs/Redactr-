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
    { type: "AWS_KEY", severity: "high", weight: 40, regex: /AKIA[0-9A-Z]{16}/g },
    { type: "API_KEY", severity: "high", weight: 40, regex: /sk-[A-Za-z0-9]{20,}/g },
    {
      type: "EMAIL",
      severity: "low",
      weight: 5,
      regex: /[\w.+-]+@[\w-]+\.[\w.-]+/g,
    },
    {
      type: "PHONE",
      severity: "medium",
      weight: 15,
      regex: /(\+?\d{1,2}[ -]?)?\(?\d{3}\)?[ -]?\d{3}[ -]?\d{4}\b/g,
    },
    {
      type: "IP_ADDRESS",
      severity: "medium",
      weight: 10,
      regex: /\b(?:\d{1,3}\.){3}\d{1,3}\b/g,
    },
  ];

  const CREDIT_CARD_CANDIDATE = /\b(?:\d[ -]?){13,19}\b/g;

  // Weight per finding type, used for both Tier-1 regex findings and Tier-2
  // NER findings merged in by scanTier2() — see mergeTier2Findings().
  const WEIGHTS = {
    AWS_KEY: 40,
    API_KEY: 40,
    CREDIT_CARD: 35,
    EMAIL: 5,
    PHONE: 15,
    IP_ADDRESS: 10,
    PERSON: 20,
    LOCATION: 20,
    CUSTOM_KEYWORD: 30,
  };

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

  function findCreditCards(text) {
    const findings = [];
    let match;
    CREDIT_CARD_CANDIDATE.lastIndex = 0;
    while ((match = CREDIT_CARD_CANDIDATE.exec(text)) !== null) {
      const raw = match[0];
      const digits = raw.replace(/[ -]/g, "");
      if (digits.length >= 13 && digits.length <= 19 && luhnCheck(digits)) {
        findings.push({
          type: "CREDIT_CARD",
          match: raw,
          start: match.index,
          end: match.index + raw.length,
          severity: "high",
        });
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
    const rawScore = findings.reduce((sum, f) => sum + (WEIGHTS[f.type] || 0), 0);
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
    return new Promise((resolve) => {
      chrome.runtime.sendMessage(
        { target: "background", type: "TIER2_SCAN", text },
        (response) => {
          if (!response?.ok) {
            resolve(tier1Result);
            return;
          }
          resolve(mergeTier2Findings(tier1Result, response.entities));
        }
      );
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
