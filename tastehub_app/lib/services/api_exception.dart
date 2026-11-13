// ============================================================
//  api_exception.dart - one friendly error type for the whole app
// ============================================================

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// True when the server answered but rejected the request, as opposed to a
  /// network or timeout failure where [statusCode] is null.
  bool get hasStatus => statusCode != null;

  @override
  String toString() => message;
}
