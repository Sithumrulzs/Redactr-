/* ===================================================
   REDACTR — pricing.js
   3D scroll-reveal stagger for the 3 pricing cards (side cards recede
   and tilt back, the popular card pops forward) — adapted from a
   framer-motion reference into GSAP/ScrollTrigger. Desktop-only depth
   effect; mobile just fades the cards in, same as the rest of the site.
=================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const grid = document.querySelector('.pricing-grid');
  if (!grid) return; // not the pricing page

  const cards = Array.from(grid.querySelectorAll('.pricing-card'));
  if (!cards.length) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const isDesktop = window.matchMedia('(min-width: 1025px)').matches;

  if (reducedMotion || typeof gsap === 'undefined') return; // HTML default is already fully visible

  if (!isDesktop) {
    // Mobile/tablet — simple fade+rise, no 3D splay.
    gsap.set(cards, { autoAlpha: 0, y: 40 });
    gsap.to(cards, {
      autoAlpha: 1, y: 0, duration: 0.6, stagger: 0.12, ease: 'power2.out',
      scrollTrigger: { trigger: grid, start: 'top 80%', once: true },
    });
    return;
  }

  gsap.registerPlugin(ScrollTrigger);

  cards.forEach((card, i) => {
    const isPopular = card.classList.contains('popular');
    const side = i === 0 ? -1 : i === cards.length - 1 ? 1 : 0;
    gsap.set(card, {
      autoAlpha: 0,
      y: 50,
      x: side * 30,
      scale: isPopular ? 1 : 0.94,
      rotationY: side * -10,
      transformPerspective: 1200,
    });
  });

  gsap.to(cards, {
    autoAlpha: 1,
    y: (i, target) => (target.classList.contains('popular') ? -10 : 0),
    x: 0,
    scale: 1,
    rotationY: 0,
    duration: 1.1,
    ease: 'power3.out',
    stagger: 0.12,
    scrollTrigger: { trigger: grid, start: 'top 75%', once: true },
  });
});
