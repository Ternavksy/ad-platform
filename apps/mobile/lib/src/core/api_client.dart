import 'package:dio/dio.dart';

abstract interface class ApiTransport {
  void setToken(String? value);

  Future<dynamic> get(String path, {Map<String, dynamic>? query});

  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  });

  Future<dynamic> put(String path, {Object? data});

  Future<dynamic> upload(
    String path, {
    required String method,
    required Map<String, String> fields,
    required String filePath,
    required String fileName,
  });

  Future<void> delete(String path);
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient implements ApiTransport {
  ApiClient(String baseUrl)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          headers: const {'Content-Type': 'application/json'},
        ),
      );

  final Dio _dio;
  String? _token;

  @override
  void setToken(String? value) => _token = value;

  Options get _options => Options(
    headers: _token == null ? null : {'Authorization': 'Bearer $_token'},
  );

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      return (await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: _options,
      )).data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<dynamic> post(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
  }) async {
    try {
      return (await _dio.post<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: _options,
      )).data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<dynamic> put(String path, {Object? data}) async {
    try {
      return (await _dio.put<dynamic>(
        path,
        data: data,
        options: _options,
      )).data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<dynamic> upload(
    String path, {
    required String method,
    required Map<String, String> fields,
    required String filePath,
    required String fileName,
  }) async {
    try {
      final form = FormData.fromMap({
        ...fields,
        'file': await MultipartFile.fromFile(filePath, filename: fileName),
      });
      return (await _dio.request<dynamic>(
        path,
        data: form,
        options: Options(
          method: method,
          contentType: Headers.multipartFormDataContentType,
          headers: _token == null ? null : {'Authorization': 'Bearer $_token'},
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(seconds: 30),
        ),
      )).data;
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _dio.delete<dynamic>(path, options: _options);
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  ApiException _mapError(DioException error) {
    final response = error.response;
    final body = response?.data;
    String? message;
    if (body is Map<String, dynamic>) {
      message = body['detail']?.toString() ?? body['error']?.toString();
    }
    message ??= switch (error.type) {
      DioExceptionType.connectionError =>
        'Не удалось подключиться к серверу. Проверьте, что бэкенд запущен.',
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout => 'Сервер отвечает слишком долго.',
      _ => 'Не удалось выполнить запрос.',
    };
    return ApiException(message, statusCode: response?.statusCode);
  }
}
