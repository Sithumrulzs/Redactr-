/* ===================================================
   REDACTR — animations.js
   Premium/techy visual layer: scroll progress, cursor glow,
   particle network, card tilt + spotlight, animated counters,
   and the hero's live-typing terminal.
=================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ── Scroll progress bar ──────────────────────────── */
  const progressBar = document.createElement('div');
  progressBar.className = 'scroll-progress';
  document.body.appendChild(progressBar);

  function updateProgress() {
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;
    const pct = scrollable > 0 ? (window.scrollY / scrollable) * 100 : 0;
    progressBar.style.width = `${pct}%`;
  }
  window.addEventListener('scroll', updateProgress, { passive: true });
  updateProgress();

  /* ── Ambient cursor glow (desktop only, see CSS media query) ── */
  if (!reducedMotion && window.matchMedia('(min-width: 769px)').matches) {
    const glow = document.createElement('div');
    glow.className = 'cursor-glow';
    document.body.appendChild(glow);

    let targetX = window.innerWidth / 2;
    let targetY = window.innerHeight / 2;
    let curX = targetX;
    let curY = targetY;

    window.addEventListener('mousemove', (e) => {
      targetX = e.clientX;
      targetY = e.clientY;
    });

    function tickGlow() {
      curX += (targetX - curX) * 0.12;
      curY += (targetY - curY) * 0.12;
      glow.style.transform = `translate(${curX}px, ${curY}px) translate(-50%, -50%)`;
      requestAnimationFrame(tickGlow);
    }
    requestAnimationFrame(tickGlow);
  }

  /* ── Card tilt + spotlight ─────────────────────────── */
  if (!reducedMotion) {
    document.querySelectorAll('.card, .testimonial-card').forEach((card) => {
      card.classList.add('tilt');

      card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;
        const px = (x / rect.width) * 100;
        const py = (y / rect.height) * 100;
        card.style.setProperty('--spot-x', `${px}%`);
        card.style.setProperty('--spot-y', `${py}%`);

        const rotateY = ((x / rect.width) - 0.5) * 6;
        const rotateX = ((y / rect.height) - 0.5) * -6;
        card.style.transform = `perspective(800px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) translateY(-4px)`;
      });

      card.addEventListener('mouseleave', () => {
        card.style.transform = '';
      });
    });
  }

  /* ── Animated counters (hero stats, etc.) ─────────── */
  const counters = document.querySelectorAll('[data-count-to]');
  if (counters.length && 'IntersectionObserver' in window) {
    const counterObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        animateCounter(entry.target);
        counterObserver.unobserve(entry.target);
      });
    }, { threshold: 0.4 });
    counters.forEach((el) => counterObserver.observe(el));
  }

  function animateCounter(el) {
    const to = parseFloat(el.dataset.countTo);
    const suffix = el.dataset.countSuffix || '';
    const prefix = el.dataset.countPrefix || '';
    const decimals = el.dataset.countDecimals ? parseInt(el.dataset.countDecimals, 10) : 0;
    const duration = 1400;
    const start = performance.now();

    el.classList.add('counting');
    el.textContent = `${prefix}${(0).toFixed(decimals)}${suffix}`;

    function tick(now) {
      const progress = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - progress, 3);
      const value = to * eased;
      el.textContent = `${prefix}${value.toFixed(decimals)}${suffix}`;
      if (progress < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  /* ── Particle network canvas (hero backdrop) ───────── */
  document.querySelectorAll('.particle-canvas').forEach((canvas) => initParticles(canvas));

  function initParticles(canvas) {
    const ctx = canvas.getContext('2d');
    let width, height, particles;
    const DENSITY = 14000; // px² per particle — lower = denser

    function resize() {
      const rect = canvas.parentElement.getBoundingClientRect();
      width = canvas.width = rect.width;
      height = canvas.height = rect.height;
      const count = Math.min(90, Math.floor((width * height) / DENSITY));
      particles = Array.from({ length: count }, () => ({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * 0.35,
        vy: (Math.random() - 0.5) * 0.35,
        r: Math.random() * 1.6 + 0.6,
      }));
    }

    function step() {
      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = 'rgba(20, 200, 166, 0.7)';

      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0 || p.x > width) p.vx *= -1;
        if (p.y < 0 || p.y > height) p.vy *= -1;
      }

      const maxDist = 140;
      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const a = particles[i], b = particles[j];
          const dx = a.x - b.x, dy = a.y - b.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < maxDist) {
            ctx.strokeStyle = `rgba(20, 200, 166, ${0.18 * (1 - dist / maxDist)})`;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }

      for (const p of particles) {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fill();
      }

      if (!reducedMotion) requestAnimationFrame(step);
    }

    let resizeTimer;
    window.addEventListener('resize', () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(resize, 200);
    });

    resize();
    step();
  }

  /* ── Hero live-typing terminal ─────────────────────── */
  const terminalBody = document.querySelector('[data-live-terminal]');
  if (terminalBody) {
    const script = JSON.parse(terminalBody.dataset.liveTerminal);
    runTerminalLoop(terminalBody, script);
  }

  async function runTerminalLoop(el, lines) {
    while (true) {
      el.innerHTML = '';
      for (const line of lines) {
        await typeLine(el, line);
      }
      await sleep(2600);
      if (reducedMotion) break; // render once, skip the infinite retype loop
    }
  }

  function typeLine(el, line) {
    return new Promise((resolve) => {
      if (line.break) {
        el.appendChild(document.createElement('br'));
        resolve();
        return;
      }

      const div = document.createElement('div');
      div.className = `typed-line ${line.cls || ''}`;
      el.appendChild(div);

      if (reducedMotion) {
        div.textContent = line.text;
        resolve();
        return;
      }

      const cursor = document.createElement('span');
      cursor.className = 'terminal-cursor';

      let i = 0;
      const speed = line.speed || 18;
      const interval = setInterval(() => {
        i++;
        div.textContent = line.text.slice(0, i);
        div.appendChild(cursor);
        if (i >= line.text.length) {
          clearInterval(interval);
          cursor.remove();
          setTimeout(resolve, line.pause || 120);
        }
      }, speed);
    });
  }

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  /* ── Hero "live activity" badge — cycles through recent catches ── */
  const liveBadge = document.querySelector('[data-live-badge]');
  if (liveBadge && !reducedMotion) {
    let feed;
    try {
      feed = JSON.parse(liveBadge.dataset.liveBadge);
    } catch {
      feed = null;
    }
    if (feed && feed.length > 1) {
      const titleEl = liveBadge.querySelector('.badge-title');
      const subEl = liveBadge.querySelector('.badge-sub');
      let index = 0;
      setInterval(() => {
        index = (index + 1) % feed.length;
        [titleEl, subEl].forEach((node) => node && (node.style.opacity = '0'));
        setTimeout(() => {
          if (titleEl) titleEl.textContent = feed[index].title;
          if (subEl) subEl.textContent = feed[index].sub;
          [titleEl, subEl].forEach((node) => node && (node.style.opacity = '1'));
        }, 350);
      }, 3200);
    }
  }

  /* ── Live leak-detection showcase ───────────────────
     Weights match the real Tier-1 detector (see
     redactr-extension/lib/detector.js's WEIGHTS) so the score
     shown here is the same number the product would actually
     produce, not an invented marketing figure. */
  const demoSection = document.getElementById('live-demo');
  if (demoSection) {
    const chatbox = document.getElementById('demo-chatbox');
    const piiEls = Array.from(chatbox.querySelectorAll('.pii'));
    const beam = document.getElementById('demo-scan-beam');
    const statusEl = document.getElementById('demo-status');
    const statusText = document.getElementById('demo-status-text');
    const gauge = document.getElementById('risk-gauge');
    const gaugeVal = document.getElementById('risk-gauge-val');
    const findingsEl = document.getElementById('demo-findings');
    const WEIGHTS = { 'AWS Key': 40, 'Card Number': 35, Email: 5 };

    piiEls.forEach((el) => {
      el.dataset.original = el.textContent;
    });

    function setGauge(pct, color) {
      gauge.style.setProperty('--pct', pct);
      gauge.style.setProperty('--gauge-color', color);
    }

    function currentPct() {
      return parseFloat(gauge.style.getPropertyValue('--pct')) || 0;
    }

    function tweenGauge(to, color, duration) {
      const from = currentPct();
      return new Promise((resolve) => {
        const start = performance.now();
        function frame(now) {
          const t = Math.min(1, (now - start) / duration);
          const val = from + (to - from) * t;
          setGauge(val, color);
          gaugeVal.textContent = Math.round(val);
          if (t < 1) requestAnimationFrame(frame);
          else resolve();
        }
        requestAnimationFrame(frame);
      });
    }

    function setStatus(cls, text) {
      statusEl.className = `demo-status ${cls}`;
      statusText.textContent = text;
    }

    function addFindingChip(label) {
      const chip = document.createElement('div');
      chip.className = 'demo-finding-chip';
      chip.dataset.label = label;
      chip.innerHTML = `<span>${label}</span><span class="chip-check warn">⚠</span>`;
      findingsEl.appendChild(chip);
    }

    function markFindingRedacted(label) {
      const chip = findingsEl.querySelector(`[data-label="${label}"] .chip-check`);
      if (!chip) return;
      chip.textContent = '✓';
      chip.classList.replace('warn', 'done');
    }

    async function runDemo() {
      piiEls.forEach((el) => {
        el.classList.remove('exposed', 'redacted');
        el.textContent = el.dataset.original;
      });
      findingsEl.innerHTML = '';
      setStatus('', 'Idle — watching this input field…');
      setGauge(0, 'var(--success)');
      gaugeVal.textContent = '0';

      if (reducedMotion) {
        piiEls.forEach((el) => {
          el.textContent = el.dataset.token;
          el.classList.add('redacted');
        });
        setStatus('safe', '✓ Safe prompt sent · Manager notified');
        return; // no auto-loop when motion is reduced
      }

      await sleep(900);
      setStatus('scanning', 'Scanning…');
      beam.classList.add('active');
      await sleep(500);

      let score = 0;
      for (const el of piiEls) {
        await sleep(300);
        el.classList.add('exposed');
        score += WEIGHTS[el.dataset.label] || 20;
        addFindingChip(el.dataset.label);
        await tweenGauge(score, 'var(--danger)', 350);
      }

      await sleep(500);
      beam.classList.remove('active');
      setStatus('danger', `⚠ RISK DETECTED · Score ${score} · CRITICAL`);
      await sleep(900);

      setStatus('scanning', 'Generating safe version…');
      for (const el of piiEls) {
        await sleep(280);
        el.classList.remove('exposed');
        el.textContent = el.dataset.token;
        el.classList.add('redacted');
        markFindingRedacted(el.dataset.label);
      }
      await tweenGauge(0, 'var(--success)', 600);
      setStatus('safe', '✓ Safe prompt sent · Manager notified');

      await sleep(3400);
      runDemo();
    }

    if ('IntersectionObserver' in window) {
      const demoObserver = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            runDemo();
            demoObserver.unobserve(entry.target);
          }
        });
      }, { threshold: 0.3 });
      demoObserver.observe(demoSection);
    } else {
      runDemo();
    }
  }

  /* ── Use Case — live chatbot simulation (GSAP/ScrollTrigger) ──
     The only GSAP usage on the site so far — CDN scripts are loaded in
     index.html right before main.js. Builds a real GSAP timeline (not
     the hand-rolled promise/setTimeout pattern the leak-detection demo
     above uses) and plays it once the section scrolls into view, then
     loops with a pause, matching that demo's cadence. */
  buildUseCaseDemo();

  function buildUseCaseDemo() {
    const section = document.getElementById('usecase');
    if (!section) return;

    const chatField = document.getElementById('chat-input-field');
    const typedEl = document.getElementById('chat-input-typed');
    const preEl = document.getElementById('chat-input-pre');
    const placeholderEl = document.getElementById('chat-input-placeholder');
    const secretEl = document.getElementById('chat-input-secret');
    const safeEl = document.getElementById('chat-input-safe');
    const badgeEl = document.getElementById('chat-leak-badge');
    const sendBtn = document.getElementById('chat-send-btn');
    const finalMsg = document.getElementById('chat-msg-final');

    if (typeof gsap === 'undefined' || typeof ScrollTrigger === 'undefined') {
      return; // HTML defaults already show the finished, safe end-state.
    }
    gsap.registerPlugin(ScrollTrigger);

    if (reducedMotion) {
      gsap.set(typedEl, { width: '0ch' });
      gsap.set(safeEl, { opacity: 1 });
      gsap.set(secretEl, { opacity: 0 });
      gsap.set(finalMsg, { opacity: 1, y: 0 });
      return;
    }

    // Pre-text + secret text only — typedEl's own textContent would also
    // pull in the hidden [SECRET_1] replacement text and overcount.
    const charCount = preEl.textContent.length + secretEl.textContent.length;

    function resetState() {
      gsap.set(typedEl, { width: '0ch', opacity: 1 });
      gsap.set(placeholderEl, { opacity: 1 });
      gsap.set(secretEl, { opacity: 1, clearProps: 'color', textShadow: 'none' });
      gsap.set(safeEl, { opacity: 0 });
      gsap.set(badgeEl, { opacity: 0, y: 6, scale: 0.96 });
      gsap.set(sendBtn, { scale: 1 });
      gsap.set(finalMsg, { opacity: 0, y: 16 });
      chatField.classList.remove('leak-detected');
    }

    function buildTimeline() {
      resetState();
      const tl = gsap.timeline({ repeat: -1, repeatDelay: 2.6 });

      tl.to(placeholderEl, { opacity: 0, duration: 0.2 })
        // Typing — same width(ch) reveal technique as the hero terminal.
        .to(typedEl, { width: `${charCount}ch`, duration: Math.max(1.4, charCount * 0.045), ease: 'none' })
        .to({}, { duration: 0.45 }) // brief pause, cursor blinking, before send
        // Send button: quick scale down and back up.
        .to(sendBtn, { scale: 0.82, duration: 0.12, ease: 'power2.out' })
        .to(sendBtn, { scale: 1, duration: 0.18, ease: 'back.out(2)' })
        // Intercept: border flashes crimson, tooltip pops up.
        .add(() => chatField.classList.add('leak-detected'))
        .to(badgeEl, { opacity: 1, y: 0, scale: 1, duration: 0.35, ease: 'back.out(1.6)' })
        .to({}, { duration: 1.0 }) // hold the warning so it's actually readable
        // Redaction: amber glow, then crossfade into the turquoise safe tag.
        .to(secretEl, { color: '#F4B740', textShadow: '0 0 12px rgba(244,183,64,0.6)', duration: 0.3 })
        .to({}, { duration: 0.45 })
        .to(secretEl, { opacity: 0, duration: 0.25 })
        .to(safeEl, { opacity: 1, duration: 0.3 }, '<0.1')
        .add(() => chatField.classList.remove('leak-detected'))
        .to(badgeEl, { opacity: 0, y: 6, scale: 0.96, duration: 0.3 })
        .to({}, { duration: 0.35 })
        // Clear the input and slide the now-safe prompt into chat history.
        .to(typedEl, { opacity: 0, duration: 0.25 })
        .add(() => { gsap.set(typedEl, { width: '0ch', opacity: 1 }); gsap.set(placeholderEl, { opacity: 1 }); })
        .to(finalMsg, { opacity: 1, y: 0, duration: 0.45, ease: 'power3.out' });

      return tl;
    }

    let started = false;
    ScrollTrigger.create({
      trigger: section,
      start: 'top 75%',
      onEnter: () => { if (!started) { started = true; buildTimeline(); } },
      onEnterBack: () => { if (!started) { started = true; buildTimeline(); } },
    });
  }
});
