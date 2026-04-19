import 'dart:async';

import 'package:darc/src/api_constants.dart';
import 'package:darc/src/api_consumer.dart';
import 'package:darc/src/api_error_reporter.dart';
import 'package:darc/src/api_o_auth2_token.dart';
import 'package:darc/src/api_result_of.dart';
import 'package:darc/src/impl/dio_download_canceller.dart';
import 'package:darc/src/multi_part_file_model.dart';
import 'package:darc/src/request_exceptions.dart';
import 'package:darc/src/status_codes.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:fresh_dio/fresh_dio.dart';
import 'package:meta/meta.dart';

part 'flatten_map.dart';
part 'handle_dio_error.dart';
part 'multipart_file_factory.dart';

/// Concrete implementation of [ApiConsumer] using the Dio HTTP client.
class DioConsumer implements ApiConsumer<DioDownloadCanceller> {
  DioConsumer({
    required this.client,
    required this.tokenInterceptor,
    required String baseUrl,
    MultipartFileFactory? fileFactory,
  })  : _isInitializedCompleter = Completer<bool>(),
        _hasToken = false,
        _fileFactory = fileFactory ?? DefaultMultipartFileFactory() {
    isInitialized = _isInitializedCompleter.future;
    _prepareClient(baseUrl);

    tokenInterceptor.authenticationStatus.listen((status) {
      _hasToken = status == AuthenticationStatus.authenticated;
      if (!_isInitializedCompleter.isCompleted) {
        _isInitializedCompleter.complete(true);
      }
    });
  }

  @visibleForTesting
  final Dio client;
  @visibleForTesting
  final Fresh<ApiOAuth2Token> tokenInterceptor;
  final MultipartFileFactory _fileFactory;
  bool _hasToken;
  @visibleForTesting
  late final Future<bool> isInitialized;
  final Completer<bool> _isInitializedCompleter;

  @override
  Future<void> setToken(ApiOAuth2Token token) async {
    final isInitialized = await this.isInitialized;
    if (!isInitialized) {
      throw Exception('DioConsumer is not initialized');
    }

    return tokenInterceptor.setToken(token);
  }

  @override
  bool get hasToken => _hasToken;

  @override
  void saveLocale(String locale) {
    client.options.headers['X-APP-LOCALE'] = locale;
  }

  @override
  Future<void> removeToken() async {
    final isInitialized = await this.isInitialized;
    if (!isInitialized) {
      throw Exception('DioConsumer is not initialized');
    }

    return tokenInterceptor.clearToken();
  }

  @override
  ApiResultOf<E, Stream<Either<RequestException<E>, double>>> download<E>(
    String url,
    String filePath, {
    E Function(dynamic data)? errorParser,
    DioDownloadCanceller? canceller,
  }) async {
    try {
      final isInitialized = await this.isInitialized;
      if (!isInitialized) {
        throw Exception('DioConsumer is not initialized');
      }

      final streamController =
          StreamController<Either<RequestException<E>, double>>.broadcast();

      unawaited(
        client.download(
          url,
          filePath,
          cancelToken: canceller?.cancelToken,
          onReceiveProgress: (count, total) {
            final double progress;
            if (total <= 0) {
              progress = 0;
            } else {
              progress = (count / total).clamp(0, 1).toDouble();
            }

            streamController.add(
              right<RequestException<E>, double>(progress),
            );
          },
        ).then((_) {
          if (!streamController.isClosed) {
            unawaited(streamController.close());
          }
        }).catchError((Object e, StackTrace s) {
          if (e is! RequestException) {
            ApiErrorReporter.reportError(e, s);
          }

          final exception = switch (e) {
            RequestException<E>() => e,
            DioException() => handleDioError<E>(
                e,
                errorParser: errorParser,
              ),
            _ => RequestUnknownException<E>(),
          };

          streamController.add(
            left<RequestException<E>, double>(exception),
          );

          if (!streamController.isClosed) {
            unawaited(streamController.close());
          }
        }),
      );

      return right(streamController.stream);
    } on RequestException<E> catch (e) {
      return Left(e);
    } on DioException catch (e) {
      return Left(handleDioError<E>(e, errorParser: errorParser));
    } catch (e, s) {
      ApiErrorReporter.reportError(e, s);
      return Left(RequestUnknownException<E>());
    }
  }

  @override
  ApiResultOf<E?, T> get<E, T>(
    String path, {
    required T Function(dynamic data) parser,
    E Function(dynamic data)? errorParser,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? additionalHeaders,
  }) async {
    try {
      final isInitialized = await this.isInitialized;
      if (!isInitialized) {
        throw Exception('DioConsumer is not initialized');
      }

      final response = await client
          .get<dynamic>(
            path,
            queryParameters: queryParameters,
            options: Options(headers: additionalHeaders),
          )
          .then((response) => parser(response.data));

      return right(response);
    } on DioException catch (e) {
      final error = handleDioError(e, errorParser: errorParser);
      return left(error);
    } catch (e, s) {
      ApiErrorReporter.reportError(e, s);
      return left(RequestUnknownException());
    }
  }

  @override
  ApiResultOf<E?, T> post<E, T>(
    String path, {
    required T Function(dynamic data) parser,
    E Function(dynamic data)? errorParser,
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? additionalHeaders,
    List<MultiPartFileModel>? files,
  }) async {
    try {
      final isInitialized = await this.isInitialized;
      if (!isInitialized) {
        throw Exception('DioConsumer is not initialized');
      }

      if (files != null && files.isNotEmpty) {
        final filesMap =
            <String, dynamic /* MultipartFile or List<MultipartFile> */ >{};

        for (final file in files) {
          final multipartFile = await _fileFactory.create(
            filePath: file.filePath,
            filename: file.fileName,
          );

          final current = filesMap[file.requestBodyName];
          if (current is List) {
            filesMap[file.requestBodyName] = [...current, multipartFile];
          } else if (current is MultipartFile) {
            filesMap[file.requestBodyName] = [current, multipartFile];
          } else {
            filesMap[file.requestBodyName] = multipartFile;
          }
        }

        final formMap = {...flattenMap('', body ?? {}, {}), ...filesMap};

        final response = await client
            .post<dynamic>(
              path,
              queryParameters: queryParameters,
              data: FormData.fromMap(formMap),
              options: Options(headers: additionalHeaders),
            )
            .then((response) => parser(response.data));

        return right(response);
      } else {
        final response = await client
            .post<dynamic>(
              path,
              queryParameters: queryParameters,
              data: body,
              options: Options(headers: additionalHeaders),
            )
            .then((response) => parser(response.data));

        return right(response);
      }
    } on DioException catch (e) {
      final error = handleDioError(e, errorParser: errorParser);
      return left(error);
    } catch (e, s) {
      ApiErrorReporter.reportError(e, s);
      return left(RequestUnknownException());
    }
  }

  @override
  ApiResultOf<E?, T> put<E, T>(
    String path, {
    required T Function(dynamic data) parser,
    E Function(dynamic data)? errorParser,
    Map<String, dynamic>? body,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? additionalHeaders,
    List<MultiPartFileModel>? files,
  }) async {
    try {
      final isInitialized = await this.isInitialized;
      if (!isInitialized) {
        throw Exception('DioConsumer is not initialized');
      }

      if (files != null && files.isNotEmpty) {
        final filesMap =
            <String, dynamic /* MultipartFile or List<MultipartFile> */ >{};

        for (final file in files) {
          final multipartFile = await _fileFactory.create(
            filePath: file.filePath,
            filename: file.fileName,
          );

          final current = filesMap[file.requestBodyName];
          if (current is List) {
            filesMap[file.requestBodyName] = [...current, multipartFile];
          } else if (current is MultipartFile) {
            filesMap[file.requestBodyName] = [current, multipartFile];
          } else {
            filesMap[file.requestBodyName] = multipartFile;
          }
        }

        final formMap = {...flattenMap('', body ?? {}, {}), ...filesMap};

        final response = await client
            .put<dynamic>(
              path,
              queryParameters: queryParameters,
              data: FormData.fromMap(formMap),
              options: Options(headers: additionalHeaders),
            )
            .then((response) => parser(response.data));

        return right(response);
      } else {
        final response = await client
            .put<dynamic>(
              path,
              queryParameters: queryParameters,
              data: body,
              options: Options(headers: additionalHeaders),
            )
            .then((response) => parser(response.data));

        return right(response);
      }
    } on DioException catch (e) {
      final error = handleDioError(e, errorParser: errorParser);
      return left(error);
    } catch (e, s) {
      ApiErrorReporter.reportError(e, s);
      return left(RequestUnknownException());
    }
  }

  @override
  ApiResultOf<E?, T> delete<E, T>(
    String path, {
    required T Function(dynamic data) parser,
    E Function(dynamic data)? errorParser,
    Map<String, dynamic>? additionalHeaders,
    Map<String, dynamic>? data,
  }) async {
    try {
      final isInitialized = await this.isInitialized;
      if (!isInitialized) {
        throw Exception('DioConsumer is not initialized');
      }

      final response = await client
          .delete<dynamic>(
            path,
            data: data,
            options: Options(headers: additionalHeaders),
          )
          .then((response) => parser(response.data));

      return right(response);
    } on DioException catch (e) {
      final error = handleDioError(e, errorParser: errorParser);
      return left(error);
    } catch (e, s) {
      ApiErrorReporter.reportError(e, s);
      return left(RequestUnknownException());
    }
  }

  void _prepareClient(String baseUrl) {
    client.options
      ..baseUrl = baseUrl
      ..responseType = ResponseType.json
      ..followRedirects = false;

    client.interceptors.add(tokenInterceptor);
    client.options.headers[AppHeaders.accept] = AppHeaders.textPlain;
  }
}
