import 'package:dio/dio.dart';

import 'config.dart';
import 'models.dart';

class Wallet {
  Wallet({this.balanceUsd = 0, this.subscriptionStatus = 'INACTIVE', this.hasActiveSubscription = false, this.expiresAt});
  final double balanceUsd;
  final String subscriptionStatus;
  final bool hasActiveSubscription;
  final DateTime? expiresAt;

  factory Wallet.fromJson(Map j) => Wallet(
        balanceUsd: (j['credit_balance_usd'] as num?)?.toDouble() ?? 0,
        subscriptionStatus: '${j['subscription_status'] ?? 'INACTIVE'}',
        hasActiveSubscription: j['has_active_subscription'] == true,
        expiresAt: DateTime.tryParse('${j['subscription_expires_at'] ?? ''}'),
      );
}

class EngineTier {
  EngineTier({required this.id, required this.name, required this.description, required this.modelLabel, this.costPerApp});
  final String id, name, description, modelLabel;
  final double? costPerApp;
  factory EngineTier.fromJson(Map j) => EngineTier(
        id: '${j['id']}',
        name: '${j['name'] ?? j['id']}',
        description: '${j['description'] ?? ''}',
        modelLabel: '${j['model_label'] ?? j['label'] ?? ''}',
        costPerApp: (j['est_cost_per_application_usd'] as num?)?.toDouble(),
      );

  static final defaults = [
    EngineTier(id: 'apex-flash', name: 'Apex Flash', description: 'Fast and economical.', modelLabel: ''),
    EngineTier(id: 'apex-pro', name: 'Apex Pro', description: 'Balanced quality and cost. Recommended.', modelLabel: ''),
    EngineTier(id: 'apex-elite', name: 'Apex Elite', description: 'Highest writing quality.', modelLabel: ''),
  ];
}

class EngineCatalog {
  EngineCatalog({required this.tiers, required this.models});
  final List<EngineTier> tiers;
  final List<EngineTier> models;
}

/// REST client for the ApexHunt gateway.
class GatewayApi {
  GatewayApi(this.tokenProvider, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: AppConfig.gatewayUrl, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)));

  final Future<String?> Function() tokenProvider;
  final Dio _dio;

  Future<Options> _auth() async {
    final t = await tokenProvider();
    if (t == null) throw StateError('Not signed in');
    return Options(headers: {'Authorization': 'Bearer $t'});
  }

  Future<Wallet> me() async {
    final r = await _dio.get('/api/v1/me', options: await _auth());
    return Wallet.fromJson((r.data as Map)['wallet'] as Map);
  }

  Future<EngineCatalog> catalog() async {
    final r = await _dio.get('/api/v1/llm/catalog');
    final d = r.data as Map;
    return EngineCatalog(
      tiers: (d['tiers'] as List? ?? []).whereType<Map>().map(EngineTier.fromJson).toList(),
      models: (d['models'] as List? ?? [])
          .whereType<Map>()
          .map((m) => EngineTier(id: '${m['id']}', name: '${m['label']}', description: '', modelLabel: '${m['label']}', costPerApp: (m['est_cost_per_application_usd'] as num?)?.toDouble()))
          .toList(),
    );
  }

  Future<List<Opportunity>> searchJobs(String query, List<String> countries) async {
    final r = await _dio.post('/api/v1/jobs/search', data: {'query': query, 'countries': countries}, options: await _auth());
    return ((r.data as Map)['jobs'] as List? ?? []).whereType<Map>().map((j) => Opportunity.fromJson(Map<String, dynamic>.from(j))).toList();
  }

  Future<Wallet?> syncBilling() async {
    final r = await _dio.post('/api/v1/billing/sync', options: await _auth());
    final w = (r.data as Map)['wallet'];
    return w is Map ? Wallet.fromJson(w) : null;
  }

  Future<void> flag({required String kind, required String reason, String notes = '', String excerpt = ''}) async {
    await _dio.post('/api/v1/flags',
        data: {'artifact_kind': kind, 'reason': reason, 'notes': notes, 'excerpt': excerpt.length > 3900 ? excerpt.substring(0, 3900) : excerpt},
        options: await _auth());
  }

  Future<void> deleteAccount() async {
    await _dio.delete('/api/v1/users/me', options: await _auth());
  }
}
