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

/// Merges with other [_MergeableAdd] commands by summing amounts.
class _MergeableAdd extends Command<int> {
  const _MergeableAdd(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;

  @override
  String get label => 'Add $amount';

  @override
  Command<int>? mergeWith(Command<int> next) {
    if (next is! _MergeableAdd) return null;
    return _MergeableAdd(amount + next.amount);
  }
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

  // ── FunctionCommand ───────────────────────────────────────────────────────

  group('FunctionCommand', () {
    test('executes the provided function', () {
      final h = CommandHistory.initial(0)
          .execute(FunctionCommand((s) => s + 7));
      expect(h.state, 7);
    });

    test('label is null by default', () {
      expect(FunctionCommand<int>((s) => s).label, isNull);
    });

    test('label is returned when provided', () {
      expect(FunctionCommand<int>((s) => s, label: 'My Op').label, 'My Op');
    });

    test('no-op function does not push to undo stack', () {
      final h = CommandHistory.initial(5)
          .execute(FunctionCommand((s) => s));
      expect(h.canUndo, isFalse);
    });

    test('is undoable', () {
      final h = CommandHistory.initial(0)
          .execute(FunctionCommand((s) => s + 3, label: 'Add 3'))
          .undo();
      expect(h.state, 0);
    });
  });

  // ── CompositeCommand ──────────────────────────────────────────────────────

  group('CompositeCommand', () {
    test('executes all commands in sequence', () {
      final h = CommandHistory.initial(0).execute(
        CompositeCommand([const _Add(1), const _Add(2), const _Add(3)]),
      );
      expect(h.state, 6);
    });

    test('counts as one undo step', () {
      final h = CommandHistory.initial(0)
          .execute(CompositeCommand([const _Add(1), const _Add(2)]))
          .undo();
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
    });

    test('label is forwarded', () {
      final h = CommandHistory.initial(0).execute(
        CompositeCommand([const _Add(1)], label: 'Batch'),
      );
      expect(h.undoLabel, 'Batch');
    });

    test('all-no-op composite does not push to undo stack', () {
      final h = CommandHistory.initial(5).execute(
        CompositeCommand([const _Noop(), const _Noop()]),
      );
      expect(h.canUndo, isFalse);
    });

    test('empty composite is a no-op', () {
      final h = CommandHistory.initial(5);
      expect(identical(h, h.execute(CompositeCommand([]))), isTrue);
    });

    test('partial no-op still produces a net change', () {
      final h = CommandHistory.initial(0).execute(
        CompositeCommand([const _Noop(), const _Add(4)]),
      );
      expect(h.state, 4);
      expect(h.canUndo, isTrue);
    });
  });

  // ── undoLabels / redoLabels (plural) ──────────────────────────────────────

  group('undoLabels / redoLabels', () {
    test('undoLabels is empty on fresh history', () {
      expect(CommandHistory.initial(0).undoLabels, isEmpty);
    });

    test('redoLabels is empty on fresh history', () {
      expect(CommandHistory.initial(0).redoLabels, isEmpty);
    });

    test('undoLabels reflects all executed labels oldest→newest', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .execute(const _AddLabeled(2))
          .execute(const _AddLabeled(3));
      expect(h.undoLabels, ['Add 1', 'Add 2', 'Add 3']);
    });

    test('null entries appear for commands without label', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _AddLabeled(2));
      expect(h.undoLabels, [null, 'Add 2']);
    });

    test('redoLabels populated after undo', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .execute(const _AddLabeled(2))
          .undo()
          .undo();
      expect(h.redoLabels, ['Add 1', 'Add 2']);
    });

    test('undoLabels is unmodifiable', () {
      final h = CommandHistory.initial(0).execute(const _AddLabeled(1));
      expect(() => h.undoLabels.add(null), throwsUnsupportedError);
    });

    test('redoLabels is unmodifiable', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .undo();
      expect(() => h.redoLabels.add(null), throwsUnsupportedError);
    });
  });

  // ── undoN / redoN ─────────────────────────────────────────────────────────

  group('undoN', () {
    test('undoes exactly n steps', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .undoN(2);
      expect(h.state, 1);
      expect(h.undoStack.length, 1);
    });

    test('n=0 returns equal history', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(h.undoN(0), equals(h));
    });

    test('clamps when n exceeds stack depth', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undoN(100);
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
    });

    test('assert rejects negative n', () {
      final h = CommandHistory.initial(0);
      expect(() => h.undoN(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('redoN', () {
    test('redoes exactly n steps', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .undoN(3)
          .redoN(2);
      expect(h.state, 3);
      expect(h.redoStack.length, 1);
    });

    test('n=0 returns equal history', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo();
      expect(h.redoN(0), equals(h));
    });

    test('clamps when n exceeds stack depth', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo()
          .redoN(100);
      expect(h.state, 1);
      expect(h.canRedo, isFalse);
    });

    test('assert rejects negative n', () {
      final h = CommandHistory.initial(0);
      expect(() => h.redoN(-1), throwsA(isA<AssertionError>()));
    });
  });

  // ── withMaxSize ───────────────────────────────────────────────────────────

  group('withMaxSize', () {
    test('returns identical instance when maxSize unchanged', () {
      final h = CommandHistory.initial(0, maxSize: 5);
      expect(identical(h, h.withMaxSize(5)), isTrue);
    });

    test('trims oldest undo entries when shrinking cap', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .withMaxSize(2);
      expect(h.undoStack.length, 2);
      expect(h.undoStack, [1, 3]);
    });

    test('redo stack is not affected when trimming', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo()
          .withMaxSize(1);
      expect(h.redoStack.length, 1);
    });

    test('null removes the cap', () {
      final h = CommandHistory.initial(0, maxSize: 2)
          .withMaxSize(null);
      expect(h.maxSize, isNull);
    });

    test('new maxSize is respected by subsequent executes', () {
      var h = CommandHistory.initial(0).withMaxSize(2);
      h = h
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3));
      expect(h.undoStack.length, 2);
    });

    test('assert rejects zero', () {
      expect(
        () => CommandHistory.initial(0).withMaxSize(0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assert rejects negative', () {
      expect(
        () => CommandHistory.initial(0).withMaxSize(-1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ── peekUndo / peekRedo ───────────────────────────────────────────────────

  group('peekUndo', () {
    test('returns null when undo stack is empty', () {
      expect(CommandHistory.initial(0).peekUndo, isNull);
    });

    test('returns the state that undo would restore', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .execute(const _Add(3));
      expect(h.peekUndo, 5);
    });

    test('does not modify the history', () {
      final h = CommandHistory.initial(0).execute(const _Add(5));
      h.peekUndo;
      expect(h.state, 5);
      expect(h.canUndo, isTrue);
    });

    test('matches undo().state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(h.peekUndo, h.undo().state);
    });
  });

  group('peekRedo', () {
    test('returns null when redo stack is empty', () {
      expect(CommandHistory.initial(0).peekRedo, isNull);
    });

    test('returns the state that redo would restore', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .execute(const _Add(3))
          .undo();
      expect(h.peekRedo, 8);
    });

    test('does not modify the history', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .undo();
      h.peekRedo;
      expect(h.state, 0);
      expect(h.canRedo, isTrue);
    });

    test('matches redo().state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo();
      expect(h.peekRedo, h.redo().state);
    });
  });

  // ── timeline ─────────────────────────────────────────────────────────────

  group('timeline', () {
    test('single element when no history', () {
      expect(CommandHistory.initial(42).timeline, [42]);
    });

    test('past + present when no redo', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(h.timeline, [0, 1, 3]);
    });

    test('past + present + future after undo', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo();
      expect(h.timeline, [0, 1, 3]);
    });

    test('current state is at index undoStack.length', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .execute(const _Add(3))
          .undo();
      expect(h.timeline[h.undoStack.length], h.state);
    });

    test('is unmodifiable', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(() => h.timeline.add(99), throwsUnsupportedError);
    });
  });

  // ── stateAt ───────────────────────────────────────────────────────────────

  group('stateAt', () {
    test('index 0 returns oldest past state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(h.stateAt(0), 0);
    });

    test('index undoStack.length returns current state', () {
      final h = CommandHistory.initial(0).execute(const _Add(5));
      expect(h.stateAt(h.undoStack.length), h.state);
    });

    test('index beyond current reaches redo states', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo();
      // timeline: [0, 1, 3] — index 2 is the redo state
      expect(h.stateAt(2), 3);
    });

    test('consistent with timeline getter', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo();
      final tl = h.timeline;
      for (var i = 0; i < tl.length; i++) {
        expect(h.stateAt(i), tl[i]);
      }
    });

    test('assert fires on negative index', () {
      final h = CommandHistory.initial(0);
      expect(() => h.stateAt(-1), throwsA(isA<AssertionError>()));
    });

    test('assert fires on out-of-bounds index', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(() => h.stateAt(10), throwsA(isA<AssertionError>()));
    });
  });

  // ── jumpToIndex ───────────────────────────────────────────────────────────

  group('jumpToIndex', () {
    test('jumpToIndex(undoStack.length) is a no-op', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(h.jumpToIndex(h.undoStack.length), equals(h));
    });

    test('jumpToIndex(0) undoes all the way', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .jumpToIndex(0);
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
    });

    test('jumpToIndex(n) lands on correct state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .jumpToIndex(1);
      expect(h.state, 1);
      expect(h.undoStack.length, 1);
    });

    test('redo stack populated after jump', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .jumpToIndex(0);
      expect(h.canRedo, isTrue);
      expect(h.redoStack.length, 2);
    });

    test('assert fires on negative index', () {
      final h = CommandHistory.initial(0);
      expect(() => h.jumpToIndex(-1), throwsA(isA<AssertionError>()));
    });

    test('assert fires on index beyond undoStack.length', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(() => h.jumpToIndex(5), throwsA(isA<AssertionError>()));
    });
  });

  // ── collapse ──────────────────────────────────────────────────────────────

  group('collapse', () {
    test('merges last n steps into one undo step', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .collapse(3);
      expect(h.state, 6);
      expect(h.undoStack.length, 1);
      expect(h.undo().state, 0);
    });

    test('undoLabel is the most recent command label after collapse', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .execute(const _AddLabeled(2))
          .execute(const _AddLabeled(3))
          .collapse(3);
      expect(h.undoLabel, 'Add 3');
    });

    test('custom label overrides default', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .execute(const _AddLabeled(2))
          .collapse(2, label: 'Batch Edit');
      expect(h.undoLabel, 'Batch Edit');
    });

    test('clamps when n exceeds stack depth', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .collapse(100);
      expect(h.undoStack.length, 1);
    });

    test('clears redo stack', () {
      // 3 executes + 1 undo → undo=[0,1], state=3, redo=[6]
      // collapse(2) → undo=[0], state=3, redo=[]
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .undo()
          .collapse(2);
      expect(h.canRedo, isFalse);
    });

    test('no-op when undo stack has fewer than 2 entries', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(identical(h, h.collapse(2)), isTrue);
    });

    test('assert rejects n < 2', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(() => h.collapse(1), throwsA(isA<AssertionError>()));
    });
  });

  // ── transform ─────────────────────────────────────────────────────────────

  group('transform', () {
    test('transforms the current state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .transform((s) => s * 10);
      expect(h.state, 50);
    });

    test('transforms all undo stack entries', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .transform((s) => s + 100);
      expect(h.undoStack, [100, 101]);
    });

    test('transforms all redo stack entries', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo()
          .transform((s) => s * 2);
      expect(h.redoStack, [6]);
    });

    test('leaves labels unchanged', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(5))
          .transform((s) => s + 1);
      expect(h.undoLabel, 'Add 5');
    });

    test('identity transform returns equal history', () {
      final h = CommandHistory.initial(0).execute(const _Add(3));
      expect(h.transform((s) => s), equals(h));
    });
  });

  // ── undoWhile / redoWhile ─────────────────────────────────────────────────

  group('undoWhile', () {
    test('stops when predicate becomes false', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .undoWhile((s) => s > 1);
      expect(h.state, 1);
    });

    test('undoes all the way when predicate always true', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undoWhile((_) => true);
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
    });

    test('no-op when predicate immediately false', () {
      final h = CommandHistory.initial(5).execute(const _Add(1));
      expect(h.undoWhile((_) => false), equals(h));
    });

    test('no-op when canUndo is false', () {
      final h = CommandHistory.initial(0);
      expect(h.undoWhile((_) => true), equals(h));
    });
  });

  group('redoWhile', () {
    test('stops when predicate becomes false', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .execute(const _Add(3))
          .undoN(3)
          .redoWhile((s) => s < 3);
      expect(h.state, 3);
    });

    test('redoes all the way when predicate always true', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undoN(2)
          .redoWhile((_) => true);
      expect(h.state, 3);
      expect(h.canRedo, isFalse);
    });

    test('no-op when predicate immediately false', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo();
      expect(h.redoWhile((_) => false), equals(h));
    });

    test('no-op when canRedo is false', () {
      final h = CommandHistory.initial(0).execute(const _Add(1));
      expect(h.redoWhile((_) => true), equals(h));
    });
  });

  // ── Command merging ───────────────────────────────────────────────────────

  group('Command mergeWith', () {
    test('two mergeable commands produce one undo step', () {
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .execute(const _MergeableAdd(2));
      expect(h.state, 3);
      expect(h.undoStack.length, 1);
    });

    test('merged step undoes all the way back in one call', () {
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .execute(const _MergeableAdd(2))
          .undo();
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
    });

    test('three consecutive merges → single undo step', () {
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .execute(const _MergeableAdd(2))
          .execute(const _MergeableAdd(3));
      expect(h.state, 6);
      expect(h.undoStack.length, 1);
      expect(h.undo().state, 0);
    });

    test('merge updates the undo label', () {
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .execute(const _MergeableAdd(2));
      expect(h.undoLabel, 'Add 3');
    });

    test('non-mergeable command breaks the merge chain', () {
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .execute(const _Add(2)); // _Add does not implement mergeWith
      expect(h.undoStack.length, 2);
    });

    test('undo clears merge hint — re-execute does not merge', () {
      // execute, undo (clears _lastCommand), execute again — no merge
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .undo()
          .execute(const _MergeableAdd(2));
      // undo stack: [0] from the fresh push; state = 2
      expect(h.undoStack.length, 1);
      expect(h.state, 2);
      // the undo step takes us to 0, not 1 (no merge happened)
      expect(h.undo().state, 0);
    });

    test('redo clears merge hint — re-execute does not merge', () {
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .undo()
          .redo() // clears _lastCommand
          .execute(const _MergeableAdd(2)); // fresh push
      expect(h.undoStack.length, 2);
    });

    test('merge produces equal history regardless of _lastCommand', () {
      // Two histories with same state/stacks but different _lastCommand are equal
      final h1 = CommandHistory.initial(0).execute(const _MergeableAdd(3));
      final h2 = CommandHistory.initial(0)
          .execute(const _MergeableAdd(1))
          .execute(const _MergeableAdd(2)); // merges to state=3, same undo=[0]
      expect(h1, equals(h2));
    });

    test('no-op merge command does not grow stack', () {
      // A command that produces same state is a no-op even if it would merge
      final h = CommandHistory.initial(0)
          .execute(const _MergeableAdd(5))
          .execute(const _Noop());
      // _Noop returns identical state → no merge attempted, no push
      expect(h.undoStack.length, 1);
      expect(h.state, 5);
    });
  });

  // ── CommandHistory.fromStates ─────────────────────────────────────────────

  group('CommandHistory.fromStates', () {
    test('single-element list: state set, no undo', () {
      final h = CommandHistory.fromStates([42]);
      expect(h.state, 42);
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
    });

    test('last element becomes current state', () {
      final h = CommandHistory.fromStates([0, 1, 2, 3]);
      expect(h.state, 3);
    });

    test('earlier elements form undo stack oldest→newest', () {
      final h = CommandHistory.fromStates([0, 1, 2, 3]);
      expect(h.undoStack, [0, 1, 2]);
    });

    test('redo stack is empty', () {
      expect(CommandHistory.fromStates([0, 1, 2]).canRedo, isFalse);
    });

    test('all labels are null', () {
      final h = CommandHistory.fromStates([0, 1, 2]);
      expect(h.undoLabels, [null, null]);
    });

    test('maxSize trims oldest entries', () {
      final h = CommandHistory.fromStates([0, 1, 2, 3, 4], maxSize: 2);
      expect(h.undoStack, [2, 3]); // keeps newest 2 of [0,1,2,3]; 4 is current state
      expect(h.state, 4);
    });

    test('maxSize larger than list: no trimming', () {
      final h = CommandHistory.fromStates([0, 1, 2], maxSize: 10);
      expect(h.undoStack.length, 2);
    });

    test('can undo back through restored states', () {
      var h = CommandHistory.fromStates([10, 20, 30]);
      h = h.undo();
      expect(h.state, 20);
      h = h.undo();
      expect(h.state, 10);
      expect(h.canUndo, isFalse);
    });

    test('assert rejects empty list', () {
      expect(
        () => CommandHistory.fromStates(<int>[]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assert rejects zero maxSize', () {
      expect(
        () => CommandHistory.fromStates([1], maxSize: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ── CommandHistory.replay ─────────────────────────────────────────────────

  group('CommandHistory.replay', () {
    test('empty command list: state = initial, no undo', () {
      final h = CommandHistory.replay(5, []);
      expect(h.state, 5);
      expect(h.canUndo, isFalse);
    });

    test('replays commands in order', () {
      final h = CommandHistory.replay(0, [
        const _Add(1),
        const _Add(2),
        const _Add(3),
      ]);
      expect(h.state, 6);
    });

    test('builds correct undo depth', () {
      final h = CommandHistory.replay(0, [const _Add(1), const _Add(2)]);
      expect(h.undoStack.length, 2);
    });

    test('no-op commands are skipped', () {
      final h = CommandHistory.replay(5, [const _Noop(), const _Noop()]);
      expect(h.canUndo, isFalse);
    });

    test('maxSize is respected during replay', () {
      final h = CommandHistory.replay(
        0,
        [const _Add(1), const _Add(2), const _Add(3), const _Add(4)],
        maxSize: 2,
      );
      expect(h.undoStack.length, 2);
      expect(h.state, 10);
    });

    test('equivalent to chained execute calls', () {
      final via_replay = CommandHistory.replay(0, [
        const _Add(1),
        const _Add(2),
      ]);
      final via_execute = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(via_replay, equals(via_execute));
    });

    test('merging works during replay', () {
      final h = CommandHistory.replay(0, [
        const _MergeableAdd(1),
        const _MergeableAdd(2),
      ]);
      // Should merge → 1 undo step
      expect(h.undoStack.length, 1);
      expect(h.state, 3);
    });
  });

  // ── executeIf ────────────────────────────────────────────────────────────

  group('executeIf', () {
    test('executes when condition is true', () {
      final h = CommandHistory.initial(0)
          .executeIf(const _Add(5), condition: true);
      expect(h.state, 5);
      expect(h.canUndo, isTrue);
    });

    test('returns identical instance when condition is false', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.executeIf(const _Add(5), condition: false)), isTrue);
    });

    test('condition false leaves state unchanged', () {
      final h = CommandHistory.initial(42)
          .executeIf(const _Add(1), condition: false);
      expect(h.state, 42);
      expect(h.canUndo, isFalse);
    });

    test('no-op command with true condition still does not push to stack', () {
      final h = CommandHistory.initial(5)
          .executeIf(const _Noop(), condition: true);
      expect(h.canUndo, isFalse);
    });
  });

  // ── executeMany ───────────────────────────────────────────────────────────

  group('executeMany', () {
    test('empty list returns identical instance', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.executeMany([])), isTrue);
    });

    test('executes all commands in order', () {
      final h = CommandHistory.initial(0)
          .executeMany([const _Add(1), const _Add(2), const _Add(3)]);
      expect(h.state, 6);
    });

    test('each command is its own undo step', () {
      final h = CommandHistory.initial(0)
          .executeMany([const _Add(1), const _Add(2), const _Add(3)]);
      expect(h.undoStack.length, 3);
    });

    test('no-op commands in list are skipped', () {
      final h = CommandHistory.initial(5)
          .executeMany([const _Noop(), const _Add(1), const _Noop()]);
      expect(h.undoStack.length, 1);
      expect(h.state, 6);
    });

    test('mergeable commands in list still merge', () {
      final h = CommandHistory.initial(0).executeMany([
        const _MergeableAdd(1),
        const _MergeableAdd(2),
        const _MergeableAdd(3),
      ]);
      expect(h.undoStack.length, 1);
      expect(h.state, 6);
    });

    test('equivalent to chained execute calls', () {
      final via_many = CommandHistory.initial(0)
          .executeMany([const _Add(1), const _Add(2)]);
      final via_chain = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(via_many, equals(via_chain));
    });
  });

  // ── prune ─────────────────────────────────────────────────────────────────

  group('prune', () {
    test('returns identical instance when no entries match', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      expect(identical(h, h.prune((s) => s < 0)), isTrue);
    });

    test('removes matching entries from undo stack', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1)) // undo=[0]
          .execute(const _Add(2)) // undo=[0,1]
          .execute(const _Add(3)) // undo=[0,1,3]
          .prune((s) => s == 1);  // removes entry 1 → undo=[0,3]
      expect(h.undoStack, [0, 3]);
    });

    test('current state is preserved', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .prune((_) => true);
      expect(h.state, 5);
    });

    test('redo stack is preserved', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .undo() // redo=[3]
          .prune((_) => false);
      expect(h.canRedo, isTrue);
      expect(h.redoStack.length, 1);
    });

    test('all-match prune empties the undo stack', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .prune((_) => true);
      expect(h.canUndo, isFalse);
      expect(h.state, 3);
    });

    test('labels are pruned in parallel with states', () {
      final h = CommandHistory.initial(0)
          .execute(const _AddLabeled(1))
          .execute(const _AddLabeled(2))
          .execute(const _AddLabeled(3))
          .prune((s) => s == 1);
      expect(h.undoLabels, ['Add 1', 'Add 3']);
    });

    test('prune on empty undo stack returns identical instance', () {
      final h = CommandHistory.initial(5);
      expect(identical(h, h.prune((_) => true)), isTrue);
    });
  });

  // ── Named checkpoints ─────────────────────────────────────────────────────

  group('checkpoint / restoreCheckpoint', () {
    test('hasCheckpoint returns false before any checkpoint', () {
      expect(CommandHistory.initial(0).hasCheckpoint('save'), isFalse);
    });

    test('hasCheckpoint returns true after checkpoint', () {
      final h = CommandHistory.initial(0).checkpoint('save');
      expect(h.hasCheckpoint('save'), isTrue);
    });

    test('checkpoints getter exposes saved names', () {
      final h = CommandHistory.initial(0).checkpoint('a').checkpoint('b');
      expect(h.checkpoints.keys, containsAll(['a', 'b']));
    });

    test('restoreCheckpoint returns exact saved state', () {
      final h0 = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2));
      final saved = h0.checkpoint('mid');
      final h1 = saved.execute(const _Add(3));
      final restored = h1.restoreCheckpoint('mid');
      expect(restored.state, h0.state);
      expect(restored.undoStack, h0.undoStack);
    });

    test('restore returns full history including undo stack', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .execute(const _Add(2))
          .checkpoint('here')
          .execute(const _Add(3));
      final restored = h.restoreCheckpoint('here');
      expect(restored.canUndo, isTrue);
      expect(restored.undoStack.length, 2);
    });

    test('checkpoint survives execute', () {
      final h = CommandHistory.initial(0)
          .checkpoint('start')
          .execute(const _Add(5));
      expect(h.hasCheckpoint('start'), isTrue);
    });

    test('checkpoint survives undo', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .checkpoint('c')
          .undo();
      expect(h.hasCheckpoint('c'), isTrue);
    });

    test('checkpoint survives redo', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .undo()
          .checkpoint('c')
          .redo();
      expect(h.hasCheckpoint('c'), isTrue);
    });

    test('overwriting a checkpoint stores the new snapshot', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .checkpoint('p')      // saves state=1
          .execute(const _Add(2))
          .checkpoint('p');     // overwrites: now saves state=3
      final restored = h.restoreCheckpoint('p');
      expect(restored.state, 3);
    });

    test('assert fires when restoring non-existent checkpoint', () {
      final h = CommandHistory.initial(0);
      expect(
        () => h.restoreCheckpoint('nope'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('checkpoints map is unmodifiable', () {
      final h = CommandHistory.initial(0).checkpoint('x');
      expect(
        () => h.checkpoints['y'] = CommandHistory.initial(0),
        throwsUnsupportedError,
      );
    });
  });

  group('deleteCheckpoint / clearCheckpoints', () {
    test('deleteCheckpoint removes named checkpoint', () {
      final h = CommandHistory.initial(0)
          .checkpoint('a')
          .checkpoint('b')
          .deleteCheckpoint('a');
      expect(h.hasCheckpoint('a'), isFalse);
      expect(h.hasCheckpoint('b'), isTrue);
    });

    test('deleteCheckpoint on missing name returns identical instance', () {
      final h = CommandHistory.initial(0).checkpoint('a');
      expect(identical(h, h.deleteCheckpoint('missing')), isTrue);
    });

    test('clearCheckpoints removes all checkpoints', () {
      final h = CommandHistory.initial(0)
          .checkpoint('x')
          .checkpoint('y')
          .clearCheckpoints();
      expect(h.checkpoints, isEmpty);
    });

    test('clearCheckpoints on empty returns identical instance', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.clearCheckpoints()), isTrue);
    });

    test('clearHistory preserves checkpoints', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(1))
          .checkpoint('before')
          .clearHistory();
      expect(h.hasCheckpoint('before'), isTrue);
    });
  });

  group('equality with checkpoints', () {
    test('histories with same checkpoints are equal', () {
      final h1 = CommandHistory.initial(0).checkpoint('a');
      final h2 = CommandHistory.initial(0).checkpoint('a');
      expect(h1, equals(h2));
    });

    test('histories with different checkpoints are not equal', () {
      final h1 = CommandHistory.initial(0).checkpoint('a');
      final h2 = CommandHistory.initial(0).checkpoint('b');
      expect(h1, isNot(equals(h2)));
    });

    test('hashCode consistent with == for checkpoint equality', () {
      final h1 = CommandHistory.initial(0).checkpoint('x');
      final h2 = CommandHistory.initial(0).checkpoint('x');
      expect(h1.hashCode, h2.hashCode);
    });

    test('adding a checkpoint makes histories unequal', () {
      final h = CommandHistory.initial(0);
      final hc = h.checkpoint('save');
      expect(h, isNot(equals(hc)));
    });

    test('two empty-checkpoint histories remain equal', () {
      final h1 = CommandHistory.initial(42);
      final h2 = CommandHistory.initial(42);
      expect(h1, equals(h2));
    });
  });
}
