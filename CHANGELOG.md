## 0.4.0

- **Command merging** — `Command<S>` gains `mergeWith(Command<S> next) → Command<S>?` (default `null`).
  Override it to coalesce consecutive commands of the same type into a single undoable step (e.g.
  per-keystroke typing). When `execute` is called and the previous command returns a non-null merge
  result, the top of the undo stack is extended in-place instead of growing. Undo still reverses the
  entire merged batch in one step.
- **Named checkpoints** — full history snapshots stored by name:
  - `checkpoint(String name)` — save the current history under a key (silently overwrites).
  - `restoreCheckpoint(String name)` — jump back to the exact state, stacks, and labels at snapshot
    time (asserts that the name exists).
  - `deleteCheckpoint(String name)` / `clearCheckpoints()` — remove one or all checkpoints.
  - `hasCheckpoint(String name)` — boolean existence check.
  - `checkpoints` getter — unmodifiable `Map<String, CommandHistory<S>>`.
  - Checkpoints survive `execute`, `undo`, `redo`, and `clearHistory`. They are included in `==` and
    `hashCode` so checkpoint changes trigger Riverpod/BLoC rebuilds.
- **`CommandHistory.fromStates(List<S> states, {int? maxSize})`** factory — reconstruct history from
  a list of persisted state values: the last element becomes `state`, earlier elements form the undo
  stack oldest → newest. Useful when states were saved to disk but not the commands.
- **`CommandHistory.replay(S initial, List<Command<S>> commands, {int? maxSize})`** factory —
  rebuild history by replaying a list of commands from an initial state. Equivalent to chaining
  `execute` calls; merging rules apply between consecutive commands.
- **`executeIf(Command<S> command, {required bool condition})`** — executes only when `condition` is
  `true`; returns `this` otherwise. Eliminates per-call-site `if` guards.
- **`executeMany(List<Command<S>> commands)`** — executes a list of commands in order, each as its
  own undo step. Merging rules still apply between consecutive entries.
- **`prune(bool Function(S state) test)`** — removes entries from the undo stack for which `test`
  returns `true`, leaving the current state and redo stack intact. Parallel label entries are removed
  alongside their state entries.
- Tests: 136 → 200.

## 0.3.0

- **`FunctionCommand<S>`**: build a command from a plain function with an optional label — no
  subclass needed (`FunctionCommand((s) => s + 1, label: 'Increment')`).
- **`CompositeCommand<S>`**: execute a list of commands as one atomic undo step
  (`CompositeCommand([MoveCmd(), ResizeCmd()], label: 'Resize and Move')`). The no-op check
  applies to the net result, so a fully no-op composite never pushes to the stack.
- **`undoLabels` / `redoLabels`** (plural): unmodifiable `List<String?>` getters exposing the
  full label stacks oldest→newest / most-recent-undo-first, parallel to `undoStack`/`redoStack`.
  Useful for building a history-panel UI.
- **`undoN(int n)` / `redoN(int n)`**: undo or redo *n* steps at once. Clamps to available
  depth (does not throw). Asserts `n >= 0`.
- **`withMaxSize(int? newMaxSize)`**: returns a copy of the history with a new cap. If the new
  cap is smaller than the current undo stack, the oldest entries are trimmed. Pass `null` to
  remove the cap. Returns `this` when the cap is unchanged.
- **`peekUndo` / `peekRedo`**: `S?` getters returning the state that `undo()`/`redo()` would
  restore, without applying the operation. Return `null` when the respective stack is empty.
- **`timeline`** getter: `List<S>` of every state in order — `[...undoStack, state, ...redoStack]`.
  Index `undoStack.length` is always the present. Useful for time-travel sliders.
- **`stateAt(int index)`**: read any state in [timeline] by absolute index without jumping there.
- **`jumpToIndex(int index)`**: jump to any past position in the undo history in one call
  (`0` = oldest, `undoStack.length` = present).
- **`collapse(int n, {String? label})`**: squash the last *n* undo entries into one step — the
  surviving label defaults to the most-recently executed command's label. Useful at drag-end
  events to avoid hundreds of micro-commands in the undo stack.
- **`transform(S Function(S) fn)`**: apply a function to *every* state in the history (current +
  all undo + all redo entries) at once. Propagates a schema migration or server-sync change
  across the entire snapshot ring without clearing history.
- **`undoWhile(bool Function(S) predicate)` / `redoWhile(bool Function(S) predicate)`**: keep
  undoing/redoing as long as the current state satisfies the predicate. Stop when it doesn't or
  the respective stack is exhausted.
- Tests: 58 → 136.

## 0.2.0

**Breaking change**: `Command<S>` is now `abstract class` (was `abstract interface class`).
Change `implements Command<S>` to `extends Command<S>` in your command classes.

- **Immutable stacks**: `undoStack`/`redoStack` are now exposed via `UnmodifiableListView` — any
  attempt to mutate them throws `UnsupportedError`. `replaceCurrent` with mappers uses
  `List.unmodifiable()` for the same guarantee.
- **Command labels**: `Command` gains `String? get label => null`. Override it to drive
  `CommandHistory.undoLabel` / `CommandHistory.redoLabel` (e.g. `"Undo Paint Stroke"`).
- **Bounded history**: `CommandHistory.initial(state, maxSize: N)` caps undo depth; oldest
  entry is dropped on overflow.
- **Value equality**: `==` and `hashCode` compare state + both stacks element-by-element,
  enabling use in Riverpod/BLoC state containers without spurious rebuilds and as `Map` keys.
- **`clearHistory()`**: resets both stacks while preserving `state` and `maxSize` — useful
  after a save-point event.
- **`toString()`**: `CommandHistory(state: 5, undo: 2, redo: 0)` for debugger output.
- Tests: 26 → 58.

## 0.1.0

- Initial extraction from sdraw monorepo.
- `Command<S>`: abstract interface for reversible state operations.
- `CommandHistory<S>`: generic immutable undo/redo ring.
- No Flutter dependency — pure Dart.
