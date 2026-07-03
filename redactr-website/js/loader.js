/* ===================================================
   REDACTR — loader.js
   One-time 3D (Three.js) branded intro on index.html: a scanning
   core + wireframe shell + particle ring, echoing the same
   scan/detect visual language used elsewhere on the site
   (particle-canvas, demo-scan-beam). Plays once per browser session
   (see the inline <head> script), skipped entirely under
   prefers-reduced-motion, and hard-capped so a slow/failed CDN load
   can never block the page.

   Runs immediately (not on DOMContentLoaded) — this script tag sits
   right after #site-loader in the DOM, so the elements it needs
   already exist, and starting early lets the 3D scene begin
   rendering while the rest of the page is still parsing.
=================================================== */
(function () {
  var html = document.documentElement;
  if (!html.classList.contains('js-loading')) return; // skipped this run

  var overlay = document.getElementById('site-loader');
  var canvas = document.getElementById('loader-canvas');
  var statusEl = document.getElementById('loader-status');
  var barFill = document.getElementById('loader-bar-fill');

  var finished = false;
  function finish() {
    if (finished) return;
    finished = true;
    try { sessionStorage.setItem('redactr_intro_played', '1'); } catch (e) {}
    if (overlay) {
      overlay.classList.add('hide');
      setTimeout(function () { overlay.remove(); }, 650);
    }
    html.classList.remove('js-loading');
  }

  if (!overlay || !canvas) { finish(); return; }

  // Never let a slow/broken CDN or WebGL failure block the page.
  var failsafe = setTimeout(finish, 4000);

  if (typeof THREE === 'undefined') { finish(); return; }

  try {
    runScene();
  } catch (e) {
    finish();
  }

  function runScene() {
    var renderer = new THREE.WebGLRenderer({ canvas: canvas, alpha: true, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));

    var scene = new THREE.Scene();
    var camera = new THREE.PerspectiveCamera(45, 1, 0.1, 100);
    camera.position.set(0, 0, 6.2);

    function resize() {
      var parent = canvas.parentElement;
      var size = Math.max(120, Math.min(parent.clientWidth, parent.clientHeight || parent.clientWidth, 340));
      renderer.setSize(size, size, false);
      camera.aspect = 1;
      camera.updateProjectionMatrix();
    }
    resize();
    window.addEventListener('resize', resize);

    // Inner glowing core.
    var core = new THREE.Mesh(
      new THREE.IcosahedronGeometry(1.15, 1),
      new THREE.MeshStandardMaterial({
        color: 0x14C8A6, emissive: 0x14C8A6, emissiveIntensity: 0.55,
        roughness: 0.35, metalness: 0.25,
      })
    );
    scene.add(core);

    // Outer wireframe shell.
    var shell = new THREE.LineSegments(
      new THREE.EdgesGeometry(new THREE.IcosahedronGeometry(1.9, 1)),
      new THREE.LineBasicMaterial({ color: 0x22DDB8, transparent: true, opacity: 0.65 })
    );
    scene.add(shell);

    // Orbiting particle ring — same motif as the hero's particle-canvas.
    var ringCount = 140;
    var ringPositions = new Float32Array(ringCount * 3);
    for (var i = 0; i < ringCount; i++) {
      var angle = (i / ringCount) * Math.PI * 2;
      var radius = 2.6 + Math.random() * 0.35;
      ringPositions[i * 3] = Math.cos(angle) * radius;
      ringPositions[i * 3 + 1] = (Math.random() - 0.5) * 0.4;
      ringPositions[i * 3 + 2] = Math.sin(angle) * radius;
    }
    var ringGeo = new THREE.BufferGeometry();
    ringGeo.setAttribute('position', new THREE.BufferAttribute(ringPositions, 3));
    var ring = new THREE.Points(ringGeo, new THREE.PointsMaterial({
      color: 0x14C8A6, size: 0.045, transparent: true, opacity: 0.85,
    }));
    scene.add(ring);

    // Scanning plane sweeping through the core — same idea as the
    // product demo's scan beam, just rendered in 3D here.
    var scan = new THREE.Mesh(
      new THREE.PlaneGeometry(4.4, 0.06),
      new THREE.MeshBasicMaterial({ color: 0x22DDB8, transparent: true, opacity: 0.5, side: THREE.DoubleSide })
    );
    scene.add(scan);

    scene.add(new THREE.AmbientLight(0x14181F, 1.2));
    var point = new THREE.PointLight(0x22DDB8, 2.2, 12);
    point.position.set(2, 2, 3);
    scene.add(point);

    var clock = new THREE.Clock();
    var raf;
    function tick() {
      var t = clock.getElapsedTime();
      core.rotation.y = t * 0.6;
      core.rotation.x = t * 0.35;
      shell.rotation.y = -t * 0.35;
      shell.rotation.x = t * 0.22;
      ring.rotation.y = t * 0.25;
      scan.position.y = Math.sin(t * 1.4) * 1.7;
      core.material.emissiveIntensity = 0.5 + Math.sin(t * 3) * 0.15;
      renderer.render(scene, camera);
      raf = requestAnimationFrame(tick);
    }
    tick();

    var statuses = ['Initializing secure scan…', 'Loading detection engine…', 'Almost ready…'];
    var si = 0;
    var statusTimer = statusEl ? setInterval(function () {
      si = (si + 1) % statuses.length;
      statusEl.textContent = statuses[si];
    }, 550) : null;

    // Cosmetic progress bar timed to the intro — not tied to real
    // asset loading (there's nothing meaningful to wait on here, this
    // is a branded moment, not a functional loading indicator).
    var DURATION = 2100;
    var start = performance.now();
    function tickBar(now) {
      var p = Math.min(1, (now - start) / DURATION);
      if (barFill) barFill.style.width = (p * 100) + '%';
      if (p < 1) requestAnimationFrame(tickBar);
    }
    requestAnimationFrame(tickBar);

    setTimeout(function () {
      clearTimeout(failsafe);
      if (statusTimer) clearInterval(statusTimer);
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
      renderer.dispose();
      finish();
    }, DURATION);
  }
})();
