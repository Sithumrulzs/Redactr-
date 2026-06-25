/* ===================================================
   REDACTR — cinematic.js
   Single-shot scroll journey, built scene-by-scene with
   GSAP ScrollTrigger. Every visual change is a tween placed
   directly on a scrubbed timeline (never a one-shot side
   effect), so scrolling back up reverses it cleanly instead
   of leaving stale state behind.
=================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const gsapAvailable = typeof gsap !== 'undefined' && typeof ScrollTrigger !== 'undefined';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  if (!gsapAvailable || reducedMotion) {
    showStaticFallback();
    return;
  }

  gsap.registerPlugin(ScrollTrigger);

  buildScene1();
  buildScene2();
  buildScene3();
  buildScene4();

  // Tailwind's CDN build, web fonts, and the logo image can all still be
  // settling after DOMContentLoaded — recompute every pin distance once
  // everything has actually finished loading, so a slow load never
  // leaves ScrollTrigger holding stale (collapsed) measurements.
  window.addEventListener('load', () => ScrollTrigger.refresh());

  /* ── Scene 1 — The Launch ─────────────────────────── */
  function buildScene1() {
    const codeEl = document.getElementById('s1-code');
    const charCount = codeEl.textContent.length;
    gsap.set(codeEl, { width: '0ch' });

    gsap.timeline({
      scrollTrigger: {
        trigger: '#scene-1',
        start: 'top top',
        end: '+=120%',
        scrub: true,
        pin: true,
        anticipatePin: 1,
      },
    })
      .to('#s1-eyebrow', { opacity: 0, duration: 0.15 }, 0)
      .to(codeEl, { width: `${charCount}ch`, ease: 'none', duration: 0.45 }, 0)
      .to('#s1-wrap', { scale: 9, filter: 'blur(8px) brightness(1.5)', ease: 'power4.in', duration: 0.5 }, 0.42)
      .to('#scene-1', { autoAlpha: 0, duration: 0.18 }, 0.82);
  }

  /* ── Scene 2 — The Glass Wall / The Intercept ─────── */
  function buildScene2() {
    // yPercent:-50 recreates the vertical centering that would otherwise
    // come from a Tailwind -translate-y-1/2 class — GSAP needs to own the
    // whole transform itself once it starts animating xPercent on this
    // element, or the two approaches fight over the transform property.
    gsap.set('#s2-glass', { xPercent: 110, yPercent: -50 });
    gsap.set('#s2-raw', { opacity: 1 });
    gsap.set('#s2-safe', { opacity: 0 });
    gsap.set('#scene-2', { autoAlpha: 1 });

    const particleHost = document.getElementById('s2-particles');
    const PARTICLE_COUNT = 16;
    const particles = [];
    for (let i = 0; i < PARTICLE_COUNT; i++) {
      const dot = document.createElement('div');
      dot.className = 'particle';
      dot.style.left = '50%';
      dot.style.top = '50%';
      particleHost.appendChild(dot);
      particles.push(dot);
    }
    const angles = particles.map((_, i) => (i / PARTICLE_COUNT) * Math.PI * 2);

    gsap.timeline({
      scrollTrigger: {
        trigger: '#scene-2',
        start: 'top top',
        end: '+=160%',
        scrub: true,
        pin: true,
        anticipatePin: 1,
      },
    })
      .to('#s2-glass', { xPercent: 0, ease: 'power4.out', duration: 0.4 }, 0)
      .to('#s2-cam', { rotateY: 7, rotateX: -2, ease: 'none', duration: 0.6 }, 0)
      .to('#s2-text', { x: -60, ease: 'none', duration: 0.45 }, 0.05)
      // Raw secret glows danger-amber right before it shatters.
      .to('#s2-raw', { color: '#ffb020', textShadow: '0 0 18px rgba(255,176,32,0.7)', duration: 0.12 }, 0.42)
      // Shatter: particles burst outward from the secret's position.
      .to(particles, {
        opacity: 1,
        x: (i) => Math.cos(angles[i]) * gsap.utils.random(40, 140),
        y: (i) => Math.sin(angles[i]) * gsap.utils.random(40, 140),
        duration: 0.22,
        ease: 'power2.out',
        stagger: 0.01,
      }, 0.46)
      .to(particles, { opacity: 0, duration: 0.18 }, 0.62)
      // Raw text fades, safe token fades in — the morph.
      .to('#s2-raw', { opacity: 0, duration: 0.14 }, 0.5)
      .to('#s2-safe', { opacity: 1, duration: 0.16 }, 0.58)
      .to('#scene-2', { autoAlpha: 0, duration: 0.15 }, 0.86);
  }

  /* ── Scene 3 — The Mobile Command Center ──────────── */
  function buildScene3() {
    gsap.set('#scene-3', { autoAlpha: 1 });
    gsap.set('#s3-phone', { y: '70vh' });
    gsap.set('#s3-notif', { opacity: 0, y: 16 });
    gsap.set('#s3-ripple', { opacity: 0, scale: 0.2 });

    gsap.timeline({
      scrollTrigger: {
        trigger: '#scene-3',
        start: 'top top',
        end: '+=140%',
        scrub: true,
        pin: true,
        anticipatePin: 1,
      },
    })
      .to('#s3-phone', { y: 0, ease: 'power4.out', duration: 0.45 }, 0)
      .to('#s3-notif', { opacity: 1, y: 0, ease: 'power3.out', duration: 0.3 }, 0.42)
      // Automated approve pulse — a ripple of light across the screen.
      .to('#s3-approve', { boxShadow: '0 0 30px rgba(215,255,63,0.8)', duration: 0.15 }, 0.7)
      .to('#s3-ripple', { opacity: 0.9, scale: 22, ease: 'power2.out', duration: 0.35 }, 0.72)
      .to('#s3-ripple', { opacity: 0, duration: 0.15 }, 0.95)
      .to('#scene-3', { autoAlpha: 0, duration: 0.15 }, 1.0);
  }

  /* ── Scene 4 — The Clean Output ────────────────────── */
  function buildScene4() {
    gsap.set('#scene-4', { autoAlpha: 1 });
    gsap.set('#s4-orb-wrap', { opacity: 0, scale: 0.2 });
    gsap.set('#s4-terminal', { opacity: 0, y: 36 });

    gsap.timeline({
      scrollTrigger: {
        trigger: '#scene-4',
        start: 'top top',
        end: '+=110%',
        scrub: true,
        pin: true,
        anticipatePin: 1,
      },
    })
      .to('#s4-orb-wrap', { opacity: 0.7, scale: 1, ease: 'power3.out', duration: 0.45 }, 0)
      .to('#s4-terminal', { opacity: 1, y: 0, ease: 'power4.out', duration: 0.5 }, 0.35);
  }

  /* ── Fallback if GSAP fails to load or motion is reduced ──
     The journey is the whole point of this page, but the
     content — and the path to checkout — still has to be
     reachable without it. */
  function showStaticFallback() {
    document.querySelectorAll('.scene').forEach((scene) => {
      scene.style.opacity = '1';
      scene.style.position = 'relative';
      scene.style.minHeight = '100vh';
    });
    setOpacity('#s2-safe', '1');
    setOpacity('#s2-raw', '0');
    const glass = document.getElementById('s2-glass');
    if (glass) glass.style.transform = 'translateX(0)';
    const phone = document.getElementById('s3-phone');
    if (phone) phone.style.transform = 'translateY(0)';
    setOpacity('#s3-notif', '1');
    const notif = document.getElementById('s3-notif');
    if (notif) notif.style.transform = 'translateY(0)';
    setOpacity('#s4-orb-wrap', '0.6');
    const orb = document.getElementById('s4-orb-wrap');
    if (orb) orb.style.transform = 'scale(1)';
    setOpacity('#s4-terminal', '1');
    const terminal = document.getElementById('s4-terminal');
    if (terminal) terminal.style.transform = 'translateY(0)';
  }

  function setOpacity(selector, value) {
    const el = document.querySelector(selector);
    if (el) el.style.opacity = value;
  }
});
