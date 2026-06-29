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
