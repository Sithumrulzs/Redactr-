/* =========================================================
   REDACTR — pricing.js
   • Spring-physics card entrance (popular rises, sides recede)
   • Toggle switch with confetti on annual billing
   • Animated NumberFlow-style counter on price change
========================================================= */

document.addEventListener('DOMContentLoaded', () => {
  const grid    = document.querySelector('.pricing-grid');
  if (!grid) return;

  const cards   = Array.from(grid.querySelectorAll('.pricing-card'));
  const toggle  = document.getElementById('prc-switch');
  if (!cards.length) return;

  /* ── Annual prices (20% off, rounded) ── */
  const ANNUAL = { starter: 7, professional: 23, enterprise: 79 };

  let isAnnual = false;

  /* ── Animated number counter ── */
  function animateNum(el, from, to) {
    const duration = 480;
    const start    = performance.now();
    const run = (now) => {
      const p    = Math.min((now - start) / duration, 1);
      const ease = 1 - Math.pow(1 - p, 3); // ease-out cubic
      el.textContent = Math.round(from + (to - from) * ease);
      if (p < 1) requestAnimationFrame(run);
    };
    requestAnimationFrame(run);
  }

  /* ── Toggle switch ── */
  if (toggle) {
    toggle.addEventListener('click', () => {
      isAnnual = !isAnnual;
      toggle.setAttribute('aria-checked', String(isAnnual));

      /* Update each card's price */
      cards.forEach(card => {
        const monthlyVal = Number(card.dataset.monthly);
        const annualVal  = Number(card.dataset.annual) ||
                           Math.round(monthlyVal * 0.8);
        const numEl      = card.querySelector('.price-num');
        const billingEl  = card.querySelector('.price-billing');

        if (numEl) {
          const from = isAnnual ? monthlyVal : annualVal;
          const to   = isAnnual ? annualVal  : monthlyVal;
          animateNum(numEl, from, to);
        }
        if (billingEl) {
          billingEl.textContent = isAnnual ? 'billed annually' : 'billed monthly';
        }
      });

      /* Confetti burst when switching to annual */
      if (isAnnual && typeof confetti !== 'undefined') {
        const rect = toggle.getBoundingClientRect();
        confetti({
          particleCount : 65,
          spread        : 72,
          origin: {
            x: (rect.left + rect.width  / 2) / window.innerWidth,
            y: (rect.top  + rect.height / 2) / window.innerHeight,
          },
          colors       : ['#14c8a6', '#5eead4', '#0d9278', '#a7f3d0', '#ffffff'],
          ticks        : 230,
          gravity      : 1.2,
          decay        : 0.93,
          startVelocity: 34,
          shapes       : ['circle'],
        });
      }
    });
  }

  /* ── Card entrance animation ── */
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reducedMotion) {
    cards.forEach(c => { c.style.opacity = '1'; c.style.transform = 'none'; });
    return;
  }

  const isDesktop = window.matchMedia('(min-width: 1025px)').matches;

  /*
   * Matches the React component's whileInView targets:
   *   index 0 → x:  30, scale: 0.94, y: 0
   *   index 1 → x:   0, scale: 1.00, y: -20  (popular, floats up)
   *   index 2 → x: -30, scale: 0.94, y: 0
   */
  const TARGETS = isDesktop
    ? [
        { y: 0,   x:  30, scale: 0.94 },
        { y: -20, x:   0, scale: 1.00 },
        { y: 0,   x: -30, scale: 0.94 },
      ]
    : cards.map(() => ({ y: 0, x: 0, scale: 1 }));

  if (typeof gsap !== 'undefined' && typeof ScrollTrigger !== 'undefined') {
    gsap.registerPlugin(ScrollTrigger);

    /* Set initial state: cards hidden below their resting position */
    gsap.set(cards, { opacity: 0, y: 50 });

    ScrollTrigger.create({
      trigger: grid,
      start  : 'top 82%',
      once   : true,
      onEnter() {
        cards.forEach((card, i) => {
          const { y, x, scale } = TARGETS[i];

          gsap.to(card, {
            opacity  : 1,
            y, x, scale,
            duration : 1.6,
            ease     : 'power4.out',   /* approximates spring stiffness:100 damping:30 */
            delay    : 0.4 + i * 0.06,
            onComplete() {
              /* Hand hover/transition control back to CSS */
              card.classList.add('prc-live');
            },
          });
        });
      },
    });

  } else {
    /* Fallback: IntersectionObserver (no GSAP) */
    const io = new IntersectionObserver((entries) => {
      if (!entries[0].isIntersecting) return;
      io.disconnect();
      cards.forEach((card, i) => {
        setTimeout(() => {
          const { y, x, scale } = TARGETS[i];
          card.style.transition = 'opacity 0.7s ease, transform 0.9s cubic-bezier(0.16,1,0.3,1)';
          card.style.opacity    = '1';
          card.style.transform  = `translateY(${y}px) translateX(${x}px) scale(${scale})`;
          card.classList.add('prc-live');
        }, 400 + i * 60);
      });
    }, { threshold: 0.15 });
    io.observe(grid);
  }
});
