/* ===================================================
   REDACTR — location-map.js
   Vanilla recreation of a React/Framer-Motion "LocationMap" card:
   mouse-tracked 3D tilt while collapsed, click to expand and reveal
   the real Google Maps embed underneath the decorative overlay.
=================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const card = document.getElementById('location-map');
  if (!card) return; // not the contact page

  const inner = document.getElementById('location-map-inner');
  const closeBtn = document.getElementById('location-map-close');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let expanded = false;

  function setExpanded(value) {
    expanded = value;
    card.classList.toggle('expanded', expanded);
    if (expanded) {
      // The tilt would otherwise fight the user trying to pan/zoom the
      // real map underneath, so freeze it flat once expanded.
      inner.style.transform = 'rotateX(0deg) rotateY(0deg)';
    }
  }

  card.addEventListener('click', (e) => {
    if (e.target === closeBtn) return; // handled separately, see below
    setExpanded(!expanded);
  });

  if (closeBtn) {
    closeBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      setExpanded(false);
    });
  }

  if (reducedMotion) return; // skip the mouse-tracked tilt entirely

  // ── 3D tilt while collapsed (CSS transition does the "spring" settle) ──
  card.addEventListener('mousemove', (e) => {
    if (expanded) return;
    const rect = inner.getBoundingClientRect();
    const x = e.clientX - (rect.left + rect.width / 2);
    const y = e.clientY - (rect.top + rect.height / 2);
    const rotateY = (x / (rect.width / 2)) * 8;
    const rotateX = (y / (rect.height / 2)) * -8;
    inner.style.transform = `rotateX(${rotateX}deg) rotateY(${rotateY}deg)`;
  });

  card.addEventListener('mouseleave', () => {
    inner.style.transform = 'rotateX(0deg) rotateY(0deg)';
  });
});
