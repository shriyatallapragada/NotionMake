(function () {
  // Tasks come from the link: ?items=Read ch. 1|Write essay|Revise   (up to 30)
  var items = NM.str('items', '', 2400).split('|').map(function (s) { return s.trim().slice(0, 60); }).filter(Boolean).slice(0, 30);
  var title = NM.str('title', '', 40);
  if (title) NM.setText('label', title); else NM.$('label').hidden = true;
  if (!items.length) {
    NM.$('bar').hidden = true; NM.$('reset').hidden = true; NM.$('pct').parentNode.hidden = true;
    NM.setText('note', 'Add ?items=Task one|Task two to the link.');
    return;
  }
  var pre = NM.str('done', '', 120).split(',').map(function (n) { return parseInt(n, 10); });
  var state = items.map(function (_, i) { return pre.indexOf(i + 1) >= 0; });

  // Progress is remembered in this browser (not synced between devices).
  function hash(s) { var h = 5381; for (var i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0; return (h >>> 0).toString(36); }
  var key = 'nm-checklist:' + hash(title + '\n' + items.join('|'));
  function load() {
    try {
      var saved = JSON.parse(localStorage.getItem(key) || 'null');
      if (Array.isArray(saved) && saved.length === items.length) state = saved.map(Boolean);
    } catch (e) { /* storage unavailable: keep the starting state */ }
  }
  function save() { try { localStorage.setItem(key, JSON.stringify(state)); } catch (e) { /* ignore */ } }
  load();

  var list = NM.$('list'), boxes = [];
  items.forEach(function (text, i) {
    var li = document.createElement('li'), label = document.createElement('label');
    var box = document.createElement('input'), span = document.createElement('span');
    box.type = 'checkbox';
    span.textContent = text; // always text, never HTML
    box.addEventListener('change', function () { state[i] = box.checked; save(); render(); });
    label.appendChild(box); label.appendChild(span); li.appendChild(label); list.appendChild(li);
    boxes.push({ li: li, box: box });
  });

  function render() {
    var done = state.filter(Boolean).length, pct = Math.round(done / items.length * 100);
    boxes.forEach(function (b, i) { b.box.checked = state[i]; b.li.className = state[i] ? 'done' : ''; });
    NM.setText('pct', pct + '%');
    NM.setText('count', done + ' of ' + items.length + ' done');
    NM.$('fill').style.setProperty('width', pct + '%');
    NM.$('bar').setAttribute('aria-valuenow', String(pct));
    NM.setText('note', done === items.length ? 'All done! 🎉' : '');
  }
  NM.$('reset').addEventListener('click', function () { state = items.map(function () { return false; }); save(); render(); });
  render();
})();
