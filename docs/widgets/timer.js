(function () {
  var mode = NM.oneOf('mode', ['pomodoro', 'countdown', 'stopwatch'], 'pomodoro');
  var focus = NM.num('focus', 25, 1, 180), brk = NM.num('break', 5, 1, 60), lng = NM.num('long', 15, 1, 120);
  var rounds = Math.round(NM.num('rounds', 4, 1, 12)), mins = NM.num('minutes', 10, 1, 600), auto = NM.flag('auto', false);
  var phase = 'focus', round = 1, running = false, elapsed = 0, startedAt = 0, timerId = null;
  var names = { focus: 'Focus', brk: 'Short break', lng: 'Long break' };

  function total() {
    if (mode === 'pomodoro') return (phase === 'focus' ? focus : phase === 'brk' ? brk : lng) * 60000;
    return mins * 60000;
  }
  function used() { return elapsed + (running ? Date.now() - startedAt : 0); }
  function fmt(ms, up) {
    var s = up ? Math.floor(ms / 1000) : Math.ceil(ms / 1000);
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return (h ? h + ':' + NM.pad(m) : NM.pad(m)) + ':' + NM.pad(sec);
  }
  function beep() {
    try {
      var C = window.AudioContext || window.webkitAudioContext, a = new C();
      [0, 0.25, 0.5].forEach(function (t) {
        var o = a.createOscillator(), g = a.createGain();
        o.frequency.value = 880; g.gain.value = 0.15; o.connect(g); g.connect(a.destination);
        o.start(a.currentTime + t); o.stop(a.currentTime + t + 0.15);
      });
    } catch (e) { /* sound is optional */ }
  }
  function render() {
    var u = used(), t = total(), shown;
    if (mode === 'stopwatch') { shown = fmt(u, true); NM.$('fill').style.setProperty('width', '0%'); }
    else { shown = fmt(Math.max(0, t - u), false); NM.$('fill').style.setProperty('width', Math.min(100, u / t * 100) + '%'); }
    NM.setText('time', shown);
    NM.setText('mode', mode === 'pomodoro' ? names[phase] : mode === 'countdown' ? 'Countdown' : 'Stopwatch');
    NM.setText('round', mode === 'pomodoro' ? 'Round ' + round + ' of ' + rounds : '');
    NM.setText('go', running ? 'Pause' : (u > 0 ? 'Resume' : 'Start'));
    document.title = shown + ' · ' + NM.$('mode').textContent;
  }
  function advance() {
    if (mode !== 'pomodoro') return;
    if (phase === 'focus') phase = round < rounds ? 'brk' : 'lng';
    else { if (phase === 'lng') round = 1; else round++; phase = 'focus'; }
    elapsed = 0; running = false; stop();
    if (auto) start();
  }
  function stop() { if (timerId) { clearInterval(timerId); timerId = null; } }
  function start() { running = true; startedAt = Date.now(); stop(); timerId = setInterval(loop, 250); render(); }
  function pause() { elapsed = used(); running = false; stop(); render(); }
  function loop() {
    if (mode !== 'stopwatch' && used() >= total()) {
      beep();
      if (mode === 'pomodoro') { advance(); }
      else { elapsed = total(); running = false; stop(); }
    }
    render();
  }
  NM.$('go').addEventListener('click', function () { running ? pause() : start(); });
  NM.$('reset').addEventListener('click', function () { stop(); running = false; elapsed = 0; phase = 'focus'; round = 1; render(); });
  if (mode === 'pomodoro') {
    NM.$('skip').hidden = false;
    NM.$('skip').addEventListener('click', function () { var was = running; advance(); if (was && !auto) start(); });
  }
  render();
})();
