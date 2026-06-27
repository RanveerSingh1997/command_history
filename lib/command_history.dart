/// Generic immutable undo/redo ring for Dart.
///
/// Define your state type [S] and implement [Command<S>] for each action.
/// [CommandHistory<S>] is immutable and safe to use in any state container.
///
/// ```dart
/// var history = CommandHistory.initial(MyState.empty());
/// history = history.execute(AddItemCommand('hello'));
/// history = history.undo();
/// ```
library command_history;

export 'src/command.dart';
export 'src/command_history.dart';
