import 'package:command_history/command_history.dart';
import 'package:test/test.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

class _Add implements Command<int> {
  const _Add(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;
}

class _Noop implements Command<int> {
  const _Noop();

  @override
  int execute(int state) => state; // returns identical value
}

class _SetList implements Command<List<String>> {
  const _SetList(this.value);
  final List<String> value;

  @override
  List<String> execute(List<String> state) => value;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CommandHistory.initial', () {
    test('state is the initial value', () {
      expect(CommandHistory.initial(42).state, 42);
    });

    test('canUndo is false', () {
      expect(CommandHistory.initial(0).canUndo, isFalse);
    });

    test('canRedo is false', () {
      expect(CommandHistory.initial(0).canRedo, isFalse);
    });

    test('works with non-primitive state type', () {
      final h = CommandHistory.initial(<String>[]);
      expect(h.state, isEmpty);
    });
  });

  group('execute', () {
    test('updates state', () {
      final h = CommandHistory.initial(0).execute(const _Add(5));
      expect(h.state, 5);
    });

    test('enables canUndo after first execute', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(h.canUndo, isTrue);
    });

    test('clears redo stack', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo()
          .execute(const _Add(2));
      expect(h.canRedo, isFalse);
    });

    test('stacks multiple executes', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3));
      expect(h.state, 6);
      expect(h.undoStack.length, 3);
    });

    test('returns identical instance when command is a no-op', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.execute(const _Noop())), isTrue);
    });

    test('does not push to undo stack when no-op', () {
      final h = CommandHistory.initial(0).execute(const _Noop());
      expect(h.undoStack, isEmpty);
    });
  });

  group('undo', () {
    test('reverts to previous state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .execute(const _Add(3))
          .undo();
      expect(h.state, 5);
    });

    test('enables canRedo after undo', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo();
      expect(h.canRedo, isTrue);
    });

    test('multiple undos walk back the stack', () {
      var h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3));
      h = h.undo();
      expect(h.state, 3);
      h = h.undo();
      expect(h.state, 1);
      h = h.undo();
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
    });

    test('returns identical instance when stack is empty', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.undo()), isTrue);
    });
  });

  group('redo', () {
    test('re-applies undone state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .undo()
          .redo();
      expect(h.state, 5);
    });

    test('disables canRedo after redo', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo()
          .redo();
      expect(h.canRedo, isFalse);
    });

    test('multiple redos walk forward the stack', () {
      var h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .undo()
          .undo()
          .undo();
      h = h.redo();
      expect(h.state, 1);
      h = h.redo();
      expect(h.state, 3);
      h = h.redo();
      expect(h.state, 6);
      expect(h.canRedo, isFalse);
    });

    test('returns identical instance when redo stack is empty', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.redo()), isTrue);
    });
  });

  group('replaceCurrent', () {
    test('replaces state without touching stacks', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .replaceCurrent(99);
      expect(h.state, 99);
      expect(h.undoStack.length, 1);
    });

    test('mapUndo transforms undo stack entries', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(10))
          .execute(const _Add(20))
          .replaceCurrent(999, mapUndo: (s) => s + 1000);
      expect(h.undoStack, [1000, 1010]);
    });

    test('mapRedo transforms redo stack entries', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(10))
          .undo()
          .replaceCurrent(999, mapRedo: (s) => s + 1000);
      expect(h.redoStack, [1010]);
    });

    test('leaves stacks unchanged when no map functions provided', () {
      final before = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      final after = before.replaceCurrent(99);
      expect(after.undoStack, before.undoStack);
      expect(after.redoStack, before.redoStack);
    });
  });

  group('immutability', () {
    test('original history unchanged after execute', () {
      final original = CommandHistory.initial(0);
      original.execute(const _Add(5));
      expect(original.state, 0);
      expect(original.canUndo, isFalse);
    });

    test('original history unchanged after undo', () {
      final after = CommandHistory.initial(0).execute(const _Add(5));
      after.undo();
      expect(after.state, 5);
      expect(after.canUndo, isTrue);
    });
  });

  group('stack accessors', () {
    test('undoStack reflects history in order', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(h.undoStack, [0, 1]);
    });

    test('redoStack reflects undone states in order', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo()
          .undo();
      expect(h.redoStack, [1, 3]);
    });
  });
}
