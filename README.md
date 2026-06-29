# command_history

Generic immutable undo/redo ring for Dart. Type-safe `CommandHistory<S>` with
a `Command<S>` base class — no Flutter dependency, works in any Dart environment
including pure Dart, Flutter (Riverpod, BLoC, etc.), and server-side.

## Features

- **Immutable** — every operation returns a new `CommandHistory<S>`; the original is never mutated
- **Protected stacks** — `undoStack`/`redoStack` are `UnmodifiableListView`; external code cannot corrupt history
- **Bounded history** — optional `maxSize` cap drops the oldest entry instead of leaking memory
- **Undo/redo labels** — override `Command.label` to power "Undo Paint Stroke" button text with no boilerplate
- **Value equality** — `==` and `hashCode` compare content, enabling use in Riverpod/BLoC without spurious rebuilds
- **No-op safe** — `execute` skips the stack push when the command returns an equal state
- **Framework-agnostic** — no Flutter, no Riverpod, zero runtime dependencies

## Installation

```yaml
dependencies:
  command_history: ^0.2.0
```

## Core concepts

### `Command<S>`

Extend this class for each action your app can undo. Only `execute` is required;
override `label` to enable human-readable button text in your UI.

```dart
class PaintStroke extends Command<CanvasState> {
  const PaintStroke(this.points);
  final List<Offset> points;

  @override
  CanvasState execute(CanvasState state) => state.withStroke(points);

  @override
  String get label => 'Paint Stroke'; // optional
}
```

### `CommandHistory<S>`

An immutable value that holds the current state and the undo/redo stacks:

```dart
final class CommandHistory<S> {
  S         get state;
  List<S>   get undoStack;   // UnmodifiableListView, oldest → newest
  List<S>   get redoStack;   // UnmodifiableListView, most-recent-undo first
  bool      get canUndo;
  bool      get canRedo;
  String?   get undoLabel;   // label of the command that will be undone
  String?   get redoLabel;   // label of the command that will be redone
  int?      get maxSize;

  CommandHistory<S> execute(Command<S> command);
  CommandHistory<S> undo();
  CommandHistory<S> redo();
  CommandHistory<S> replaceCurrent(S next, {S Function(S)? mapUndo, S Function(S)? mapRedo});
  CommandHistory<S> clearHistory();
}
```

## Usage

### Basic counter

```dart
import 'package:command_history/command_history.dart';

class Add extends Command<int> {
  const Add(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;

  @override
  String get label => 'Add $amount';
}

void main() {
  var h = CommandHistory.initial(0, maxSize: 50);

  h = h.execute(const Add(5));
  print(h.state);      // 5
  print(h.undoLabel);  // Add 5

  h = h.execute(const Add(3));
  print(h.state);      // 8

  h = h.undo();
  print(h.state);      // 5
  print(h.redoLabel);  // Add 3

  h = h.redo();
  print(h.state);      // 8

  print(h.canUndo);    // true
  print(h.canRedo);    // false
}
```

### With an immutable state class

```dart
import 'package:command_history/command_history.dart';

class TodoList {
  const TodoList({this.items = const []});
  final List<String> items;

  TodoList add(String item) => TodoList(items: [...items, item]);
  TodoList remove(int index) => TodoList(
    items: [...items.sublist(0, index), ...items.sublist(index + 1)],
  );
}

class AddTodo extends Command<TodoList> {
  const AddTodo(this.text);
  final String text;

  @override
  TodoList execute(TodoList state) => state.add(text);

  @override
  String get label => 'Add "$text"';
}

class RemoveTodo extends Command<TodoList> {
  const RemoveTodo(this.index);
  final int index;

  @override
  TodoList execute(TodoList state) => state.remove(index);
}

void main() {
  var h = CommandHistory.initial(const TodoList());

  h = h.execute(const AddTodo('Buy milk'));
  h = h.execute(const AddTodo('Walk the dog'));
  print(h.state.items);  // [Buy milk, Walk the dog]
  print(h.undoLabel);    // Add "Walk the dog"

  h = h.undo();
  print(h.state.items);  // [Buy milk]
}
```

### With Riverpod

Because `CommandHistory` implements `==` and `hashCode`, Riverpod rebuilds only
when the history actually changes — no wrapper or selector needed.

```dart
@riverpod
class TodoHistoryNotifier extends _$TodoHistoryNotifier {
  @override
  CommandHistory<TodoList> build() =>
      CommandHistory.initial(const TodoList(), maxSize: 100);

  void execute(Command<TodoList> command) =>
      state = state.execute(command);

  void undo() => state = state.undo();
  void redo() => state = state.redo();

  /// Call after the user saves — prevents undoing past the save point.
  void markSaved() => state = state.clearHistory();
}

// In your widget:
// final history = ref.watch(todoHistoryNotifierProvider);
// ElevatedButton(
//   onPressed: history.canUndo ? () => ref.read(...).undo() : null,
//   child: Text(history.undoLabel != null ? 'Undo ${history.undoLabel}' : 'Undo'),
// )
```

### Bounded history

```dart
// Only the last 50 commands can be undone.
var h = CommandHistory.initial(initialState, maxSize: 50);
```

When the 51st `execute` is called the oldest undo entry is silently dropped,
keeping memory bounded regardless of session length.

### Clearing history at a save point

```dart
// User pressed Save — undo should not reach before this point.
history = history.clearHistory();
// history.state is preserved; canUndo and canRedo are false.
```

### Out-of-band state update (server sync)

Use `replaceCurrent` when external state arrives and you need to keep the
undo/redo stacks valid relative to the new base:

```dart
history = history.replaceCurrent(
  serverState,
  mapUndo: (old) => old.copyWith(version: serverState.version),
  mapRedo: (old) => old.copyWith(version: serverState.version),
);
```

## API reference

### `CommandHistory.initial(S initialState, {int? maxSize})`

Creates a history with empty stacks. `maxSize` must be positive if provided.

### `execute(Command<S> command) → CommandHistory<S>`

Runs `command.execute(state)`. If the result differs from the current state
(via `==`), pushes the current state and label onto the undo stack and clears
the redo stack. Returns `this` unchanged on a no-op command.

### `undo() → CommandHistory<S>`

Restores the top of the undo stack as the new state. Returns `this` when
`canUndo` is false.

### `redo() → CommandHistory<S>`

Re-applies the top of the redo stack as the new state. Returns `this` when
`canRedo` is false.

### `replaceCurrent(S next, {mapUndo, mapRedo}) → CommandHistory<S>`

Replaces the current state without adding an undo entry. The optional
`mapUndo` / `mapRedo` callbacks transform existing stack entries.

### `clearHistory() → CommandHistory<S>`

Returns a history with the same `state` and `maxSize` but empty stacks.

### `undoLabel` / `redoLabel`

`String?` getters backed by parallel label stacks. Return `null` when the
stack is empty or the relevant command did not override `label`.

## Migrating from 0.1.0

Replace `implements Command<S>` with `extends Command<S>` in all command
classes. No other changes are required — the `label` getter has a default
implementation (`null`) so existing commands that do not need labels compile
without modification.

```dart
// Before (0.1.0)
class MyCommand implements Command<MyState> { ... }

// After (0.2.0)
class MyCommand extends Command<MyState> { ... }
```

## License

MIT — see [LICENSE](LICENSE).
