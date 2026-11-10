import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// One chat turn.
class ChatMsg {
  const ChatMsg(this.role, this.content);
  const ChatMsg.system(this.content) : role = 'system';
  const ChatMsg.user(this.content) : role = 'user';
  final String role, content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

class LlmResult {
  LlmResult({required this.content, this.chargedUsd = 0, this.balanceUsd, this.promptTokens = 0, this.completionTokens = 0});
  final String content;
  final double chargedUsd;
  final double? balanceUsd;
  final int promptTokens, completionTokens;
}

class LlmException implements Exception {
  LlmException(this.message, {this.needsCredits = false, this.needsSignIn = false, this.needsPro = false});
  final String message;
  final bool needsCredits, needsSignIn, needsPro;
  @override
  String toString() => message;
}

abstract class LlmClient {
  String get label;
  Future<LlmResult> complete(List<ChatMsg> messages, {bool json = false, int maxTokens = 3000, double temperature = 0.4, String purpose = 'chat'});
}

// ---------------------------------------------------------------------------- BYOK providers

enum ByokProvider { openRouter, openAi, anthropic, gemini, groq, custom }

extension ByokProviderInfo on ByokProvider {
  String get label => switch (this) {
        ByokProvider.openRouter => 'OpenRouter',
        ByokProvider.openAi => 'OpenAI',
        ByokProvider.anthropic => 'Anthropic',
        ByokProvider.gemini => 'Google Gemini',
        ByokProvider.groq => 'Groq',
        ByokProvider.custom => 'Custom (OpenAI-compatible)',
      };

  String get defaultBaseUrl => switch (this) {
        ByokProvider.openRouter => 'https://openrouter.ai/api/v1',
        ByokProvider.openAi => 'https://api.openai.com/v1',
        ByokProvider.anthropic => 'https://api.anthropic.com/v1',
        ByokProvider.gemini => 'https://generativelanguage.googleapis.com/v1beta/openai',
        ByokProvider.groq => 'https://api.groq.com/openai/v1',
        ByokProvider.custom => 'http://192.168.1.10:11434/v1',
      };

  String get modelHint => switch (this) {
        ByokProvider.openRouter => 'e.g. anthropic/claude-haiku-5.5',
        ByokProvider.openAi => 'e.g. gpt-6-luna',
        ByokProvider.anthropic => 'e.g. claude-haiku-5-5',
        ByokProvider.gemini => 'e.g. gemini-3.5-flash-lite',
        ByokProvider.groq => 'e.g. llama-3.3-70b-versatile',
        ByokProvider.custom => 'e.g. llama3.1:8b',
      };

  /// Tap-to-pick model codes (Google's models page, Oct 2026). Others are typed in.
  List<(String code, String label)> get quickModels => switch (this) {
        ByokProvider.gemini => const [
            ('gemini-3.5-flash-lite', 'Flash-Lite · fastest, best on free keys'),
            ('gemini-3.6-flash', '3.6 Flash'),
            ('gemini-3.8-flash', '3.8 Flash · smartest, can be slow on free keys'),
          ],
        _ => const [],
      };

  /// The model filled in when this provider is chosen.
  String get defaultModel => switch (this) {
        ByokProvider.gemini => 'gemini-3.5-flash-lite',
        ByokProvider.openRouter => 'anthropic/claude-haiku-5.5',
        ByokProvider.groq => 'llama-3.3-70b-versatile',
        _ => '',
      };

  /// Model codes never contain spaces; Gemini's are lowercase ("Gemini 3.8 Flash" → "gemini-3.8-flash").
  String normalizeModel(String input) {
    var m = input.trim().replaceAll(RegExp(r'\s+'), '-');
    if (this == ByokProvider.gemini) m = m.toLowerCase().replaceFirst(RegExp(r'^models/'), '');
    return m;
  }

  String get keyHelpUrl => switch (this) {
        ByokProvider.openRouter => 'https://openrouter.ai/keys',
        ByokProvider.openAi => 'https://platform.openai.com/api-keys',
        ByokProvider.anthropic => 'https://console.anthropic.com/settings/keys',
        ByokProvider.gemini => 'https://aistudio.google.com/apikey',
        ByokProvider.groq => 'https://console.groq.com/keys',
        ByokProvider.custom => '',
      };
}

@visibleForTesting
String aiErrorMessage(DioException e) => _errorMessage(e);

String _errorMessage(DioException e) {
  final status = e.response?.statusCode;
  var data = e.response?.data;
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {}
  }
  if (data is List && data.isNotEmpty) data = data.first; // Gemini's OpenAI endpoint: [{"error": {...}}]
  String? detail;
  if (data is Map) {
    final err = data['error'];
    if (err is Map && err['message'] != null) detail = '${err['message']}';
    if (err is String) detail = err;
    if (detail == null && data['detail'] != null) detail = '${data['detail']}';
  }
  final hint = switch (status) {
    400 when (detail ?? '').toLowerCase().contains('model') => "The model code isn't recognised. Pick one from the list (e.g. gemini-3.5-flash-lite).",
    400 => 'The AI provider rejected the request. Check the model code.',
    401 || 403 => 'The API key was rejected. Copy it again from your provider and paste it fresh.',
    404 => "Model not found. Pick one from the list or check the code.",
    429 => 'Rate limit or free quota reached. Wait a minute, or pick a lighter model.',
    final int s when s >= 500 => 'The AI provider is having trouble. Try again, or pick a faster model.',
    _ => null,
  };
  if (hint != null) return detail == null || detail.length > 160 ? hint : '$hint ($detail)';
  if (detail != null) return detail;
  if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout) {
    return 'The AI provider took too long to respond. Try again, or pick a faster model.';
  }
  if (e.type == DioExceptionType.connectionError) return 'No connection to the AI provider. Check your internet.';
  return 'The connection to the AI provider dropped before it answered. Try again, or pick a faster model.';
}

/// Calls the user's own provider directly from the device. The key never touches our servers.
class ByokLlmClient implements LlmClient {
  ByokLlmClient({required this.provider, required this.apiKey, required this.model, String? baseUrl, Dio? dio})
      : baseUrl = (baseUrl == null || baseUrl.isEmpty ? provider.defaultBaseUrl : baseUrl).replaceAll(RegExp(r'/+$'), ''),
        _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 180)));

  final ByokProvider provider;
  final String apiKey, model, baseUrl;
  final Dio _dio;

  @override
  String get label => '${provider.label} · $model';

  @override
  Future<LlmResult> complete(List<ChatMsg> messages, {bool json = false, int maxTokens = 3000, double temperature = 0.4, String purpose = 'chat'}) =>
      _complete(messages, json: json, maxTokens: maxTokens, temperature: temperature);

  Future<LlmResult> _complete(List<ChatMsg> messages, {bool json = false, int maxTokens = 3000, double temperature = 0.4, Duration? timeout}) async {
    try {
      if (provider == ByokProvider.anthropic) return await _anthropic(messages, json, maxTokens, temperature, timeout);
      return await _openAiCompatible(messages, json, maxTokens, temperature, timeout);
    } on DioException catch (e) {
      throw LlmException(_errorMessage(e));
    }
  }

  Future<LlmResult> _openAiCompatible(List<ChatMsg> messages, bool json, int maxTokens, double temperature, Duration? timeout) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'max_tokens': maxTokens,
      'temperature': temperature,
      if (json) 'response_format': {'type': 'json_object'},
    };
    final headers = <String, dynamic>{
      'Authorization': 'Bearer $apiKey',
      if (provider == ByokProvider.openRouter) 'X-Title': 'ApexHunt AI',
    };
    Response res;
    try {
      res = await _dio.post('$baseUrl/chat/completions', data: body, options: Options(headers: headers, receiveTimeout: timeout));
    } on DioException catch (e) {
      // Some local/custom servers reject response_format — retry once without it.
      if (json && (e.response?.statusCode == 400 || e.response?.statusCode == 422)) {
        body.remove('response_format');
        res = await _dio.post('$baseUrl/chat/completions', data: body, options: Options(headers: headers, receiveTimeout: timeout));
      } else {
        rethrow;
      }
    }
    final data = res.data is String ? jsonDecode(res.data as String) : res.data as Map;
    final content = (((data['choices'] as List?)?.firstOrNull as Map?)?['message'] as Map?)?['content'];
    final usage = data['usage'] as Map? ?? {};
    return LlmResult(
      content: content is String ? content : '',
      promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  Future<LlmResult> _anthropic(List<ChatMsg> messages, bool json, int maxTokens, double temperature, Duration? timeout) async {
    final system = messages.where((m) => m.role == 'system').map((m) => m.content).join('\n\n');
    final turns = messages.where((m) => m.role != 'system').map((m) => m.toJson()).toList();
    final res = await _dio.post('$baseUrl/messages',
        data: {
          'model': model,
          'max_tokens': maxTokens,
          'temperature': temperature,
          if (system.isNotEmpty) 'system': json ? '$system\n\nRespond with a single valid JSON object only.' : system,
          'messages': turns,
        },
        options: Options(headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'}, receiveTimeout: timeout));
    final data = res.data as Map;
    final blocks = (data['content'] as List? ?? []).whereType<Map>();
    final text = blocks.where((b) => b['type'] == 'text').map((b) => b['text']).join();
    final usage = data['usage'] as Map? ?? {};
    return LlmResult(
      content: text,
      promptTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      completionTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  /// Short ping used by "Test connection": gives up after 30 seconds instead of the 3 minutes real steps get.
  Future<void> ping({Duration timeout = const Duration(seconds: 30)}) async {
    await _complete(const [ChatMsg.user('Reply with the word OK.')], maxTokens: 5, temperature: 0, timeout: timeout);
  }
}

/// Managed "Apex" engines through the ApexHunt gateway (credits wallet).
class ManagedLlmClient implements LlmClient {
  ManagedLlmClient({required this.gatewayUrl, required this.tokenProvider, required this.engine, required this.engineLabel, this.onBalance, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 180)));

  final String gatewayUrl, engine, engineLabel;
  final Future<String?> Function() tokenProvider;
  final void Function(double balance)? onBalance;
  final Dio _dio;

  @override
  String get label => engineLabel;

  @override
  Future<LlmResult> complete(List<ChatMsg> messages, {bool json = false, int maxTokens = 3000, double temperature = 0.4, String purpose = 'chat'}) async {
    final token = await tokenProvider();
    if (token == null) throw LlmException('Sign in to use Apex AI credits.', needsSignIn: true);
    try {
      final res = await _dio.post('$gatewayUrl/api/v1/llm/chat',
          data: {
            'model': engine,
            'messages': messages.map((m) => m.toJson()).toList(),
            'max_tokens': maxTokens,
            'temperature': temperature,
            'json_mode': json,
            'purpose': purpose,
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      final d = res.data as Map;
      final balance = (d['balance_usd'] as num?)?.toDouble();
      if (balance != null) onBalance?.call(balance);
      final usage = d['usage'] as Map? ?? {};
      return LlmResult(
        content: '${d['content'] ?? ''}',
        chargedUsd: (d['charged_usd'] as num?)?.toDouble() ?? 0,
        balanceUsd: balance,
        promptTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final msg = _errorMessage(e);
      if (code == 402) {
        throw LlmException(msg, needsCredits: !msg.toLowerCase().contains('subscription'), needsPro: msg.toLowerCase().contains('subscription'));
      }
      if (code == 401) throw LlmException('Your session expired. Please sign in again.', needsSignIn: true);
      throw LlmException(msg);
    }
  }
}

/// Pulls the first JSON object out of a model reply (handles ```json fences and chatter).
Map<String, dynamic> parseJsonObject(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();
  try {
    final v = jsonDecode(text);
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final v = jsonDecode(text.substring(start, end + 1));
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
  }
  throw LlmException('The AI returned an unreadable answer. Try again or switch engine.');
}
