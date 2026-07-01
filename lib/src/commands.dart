import 'command.dart';

/// A [Command] built from a plain function — no subclass needed.
///
/// ```dart
/// history = history.execute(
///   FunctionCommand((s) => s + 1, label: 'Increment'),
/// );
/// ```
///
/// Useful for simple one-off operations in tests or prototypes where defining
/// a full [Command] subclass would be overkill.
class FunctionCommand<S> extends Command<S> {
  const FunctionCommand(this._fn, {String? label}) : _label = label;

  final S Function(S state) _fn;
  final String? _label;

  @override
  S execute(S state) => _fn(state);

  @override
  String? get label => _label;
}

/// A [Command] that executes a list of [Command]s in sequence as one
/// undoable unit.
///
/// The composite is a no-op (at the [CommandHistory] level) only when the
/// net result equals the original state via `==`.
///
/// ```dart
/// history = history.execute(
///   CompositeCommand([MoveCommand(offset), ResizeCommand(size)],
///       label: 'Resize and Move'),
/// );
/// ```
class CompositeCommand<S> extends Command<S> {
  const CompositeCommand(this._commands, {String? label}) : _label = label;

  final List<Command<S>> _commands;
  final String? _label;

  @override
  S execute(S state) => _commands.fold(state, (s, cmd) => cmd.execute(s));

  @override
  String? get label => _label;
}
