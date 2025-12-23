# darc

[![Build Status](https://github.com/Mohamed-Shalabi/darc/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/Mohamed-Shalabi/darc/actions/workflows/main.yml)
[![codecov](https://codecov.io/gh/Mohamed-Shalabi/darc/graph/badge.svg?token=CODECOV_TOKEN)](https://codecov.io/gh/Mohamed-Shalabi/darc)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C2E.svg)](https://pub.dev/packages/very_good_analysis)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Dart SDK](https://img.shields.io/badge/Dart-3.0%2B-0175C2.svg?logo=dart&logoColor=white)](https://dart.dev)
[![Pub Package](https://img.shields.io/pub/v/darc.svg )](https://pub.dev/packages/darc )

**DARC** (**D**etails-**A**gnostic **R**EST **C**onsumer) is a clean, opinionated networking abstraction for Flutter applications. It provides a minimal yet powerful public interface while internalizing the complexity of error handling, **callback-based response parsing**, token refresh, file downloads, and multipart uploads. It is designed for teams who want to separate HTTP transport concerns from business logic without sacrificing testability or control.

---

## Features

### Type-Safe API Surface

Generic methods enforce typed responses and errors at compile time. Every request specifies both its success type `T` and optional error type `E`, eliminating implicit `dynamic` from the public API.


### Callback-Based Parsing

Parsing logic is injected directly into requests via callbacks. This decoupling ensures that raw data is transformed into domain objects immediately *within* the network layer boundary, preventing untyped `dynamic` data from ever leaking into your app.

### No Try/Catch Required

All errors are handled internally — including network errors, HTTP status codes, and **exceptions thrown inside parser functions**. Errors are returned as `Left` values in the `Either` result, never thrown:

```dart
// No try/catch needed — parser exceptions are caught and wrapped
final result = await api.get<void, User>(
  '/users/me',
  parser: (data) => User.fromJson(data), // If this throws, it becomes RequestUnknownException
);

result.fold(
  (error) => handleError(error),  // All errors come here, including parser errors
  (user) => displayUser(user),
);
```

### Unified HTTP Interface

GET, POST, PUT, DELETE through a single abstract contract. One interface for all operations.

### Either-Based Result Type

Compile-time enforcement of error handling using the `Either` pattern from functional programming. Callers cannot forget to handle errors.

### Sealed Exception Hierarchy

Exhaustive, typed error handling with pattern matching. Every HTTP status code maps to a specific exception type.

### Automatic Token Refresh

Built-in OAuth2 token management. When a 401 is received, tokens are automatically refreshed and the request is retried.

### File Downloads with Progress

Stream-based download progress reporting with cancellation support via `DownloadCanceller`.

### Multipart File Uploads

Nested body flattening for complex form data. Upload files alongside structured JSON bodies.

### Testable by Design

Abstract interfaces, dependency injection, and injectable factories. Every component can be mocked or replaced.

---

## Getting Started

### Installation

Add `darc` to your `pubspec.yaml`:

```yaml
dependencies:
  darc: <Version>
  fresh_dio: <Version> # Optional, for using the default token storage that is below
  flutter_secure_storage: <Version> # Optional, for using the default token storage that is below
```

### Token Storage Implementation

You need to provide a `TokenStorage` implementation to manage token persistence. Here is an example using `flutter_secure_storage`:

```dart
import 'package:darc/darc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fresh_dio/fresh_dio.dart';

/// Secure token storage implementation backed by [FlutterSecureStorage].
///
/// Persists OAuth2 access and refresh tokens securely on device.
class AppTokenStorage extends TokenStorage<ApiOAuth2Token> {
  /// Creates a new token storage using the provided secure [storage].
  AppTokenStorage({required this.storage});

  @visibleForTesting
  static const refreshTokenKey = 'refresh-token';
  @visibleForTesting
  static const authTokenKey = 'auth-token';

  /// Underlying secure storage for persisting tokens.
  final FlutterSecureStorage storage;

  /// Deletes both refresh and access tokens from secure storage.
  @override
  Future<void> delete() async {
    await storage.delete(key: refreshTokenKey);
    await storage.delete(key: authTokenKey);
  }

  /// Reads tokens from secure storage and reconstructs an [OAuth2Token].
  /// Returns `null` if no access token is found.
  @override
  Future<ApiOAuth2Token?> read() async {
    final [refreshToken, authToken] = await Future.wait([
      storage.read(key: refreshTokenKey),
      storage.read(key: authTokenKey),
    ]);

    if (authToken == null) {
      return null;
    }

    return ApiOAuth2Token(refreshToken: refreshToken, accessToken: authToken);
  }

  /// Writes both refresh and access tokens to secure storage.
  @override
  Future<void> write(ApiOAuth2Token token) async {
    await storage.write(key: refreshTokenKey, value: token.refreshToken ?? '');
    await storage.write(key: authTokenKey, value: token.accessToken);
  }
}
```

### Setup

```dart
import 'package:darc/darc.dart';
import 'package:dio/dio.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final client = Dio();

// defined in fresh_dio
final tokenInterceptor = Fresh<ApiOAuth2Token>(
  tokenHeader: (token) => {'Authorization': 'Bearer ${token.accessToken}'},
  tokenStorage: AppTokenStorage(storage: const FlutterSecureStorage()),
  shouldRefresh: (response) => response?.statusCode == 401,
  refreshToken: (token, httpClient) {
    // Refresh token logic
  },
);

final api = DioConsumer(
  client: client,
  tokenInterceptor: tokenInterceptor,
  baseUrl: 'https://api.example.com',
);
```

### Customizing Error Messages

You can customize the error messages by replacing the default `ApiErrorMessages` instance. This class uses **callback functions** instead of static strings, allowing you to return localized strings implementation (e.g., from `easy_localization` or `intl`) dynamically at runtime.

```dart
ApiErrorMessages.instance = ApiErrorMessages(
  connectionError: () => TrKeys.noInternetConnection.tr(),
  downloadCanceled: () => TrKeys.downloadStopped.tr(),
  unknownError: () => TrKeys.somethingWentWrong.tr(),
  pleaseLogin: () => TrKeys.sessionExpiredPleaseLogIn.tr(),
  wrongData: () => TrKeys.invalidDataReceived.tr(),
  serverError: () => TrKeys.serverEncounteredAnError.tr(),
  unauthorized: () => TrKeys.accessDenied.tr(),
);
```

### Error Reporting Hook

You can configure a global error reporter to capture parsing errors and report them to an external service like Crashlytics or Flutter's error handling.

```dart
ApiErrorReporter.errorReporter = (error, stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
    ),
  );
};
```

---

## Usage Examples

### Basic GET Request

```dart
final result = await api.get<void, List<Product>>(
  '/products',
  parser: (data) => (data as List).map((e) => Product.fromJson(e)).toList(),
  queryParameters: {'category': 'electronics'},
);

result.fold(
  (error) => print('Failed: ${error.message}'),
  (products) => print('Loaded ${products.length} products'),
);
```

### POST with Body

```dart
final result = await api.post<ValidationErrors, Order>(
  '/orders',
  parser: Order.fromJson,
  errorParser: ValidationErrors.fromJson,
  body: {'product_id': 123, 'quantity': 2},
);

result.fold(
  (error) {
    if (error is UnProcessableDataException<ValidationErrors>) {
      displayFieldErrors(error.data);
    }
  },
  (order) => navigateToConfirmation(order),
);
```

### File Upload

```dart
final result = await api.post<void, UploadResponse>(
  '/documents',
  parser: UploadResponse.fromJson,
  body: {'title': 'Report Q4'},
  files: [
    MultiPartFileModel(
      requestBodyName: 'file',
      fileName: 'report.pdf',
      filePath: '/path/to/report.pdf',
    ),
  ],
);
```

### File Download with Progress

```dart
final result = await api.download<void>(
  'https://example.com/large-file.zip',
  '/storage/downloads/file.zip',
  canceller: DioDownloadCanceller(CancelToken()),
);

result.fold(
  (error) => print('Download failed: ${error.message}'),
  (progressStream) {
    progressStream.listen(
      (either) => either.fold(
        (error) => print('Error during download'),
        (progress) => print('Progress: ${(progress * 100).toInt()}%'),
      ),
    );
  },
);
```

---


## Architectural Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Consumer Code                           │
│                   (uses ApiConsumer interface)                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       ApiConsumer<T>                            │
│                    (abstract interface)                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ get/post/   │  │ setToken/   │  │ download with progress  │  │
│  │ put/delete  │  │ removeToken │  │ and cancellation        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DioConsumer                              │
│                  (concrete implementation)                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │ handleDioError   │  │ handleResponse   │  │ flattenMap    │  │
│  │ (error mapping)  │  │ Error (status)   │  │ (form data)   │  │
│  └──────────────────┘  └──────────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     External Dependencies                       │
│  ┌─────────┐  ┌───────────────────┐  ┌───────────────────────┐  │
│  │   Dio   │  │ Fresh (token mgmt)│  │ FlutterSecureStorage  │  │
│  └─────────┘  └───────────────────┘  └───────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Core Abstractions

| Component | Type | Responsibility |
|-----------|------|----------------|
| `ApiConsumer<T>` | Abstract | HTTP operations contract |
| `DownloadCanceller` | Abstract | Cancellation interface |
| `MultipartFileFactory` | Abstract | File creation abstraction |
| `RequestException<T>` | Sealed | Error type hierarchy |
| `ApiResultOf<E, T>` | Type alias | `Future<Either<RequestException<E>, T>>` |

### Implementations

| Component | Implements | Notes |
|-----------|------------|-------|
| `DioConsumer` | `ApiConsumer` | Dio-based HTTP client |
| `DioDownloadCanceller` | `DownloadCanceller` | Wraps `CancelToken` |
| `DefaultMultipartFileFactory` | `MultipartFileFactory` | Default file creation |
| `AppTokenStorage` | `TokenStorage<ApiOAuth2Token>` | Secure token persistence |

### Dependency Direction

All application code depends only on `ApiConsumer`. The concrete `DioConsumer` depends on Dio and Fresh, but these are never exposed to consumers. This inverted dependency allows swapping implementations without changing calling code.

---

## Design Philosophy

### Complexity is Internal

DARC is designed to internally hide all the complexity of HTTP requests and their error handling through a simple yet powerful interface.

Consumers write simple, predictable code:

```dart
final result = await api.get<void, User>(
  '/users/me',
  parser: User.fromJson,
);

result.fold(
  (error) => handleError(error),
  (user) => displayUser(user),
);
```

Internally, the library handles:
- Network errors, timeouts, and cancellations
- HTTP status code interpretation
- Token expiration detection and refresh
- Response parsing and error body extraction
- Multipart encoding for file uploads

### Type Safety as a First-Class Concern

The API enforces type safety at multiple levels:

```dart
// Response type T is enforced at compile time
ApiResultOf<E?, T> get<E, T>(
  String path, {
  required T Function(dynamic data) parser,  // Must return T
  E Function(dynamic data)? errorParser,     // Custom error type E
});
```

- **Generic type parameters** — `<E, T>` ensure both success and error types are known
- **Required parser** — Forces transformation from `dynamic` to concrete types
- **Typed error data** — `errorParser` extracts structured validation errors
- **No implicit `dynamic`** — All public API returns are fully typed

### Parsing as a First-Class Concern

Every request requires a **callback-based parser function**. This ensures:
- No raw `dynamic` values leak into application code
- Parsing errors are caught and wrapped in `RequestUnknownException`
- Type safety is enforced at the API boundary

### Error Handling as a First-Class Concern

The `ApiResultOf<E, T>` type makes error handling explicit:
- Callers cannot ignore errors — `Either` forces handling
- The `errorParser` parameter allows typed validation error extraction
- All HTTP status codes map to specific exception types

### Architecture Ready

DARC is designed to fit seamlessly into any architecture, especially **Clean Architecture**. By encapsulating HTTP status codes, exception mapping, and parsing logic, it significantly simplifies the **Data Layer**, allowing Repositories to focus solely on coordinating data rather than low-level HTTP details.

---

## Error Handling Model

All errors are represented as subclasses of `RequestException<T>`:

| Exception | HTTP Status | When |
|-----------|-------------|------|
| `FetchDataException` | — | Network/timeout errors |
| `CancelledRequestException` | — | Request cancelled |
| `BadRequestException` | 400 | Validation errors |
| `UnauthenticatedException` | 401 | Authentication required |
| `UnauthorizedException` | 403 | Permission denied |
| `NotFoundException` | 404 | Resource not found |
| `ConflictException` | 409 | State conflict |
| `InvalidTokenException` | 419 | Token expired |
| `UnProcessableDataException` | 422 | Validation failed |
| `InternalServerErrorException` | 500 | Server error |
| `RequestUnknownException` | — | Parsing errors, unknown errors, other status code errors |

The sealed class hierarchy enables exhaustive pattern matching:

```dart
switch (error) {
  case UnauthenticatedException():
    navigateToLogin();
  case UnProcessableDataException(:final data):
    showValidationErrors(data);
  case FetchDataException():
    showNetworkError();
  case _:
    showGenericError(error.message);
}
```

---

## Test Coverage & Reliability

The library includes a comprehensive unit test suite covering:

- All HTTP methods (GET, POST, PUT, DELETE, DOWNLOAD)
- Success and failure paths for each operation
- Token management lifecycle (set, remove, refresh)
- Token refresh triggering on 401 responses
- Authentication status propagation
- Error mapping from Dio exceptions to typed exceptions
- Multipart file upload encoding
- Download progress streaming and cancellation

Tests use real Dio instances with `http_mock_adapter` to verify actual HTTP behavior rather than mocking internal implementation details.

---

## Extensibility & Customization

### Custom Implementation

You can implement `ApiConsumer<T>` to provide alternative HTTP clients:

```dart
class HttpClientConsumer implements ApiConsumer<CustomCanceller> {
  // Implement all methods using dart:io HttpClient
}
```

### Custom File Factory

Inject a custom `MultipartFileFactory` for testing or alternative file handling:

```dart
final api = DioConsumer(
  client: client,
  tokenInterceptor: interceptor,
  baseUrl: baseUrl,
  fileFactory: MockMultipartFileFactory(),
);
```

### Custom Error Parsing

The `errorParser` parameter on each request allows typed extraction of error details:

```dart
final result = await api.post<ServerErrors, Response>(
  '/endpoint',
  parser: Response.fromJson,
  errorParser: ServerErrors.fromJson, // Typed error data
);
```

This is suitable for forms with backend validation.

### Adding Interceptors

For simplicity, adding interceptors through `ApiConsumer` isn't supported directly. You can add interceptors to the instance of `Dio` that is sent to `DioConsumer`.

## Contributing

Contributions are welcome. Please ensure:

- All new functionality includes tests
- Code follows existing architectural patterns
- Public APIs include documentation comments
- Breaking changes are discussed in issues first
- Following current linter rules

Run tests with:

```bash
flutter test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
