/* ===================================================
   REDACTR — how-it-works.js
   GSAP/ScrollTrigger choreography for the 5-step pipeline:
   a progress spine that fills as you scroll, each step's number
   glowing on entry, and a per-step animation that matches what
   that step actually represents (typing, JSON output, an alert
   modal, a redaction morph, an approve/deny outcome).
=================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const stepsEl = document.getElementById('hiw-steps');
  if (!stepsEl) return; // not the how-it-works page

  if (typeof gsap === 'undefined' || typeof ScrollTrigger === 'undefined') return;
  gsap.registerPlugin(ScrollTrigger);

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ── Spine: fills as the user scrolls through the steps ──────
  const spineFill = document.getElementById('hiw-spine-fill');
  if (spineFill) {
    if (reducedMotion) {
      spineFill.style.height = '100%';
    } else {
      gsap.to(spineFill, {
        height: '100%',
        ease: 'none',
        scrollTrigger: { trigger: stepsEl, start: 'top center', end: 'bottom center', scrub: true },
      });
    }
  }

  // ── Step numbers glow as each one reaches the viewport ──────
  document.querySelectorAll('.hiw-step-num').forEach((numEl) => {
    ScrollTrigger.create({
      trigger: numEl,
      start: 'top 70%',
      onEnter: () => numEl.classList.add('active'),
      onEnterBack: () => numEl.classList.add('active'),
      onLeaveBack: () => numEl.classList.remove('active'),
    });
  });

  if (reducedMotion) return; // HTML defaults already show each step's finished state

  buildStep1();
  buildStep2();
  buildStep3();
  buildStep4();
  buildStep5();

  // ── Step 1 — typewriter across the 3 input lines ────────────
  function buildStep1() {
    const lineIds = ['hiw-line-1', 'hiw-line-2', 'hiw-line-3'];
    const lines = lineIds.map((id) => document.getElementById(id));
    const cursor = document.getElementById('hiw-cursor-1');
    if (!lines[0] || !cursor) return;
    const lengths = lines.map((el) => el.textContent.length);

    ScrollTrigger.create({
      trigger: '#hiw-step-1',
      start: 'top 65%',
      once: true,
      onEnter: () => {
        gsap.set(lines, { width: '0ch' });
        const tl = gsap.timeline();
        lines.forEach((el, i) => {
          tl.add(() => el.appendChild(cursor));
          tl.to(el, { width: `${lengths[i]}ch`, duration: Math.max(0.5, lengths[i] * 0.035), ease: 'none' });
        });
      },
    });
  }

  // ── Step 2 — JSON output lines stagger in, risk score counts up ──
  function buildStep2() {
    const jsonLines = document.querySelectorAll('#hiw-step-2 .hiw-json-line');
    const riskScoreEl = document.getElementById('hiw-risk-score');
    if (!jsonLines.length) return;

    gsap.set(jsonLines, { opacity: 0, x: -6 });
    if (riskScoreEl) riskScoreEl.textContent = '0';

    ScrollTrigger.create({
      trigger: '#hiw-step-2',
      start: 'top 65%',
      once: true,
      onEnter: () => {
        gsap.to(jsonLines, { opacity: 1, x: 0, duration: 0.35, stagger: 0.08, ease: 'power2.out' });
        if (riskScoreEl) animateCount(riskScoreEl, 105, 900);
      },
    });
  }

  // ── Step 3 — alert modal scales in, findings stagger in ──────
  function buildStep3() {
    const modal = document.getElementById('hiw-modal-preview');
    const rows = document.querySelectorAll('#hiw-step-3 .hiw-finding-row');
    if (!modal) return;

    gsap.set(modal, { opacity: 0, scale: 0.94 });
    gsap.set(rows, { opacity: 0, x: -8 });

    ScrollTrigger.create({
      trigger: '#hiw-step-3',
      start: 'top 65%',
      once: true,
      onEnter: () => {
        gsap.to(modal, { opacity: 1, scale: 1, duration: 0.4, ease: 'back.out(1.5)' });
        gsap.to(rows, { opacity: 1, x: 0, duration: 0.3, stagger: 0.1, delay: 0.25, ease: 'power2.out' });
      },
    });
  }

  // ── Step 4 — redaction morph: amber glow then turquoise tag ──
  function buildStep4() {
    const pairs = [
      ['hiw-redact-email', 'hiw-redact-email-safe'],
      ['hiw-redact-phone', 'hiw-redact-phone-safe'],
      ['hiw-redact-key', 'hiw-redact-key-safe'],
    ].map(([rawId, safeId]) => [document.getElementById(rawId), document.getElementById(safeId)]);

    if (!pairs[0][0]) return;

    pairs.forEach(([raw, safe]) => {
      gsap.set(raw, { opacity: 1, clearProps: 'color' });
      gsap.set(safe, { opacity: 0 });
    });

    ScrollTrigger.create({
      trigger: '#hiw-step-4',
      start: 'top 65%',
      once: true,
      onEnter: () => {
        const tl = gsap.timeline();
        pairs.forEach(([raw, safe], i) => {
          tl.to(raw, { color: '#F4B740', textShadow: '0 0 10px rgba(244,183,64,0.6)', duration: 0.25 }, i * 0.35)
            .to(raw, { opacity: 0, duration: 0.2 }, i * 0.35 + 0.35)
            .to(safe, { opacity: 1, duration: 0.25 }, i * 0.35 + 0.4);
        });
      },
    });
  }

  // ── Step 5 — approve/deny cards pulse to show both outcomes ──
  function buildStep5() {
    const approveCard = document.getElementById('hiw-approve-card');
    const denyCard = document.getElementById('hiw-deny-card');
    if (!approveCard || !denyCard) return;

    ScrollTrigger.create({
      trigger: '#hiw-step-5',
      start: 'top 65%',
      once: true,
      onEnter: () => {
        gsap.timeline()
          .from(approveCard, { scale: 0.85, opacity: 0.4, duration: 0.35, ease: 'back.out(1.6)' })
          .to(approveCard, { boxShadow: '0 0 24px rgba(20,200,166,0.35)', duration: 0.3 })
          .to(approveCard, { boxShadow: 'none', duration: 0.4 })
          .from(denyCard, { scale: 0.85, opacity: 0.4, duration: 0.35, ease: 'back.out(1.6)' }, '+=0.15')
          .to(denyCard, { boxShadow: '0 0 24px rgba(239,84,102,0.35)', duration: 0.3 })
          .to(denyCard, { boxShadow: 'none', duration: 0.4 });
      },
    });
  }

  function animateCount(el, to, duration) {
    const start = performance.now();
    function tick(now) {
      const progress = Math.min(1, (now - start) / duration);
      el.textContent = Math.round(to * (1 - Math.pow(1 - progress, 3)));
      if (progress < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }
});
