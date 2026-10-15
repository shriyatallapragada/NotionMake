(function () {
  var date = NM.date('date'), time = NM.time('time') || [0, 0];
  var label = NM.str('label', '', 40);
  if (label) NM.setText('label', label); else NM.$('label').hidden = true;
  if (!date) { NM.$('units').hidden = true; NM.setText('note', 'Add ?date=YYYY-MM-DD to the link to set the date.'); return; }
  var target = new Date(date.getFullYear(), date.getMonth(), date.getDate(), time[0], time[1]).getTime();
  var dayMs = 86400000;
  NM.every(function () {
    var diff = target - Date.now(), past = diff < 0, a = Math.abs(diff);
    var d = Math.floor(a / dayMs), h = Math.floor(a % dayMs / 3600000), m = Math.floor(a % 3600000 / 60000), s = Math.floor(a % 60000 / 1000);
    if (past) { d = h = m = s = 0; }
    NM.setText('d', String(d)); NM.setText('h', NM.pad(h)); NM.setText('m', NM.pad(m)); NM.setText('s', NM.pad(s));
    if (!past) {
      NM.setText('note', 'until ' + date.toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }));
    } else {
      var ago = Math.floor(a / dayMs);
      NM.setText('note', ago < 1 ? 'It is today!' : ago + (ago === 1 ? ' day ago' : ' days ago'));
    }
  }, 1000);
})();
