/// Demo terminal screens for the README screenshots. Everything here is
/// made up: a demo todo app, placeholder machines and paths.
///
/// Only glyphs the bundled JetBrains Mono Nerd Font has are used, so the
/// test renders them without a system fallback font (Claude Code's `⎿`
/// becomes `└`, its `✻` spinner `✶`).
library;

const _reset = '\x1b[0m';
const _bold = '\x1b[1m';
const _orange = '\x1b[38;5;173m';
const _green = '\x1b[32m';
const _red = '\x1b[31m';
const _blue = '\x1b[34m';
const _cyan = '\x1b[36m';
const _grey = '\x1b[90m';
const _yellow = '\x1b[33m';
const _addBg = '\x1b[48;5;22m';
const _delBg = '\x1b[48;5;52m';

String _lines(List<String> lines) => lines.join('\r\n');

final _ansi = RegExp('\x1b\\[[0-9;]*m');

/// A rounded Ink-style box, [width] cells wide, around [body].
List<String> _box(
  List<String> body, {
  required int width,
  String color = _orange,
}) {
  final inner = width - 4;
  String pad(String line) =>
      ' ' * (inner - line.replaceAll(_ansi, '').length).clamp(0, inner);
  return [
    '$color╭${'─' * (width - 2)}╮$_reset',
    for (final line in body)
      '$color│$_reset $line$_reset${pad(line)} $color│$_reset',
    '$color╰${'─' * (width - 2)}╯$_reset',
  ];
}

String _tool(String name, String argument) =>
    '$_green●$_reset $_bold$name$_reset($argument)';

String _result(String text) => '  $_grey└$_reset  $text';

List<String> _permission({required int width}) => _box([
  '${_bold}Bash command$_reset',
  '',
  '  npm test -- due-date',
  '  ${_grey}Run the due date tests$_reset',
  '',
  'Do you want to proceed?',
  '$_orange❯ 1. Yes$_reset',
  '  2. Yes, and don\'t ask again for',
  '     npm test commands',
  '  3. No, and tell Claude what to do',
  '     differently $_grey(esc)$_reset',
], width: width);

List<String> _input({required int width}) => [
  ..._box(['>'], width: width, color: _grey),
  '$_grey  ▸▸ accept edits on (shift+tab to cycle)$_reset',
];

/// Claude Code asking to run the tests (home tile "api", needs input).
String claudePermissionScreen() => _lines([
  '$_bold>$_reset Add a due date to todos and cover it',
  '  with tests',
  '',
  '$_green●$_reset I\'ll add an optional $_cyan`dueDate`$_reset field and',
  '  validate it in the create route.',
  '',
  _tool('Update', 'src/routes/todos.ts'),
  _result('Updated with ${_bold}6$_reset additions'),
  '    $_grey 41$_reset $_addBg+  dueDate: z.string().datetime()$_reset',
  '    $_grey 42$_reset $_addBg+    .optional(),                 $_reset',
  '',
  _tool('Write', 'test/due-date.test.ts'),
  _result('Wrote ${_bold}38$_reset lines'),
  '',
  ..._permission(width: 44),
]);

/// Claude Code mid-task (home tile "web", working).
String claudeWorkingScreen() => _lines([
  '$_bold>$_reset Make the todo list keyboard friendly',
  '',
  _tool('Read', 'src/components/TodoList.tsx'),
  _result('Read ${_bold}112$_reset lines'),
  '',
  _tool('Update', 'src/components/TodoList.tsx'),
  _result('Updated with ${_bold}14$_reset additions'),
  '',
  _tool('Bash', 'npm run lint'),
  _result('$_green✓$_reset 0 problems'),
  '',
  '$_orange●$_reset ${_bold}Update Todos$_reset',
  _result('$_green■$_reset Arrow keys move the selection'),
  '     $_green■$_reset Space toggles done',
  '     $_orange□$_reset ${_bold}Delete removes a todo$_reset',
  '     □ Tests for the shortcuts',
  '',
  '$_orange✶ Refactoring TodoList…$_reset $_grey(48s · esc to$_reset',
  '$_grey  interrupt)$_reset',
  '',
  ..._input(width: 44),
]);

/// Claude Code in a Herdr pane, for the terminal and menu-button screens:
/// writing tests, or asking to run them.
/// [width] is the box width in cells (46 on the phone, wider on desktop).
String claudeTerminalScreen({bool withPrompt = true, int width = 46}) =>
    _lines([
      '$_bold$_orange✶$_reset$_bold Welcome to Claude Code!$_reset',
      '$_grey  /help for help, /status for your setup$_reset',
      '$_grey  cwd: ~/todo-api$_reset',
      '',
      '$_bold>$_reset Add a due date to todos and cover it',
      '  with tests',
      '',
      '$_green●$_reset I\'ll add an optional $_cyan`dueDate`$_reset field,',
      '  validate it, and test overdue sorting.',
      '',
      _tool('Read', 'src/routes/todos.ts'),
      _result('Read ${_bold}86$_reset lines'),
      '',
      _tool('Update', 'src/routes/todos.ts'),
      _result('Updated with ${_bold}6$_reset additions and'),
      '     ${_bold}1$_reset removal',
      '     $_grey 40$_reset   title: z.string().min(1),',
      '     $_grey 41$_reset $_addBg+  dueDate: z.string()        $_reset',
      '     $_grey 42$_reset $_addBg+    .datetime().optional(),  $_reset',
      '     $_grey 43$_reset $_delBg-  done: z.boolean(),         $_reset',
      '     $_grey 43$_reset $_addBg+  done: z.boolean()          $_reset',
      '     $_grey 44$_reset $_addBg+    .default(false),         $_reset',
      '',
      _tool('Write', 'test/due-date.test.ts'),
      _result('Wrote ${_bold}38$_reset lines to test/due-date.test.ts'),
      '',
      if (withPrompt)
        ..._permission(width: width)
      else ...[
        _tool('Bash', 'npm run typecheck'),
        _result('$_green✓$_reset No type errors'),
        '',
        '$_orange●$_reset ${_bold}Update Todos$_reset',
        _result('$_green■$_reset Add dueDate to the schema'),
        '     $_green■$_reset Validate ISO dates',
        '     $_orange□$_reset ${_bold}Test overdue sorting$_reset',
        '',
        '$_orange✶ Writing tests…$_reset $_grey(21s · esc to interrupt)$_reset',
        '',
        ..._input(width: width),
      ],
    ]);

/// A plain shell running the demo app's tests (tmux).
String shellTestsScreen() => _lines([
  '${_green}demo@build-box$_reset:$_blue~/todo-web$_reset\$ npm test',
  '',
  '> todo-web@1.4.0 test',
  '> vitest run',
  '',
  ' $_green✓$_reset src/lib/dates.test.ts $_grey(6 tests)$_reset',
  ' $_green✓$_reset src/lib/store.test.ts $_grey(14 tests)$_reset',
  ' $_green✓$_reset src/components/TodoList.test.tsx',
  ' $_red✗$_reset src/components/DueDate.test.tsx',
  '   $_red→ shows overdue todos in red$_reset',
  '',
  ' Test Files  $_red${_bold}1 failed$_reset | $_green${_bold}3 passed$_reset (4)',
  '      Tests  $_red${_bold}1 failed$_reset | $_green${_bold}31 passed$_reset (32)',
  '',
  '${_green}demo@build-box$_reset:$_blue~/todo-web$_reset\$ $_yellow$_reset',
]);

/// A Vite dev server started in a tmux window, for the "Preview ready"
/// chip.
String viteDevServerScreen() => _lines([
  // Empty rows under the chip.
  '',
  '',
  '',
  '${_green}demo@workstation$_reset:$_blue~/todo-web$_reset\$ npm run dev',
  '',
  '> todo-web@1.4.0 dev',
  '> vite',
  '',
  '',
  '  $_green${_bold}VITE$_reset ${_green}v5.4.2$_reset  ${_grey}ready in$_reset ${_bold}312$_reset ${_grey}ms$_reset',
  '',
  '  $_green➜$_reset  ${_bold}Local$_reset:   ${_cyan}http://localhost:${_bold}5173$_reset$_cyan/$_reset',
  '  $_green➜$_reset  ${_bold}Network$_reset: ${_grey}use --host to expose$_reset',
  '  $_green➜$_reset  ${_grey}press$_reset ${_bold}h + enter$_reset ${_grey}to show help$_reset',
  '',
  '${_grey}10:23:41$_reset $_cyan$_bold[vite]$_reset ${_green}hmr update$_reset $_grey/src/DueDate.tsx$_reset',
  '${_grey}10:23:58$_reset $_cyan$_bold[vite]$_reset ${_green}hmr update$_reset $_grey/src/TodoList.tsx$_reset',
]);
