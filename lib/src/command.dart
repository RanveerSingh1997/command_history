/// A reversible operation that transforms a state of type [S].
///
/// Implement this interface for each action your app can undo:
/// ```dart
/// class IncrementCommand implements Command<int> {
///   const IncrementCommand();
///
///   @override
///   int execute(int state) => state + 1;
/// }
/// ```
abstract interface class Command<S> {
  S execute(S state);
}
