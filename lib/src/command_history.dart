import 'dart:collection';

import 'command.dart';

/// Immutable undo/redo ring for any state type [S].
///
/// Every mutation returns a new [CommandHistory] — the current instance is
/// never modified. Suitable for use inside Riverpod Notifiers, BLoC, or any
/// other state container.
///
/// ```dart
/// var history = CommandHistory.initial(0, maxSize: 50);
/// history = history.execute(IncrementCommand()); // state → 1
/// history = history.execute(IncrementCommand()); // state → 2
/// history = history.undo();                      // state → 1
/// history = history.redo();                      // state → 2
/// ```
///
/// **Immutable state requirement**: [S] must be immutable (or treated as
/// read-only). Mutating a state object in-place after storing it corrupts
/// the undo/redo stacks.
///
/// **Equality**: [CommandHistory] implements `==` and [hashCode] by comparing
/// [state] and both stacks element-by-element. This makes it suitable for use
/// as a value in Riverpod, BLoC, or `ValueNotifier` without spurious rebuilds.
final class CommandHistory<S> {
  CommandHistory._({
    required this.state,
    required List<S> undoStack,
    required List<S> redoStack,
    required List<String?> undoLabels,
    required List<String?> redoLabels,
    this.maxSize,
  })  : _undoStack = undoStack,
        _redoStack = redoStack,
        _undoLabels = undoLabels,
        _redoLabels = redoLabels;

  /// Creates a [CommandHistory] with [initialState] and empty stacks.
  ///
  /// [maxSize] caps how many undo entries are kept. When exceeded, the oldest
  /// entry is dropped. Pass `null` (default) for unlimited history.
  factory CommandHistory.initial(S initialState, {int? maxSize}) {
    assert(maxSize == null || maxSize > 0, 'maxSize must be positive');
    return CommandHistory._(
      state: initialState,
      undoStack: const [],
      redoStack: const [],
      undoLabels: const [],
      redoLabels: const [],
      maxSize: maxSize,
    );
  }

  /// The current state.
  final S state;

  /// Maximum number of undo entries to retain. `null` means unlimited.
  final int? maxSize;

  final List<S> _undoStack;
  final List<S> _redoStack;
  final List<String?> _undoLabels;
  final List<String?> _redoLabels;

  /// Unmodifiable view of the undo stack (oldest → newest).
  List<S> get undoStack => UnmodifiableListView(_undoStack);

  /// Unmodifiable view of the redo stack (most-recent-undo first).
  List<S> get redoStack => UnmodifiableListView(_redoStack);

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Label of the command that will be undone, e.g. `"Draw Stroke"`.
  /// `null` when [canUndo] is false or the last command had no label.
  String? get undoLabel => _undoLabels.isEmpty ? null : _undoLabels.last;

  /// Label of the command that will be redone, e.g. `"Draw Stroke"`.
  /// `null` when [canRedo] is false or the undone command had no label.
  String? get redoLabel => _redoLabels.isEmpty ? null : _redoLabels.first;

  /// Executes [command] against [state] and pushes the previous state onto the
  /// undo stack. No-ops (returns `this`) if [command] returns a state that
  /// compares equal to the current one via `==`.
  ///
  /// When [maxSize] is set and the undo stack would exceed it, the oldest
  /// entry is dropped to keep the stack within bounds.
  CommandHistory<S> execute(Command<S> command) {
    final next = command.execute(state);
    if (next == state) return this;

    var newUndoStack = [..._undoStack, state];
    var newUndoLabels = [..._undoLabels, command.label];

    if (maxSize != null && newUndoStack.length > maxSize!) {
      final trim = newUndoStack.length - maxSize!;
      newUndoStack = newUndoStack.sublist(trim);
      newUndoLabels = newUndoLabels.sublist(trim);
    }

    return CommandHistory._(
      state: next,
      undoStack: newUndoStack,
      redoStack: const [],
      undoLabels: newUndoLabels,
      redoLabels: const [],
      maxSize: maxSize,
    );
  }

  /// Reverts to the previous state. No-ops when [canUndo] is false.
  CommandHistory<S> undo() {
    if (!canUndo) return this;
    return CommandHistory._(
      state: _undoStack.last,
      undoStack: _undoStack.sublist(0, _undoStack.length - 1),
      redoStack: [state, ..._redoStack],
      undoLabels: _undoLabels.sublist(0, _undoLabels.length - 1),
      redoLabels: [_undoLabels.last, ..._redoLabels],
      maxSize: maxSize,
    );
  }

  /// Re-applies the most recently undone state. No-ops when [canRedo] is false.
  CommandHistory<S> redo() {
    if (!canRedo) return this;
    return CommandHistory._(
      state: _redoStack.first,
      undoStack: [..._undoStack, state],
      redoStack: _redoStack.sublist(1),
      undoLabels: [..._undoLabels, _redoLabels.first],
      redoLabels: _redoLabels.sublist(1),
      maxSize: maxSize,
    );
  }

  /// Replaces the current state without adding an undo entry.
  ///
  /// Optionally maps [mapUndo] / [mapRedo] over the existing stacks — useful
  /// when an out-of-band update (e.g. server sync) must be reflected in history
  /// so that undo/redo do not restore stale states. If neither mapper is
  /// provided the existing stacks are preserved as-is.
  CommandHistory<S> replaceCurrent(
    S next, {
    S Function(S s)? mapUndo,
    S Function(S s)? mapRedo,
  }) {
    return CommandHistory._(
      state: next,
      undoStack: mapUndo == null
          ? _undoStack
          : List.unmodifiable(_undoStack.map(mapUndo)),
      redoStack: mapRedo == null
          ? _redoStack
          : List.unmodifiable(_redoStack.map(mapRedo)),
      undoLabels: _undoLabels,
      redoLabels: _redoLabels,
      maxSize: maxSize,
    );
  }

  /// Returns a new history with the same [state] but empty undo/redo stacks.
  ///
  /// Useful after a save event when the user should not be able to undo past
  /// the save point.
  CommandHistory<S> clearHistory() {
    return CommandHistory._(
      state: state,
      undoStack: const [],
      redoStack: const [],
      undoLabels: const [],
      redoLabels: const [],
      maxSize: maxSize,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CommandHistory<S>) return false;
    if (other.state != state) return false;
    if (other._undoStack.length != _undoStack.length) return false;
    if (other._redoStack.length != _redoStack.length) return false;
    for (var i = 0; i < _undoStack.length; i++) {
      if (_undoStack[i] != other._undoStack[i]) return false;
    }
    for (var i = 0; i < _redoStack.length; i++) {
      if (_redoStack[i] != other._redoStack[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        state,
        Object.hashAll(_undoStack),
        Object.hashAll(_redoStack),
      );

  @override
  String toString() =>
      'CommandHistory(state: $state, undo: ${_undoStack.length}, redo: ${_redoStack.length})';
}
