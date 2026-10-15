(function () {
  // Short, original lines. Tags: study, focus, calm.
  var Q = [
    ['study', 'Small steps, taken daily, add up to big change.'],
    ['study', 'You do not have to be perfect, just keep showing up.'],
    ['study', 'Today I learn one new thing, and that is enough.'],
    ['study', 'Mistakes are the notes your brain takes for next time.'],
    ['study', 'Start before you feel ready.'],
    ['study', 'Hard today means easier tomorrow.'],
    ['study', 'Curious beats clever.'],
    ['study', 'Ask the question. Someone else needed it asked.'],
    ['study', 'Rest is part of studying.'],
    ['study', 'One page now is better than ten pages later.'],
    ['focus', 'One task. One timer. Begin.'],
    ['focus', 'Put the phone down. Pick the work up.'],
    ['focus', 'Finish the next small thing.'],
    ['focus', 'Deep work starts with a single quiet minute.'],
    ['focus', 'Progress, not perfection.'],
    ['focus', 'Decide what matters, then do that first.'],
    ['focus', 'Twenty-five minutes is shorter than you think.'],
    ['focus', 'Done is a wonderful thing to be.'],
    ['focus', 'Make it work, then make it nice.'],
    ['focus', 'Your future self is watching. Make them proud.'],
    ['calm', 'Breathe in. Breathe out. Begin again.'],
    ['calm', 'There is room for you to go at your own pace.'],
    ['calm', 'Not everything has to be solved today.'],
    ['calm', 'Be kind to yourself, you are doing a lot.'],
    ['calm', 'A calm mind finds the next step.'],
    ['calm', 'Water, stretch, sunlight. Then back to it.'],
    ['calm', 'Slow is smooth, and smooth is fast.'],
    ['calm', 'This moment is enough.'],
    ['calm', 'Let it be good enough for now.'],
    ['calm', 'You have handled hard days before.']
  ];
  var tag = NM.oneOf('tag', ['any', 'study', 'focus', 'calm'], 'any');
  var list = Q.filter(function (x) { return tag === 'any' || x[0] === tag; });
  var day = Math.floor((Date.now() - new Date(new Date().getFullYear(), 0, 0)) / 86400000), shift = 0;
  function show() { NM.setText('text', '“' + list[(day + shift) % list.length][1] + '”'); }
  NM.$('next').addEventListener('click', function () { shift++; show(); });
  show();
})();
