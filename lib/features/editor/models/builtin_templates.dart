import '../../../core/constants.dart';
import 'template_model.dart';

class BuiltinTemplate {
  final String name;
  final String description;
  final Template Function() build;
  const BuiltinTemplate(this.name, this.description, this.build);
}

final _ocean = TemplateTheme.all[1];
final _forest = TemplateTheme.all[2];
final _sunset = TemplateTheme.all[3];
final _royal = TemplateTheme.all[5];
final _blossom = TemplateTheme.all[4];

Template dailyPlanner() => Template(
  title: 'Daily Planner',
  icon: '📅',
  blocks: [
    TemplateBlock.heading('Today'),
    TemplateBlock.callout('Plan your day: top 3 priorities, then everything else.'),
    TemplateBlock.divider(),
    TemplateBlock.heading('Top 3 priorities', level: 2),
    TemplateBlock.todo('Priority 1\nPriority 2\nPriority 3'),
    TemplateBlock.heading('Schedule', level: 2),
    TemplateBlock.bullet('Morning\nAfternoon\nEvening'),
    TemplateBlock.heading('Notes', level: 2),
    TemplateBlock.paragraph(''),
  ],
).withTheme(_ocean);

final List<BuiltinTemplate> builtinTemplates = [
  BuiltinTemplate('Daily Planner', 'Priorities, schedule and notes for one day.', dailyPlanner),
  BuiltinTemplate(
    'Weekly Review',
    'Wins, lessons and next week\'s focus.',
    () => Template(
      title: 'Weekly Review',
      icon: '🗓️',
      blocks: [
        TemplateBlock.heading('This week'),
        TemplateBlock.callout('Take 15 minutes to look back before planning ahead.'),
        TemplateBlock.heading('Wins', level: 2),
        TemplateBlock.bullet('Win 1\nWin 2'),
        TemplateBlock.heading('What didn\'t go well', level: 2),
        TemplateBlock.bullet('Lesson 1'),
        TemplateBlock.heading('Next week\'s focus', level: 2),
        TemplateBlock.todo('Focus 1\nFocus 2\nFocus 3'),
        TemplateBlock.divider(),
        TemplateBlock.quote('What would make next week a success?'),
      ],
    ).withTheme(_forest),
  ),
  BuiltinTemplate(
    'Meeting Notes',
    'Agenda, discussion and action items.',
    () => Template(
      title: 'Meeting Notes',
      icon: '📝',
      blocks: [
        TemplateBlock.heading('Meeting'),
        TemplateBlock.callout('Date · Attendees · Goal', emoji: '👥'),
        TemplateBlock.heading('Agenda', level: 2),
        TemplateBlock.bullet('Topic 1\nTopic 2'),
        TemplateBlock.heading('Discussion', level: 2),
        TemplateBlock.paragraph(''),
        TemplateBlock.heading('Action items', level: 2),
        TemplateBlock.todo('Owner: task'),
      ],
    ).withTheme(_sunset),
  ),
  BuiltinTemplate(
    'Project Dashboard',
    'Goal, milestones and status side by side.',
    () => Template(
      title: 'Project Dashboard',
      icon: '🚀',
      blocks: [
        TemplateBlock.heading('Project name'),
        TemplateBlock.callout('One sentence: what does success look like?', emoji: '🎯'),
        TemplateBlock.columns([
          [
            TemplateBlock.heading('Milestones', level: 2),
            TemplateBlock.todo('Kickoff\nFirst draft\nReview\nLaunch'),
          ],
          [
            TemplateBlock.heading('Status', level: 2),
            TemplateBlock.bullet('On track / at risk / blocked'),
            TemplateBlock.heading('Next steps', level: 2),
            TemplateBlock.bullet('Step 1'),
          ],
        ]),
        TemplateBlock.toggle('Resources and links', [TemplateBlock.bullet('Link or document')]),
        TemplateBlock.toggle('Meeting notes', [TemplateBlock.paragraph('')]),
      ],
    ).withTheme(_royal),
  ),
  BuiltinTemplate(
    'Reading List',
    'To read, reading and finished in three columns.',
    () => Template(
      title: 'Reading List',
      icon: '📖',
      blocks: [
        TemplateBlock.heading('My books'),
        TemplateBlock.callout('Move titles between columns as you go.', emoji: '📚'),
        TemplateBlock.columns([
          [TemplateBlock.heading('To read', level: 2), TemplateBlock.todo('Book 1\nBook 2')],
          [TemplateBlock.heading('Reading', level: 2), TemplateBlock.todo('Book 3')],
          [TemplateBlock.heading('Finished', level: 2), TemplateBlock.bullet('Book 4')],
        ]),
        TemplateBlock.divider(),
        TemplateBlock.toggle('Favorite quotes', [TemplateBlock.quote('')]),
      ],
    ).withTheme(_forest),
  ),
  BuiltinTemplate(
    'Weekly Planner',
    'Plan each day of the week in columns.',
    () => Template(
      title: 'Weekly Planner',
      icon: '🗒️',
      blocks: [
        TemplateBlock.heading('This week'),
        TemplateBlock.callout('Pick one big goal for the week.', emoji: '🎯'),
        TemplateBlock.columns([
          [TemplateBlock.heading('Mon', level: 3), TemplateBlock.todo('Task')],
          [TemplateBlock.heading('Tue', level: 3), TemplateBlock.todo('Task')],
          [TemplateBlock.heading('Wed', level: 3), TemplateBlock.todo('Task')],
        ]),
        TemplateBlock.columns([
          [TemplateBlock.heading('Thu', level: 3), TemplateBlock.todo('Task')],
          [TemplateBlock.heading('Fri', level: 3), TemplateBlock.todo('Task')],
          [TemplateBlock.heading('Weekend', level: 3), TemplateBlock.todo('Task')],
        ]),
      ],
    ).withTheme(_ocean),
  ),
  BuiltinTemplate(
    'Student Hub',
    'Courses, assignments and study notes.',
    () => Template(
      title: 'Student Hub',
      icon: '🎓',
      blocks: [
        TemplateBlock.heading('This semester'),
        TemplateBlock.callout('Stay on top of deadlines.', emoji: '📚'),
        TemplateBlock.heading('Courses', level: 2),
        TemplateBlock.bullet('Course 1\nCourse 2\nCourse 3'),
        TemplateBlock.heading('Assignments', level: 2),
        TemplateBlock.todo('Assignment 1\nAssignment 2'),
        TemplateBlock.heading('Study notes', level: 2),
        TemplateBlock.paragraph(''),
      ],
    ).withTheme(_blossom),
  ),
  BuiltinTemplate(
    'Task Tracker',
    'A table of tasks with a progress bar that follows the Done checkbox.',
    () => Template(
      title: 'Task Tracker',
      icon: '✅',
      blocks: [
        TemplateBlock.heading('Tasks'),
        TemplateBlock.callout(
          'Add rows below. Click a column header in Notion to sort or filter.',
          emoji: '💡',
        ),
        TemplateBlock.database(
          'Tasks',
          [
            DbProperty.make('Task', DbPropType.title),
            DbProperty.make('Priority', DbPropType.select, options: 'High, Medium, Low'),
            DbProperty.make('Due', DbPropType.date),
            DbProperty.make('Done', DbPropType.checkbox),
          ],
          [
            {'Task': 'Write the first draft', 'Priority': 'High', 'Done': 'false'},
            {'Task': 'Review with a friend', 'Priority': 'Medium', 'Done': 'false'},
            {'Task': 'Publish', 'Priority': 'Low', 'Done': 'false'},
          ],
          'Done', // progress bar follows the Done checkbox
        ),
      ],
    ).withTheme(_sunset),
  ),
  BuiltinTemplate(
    'Habit Tracker',
    'Habits with how often and whether you did them today.',
    () => Template(
      title: 'Habit Tracker',
      icon: '🔥',
      blocks: [
        TemplateBlock.heading('Habits'),
        TemplateBlock.callout('Tick "Today" each day. Small and steady wins.', emoji: '🌱'),
        TemplateBlock.database(
          'Habits',
          [
            DbProperty.make('Habit', DbPropType.title),
            DbProperty.make('Frequency', DbPropType.select, options: 'Daily, Weekdays, Weekly'),
            DbProperty.make('Streak', DbPropType.number),
            DbProperty.make('Today', DbPropType.checkbox),
          ],
          [
            {'Habit': 'Drink water', 'Frequency': 'Daily', 'Streak': '0', 'Today': 'false'},
            {'Habit': 'Read 10 pages', 'Frequency': 'Daily', 'Streak': '0', 'Today': 'false'},
            {'Habit': 'Exercise', 'Frequency': 'Weekdays', 'Streak': '0', 'Today': 'false'},
          ],
        ),
      ],
    ).withTheme(_forest),
  ),
  BuiltinTemplate(
    'Book Tracker',
    'Books with author, status, rating and finish date.',
    () => Template(
      title: 'Book Tracker',
      icon: '📚',
      blocks: [
        TemplateBlock.heading('Books'),
        TemplateBlock.database(
          'Books',
          [
            DbProperty.make('Title', DbPropType.title),
            DbProperty.make('Author', DbPropType.text),
            DbProperty.make('Status', DbPropType.select, options: 'To read, Reading, Finished'),
            DbProperty.make('Rating', DbPropType.number),
            DbProperty.make('Finished', DbPropType.date),
          ],
          [
            {'Title': 'Example book', 'Author': 'Someone', 'Status': 'To read'},
          ],
        ),
        TemplateBlock.toggle('Favorite quotes', [TemplateBlock.quote('')]),
      ],
    ).withTheme(_blossom),
  ),
  BuiltinTemplate(
    'Expense Tracker',
    'Spending by category with amount and date.',
    () => Template(
      title: 'Expense Tracker',
      icon: '💸',
      blocks: [
        TemplateBlock.heading('Expenses'),
        TemplateBlock.callout('Log each purchase as a row.', emoji: '🧾'),
        TemplateBlock.database(
          'Expenses',
          [
            DbProperty.make('Item', DbPropType.title),
            DbProperty.make('Amount', DbPropType.number),
            DbProperty.make(
              'Category',
              DbPropType.multiSelect,
              options: 'Food, Transport, Fun, Bills',
            ),
            DbProperty.make('Date', DbPropType.date),
          ],
          [
            {'Item': 'Lunch', 'Amount': '12.50', 'Category': 'Food'},
            {'Item': 'Bus pass', 'Amount': '30', 'Category': 'Transport'},
          ],
        ),
      ],
    ).withTheme(_ocean),
  ),
  BuiltinTemplate(
    'Blank page',
    'Start from scratch.',
    () => Template(title: 'Untitled', icon: '📄', blocks: [TemplateBlock.paragraph('')]),
  ),
];
