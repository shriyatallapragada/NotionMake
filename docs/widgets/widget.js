// Shared helpers for the NotionMake widgets.
// Settings come from the URL and are validated here. They are only ever written
// into the page as text (textContent), never as HTML, so they cannot inject code.
(function () {
  var q = new URLSearchParams(location.search);
  var THEMES = ['auto', 'dark', 'terracotta', 'sage', 'periwinkle', 'navy', 'teal', 'rose'];
  var NM = {
    str: function (k, d, max) { var v = q.get(k); return (v == null ? (d || '') : v).replace(/[\u0000-\u001f]/g, '').slice(0, max || 60); },
    num: function (k, d, min, max) { var n = parseFloat(q.get(k)); return isFinite(n) ? Math.min(max, Math.max(min, n)) : d; },
    oneOf: function (k, list, d) { var v = q.get(k); return list.indexOf(v) >= 0 ? v : d; },
    flag: function (k, d) { var v = q.get(k); return v === '1' ? true : v === '0' ? false : d; },
    // yyyy-mm-dd -> local Date at midnight, or null if not a real date
    date: function (k) { return NM.parseDate(q.get(k)); },
    parseDate: function (v) {
      var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || ''); if (!m) return null;
      var d = new Date(+m[1], +m[2] - 1, +m[3]);
      return d.getFullYear() === +m[1] && d.getMonth() === +m[2] - 1 && d.getDate() === +m[3] ? d : null;
    },
    time: function (k) { var m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(q.get(k) || ''); return m ? [+m[1], +m[2]] : null; },
    tz: function (k) {
      var v = q.get(k); if (!v || !/^[A-Za-z_\/+\-0-9]{1,40}$/.test(v)) return undefined;
      try { new Intl.DateTimeFormat('en', { timeZone: v }); return v; } catch (e) { return undefined; }
    },
    $: function (id) { return document.getElementById(id); },
    pad: function (n) { return String(n).padStart(2, '0'); },
    setText: function (id, t) { var el = document.getElementById(id); if (el && el.textContent !== t) el.textContent = t; },
    // Run fn every second, aligned to the clock, and once right now.
    every: function (fn, ms) { fn(); return setInterval(fn, ms || 1000); }
  };
  document.documentElement.setAttribute('data-theme', NM.oneOf('theme', THEMES, 'auto'));
  window.NM = NM;
})();
