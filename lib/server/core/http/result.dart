import 'dart:convert';
import 'package:shelf/shelf.dart';

class Result<T> {
  final int code;
  final String message;
  final T? data;

  Result({required this.code, required this.message, this.data});

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'data': data,
  };

  static Result<T> success<T>(T? data, {String message = 'Success'}) {
    return Result(code: 200, message: message, data: data);
  }

  static Result<T> error<T>(int code, String message, {T? data}) {
    return Result(code: code, message: message, data: data);
  }

  /// Helper to create a successful JSON response
  static Response ok<T>(T? data, {String message = 'Success'}) {
    return Response.ok(
      jsonEncode(Result.success(data, message: message).toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Helper to create a failure JSON response (HTTP 200 with error code)
  static Response fail<T>(int code, String message, {T? data}) {
    return Response.ok(
      jsonEncode(Result.error(code, message, data: data).toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
