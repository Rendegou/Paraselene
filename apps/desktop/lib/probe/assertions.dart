import '../native/generated/api/models.dart';

/// Stops acceptance on a failed contract without exposing synthetic text.
void require(bool condition, String contract) {
  if (!condition) throw StateError(contract);
}

/// Requires the stable typed Rust failure, never an arbitrary exception.
Future<void> expectBridgeError(
  String code,
  Future<Object?> Function() action,
) async {
  try {
    await action();
  } on BridgeError catch (error) {
    require(error.code == code, 'wrong_error_$code');
    return;
  }
  throw StateError('missing_error_$code');
}
