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
/// [state], both stacks element-by-element, and [checkpoints]. This makes it
/// suitable for use as a value in Riverpod, BLoC, or `ValueNotifier` without
/// spurious rebuilds.
final class CommandHistory<S> {
  CommandHistory._({
    required this.state,
    required List<S> undoStack,
    required List<S> redoStack,
    required List<String?> undoLabels,
    required List<String?> redoLabels,
    this.maxSize,
    Map<String, CommandHistory<S>>? checkpoints,
    Command<S>? lastCommand,
  })  : _undoStack = undoStack,
        _redoStack = redoStack,
        _undoLabels = undoLabels,
        _redoLabels = redoLabels,
        _checkpoints = checkpoints ?? <String, CommandHistory<S>>{},
        _lastCommand = lastCommand;

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

  /// Builds a [CommandHistory] from an ordered list of states.
  ///
  /// The last element becomes the current [state]; earlier elements form the
  /// undo stack (oldest → newest). [states] must not be empty.
  ///
  /// Useful for restoring persisted history from storage where the intermediate
  /// states were saved but the commands that produced them were not.
  ///
  /// ```dart
  /// final h = CommandHistory.fromStates([0, 1, 2, 3]);
  /// // state = 3, undoStack = [0, 1, 2], canRedo = false
  /// ```
  factory CommandHistory.fromStates(List<S> states, {int? maxSize}) {
    assert(states.isNotEmpty, 'states must not be empty');
    assert(maxSize == null || maxSize > 0, 'maxSize must be positive');
    var undoStack = states.sublist(0, states.length - 1);
    if (maxSize != null && undoStack.length > maxSize) {
      undoStack = undoStack.sublist(undoStack.length - maxSize);
    }
    return CommandHistory._(
      state: states.last,
      undoStack: undoStack,
      redoStack: const [],
      undoLabels: List.filled(undoStack.length, null),
      redoLabels: const [],
      maxSize: maxSize,
    );
  }

  /// Builds a [CommandHistory] by replaying [commands] from [initial].
  ///
  /// Equivalent to calling [execute] sequentially for each command. The
  /// resulting history carries the same undo depth as if the user had typed
  /// each command interactively (subject to [maxSize]).
  ///
  /// ```dart
  /// final h = CommandHistory.replay(0, [Add(1), Add(2), Add(3)]);
  /// // state = 6, canUndo = true (up to 3 steps)
  /// ```
  factory CommandHistory.replay(
    S initial,
    List<Command<S>> commands, {
    int? maxSize,
  }) {
    return commands.fold(
      CommandHistory.initial(initial, maxSize: maxSize),
      (h, cmd) => h.execute(cmd),
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
  final Map<String, CommandHistory<S>> _checkpoints;

  /// The last command successfully pushed to the undo stack.
  ///
  /// Used internally for command merging. Not exposed publicly; not included
  /// in [==] or [hashCode]. Cleared by [undo], [redo], [clearHistory],
  /// [replaceCurrent], [collapse], [transform], and [prune].
  final Command<S>? _lastCommand;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

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

  /// Full list of undo labels, oldest → newest, parallel to [undoStack].
  /// Entries are `null` for commands that did not override [Command.label].
  List<String?> get undoLabels => UnmodifiableListView(_undoLabels);

  /// Full list of redo labels, most-recent-undo first, parallel to [redoStack].
  /// Entries are `null` for commands that did not override [Command.label].
  List<String?> get redoLabels => UnmodifiableListView(_redoLabels);

  /// The state that [undo] would restore, or `null` when [canUndo] is false.
  /// Does not modify the history.
  S? get peekUndo => _undoStack.isEmpty ? null : _undoStack.last;

  /// The state that [redo] would restore, or `null` when [canRedo] is false.
  /// Does not modify the history.
  S? get peekRedo => _redoStack.isEmpty ? null : _redoStack.first;

  /// The full ordered timeline of states: `[...undoStack, state, ...redoStack]`.
  ///
  /// Index `undoStack.length` is always the current [state]. Indices below it
  /// are the past (undo history); indices above it are the future (redo stack).
  /// Useful for time-travel sliders and history-panel UIs.
  List<S> get timeline =>
      UnmodifiableListView([..._undoStack, state, ..._redoStack]);

  /// Named snapshots stored via [checkpoint].
  ///
  /// Each value is a full [CommandHistory] snapshot — state, undo/redo stacks,
  /// labels, and any nested checkpoints that existed at the time of capture.
  /// Included in [==] and [hashCode] so checkpoint changes trigger rebuilds.
  Map<String, CommandHistory<S>> get checkpoints =>
      UnmodifiableMapView(_checkpoints);

  // ---------------------------------------------------------------------------
  // Core undo/redo
  // ---------------------------------------------------------------------------

  /// Executes [command] against [state] and pushes the previous state onto the
  /// undo stack. No-ops (returns `this`) if [command] produces a state that
  /// compares equal to the current one.
  ///
  /// **Command merging**: if the previous command's [Command.mergeWith] returns
  /// a non-null result for [command], the top of the undo stack is updated
  /// in-place instead of growing. This lets consecutive commands of the same
  /// type (e.g. per-keystroke typing) collapse into one undoable step.
  ///
  /// When [maxSize] is set and the undo stack would exceed it, the oldest
  /// entry is dropped to keep the stack within bounds.
  CommandHistory<S> execute(Command<S> command) {
    final next = command.execute(state);
    if (next == state) return this;

    // Attempt command merging with the previous command.
    if (_lastCommand != null) {
      final merged = _lastCommand.mergeWith(command);
      if (merged != null) {
        assert(
          _undoLabels.isNotEmpty,
          'merge attempted but undo label stack is empty — this is a bug',
        );
        final newUndoLabels = [
          ..._undoLabels.sublist(0, _undoLabels.length - 1),
          merged.label,
        ];
        return CommandHistory._(
          state: next,
          undoStack: _undoStack,
          redoStack: const [],
          undoLabels: newUndoLabels,
          redoLabels: const [],
          maxSize: maxSize,
          checkpoints: _checkpoints,
          lastCommand: merged,
        );
      }
    }

    // Normal push.
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
      checkpoints: _checkpoints,
      lastCommand: command,
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
      checkpoints: _checkpoints,
      // _lastCommand cleared: merge hint is invalid after undo
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
      checkpoints: _checkpoints,
      // _lastCommand cleared
    );
  }

  /// Undoes [n] steps at once. Clamps to the available undo depth — does not
  /// throw if [n] exceeds [undoStack.length]. Returns `this` when [n] is 0.
  CommandHistory<S> undoN(int n) {
    assert(n >= 0, 'n must be non-negative');
    var h = this;
    for (var i = 0; i < n && h.canUndo; i++) {
      h = h.undo();
    }
    return h;
  }

  /// Redoes [n] steps at once. Clamps to the available redo depth — does not
  /// throw if [n] exceeds [redoStack.length]. Returns `this` when [n] is 0.
  CommandHistory<S> redoN(int n) {
    assert(n >= 0, 'n must be non-negative');
    var h = this;
    for (var i = 0; i < n && h.canRedo; i++) {
      h = h.redo();
    }
    return h;
  }

  // ---------------------------------------------------------------------------
  // Conditional and batch execution
  // ---------------------------------------------------------------------------

  /// Executes [command] only when [condition] is `true`; returns `this` otherwise.
  ///
  /// Useful for guard-checked commands without wrapping every call site in `if`:
  /// ```dart
  /// history = history.executeIf(PasteCommand(clipboard), condition: clipboard.isNotEmpty);
  /// ```
  CommandHistory<S> executeIf(Command<S> command, {required bool condition}) {
    return condition ? execute(command) : this;
  }

  /// Executes each command in [commands] in order, each as its own undoable step.
  ///
  /// Equivalent to chaining [execute] calls. Merging rules still apply between
  /// consecutive commands that return compatible [Command.mergeWith] results.
  ///
  /// ```dart
  /// history = history.executeMany([Add(1), Add(2), Add(3)]);
  /// ```
  CommandHistory<S> executeMany(List<Command<S>> commands) {
    return commands.fold(this, (h, cmd) => h.execute(cmd));
  }

  // ---------------------------------------------------------------------------
  // History navigation
  // ---------------------------------------------------------------------------

  /// Returns a copy of this history with [newMaxSize] applied.
  ///
  /// If [newMaxSize] is smaller than the current undo stack, the oldest
  /// entries are trimmed to fit. The redo stack and current [state] are
  /// unaffected. Pass `null` to remove the cap entirely.
  ///
  /// [_lastCommand] is preserved — the merge hint remains valid since the
  /// stacks were not rewritten.
  CommandHistory<S> withMaxSize(int? newMaxSize) {
    assert(newMaxSize == null || newMaxSize > 0, 'maxSize must be positive');
    if (newMaxSize == maxSize) return this;

    var newUndoStack = _undoStack;
    var newUndoLabels = _undoLabels;

    if (newMaxSize != null && _undoStack.length > newMaxSize) {
      final trim = _undoStack.length - newMaxSize;
      newUndoStack = _undoStack.sublist(trim);
      newUndoLabels = _undoLabels.sublist(trim);
    }

    return CommandHistory._(
      state: state,
      undoStack: newUndoStack,
      redoStack: _redoStack,
      undoLabels: newUndoLabels,
      redoLabels: _redoLabels,
      maxSize: newMaxSize,
      checkpoints: _checkpoints,
      lastCommand: _lastCommand,
    );
  }

  /// Returns the state at absolute [index] in [timeline] without modifying
  /// history. Valid range: `[0, timeline.length)`.
  S stateAt(int index) {
    final length = _undoStack.length + 1 + _redoStack.length;
    assert(index >= 0 && index < length,
        'index $index out of range [0, $length)');
    if (index < _undoStack.length) return _undoStack[index];
    if (index == _undoStack.length) return state;
    return _redoStack[index - _undoStack.length - 1];
  }

  /// Jumps to position [index] in the undo history.
  ///
  /// Valid range: `[0, undoStack.length]`.
  /// - `0` → oldest past (undo all the way).
  /// - `undoStack.length` → present (no change).
  ///
  /// Delegates to [undoN] so labels and the redo stack are handled correctly.
  CommandHistory<S> jumpToIndex(int index) {
    assert(index >= 0 && index <= _undoStack.length,
        'index $index out of range [0, ${_undoStack.length}]');
    return undoN(_undoStack.length - index);
  }

  // ---------------------------------------------------------------------------
  // History manipulation
  // ---------------------------------------------------------------------------

  /// Collapses the last [n] undo steps into a single undoable unit.
  ///
  /// After this call, one [undo] jumps back to where you were [n] steps ago.
  /// If [n] exceeds the available stack depth, the stack shrinks to one entry.
  /// The redo stack is cleared.
  ///
  /// The surviving undo label defaults to the most-recently executed command's
  /// label (i.e. `_undoLabels.last`). Pass [label] to override it.
  ///
  /// Useful after micro-command sequences (e.g. per-pixel drag pushes) that
  /// should collapse into a single undoable action at drag-end.
  CommandHistory<S> collapse(int n, {String? label}) {
    assert(n >= 2, 'collapse requires n >= 2');
    if (_undoStack.length < 2) return this;
    final removeCount = (n - 1).clamp(0, _undoStack.length - 1);
    if (removeCount == 0) return this;
    final keep = _undoStack.length - removeCount;
    final survivingLabel = label ?? _undoLabels.last;
    final newUndoLabels = [
      ..._undoLabels.sublist(0, keep - 1),
      survivingLabel,
    ];
    return CommandHistory._(
      state: state,
      undoStack: _undoStack.sublist(0, keep),
      redoStack: const [],
      undoLabels: newUndoLabels,
      redoLabels: const [],
      maxSize: maxSize,
      checkpoints: _checkpoints,
      // _lastCommand cleared: stack structure changed
    );
  }

  /// Applies [fn] to every state in the history — [state], all undo entries,
  /// and all redo entries — returning a new [CommandHistory] with transformed
  /// values. Labels are unchanged.
  ///
  /// Use this to propagate an out-of-band schema change across all snapshots
  /// at once (e.g. adding a new field after a server migration).
  CommandHistory<S> transform(S Function(S state) fn) {
    return CommandHistory._(
      state: fn(state),
      undoStack: _undoStack.map(fn).toList(),
      redoStack: _redoStack.map(fn).toList(),
      undoLabels: _undoLabels,
      redoLabels: _redoLabels,
      maxSize: maxSize,
      checkpoints: _checkpoints,
      // _lastCommand cleared: states changed, merge hint invalid
    );
  }

  /// Removes entries from the undo stack for which [test] returns `true`.
  ///
  /// The current [state] and redo stack are unchanged. Parallel label entries
  /// are removed alongside their state. Returns `this` if no entries match.
  /// Clears [_lastCommand].
  ///
  /// ```dart
  /// // Drop all undo states that are negative.
  /// history = history.prune((s) => s < 0);
  /// ```
  CommandHistory<S> prune(bool Function(S state) test) {
    final keptStack = <S>[];
    final keptLabels = <String?>[];
    for (var i = 0; i < _undoStack.length; i++) {
      if (!test(_undoStack[i])) {
        keptStack.add(_undoStack[i]);
        keptLabels.add(_undoLabels[i]);
      }
    }
    if (keptStack.length == _undoStack.length) return this;
    return CommandHistory._(
      state: state,
      undoStack: keptStack,
      redoStack: _redoStack,
      undoLabels: keptLabels,
      redoLabels: _redoLabels,
      maxSize: maxSize,
      checkpoints: _checkpoints,
      // _lastCommand cleared
    );
  }

  /// Repeatedly calls [undo] as long as [predicate] returns `true` for the
  /// current [state]. Stops when the predicate returns `false` or [canUndo]
  /// is false.
  CommandHistory<S> undoWhile(bool Function(S state) predicate) {
    var h = this;
    while (h.canUndo && predicate(h.state)) {
      h = h.undo();
    }
    return h;
  }

  /// Repeatedly calls [redo] as long as [predicate] returns `true` for the
  /// current [state]. Stops when the predicate returns `false` or [canRedo]
  /// is false.
  CommandHistory<S> redoWhile(bool Function(S state) predicate) {
    var h = this;
    while (h.canRedo && predicate(h.state)) {
      h = h.redo();
    }
    return h;
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
      checkpoints: _checkpoints,
      // _lastCommand cleared
    );
  }

  /// Returns a new history with the same [state] but empty undo/redo stacks.
  ///
  /// Checkpoints are preserved — they are independent bookmarks unaffected by
  /// history clearing. Use [clearCheckpoints] to remove them separately.
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
      checkpoints: _checkpoints,
      // _lastCommand cleared
    );
  }

  // ---------------------------------------------------------------------------
  // Named checkpoints
  // ---------------------------------------------------------------------------

  /// Saves a snapshot of this entire history under [name].
  ///
  /// If [name] already exists it is silently overwritten. The snapshot captures
  /// the full history — state, undo/redo stacks, labels, and any nested
  /// checkpoints that were present at call time.
  ///
  /// Use [restoreCheckpoint] to jump back to this exact point.
  CommandHistory<S> checkpoint(String name) {
    final updated = Map<String, CommandHistory<S>>.from(_checkpoints);
    updated[name] = this;
    return CommandHistory._(
      state: state,
      undoStack: _undoStack,
      redoStack: _redoStack,
      undoLabels: _undoLabels,
      redoLabels: _redoLabels,
      maxSize: maxSize,
      checkpoints: updated,
      lastCommand: _lastCommand,
    );
  }

  /// Returns the history snapshot previously saved under [name].
  ///
  /// Asserts that [name] exists — call [hasCheckpoint] first if unsure.
  ///
  /// The returned history reflects exactly what was saved: its own state,
  /// undo/redo stacks, and nested checkpoints at snapshot time.
  CommandHistory<S> restoreCheckpoint(String name) {
    assert(
      _checkpoints.containsKey(name),
      'no checkpoint named "$name" — call hasCheckpoint first',
    );
    return _checkpoints[name]!;
  }

  /// Returns a copy of this history without the checkpoint named [name].
  /// Returns `this` if [name] does not exist.
  CommandHistory<S> deleteCheckpoint(String name) {
    if (!_checkpoints.containsKey(name)) return this;
    final updated = Map<String, CommandHistory<S>>.from(_checkpoints)
      ..remove(name);
    return CommandHistory._(
      state: state,
      undoStack: _undoStack,
      redoStack: _redoStack,
      undoLabels: _undoLabels,
      redoLabels: _redoLabels,
      maxSize: maxSize,
      checkpoints: updated,
      lastCommand: _lastCommand,
    );
  }

  /// Returns a copy of this history with all checkpoints removed.
  /// Returns `this` if there are none.
  CommandHistory<S> clearCheckpoints() {
    if (_checkpoints.isEmpty) return this;
    return CommandHistory._(
      state: state,
      undoStack: _undoStack,
      redoStack: _redoStack,
      undoLabels: _undoLabels,
      redoLabels: _redoLabels,
      maxSize: maxSize,
      // checkpoints omitted → empty map via default
      lastCommand: _lastCommand,
    );
  }

  /// Returns `true` if a checkpoint named [name] has been stored.
  bool hasCheckpoint(String name) => _checkpoints.containsKey(name);

  // ---------------------------------------------------------------------------
  // Equality, hash, toString
  // ---------------------------------------------------------------------------

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
    // Deep map equality — Dart's Map.== uses identity, not content.
    if (_checkpoints.length != other._checkpoints.length) return false;
    for (final key in _checkpoints.keys) {
      if (!other._checkpoints.containsKey(key)) return false;
      if (_checkpoints[key] != other._checkpoints[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    // XOR-based hash for checkpoints: order-independent so insert-order
    // differences (e.g. delete + re-add) don't produce different hashes.
    var cpHash = 0;
    for (final e in _checkpoints.entries) {
      cpHash ^= Object.hash(e.key, e.value);
    }
    return Object.hash(
      state,
      Object.hashAll(_undoStack),
      Object.hashAll(_redoStack),
      cpHash,
    );
  }

  @override
  String toString() =>
      'CommandHistory(state: $state, undo: ${_undoStack.length}, redo: ${_redoStack.length})';
}
