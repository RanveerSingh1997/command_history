/// A reversible operation that transforms a state of type [S].
///
/// Extend this class for each action your app can undo:
/// ```dart
/// class IncrementCommand extends Command<int> {
///   const IncrementCommand();
///
///   @override
///   int execute(int state) => state + 1;
///
///   @override
///   String get label => 'Increment'; // optional — drives undo/redo button text
/// }
/// ```
///
/// Override [label] to enable human-readable undo/redo button text via
/// [CommandHistory.undoLabel] and [CommandHistory.redoLabel].
abstract class Command<S> {
  const Command();
  S execute(S state);

  /// Short description shown in undo/redo UI (e.g. "Draw Stroke", "Type Text").
  /// Returns `null` by default; override to provide a label.
  String? get label => null;
}
