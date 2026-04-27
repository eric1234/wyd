import 'package:synchronized/synchronized.dart';

final class SingleWriter {
  final Lock _lock = Lock();

  Future<T> run<T>(Future<T> Function() operation) {
    return _lock.synchronized(operation);
  }
}
