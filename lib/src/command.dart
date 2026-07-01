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
///   String get label => 'Increment';
/// }
/// ```
///
/// Override [label] to enable human-readable undo/redo button text via
/// [CommandHistory.undoLabel] and [CommandHistory.redoLabel].
///
/// Override [mergeWith] to enable automatic coalescing of consecutive commands
/// of the same type (e.g. collapsing per-keystroke typing into one undo step).
abstract class Command<S> {
  const Command();
  S execute(S state);

  /// Short description shown in undo/redo UI (e.g. "Draw Stroke", "Type Text").
  /// Returns `null` by default; override to provide a label.
  String? get label => null;

  /// Attempt to merge [next] into this command, returning a combined command
  /// that represents both operations as a single undoable step.
  ///
  /// Return `null` (the default) to keep them as separate undo steps.
  ///
  /// When [CommandHistory.execute] is called and the previous command returns
  /// a non-null merge result, the top of the undo stack is extended in-place
  /// instead of pushing a new entry. The merged command becomes the new
  /// `_lastCommand` for subsequent merge attempts.
  ///
  /// Example — coalesce consecutive character insertions:
  /// ```dart
  /// class TypeChar extends Command<String> {
  ///   const TypeChar(this.char);
  ///   final String char;
  ///
  ///   @override
  ///   String execute(String state) => state + char;
  ///
  ///   @override
  ///   String get label => 'Type';
  ///
  ///   @override
  ///   Command<String>? mergeWith(Command<String> next) {
  ///     if (next is! TypeChar) return null;
  ///     return _TypeString(char + next.char);
  ///   }
  /// }
  /// ```
  Command<S>? mergeWith(Command<S> next) => null;
}
