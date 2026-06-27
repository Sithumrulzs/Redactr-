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

    const icons = {
      success: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color:var(--success);"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>',
      error: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color:var(--danger);"><circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/></svg>',
      warning: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" style="color:var(--warning);"><path d="M12 9v4M12 17h.01M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"/></svg>',
      info: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color:var(--primary);"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
    };
    toast.innerHTML = `
      <span class="toast-icon">${icons[type] || icons.success}</span>
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
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  function animatePriceTo(el, from, to) {
    if (reducedMotion || from === to) {
      el.textContent = to;
      return;
    }
    const start = performance.now();
    const duration = 450;
    function tick(now) {
      const progress = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(from + (to - from) * eased);
      if (progress < 1) requestAnimationFrame(tick);
      else el.textContent = to;
    }
    requestAnimationFrame(tick);
  }

  toggleOpts.forEach(opt => {
    opt.addEventListener('click', () => {
      toggleOpts.forEach(o => o.classList.remove('active'));
      opt.classList.add('active');

      const isAnnual = opt.dataset.period === 'annual';
      document.querySelectorAll('[data-monthly]').forEach(el => {
        const monthly = parseFloat(el.dataset.monthly);
        const target = isAnnual ? Math.round(monthly * 0.8) : monthly;
        const numEl = el.querySelector('.price-num');
        const current = parseFloat(numEl.textContent) || monthly;
        animatePriceTo(numEl, current, target);
      });

      if (isAnnual) {
        showToast('Annual billing selected — save 20%!', 'info');

        // Confetti burst from the toggle's position — brand colors only.
        if (!reducedMotion && typeof confetti === 'function') {
          const rect = opt.closest('.pricing-toggle').getBoundingClientRect();
          confetti({
            particleCount: 50,
            spread: 60,
            origin: {
              x: (rect.left + rect.width / 2) / window.innerWidth,
              y: (rect.top + rect.height / 2) / window.innerHeight,
            },
            colors: ['#14C8A6', '#22DDB8', '#F4B740'],
            ticks: 200,
            gravity: 1.2,
            decay: 0.94,
            startVelocity: 30,
            shapes: ['circle'],
          });
        }
      }
    });
  });

});
