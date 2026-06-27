import 'package:command_history/command_history.dart';
import 'package:test/test.dart';

class _Add implements Command<int> {
  const _Add(this.amount);
  final int amount;

  @override
  int execute(int state) => state + amount;
}

void main() {
  group('CommandHistory', () {
    test('initial state', () {
      final h = CommandHistory.initial(0);
      expect(h.state, 0);
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
    });

    test('execute updates state', () {
      final h = CommandHistory.initial(0).execute(const _Add(5));
      expect(h.state, 5);
      expect(h.canUndo, isTrue);
    });

    test('undo reverts state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .execute(const _Add(3))
          .undo();
      expect(h.state, 5);
      expect(h.canRedo, isTrue);
    });

    test('redo re-applies state', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .undo()
          .redo();
      expect(h.state, 5);
      expect(h.canRedo, isFalse);
    });

    test('execute clears redo stack', () {
      final h = CommandHistory.initial(0)
          .execute(const _Add(5))
          .undo()
          .execute(const _Add(10));
      expect(h.state, 10);
      expect(h.canRedo, isFalse);
    });

    test('noop when command returns identical state', () {
      final h = CommandHistory.initial(0);
      final h2 = h.execute(const _Add(0));
      expect(identical(h, h2), isTrue);
    });

    test('undo noop when stack empty', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.undo()), isTrue);
    });

    test('redo noop when stack empty', () {
      final h = CommandHistory.initial(0);
      expect(identical(h, h.redo()), isTrue);
    });
  });
}
