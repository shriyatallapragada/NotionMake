(function () {
  var type = NM.oneOf('type', ['day', 'week', 'month', 'year', 'custom'], 'year');
  var label = NM.str('label', '', 40);
  var now0 = new Date(), start, end, def;
  if (type === 'day') { start = new Date(now0.getFullYear(), now0.getMonth(), now0.getDate()); end = new Date(start.getTime() + 86400000); def = 'Today'; }
  else if (type === 'week') { var off = (now0.getDay() + 6) % 7; start = new Date(now0.getFullYear(), now0.getMonth(), now0.getDate() - off); end = new Date(start.getFullYear(), start.getMonth(), start.getDate() + 7); def = 'This week'; }
  else if (type === 'month') { start = new Date(now0.getFullYear(), now0.getMonth(), 1); end = new Date(now0.getFullYear(), now0.getMonth() + 1, 1); def = 'This month'; }
  else if (type === 'custom') {
    start = NM.date('start'); end = NM.date('end'); def = 'Progress';
    if (!start || !end || end <= start) { NM.setText('note', 'Add ?start=YYYY-MM-DD&end=YYYY-MM-DD to the link.'); NM.$('bar').hidden = true; NM.$('pct').hidden = true; return; }
    end = new Date(end.getFullYear(), end.getMonth(), end.getDate() + 1); // the end date counts as a full day
  }
  else { start = new Date(now0.getFullYear(), 0, 1); end = new Date(now0.getFullYear() + 1, 0, 1); def = String(now0.getFullYear()); }
  NM.setText('label', label || def);
  NM.every(function () {
    var p = Math.min(1, Math.max(0, (Date.now() - start.getTime()) / (end.getTime() - start.getTime())));
    var pct = Math.floor(p * 100);
    NM.setText('pct', pct + '%');
    NM.$('fill').style.setProperty('width', p * 100 + '%');
    NM.$('bar').setAttribute('aria-valuenow', String(pct));
    var left = Math.ceil((end.getTime() - Date.now()) / 86400000);
    NM.setText('note', p >= 1 ? 'Done!' : left <= 1 ? 'Less than a day left' : left + ' days left');
  }, 30000);
})();
