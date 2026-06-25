/* ===================================================
   REDACTR — main.js
   Shared page behaviour: navbar, scroll, animations
=================================================== */

document.addEventListener('DOMContentLoaded', () => {

  // ── Navbar scroll state ──────────────────────────
  const navbar = document.querySelector('.navbar');
  if (navbar) {
    window.addEventListener('scroll', () => {
      navbar.classList.toggle('scrolled', window.scrollY > 20);
    }, { passive: true });
  }

  // ── Mobile menu toggle ───────────────────────────
  const menuBtn  = document.querySelector('.nav-menu-btn');
  const mobileNav = document.querySelector('.nav-mobile');

  if (menuBtn && mobileNav) {
    menuBtn.addEventListener('click', () => {
      const open = mobileNav.classList.toggle('open');
      menuBtn.setAttribute('aria-expanded', open);
      menuBtn.textContent = open ? '✕' : '☰';
    });
  }

  // ── Active nav link ──────────────────────────────
  const navLinks = document.querySelectorAll('.nav-links a, .nav-mobile a');
  const currentPage = window.location.pathname.split('/').pop() || 'index.html';

  navLinks.forEach(link => {
    const href = link.getAttribute('href');
    if (href && (href === currentPage || href.endsWith(currentPage))) {
      link.classList.add('active');
    }
  });

  // ── Scroll reveal ────────────────────────────────
  const revealEls = document.querySelectorAll('.reveal');

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry, i) => {
        if (entry.isIntersecting) {
          setTimeout(() => {
            entry.target.classList.add('visible');
          }, i * 80);
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12 });

    revealEls.forEach(el => observer.observe(el));
  } else {
    revealEls.forEach(el => el.classList.add('visible'));
  }

  // ── Toast helper ─────────────────────────────────
  window.showToast = function(message, type = 'success') {
    let toast = document.querySelector('.toast');
    if (!toast) {
      toast = document.createElement('div');
      toast.className = 'toast';
      document.body.appendChild(toast);
    }

    const icons = { success: '✅', error: '❌', warning: '⚠️', info: 'ℹ️' };
    toast.innerHTML = `
      <span class="toast-icon">${icons[type] || '✅'}</span>
      <span>${message}</span>
    `;

    toast.classList.add('show');

    clearTimeout(toast._timer);
    toast._timer = setTimeout(() => toast.classList.remove('show'), 3500);
  };

  // ── Smooth scroll for anchor links ───────────────
  document.querySelectorAll('a[href^="#"]').forEach(link => {
    link.addEventListener('click', e => {
      const target = document.querySelector(link.getAttribute('href'));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        if (mobileNav) mobileNav.classList.remove('open');
      }
    });
  });

  // ── Contact form handler ──────────────────────────
  const contactForm = document.getElementById('contactForm');
  if (contactForm) {
    contactForm.addEventListener('submit', e => {
      e.preventDefault();
      const btn = contactForm.querySelector('button[type="submit"]');
      btn.disabled = true;
      btn.textContent = 'Sending…';

      setTimeout(() => {
        contactForm.reset();
        btn.disabled = false;
        btn.textContent = 'Send Message';
        showToast('Message sent! We\'ll respond within 24 hours.', 'success');
      }, 1400);
    });
  }

  // ── Pricing toggle (monthly / annual) ────────────
  const toggleOpts = document.querySelectorAll('.toggle-opt');
  toggleOpts.forEach(opt => {
    opt.addEventListener('click', () => {
      toggleOpts.forEach(o => o.classList.remove('active'));
      opt.classList.add('active');

      const isAnnual = opt.dataset.period === 'annual';
      document.querySelectorAll('[data-monthly]').forEach(el => {
        const monthly = parseFloat(el.dataset.monthly);
        const display = isAnnual
          ? `$${(monthly * 0.8).toFixed(0)}`
          : `$${monthly}`;
        el.querySelector('.price-num').textContent = display;
      });

      if (isAnnual) {
        showToast('Annual billing selected — save 20%!', 'info');
      }
    });
  });

  // ── Cinematic homepage scroll journey ────────────
  initCinematicJourney();

});

/**
 * Single-shot cinematic scroll journey for index.html only — no-ops
 * immediately on every other page (#cinematic-pin doesn't exist there).
 * One ScrollTrigger pins #cinematic-pin for the whole sequence; the four
 * .scene panels are absolutely stacked inside #smooth-wrapper and their
 * entrances/exits are driven by autoAlpha (GSAP's opacity+visibility
 * combo, so a hidden scene can't still intercept clicks) on one master
 * timeline split into four equal quarters — never by separate per-scene
 * ScrollTrigger.create({pin:true}) instances.
 *
 * Every visual change is a tween placed directly on that scrubbed
 * timeline, never a one-shot side effect, so scrolling back up reverses
 * each beat cleanly instead of leaving stale state behind.
 */
function initCinematicJourney() {
  const pinEl = document.getElementById('cinematic-pin');
  if (!pinEl) return;

  const gsapAvailable = typeof gsap !== 'undefined' && typeof ScrollTrigger !== 'undefined';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (!gsapAvailable || reducedMotion) {
    showCinematicFallback();
    return;
  }

  gsap.registerPlugin(ScrollTrigger);

  const codeEl = document.getElementById('launch-code');
  const charCount = codeEl.textContent.length;

  gsap.set(codeEl, { width: '0ch' });
  gsap.set('#intercept-shield', { xPercent: 110, yPercent: -50 });
  gsap.set('#secret-raw', { opacity: 1 });
  gsap.set('#secret-safe', { opacity: 0 });
  gsap.set('#mobile-phone', { y: '70vh' });
  gsap.set('#mobile-notif', { opacity: 0, y: 16 });
  gsap.set('#mobile-ripple', { opacity: 0, scale: 0.2 });
  gsap.set('#output-orb', { opacity: 0, scale: 0.2 });
  gsap.set('#output-terminal', { opacity: 0, y: 36 });

  // Shatter particles — pre-created so their burst is a tween on the
  // master timeline (scrubbable both ways), not a one-shot DOM mutation.
  const particleHost = document.getElementById('intercept-particles');
  const PARTICLE_COUNT = 16;
  const particles = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    const dot = document.createElement('div');
    dot.className = 'particle-dot';
    dot.style.left = '50%';
    dot.style.top = '50%';
    particleHost.appendChild(dot);
    particles.push(dot);
  }
  const angles = particles.map((_, i) => (i / PARTICLE_COUNT) * Math.PI * 2);

  const BEAT = 0.25; // each of the 4 beats owns an equal quarter of overall progress

  const master = gsap.timeline({
    scrollTrigger: {
      trigger: '#cinematic-pin',
      start: 'top top',
      end: '+=400%',
      scrub: 1,
      pin: true,
      anticipatePin: 1,
    },
  });

  // Beat 1 — The Launch: type out the key, then the camera zooms through it.
  master
    .set('#scene-launch', { autoAlpha: 1 }, 0)
    .to(codeEl, { width: `${charCount}ch`, ease: 'none', duration: BEAT * 0.45 }, 0)
    .to('#scene-launch', { scale: 9, filter: 'blur(8px) brightness(1.5)', ease: 'power3.out', duration: BEAT * 0.4 }, BEAT * 0.45)
    .to('#scene-launch', { autoAlpha: 0, duration: BEAT * 0.15 }, BEAT * 0.82);

  // Beat 2 — The Intercept: glass slides in, secret glows amber, shatters,
  // morphs into the safe token.
  master
    .set('#scene-intercept', { autoAlpha: 1 }, BEAT)
    .to('#intercept-shield', { xPercent: 0, ease: 'power3.out', duration: BEAT * 0.4 }, BEAT)
    .to('#intercept-text', { x: -60, ease: 'none', duration: BEAT * 0.45 }, BEAT + BEAT * 0.05)
    .to('#secret-raw', { color: '#ffb020', textShadow: '0 0 18px rgba(255,176,32,0.7)', duration: BEAT * 0.12 }, BEAT + BEAT * 0.42)
    .to(particles, {
      opacity: 1,
      x: (i) => Math.cos(angles[i]) * gsap.utils.random(40, 140),
      y: (i) => Math.sin(angles[i]) * gsap.utils.random(40, 140),
      duration: BEAT * 0.22,
      ease: 'power2.out',
      stagger: 0.01,
    }, BEAT + BEAT * 0.46)
    .to(particles, { opacity: 0, duration: BEAT * 0.18 }, BEAT + BEAT * 0.62)
    .to('#secret-raw', { opacity: 0, duration: BEAT * 0.14 }, BEAT + BEAT * 0.5)
    .to('#secret-safe', { opacity: 1, duration: BEAT * 0.16 }, BEAT + BEAT * 0.58)
    .to('#scene-intercept', { autoAlpha: 0, duration: BEAT * 0.15 }, BEAT + BEAT * 0.85);

  // Beat 3 — The Mobile Command Center: phone rises, notification appears,
  // an automated Approve sends a glowing ripple across the screen.
  master
    .set('#scene-mobile', { autoAlpha: 1 }, BEAT * 2)
    .to('#mobile-phone', { y: 0, ease: 'power3.out', duration: BEAT * 0.45 }, BEAT * 2)
    .to('#mobile-notif', { opacity: 1, y: 0, ease: 'power3.out', duration: BEAT * 0.3 }, BEAT * 2 + BEAT * 0.42)
    .to('#notif-approve', { boxShadow: '0 0 30px rgba(227,193,74,0.8)', duration: BEAT * 0.1 }, BEAT * 2 + BEAT * 0.7)
    .to('#mobile-ripple', { opacity: 0.9, scale: 22, ease: 'power2.out', duration: BEAT * 0.3 }, BEAT * 2 + BEAT * 0.72)
    .to('#mobile-ripple', { opacity: 0, duration: BEAT * 0.12 }, BEAT * 2 + BEAT * 0.95)
    .to('#scene-mobile', { autoAlpha: 0, duration: BEAT * 0.05 }, BEAT * 3 - BEAT * 0.05);

  // Beat 4 — The Clean Output: orb glows, the purchase terminal settles in.
  master
    .set('#scene-output', { autoAlpha: 1 }, BEAT * 3)
    .to('#output-orb', { opacity: 0.7, scale: 1, ease: 'power3.out', duration: BEAT * 0.45 }, BEAT * 3)
    .to('#output-terminal', { opacity: 1, y: 0, ease: 'power3.out', duration: BEAT * 0.5 }, BEAT * 3 + BEAT * 0.35);

  // Web fonts and the logo image can still be settling after
  // DOMContentLoaded — recompute every pin distance once everything has
  // actually finished loading, so a slow load never leaves ScrollTrigger
  // holding stale (collapsed) measurements.
  window.addEventListener('load', () => ScrollTrigger.refresh());
}

/**
 * Used when GSAP fails to load or the user has motion reduced — the
 * journey is the whole point of this page, but the content (and the
 * path to checkout) still has to be reachable without it.
 */
function showCinematicFallback() {
  document.querySelectorAll('.scene').forEach((scene) => {
    scene.style.opacity = '1';
    scene.style.visibility = 'visible';
    scene.style.position = 'relative';
    scene.style.height = 'auto';
    scene.style.minHeight = '100vh';
  });
  const pin = document.getElementById('cinematic-pin');
  if (pin) { pin.style.height = 'auto'; pin.style.overflow = 'visible'; }

  setVisible('#secret-safe', '1');
  setVisible('#secret-raw', '0');
  const shield = document.getElementById('intercept-shield');
  if (shield) shield.style.transform = 'translateX(0)';

  const phone = document.getElementById('mobile-phone');
  if (phone) phone.style.transform = 'translateY(0)';
  setVisible('#mobile-notif', '1');

  setVisible('#output-orb', '0.6');
  const orb = document.getElementById('output-orb');
  if (orb) orb.style.transform = 'scale(1)';
  setVisible('#output-terminal', '1');
  const terminal = document.getElementById('output-terminal');
  if (terminal) terminal.style.transform = 'translateY(0)';

  function setVisible(selector, value) {
    const el = document.querySelector(selector);
    if (el) el.style.opacity = value;
  }
}
