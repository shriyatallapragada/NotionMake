(function () {
  var tz = NM.tz('tz'), h12 = NM.flag('hour12', false), secs = NM.flag('seconds', true), showDate = NM.flag('date', true);
  var style = NM.oneOf('style', ['digital', 'analog'], 'digital');
  var city = tz ? tz.split('/').pop().replace(/_/g, ' ') : '';
  var label = NM.str('label', '', 40) || city;
  if (label) NM.setText('label', label); else NM.$('label').hidden = true;
  if (!showDate) NM.$('date').hidden = true;

  var fTime = new Intl.DateTimeFormat(undefined, { timeZone: tz, hour: '2-digit', minute: '2-digit', second: secs ? '2-digit' : undefined, hour12: h12, hourCycle: h12 ? undefined : 'h23' });
  var fDate = new Intl.DateTimeFormat(undefined, { timeZone: tz, weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  var fParts = new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: 'numeric', minute: 'numeric', second: 'numeric', hourCycle: 'h23' });

  var hands = null;
  if (style === 'analog') {
    var ns = 'http://www.w3.org/2000/svg', face = NM.$('face');
    face.textContent = '';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '-100 -100 200 200');
    svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', 'Analog clock');
    svg.style.setProperty('width', 'min(62vh, 80vw)');
    svg.style.setProperty('height', 'min(62vh, 80vw)');
    var ring = document.createElementNS(ns, 'circle');
    ring.setAttribute('r', '96'); ring.setAttribute('fill', 'none'); ring.setAttribute('stroke', 'currentColor'); ring.setAttribute('stroke-width', '3');
    svg.appendChild(ring);
    for (var i = 0; i < 12; i++) {
      var t = document.createElementNS(ns, 'line');
      t.setAttribute('x1', '0'); t.setAttribute('x2', '0'); t.setAttribute('y1', '-88'); t.setAttribute('y2', i % 3 ? '-80' : '-74');
      t.setAttribute('stroke', 'currentColor'); t.setAttribute('stroke-width', i % 3 ? '2' : '4'); t.setAttribute('transform', 'rotate(' + i * 30 + ')');
      svg.appendChild(t);
    }
    function hand(len, w, color) {
      var l = document.createElementNS(ns, 'line');
      l.setAttribute('x1', '0'); l.setAttribute('y1', '8'); l.setAttribute('x2', '0'); l.setAttribute('y2', String(-len));
      l.setAttribute('stroke', color); l.setAttribute('stroke-width', String(w)); l.setAttribute('stroke-linecap', 'round');
      svg.appendChild(l); return l;
    }
    hands = { h: hand(50, 6, 'currentColor'), m: hand(72, 4, 'currentColor'), s: secs ? hand(80, 2, 'var(--accent)') : null };
    face.style.setProperty('color', 'var(--fg)');
    face.appendChild(svg);
  }

  function tick() {
    var now = new Date();
    if (hands) {
      var p = {}; fParts.formatToParts(now).forEach(function (x) { p[x.type] = +x.value; });
      var s = p.second, m = p.minute + s / 60, h = (p.hour % 12) + m / 60;
      hands.h.setAttribute('transform', 'rotate(' + h * 30 + ')');
      hands.m.setAttribute('transform', 'rotate(' + m * 6 + ')');
      if (hands.s) hands.s.setAttribute('transform', 'rotate(' + s * 6 + ')');
    } else {
      NM.setText('time', fTime.format(now));
    }
    if (showDate) NM.setText('date', fDate.format(now));
  }
  NM.every(tick, 1000);
})();
