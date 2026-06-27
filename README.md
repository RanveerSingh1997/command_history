# command_history

Generic immutable undo/redo ring for Dart. Type-safe `CommandHistory<S>` with
a `Command<S>` interface — no Flutter dependency, works in any Dart environment
including pure Dart, Flutter (Riverpod, BLoC, etc.), and server-side.

## Features

- **Immutable** — every operation returns a new `CommandHistory<S>`; the original is never mutated
- **Generic** — works with any state type `S`
- **No-op safe** — `execute` skips the stack push if the command returns an identical state
- **Framework-agnostic** — no Flutter, no Riverpod, no external dependencies
- **Tiny** — two files, zero dependencies beyond the Dart SDK

## Installation

```yaml
dependencies:
  command_history: ^0.1.0
```

## Core concepts

### `Command<S>`

An interface with a single method. Implement it for each action your app can undo:

```dart
abstract interface class Command<S> {
  S execute(S state);
}
```

### `CommandHistory<S>`

An immutable snapshot of the current state plus the undo/redo stacks:

```dart
final class CommandHistory<S> {
  S get state;
  bool get canUndo;
  bool get canRedo;

  CommandHistory<S> execute(Command<S> command);
  CommandHistory<S> undo();
  CommandHistory<S> redo();
  CommandHistory<S> replaceCurrent(S next, {S Function(S)? mapUndo, S Function(S)? mapRedo});
}
```

## Usage

### Basic counter example

```dart
import 'package:command_history/command_history.dart';

// 1. Define your state (can be any type — int, a record, an immutable class).
// 2. Implement Command<S> for each action.

class Add implements Command<int> {
  const Add(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;
}

class Reset implements Command<int> {
  const Reset();

  @override
  int execute(int state) => 0;
}

void main() {
  var history = CommandHistory.initial(0);
  print(history.state);   // 0

  history = history.execute(const Add(5));
  print(history.state);   // 5

  history = history.execute(const Add(3));
  print(history.state);   // 8

  history = history.undo();
  print(history.state);   // 5

  history = history.redo();
  print(history.state);   // 8

  print(history.canUndo); // true
  print(history.canRedo); // false
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

class AddTodo implements Command<TodoList> {
  const AddTodo(this.text);
  final String text;

  @override
  TodoList execute(TodoList state) => state.add(text);
}

class RemoveTodo implements Command<TodoList> {
  const RemoveTodo(this.index);
  final int index;

  @override
  TodoList execute(TodoList state) => state.remove(index);
}

void main() {
  var history = CommandHistory.initial(const TodoList());

  history = history.execute(const AddTodo('Buy milk'));
  history = history.execute(const AddTodo('Walk the dog'));
  print(history.state.items); // [Buy milk, Walk the dog]

  history = history.undo();
  print(history.state.items); // [Buy milk]
}
```

### With Riverpod

```dart
class TodoNotifier extends Notifier<TodoList> {
  late CommandHistory<TodoList> _history;

  @override
  TodoList build() {
    _history = CommandHistory.initial(const TodoList());
    return _history.state;
  }

  void execute(Command<TodoList> command) {
    _history = _history.execute(command);
    state = _history.state;
  }

  void undo() {
    _history = _history.undo();
    state = _history.state;
  }

  void redo() {
    _history = _history.redo();
    state = _history.state;
  }

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
}
```

## API

### `CommandHistory.initial(S initialState)`

Creates a new history with the given initial state and empty stacks.

### `execute(Command<S> command) → CommandHistory<S>`

Runs `command.execute(state)` and, if the result differs from the current
state, pushes the current state onto the undo stack and clears the redo stack.
Returns `this` unchanged when the command produces an identical state.

### `undo() → CommandHistory<S>`

Pops the top of the undo stack as the new state. Returns `this` when
`canUndo` is false.

### `redo() → CommandHistory<S>`

Pops the top of the redo stack as the new state. Returns `this` when
`canRedo` is false.

### `replaceCurrent(S next, {mapUndo, mapRedo}) → CommandHistory<S>`

Replaces the current state without modifying the stacks. The optional
`mapUndo` / `mapRedo` callbacks let you transform existing stack entries —
useful when an out-of-band update (e.g. server sync) must be reflected in
history so that undo/redo don't restore stale states.

```dart
// Server patched a field — keep history valid.
history = history.replaceCurrent(
  serverState,
  mapUndo: (old) => old.copyWith(serverPatchedField: serverState.serverPatchedField),
);
```

## License

MIT — see [LICENSE](LICENSE).
