import 'dart:convert';
import 'dart:typed_data';

import 'package:apexhunt_ai/core/ai/llm.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build 4: the AI key setup Sk tripped over on build 3.
DioException _err(int? status, Object? data, {DioExceptionType type = DioExceptionType.badResponse}) {
  final req = RequestOptions(path: '/chat/completions');
  return DioException(requestOptions: req, type: type, response: status == null ? null : Response(requestOptions: req, statusCode: status, data: data));
}

class _Recorder implements HttpClientAdapter {
  Duration? receiveTimeout;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    receiveTimeout = options.receiveTimeout;
    return ResponseBody.fromString(jsonEncode({'choices': [{'message': {'content': 'OK'}}]}), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('Gemini defaults to a model that works on new free keys', () {
    expect(ByokProvider.gemini.defaultModel, 'gemini-3.5-flash-lite');
    expect(ByokProvider.gemini.quickModels.map((m) => m.$1), contains('gemini-3.5-flash-lite'));
  });

  test('typed model names are turned into model codes', () {
    expect(ByokProvider.gemini.normalizeModel('gemini 3.8 flash'), 'gemini-3.8-flash');
    expect(ByokProvider.gemini.normalizeModel('  Gemini-3.5-Flash-Lite '), 'gemini-3.5-flash-lite');
    expect(ByokProvider.gemini.normalizeModel('models/gemini-3.6-flash'), 'gemini-3.6-flash');
    expect(ByokProvider.openRouter.normalizeModel(' anthropic/claude-haiku-5.5 '), 'anthropic/claude-haiku-5.5');
  });

  test('errors are explained in plain words', () {
    // Gemini's OpenAI endpoint wraps errors in a list; build 3 showed "AI request failed (400)".
    expect(aiErrorMessage(_err(400, [{'error': {'message': 'models/gemini 3.8 flash is not found for API version v1beta'}}])), contains("model code isn't recognised"));
    expect(aiErrorMessage(_err(401, {'error': {'message': 'API key not valid'}})), contains('API key was rejected'));
    expect(aiErrorMessage(_err(429, null)), contains('quota'));
    expect(aiErrorMessage(_err(503, null)), contains('having trouble'));
    expect(aiErrorMessage(_err(null, null, type: DioExceptionType.receiveTimeout)), contains('took too long'));
    expect(aiErrorMessage(_err(null, null, type: DioExceptionType.unknown)), contains('dropped'), reason: 'build 3 showed "AI request failed (network)"');
  });

  test('the connection test gives up after 30 seconds, not 3 minutes', () async {
    final rec = _Recorder();
    final dio = Dio()..httpClientAdapter = rec;
    await ByokLlmClient(provider: ByokProvider.gemini, apiKey: 'k', model: 'gemini-3.5-flash-lite', dio: dio).ping();
    expect(rec.receiveTimeout, const Duration(seconds: 30));
  });
}
