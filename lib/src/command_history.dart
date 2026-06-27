import 'command.dart';

/// Immutable undo/redo ring for any state type [S].
///
/// Every mutation returns a new [CommandHistory] — the current instance is
/// never modified. Suitable for use inside Riverpod Notifiers, BLoC, or any
/// other state container.
///
/// ```dart
/// var history = CommandHistory.initial(0);
/// history = history.execute(IncrementCommand()); // state → 1
/// history = history.execute(IncrementCommand()); // state → 2
/// history = history.undo();                      // state → 1
/// history = history.redo();                      // state → 2
/// ```
final class CommandHistory<S> {
  const CommandHistory._({
    required this.state,
    required this.undoStack,
    required this.redoStack,
  });

  factory CommandHistory.initial(S initialState) {
    return CommandHistory._(
      state: initialState,
      undoStack: const [],
      redoStack: const [],
    );
  }

  /// The current state.
  final S state;
  final List<S> undoStack;
  final List<S> redoStack;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  /// Executes [command] against [state] and pushes the previous state onto the
  /// undo stack. No-ops if [command] returns an identical state.
  CommandHistory<S> execute(Command<S> command) {
    final next = command.execute(state);
    if (next == state) return this;
    return CommandHistory._(
      state: next,
      undoStack: [...undoStack, state],
      redoStack: const [],
    );
  }

  /// Reverts to the previous state. No-ops when [canUndo] is false.
  CommandHistory<S> undo() {
    if (!canUndo) return this;
    return CommandHistory._(
      state: undoStack.last,
      undoStack: undoStack.sublist(0, undoStack.length - 1),
      redoStack: [state, ...redoStack],
    );
  }

  /// Re-applies the most recently undone state. No-ops when [canRedo] is false.
  CommandHistory<S> redo() {
    if (!canRedo) return this;
    return CommandHistory._(
      state: redoStack.first,
      undoStack: [...undoStack, state],
      redoStack: redoStack.sublist(1),
    );
  }

  /// Replaces the current state without touching the undo/redo stacks.
  ///
  /// Optionally maps [mapUndo] / [mapRedo] over the existing stacks — useful
  /// when an out-of-band update (e.g. server sync) must be reflected in history
  /// so that undo/redo do not restore stale states.
  CommandHistory<S> replaceCurrent(
    S next, {
    S Function(S state)? mapUndo,
    S Function(S state)? mapRedo,
  }) {
    return CommandHistory._(
      state: next,
      undoStack: mapUndo == null
          ? undoStack
          : undoStack.map(mapUndo).toList(growable: false),
      redoStack: mapRedo == null
          ? redoStack
          : redoStack.map(mapRedo).toList(growable: false),
    );
  }
}
