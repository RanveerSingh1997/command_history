import 'package:command_history/command_history.dart';
import 'package:test/test.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

class _Add extends Command<int> {
  const _Add(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;
}

class _AddLabeled extends Command<int> {
  const _AddLabeled(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;

  @override
  String get label => 'Add $amount';
}

class _Noop extends Command<int> {
  const _Noop();

  @override
  int execute(int state) => state; // returns identical value
}

class _SetList extends Command<List<String>> {
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

    test('mapped stacks are unmodifiable', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .replaceCurrent(99, mapUndo: (s) => s + 100);
      expect(() => h.undoStack.add(0), throwsUnsupportedError);
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

    test('undoStack is unmodifiable', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(() => h.undoStack.add(0), throwsUnsupportedError);
    });

    test('redoStack is unmodifiable', () {
      final h = CommandHistory.initial(0).execute(const _Add(1)).undo();
      expect(() => h.redoStack.add(0), throwsUnsupportedError);
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

  // ── New feature groups ────────────────────────────────────────────────────

  group('maxSize', () {
    test('assert rejects zero', () {
      expect(() => CommandHistory.initial(0, maxSize: 0), throwsA(isA<AssertionError>()));
    });

    test('assert rejects negative', () {
      expect(() => CommandHistory.initial(0, maxSize: -1), throwsA(isA<AssertionError>()));
    });

    test('caps undo stack at maxSize', () {
      var h = CommandHistory.initial(0, maxSize: 2)
          .execute(const _Add(1))  // undo=[0]
          .execute(const _Add(2))  // undo=[0,1]
          .execute(const _Add(3)); // undo=[1,3] — 0 is trimmed
      expect(h.undoStack.length, 2);
      expect(h.undoStack, [1, 3]);
    });

    test('undo still works after cap', () {
      final h = CommandHistory.initial(0, maxSize: 2)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3)) // state=6, undo=[1,3]
          .undo();                // state=3, undo=[1]
      expect(h.state, 3);
      expect(h.undoStack, [1]);
    });

    test('oldest entry dropped when cap exceeded', () {
      final h = CommandHistory.initial(0, maxSize: 1)
          .execute(const _Add(10)) // undo=[0]
          .execute(const _Add(20)) // undo=[10] — 0 is trimmed
          .undo();                  // state=10, undo=[]
      expect(h.state, 10);
      expect(h.canUndo, isFalse);
    });

    test('maxSize is preserved through undo and redo', () {
      final h = CommandHistory.initial(0, maxSize: 2)
          .execute(const _Add(1))
          .undo()
          .redo();
      // execute two more — should still cap at 2
      final h2 = h
          .execute(const _Add(10))
          .execute(const _Add(20))
          .execute(const _Add(30));
      expect(h2.undoStack.length, 2);
    });

    test('null maxSize allows unlimited history', () {
      var h = CommandHistory.initial(0);
      for (var i = 0; i < 100; i++) {
        h = h.execute(const _Add(1));
      }
      expect(h.undoStack.length, 100);
    });
  });

  group('equality', () {
    test('two histories with same content are equal', () {
      final h1 = CommandHistory.initial(0).execute(const _Add(5));
      final h2 = CommandHistory.initial(0).execute(const _Add(5));
      expect(h1, equals(h2));
    });

    test('histories with different state are not equal', () {
      final h1 = CommandHistory.initial(0).execute(const _Add(5));
      final h2 = CommandHistory.initial(0).execute(const _Add(6));
      expect(h1, isNot(equals(h2)));
    });

    test('histories with different undo stacks are not equal', () {
      final h1 = CommandHistory.initial(0).execute(const _Add(5));
      final h2 = CommandHistory.initial(0)
          .execute(const _Add(3))
          .execute(const _Add(2)); // same state=5, undo=[0,3] vs [0]
      expect(h1, isNot(equals(h2)));
    });

    test('hashCode is consistent with ==', () {
      final h1 = CommandHistory.initial(0).execute(const _Add(5));
      final h2 = CommandHistory.initial(0).execute(const _Add(5));
      expect(h1.hashCode, h2.hashCode);
    });

    test('identical instance equals itself', () {
      final h = CommandHistory.initial(0).execute(const _Add(5));
      expect(h, equals(h));
    });

    test('usable as map key', () {
      final h1 = CommandHistory.initial(0).execute(const _Add(5));
      final h2 = CommandHistory.initial(0).execute(const _Add(5));
      final map = {h1: 'value'};
      expect(map[h2], 'value');
    });
  });

  group('labels', () {
    test('undoLabel is null on fresh history', () {
      expect(CommandHistory.initial(0).undoLabel, isNull);
    });

    test('redoLabel is null on fresh history', () {
      expect(CommandHistory.initial(0).redoLabel, isNull);
    });

    test('undoLabel reflects the last executed command', () {
      final h = CommandHistory.initial(0).execute(const _AddLabeled(5));
      expect(h.undoLabel, 'Add 5');
    });

    test('redoLabel is null when redo stack is empty', () {
      final h = CommandHistory.initial(0).execute(const _AddLabeled(5));
      expect(h.redoLabel, isNull);
    });

    test('redoLabel is set after undo', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(5))
          .undo();
      expect(h.redoLabel, 'Add 5');
      expect(h.undoLabel, isNull);
    });

    test('labels move back to undo after redo', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(5))
          .undo()
          .redo();
      expect(h.undoLabel, 'Add 5');
      expect(h.redoLabel, isNull);
    });

    test('commands without label yield null undoLabel', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(h.undoLabel, isNull);
    });

    test('multiple labels stack correctly', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .execute(const _AddLabeled(2));
      expect(h.undoLabel, 'Add 2');
      final afterUndo = h.undo();
      expect(afterUndo.undoLabel, 'Add 1');
      expect(afterUndo.redoLabel, 'Add 2');
    });

    test('labels are cleared with redo stack when execute is called', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(5))
          .undo()            // redoLabel = 'Add 5'
          .execute(const _AddLabeled(9)); // clears redo
      expect(h.redoLabel, isNull);
      expect(h.undoLabel, 'Add 9');
    });
  });

  group('toString', () {
    test('contains state value', () {
      expect(CommandHistory.initial(42).toString(), contains('42'));
    });

    test('reports undo depth', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(h.toString(), contains('undo: 1'));
    });

    test('reports redo depth', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo();
      expect(h.toString(), contains('redo: 1'));
    });
  });

  group('clearHistory', () {
    test('resets stacks but preserves state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .clearHistory();
      expect(h.state, 5);
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
    });

    test('clears redo stack too', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo()
          .clearHistory();
      expect(h.canRedo, isFalse);
    });

    test('preserves maxSize for subsequent executes', () {
      var h = CommandHistory.initial(0, maxSize: 2)
          .execute(const _Add(1))
          .clearHistory();
      h = h
          .execute(const _Add(10))
          .execute(const _Add(20))
          .execute(const _Add(30));
      expect(h.undoStack.length, 2);
    });

    test('cleared history equals a fresh initial history with same state', () {
      final cleared = CommandHistory.initial(0)
          .execute(const _Add(5))
          .clearHistory();
      final fresh = CommandHistory.initial(5);
      expect(cleared, equals(fresh));
    });
  });
}
