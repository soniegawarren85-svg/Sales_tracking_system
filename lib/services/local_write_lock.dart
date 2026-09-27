import 'dart:async';

/// Serializes local read/modify/write operations, including sync acknowledgments.
class LocalWriteLock {
  Future<void> _tail = Future<void>.value();
  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }
}
