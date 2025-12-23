import 'package:darc/src/api_error_messages.dart';
import 'package:darc/src/status_codes.dart';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Extracts a human-readable error message from a response [body].
/// Falls back to [spareMessage] when no message field is present.
String _extractErrorMessage(dynamic body, String spareMessage) {
  return body is Map && body['message'] is String
      ? body['message'] as String
      : spareMessage;
}

// ================= exceptions without body =================

/// Base class for all API request-related exceptions.
sealed class RequestException<Data> with EquatableMixin implements Exception {
  RequestException({
    required String spareMessage,
    this.responseBody,
    this.code,
    Data Function(Map<String, dynamic> body)? errorParser,
  })  : message = _extractErrorMessage(responseBody, spareMessage),
        data = responseBody is Map<String, dynamic>
            ? errorParser?.call(responseBody)
            : null;

  final int? code;
  final String message;
  final dynamic responseBody;
  final Data? data;

  @override
  @mustCallSuper
  List<Object?> get props => [message, code, data];

  @override
  String toString() {
    return '$runtimeType($code): $message';
  }
}

/// Thrown when a request fails due to connectivity issues or timeouts.
class FetchDataException<Data> extends RequestException<Data> {
  FetchDataException()
      : super(spareMessage: ApiErrorMessages.instance.connectionError());
}

/// Thrown when an in-flight request is intentionally cancelled.
class CancelledRequestException<Data> extends RequestException<Data> {
  CancelledRequestException()
      : super(spareMessage: ApiErrorMessages.instance.downloadCanceled());
}

/// Thrown for unknown or unexpected errors (e.g., errors in parsing the model).
class RequestUnknownException<Data> extends RequestException<Data> {
  RequestUnknownException({String? message})
      : super(
          spareMessage: message ?? ApiErrorMessages.instance.unknownError(),
        );
}

// ================= exceptions with body =================

/// Thrown for HTTP 400 Bad Request with validation/general errors.
class BadRequestException<Data> extends RequestException<Data> {
  BadRequestException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.unknownError(),
          code: StatusCodes.badRequest,
        );
}

/// Thrown for HTTP 401 authentication failures.
class UnauthenticatedException<Data> extends RequestException<Data> {
  UnauthenticatedException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.pleaseLogin(),
          code: StatusCodes.unauthenticated,
        );
}

/// Thrown for HTTP 403 authorization failures.
class UnauthorizedException<Data> extends RequestException<Data> {
  UnauthorizedException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.unauthorized(),
          code: StatusCodes.forbidden,
        );
}

/// Thrown for HTTP 404 when a resource cannot be found.
class NotFoundException<Data> extends RequestException<Data> {
  NotFoundException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.unknownError(),
          code: StatusCodes.notFound,
        );
}

/// Thrown for HTTP 409 conflict errors (e.g., duplicates or state conflicts).
class ConflictException<Data> extends RequestException<Data> {
  ConflictException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.unknownError(),
          code: StatusCodes.conflict,
        );
}

/// Thrown for invalid/expired token scenarios (HTTP 419).
class InvalidTokenException<Data> extends RequestException<Data> {
  InvalidTokenException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.pleaseLogin(),
          code: StatusCodes.invalidToken,
        );
}

/// Thrown for HTTP 422 unprocessable entity with validation errors.
/// Allows custom parsing of error data via `errorParser`.
class UnProcessableDataException<Data> extends RequestException<Data> {
  UnProcessableDataException({required super.responseBody, super.errorParser})
      : super(
          spareMessage: ApiErrorMessages.instance.wrongData(),
          code: StatusCodes.unProcessableData,
        );
}

/// Thrown for HTTP 500 server errors.
class InternalServerErrorException<Data> extends RequestException<Data> {
  InternalServerErrorException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.serverError(),
          code: StatusCodes.serverError,
        );
}

/// Thrown when the server returns an unexpected/malformed response (e.g., 413).
class BadResponseException<Data> extends RequestException<Data> {
  BadResponseException({required super.responseBody})
      : super(
          spareMessage: ApiErrorMessages.instance.serverError(),
          code: StatusCodes.serverError,
        );
}
