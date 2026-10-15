(function () {
  var startMon = NM.oneOf('start', ['mon', 'sun'], 'mon') === 'mon';
  var marks = {};
  NM.str('mark', '', 700).split(',').slice(0, 62).forEach(function (s) { var d = NM.parseDate(s.trim()); if (d) marks[d.getTime()] = true; });
  var now = new Date(), view = new Date(now.getFullYear(), now.getMonth(), 1);
  var mm = /^(\d{4})-(\d{2})$/.exec(NM.str('month', '', 7));
  if (mm && +mm[2] >= 1 && +mm[2] <= 12) view = new Date(+mm[1], +mm[2] - 1, 1);
  var grid = NM.$('grid');

  function render() {
    grid.textContent = '';
    NM.setText('title', view.toLocaleDateString(undefined, { month: 'long', year: 'numeric' }));
    for (var i = 0; i < 7; i++) {
      var wd = new Date(2024, 0, (startMon ? 1 : 7) + i); // 2024-01-01 is a Monday
      var h = document.createElement('div'); h.className = 'cal-h'; h.textContent = wd.toLocaleDateString(undefined, { weekday: 'narrow' });
      grid.appendChild(h);
    }
    var lead = (view.getDay() + (startMon ? 6 : 0)) % 7;
    for (var b = 0; b < lead; b++) grid.appendChild(document.createElement('div'));
    var days = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate();
    var today = new Date(); today.setHours(0, 0, 0, 0);
    for (var d = 1; d <= days; d++) {
      var date = new Date(view.getFullYear(), view.getMonth(), d), cell = document.createElement('div');
      cell.className = 'cal-d' + (date.getTime() === today.getTime() ? ' cal-today' : '') + (marks[date.getTime()] ? ' cal-mark' : '');
      cell.textContent = String(d);
      grid.appendChild(cell);
    }
  }
  NM.$('prev').addEventListener('click', function () { view = new Date(view.getFullYear(), view.getMonth() - 1, 1); render(); });
  NM.$('next').addEventListener('click', function () { view = new Date(view.getFullYear(), view.getMonth() + 1, 1); render(); });
  NM.$('today').addEventListener('click', function () { view = new Date(now.getFullYear(), now.getMonth(), 1); render(); });
  render();
})();
