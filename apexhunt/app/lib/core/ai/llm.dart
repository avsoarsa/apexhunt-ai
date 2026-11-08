import 'dart:convert';

import 'package:dio/dio.dart';

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
        ByokProvider.gemini => 'e.g. gemini-2.5-flash',
        ByokProvider.groq => 'e.g. llama-3.3-70b-versatile',
        ByokProvider.custom => 'e.g. llama3.1:8b',
      };

  String get keyHelpUrl => switch (this) {
        ByokProvider.openRouter => 'https://openrouter.ai/keys',
        ByokProvider.openAi => 'https://platform.openai.com/api-keys',
        ByokProvider.anthropic => 'https://console.anthropic.com/settings/keys',
        ByokProvider.gemini => 'https://aistudio.google.com/apikey',
        ByokProvider.groq => 'https://console.groq.com/keys',
        ByokProvider.custom => '',
      };
}

String _errorMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final err = data['error'];
    if (err is Map && err['message'] != null) return '${err['message']}';
    if (err is String) return err;
    if (data['detail'] != null) return '${data['detail']}';
  }
  if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout) {
    return 'The AI provider took too long to respond. Please try again.';
  }
  if (e.type == DioExceptionType.connectionError) return 'No connection to the AI provider. Check your internet.';
  return 'AI request failed (${e.response?.statusCode ?? 'network'}).';
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
  Future<LlmResult> complete(List<ChatMsg> messages, {bool json = false, int maxTokens = 3000, double temperature = 0.4, String purpose = 'chat'}) async {
    try {
      if (provider == ByokProvider.anthropic) return await _anthropic(messages, json, maxTokens, temperature);
      return await _openAiCompatible(messages, json, maxTokens, temperature);
    } on DioException catch (e) {
      throw LlmException(_errorMessage(e));
    }
  }

  Future<LlmResult> _openAiCompatible(List<ChatMsg> messages, bool json, int maxTokens, double temperature) async {
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
      res = await _dio.post('$baseUrl/chat/completions', data: body, options: Options(headers: headers));
    } on DioException catch (e) {
      // Some local/custom servers reject response_format — retry once without it.
      if (json && (e.response?.statusCode == 400 || e.response?.statusCode == 422)) {
        body.remove('response_format');
        res = await _dio.post('$baseUrl/chat/completions', data: body, options: Options(headers: headers));
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

  Future<LlmResult> _anthropic(List<ChatMsg> messages, bool json, int maxTokens, double temperature) async {
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
        options: Options(headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'}));
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

  /// 5-token ping used by "Verify & save".
  Future<void> ping() async {
    await complete(const [ChatMsg.user('Reply with the word OK.')], maxTokens: 5, temperature: 0);
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
