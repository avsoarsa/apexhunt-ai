import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'ai/llm.dart';
import 'billing.dart';
import 'config.dart';
import 'gateway.dart';
import 'models.dart';
import 'storage.dart';

// ============================================================================ infrastructure

final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('overridden in main'));
final vaultProvider = Provider<SecureVault>((ref) => SecureVault());
final billingServiceProvider = Provider<BillingService>((ref) => BillingService());

sb.SupabaseClient? get _supabase => AppConfig.hasAuth ? sb.Supabase.instance.client : null;

Future<String?> currentAccessToken() async {
  final client = _supabase;
  if (client == null) return null;
  var session = client.auth.currentSession;
  if (session == null) return null;
  if (session.isExpired) {
    try {
      session = (await client.auth.refreshSession()).session;
    } catch (_) {
      return null;
    }
  }
  return session?.accessToken;
}

// ============================================================================ auth

class AuthUser {
  AuthUser(this.id, this.email);
  final String id;
  final String? email;
}

final authProvider = StreamProvider<AuthUser?>((ref) {
  final client = _supabase;
  if (client == null) return Stream.value(null);
  AuthUser? map(sb.Session? s) => s == null ? null : AuthUser(s.user.id, s.user.email);
  final controller = StreamController<AuthUser?>();
  controller.add(map(client.auth.currentSession));
  final sub = client.auth.onAuthStateChange.listen((e) => controller.add(map(e.session)));
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream.distinct((a, b) => a?.id == b?.id);
});

class AuthActions {
  static Future<void> sendCode(String email) async {
    await _supabase!.auth.signInWithOtp(email: email.trim(), shouldCreateUser: true);
  }

  static Future<void> verifyCode(String email, String code) async {
    await _supabase!.auth.verifyOTP(email: email.trim(), token: code.trim(), type: sb.OtpType.email);
  }

  static Future<void> signOut() async {
    await _supabase?.auth.signOut();
  }
}

final gatewayProvider = Provider<GatewayApi?>((ref) => AppConfig.hasGateway ? GatewayApi(currentAccessToken) : null);

// ============================================================================ wallet

class WalletController extends AsyncNotifier<Wallet?> {
  @override
  Future<Wallet?> build() async {
    final user = await ref.watch(authProvider.future);
    final api = ref.watch(gatewayProvider);
    if (user == null || api == null) return null;
    return api.me();
  }

  void setBalance(double balance) {
    final w = state.value;
    if (w == null) return;
    state = AsyncData(Wallet(balanceUsd: balance, subscriptionStatus: w.subscriptionStatus, hasActiveSubscription: w.hasActiveSubscription, expiresAt: w.expiresAt));
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  Future<void> syncAfterPurchase() async {
    final api = ref.read(gatewayProvider);
    if (api == null) return;
    try {
      final w = await api.syncBilling();
      if (w != null) state = AsyncData(w);
    } catch (_) {
      await refresh();
    }
  }
}

final walletProvider = AsyncNotifierProvider<WalletController, Wallet?>(WalletController.new);

// ============================================================================ billing / Pro

class BillingController extends AsyncNotifier<BillingSnapshot> {
  @override
  Future<BillingSnapshot> build() async {
    final svc = ref.watch(billingServiceProvider);
    final user = await ref.watch(authProvider.future);
    await svc.init();
    await svc.identify(user?.id);
    return svc.load();
  }

  Future<void> reload() async => state = await AsyncValue.guard(build);
}

final billingProvider = AsyncNotifierProvider<BillingController, BillingSnapshot>(BillingController.new);

/// Pro unlocks BYOK mode, the Elite engine and batch tailoring.
/// Without a RevenueCat key (development builds) everything is unlocked.
final isProProvider = Provider<bool>((ref) {
  if (!ref.watch(billingServiceProvider).enabled) return true;
  final billing = ref.watch(billingProvider).value;
  final wallet = ref.watch(walletProvider).value;
  return (billing?.isPro ?? false) || (wallet?.hasActiveSubscription ?? false);
});

// ============================================================================ AI settings

enum AiMode { managed, byok }

class AiSettings {
  AiSettings({
    this.mode = AiMode.managed,
    this.engine = 'apex-pro',
    this.engineLabel = 'Apex Pro',
    this.byokProvider = ByokProvider.gemini,
    this.byokModel = '',
    this.byokBaseUrl = '',
    this.hasByokKey = false,
  });
  final AiMode mode;
  final String engine, engineLabel, byokModel, byokBaseUrl;
  final ByokProvider byokProvider;
  final bool hasByokKey;

  AiSettings copyWith({AiMode? mode, String? engine, String? engineLabel, ByokProvider? byokProvider, String? byokModel, String? byokBaseUrl, bool? hasByokKey}) => AiSettings(
        mode: mode ?? this.mode,
        engine: engine ?? this.engine,
        engineLabel: engineLabel ?? this.engineLabel,
        byokProvider: byokProvider ?? this.byokProvider,
        byokModel: byokModel ?? this.byokModel,
        byokBaseUrl: byokBaseUrl ?? this.byokBaseUrl,
        hasByokKey: hasByokKey ?? this.hasByokKey,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'engine': engine,
        'engine_label': engineLabel,
        'byok_provider': byokProvider.name,
        'byok_model': byokModel,
        'byok_base_url': byokBaseUrl,
      };

  factory AiSettings.fromJson(Map j, bool hasKey) => AiSettings(
        mode: j['mode'] == 'byok' ? AiMode.byok : AiMode.managed,
        engine: '${j['engine'] ?? 'apex-pro'}',
        engineLabel: '${j['engine_label'] ?? 'Apex Pro'}',
        byokProvider: ByokProvider.values.firstWhere((p) => p.name == j['byok_provider'], orElse: () => ByokProvider.gemini),
        byokModel: '${j['byok_model'] ?? ''}',
        byokBaseUrl: '${j['byok_base_url'] ?? ''}',
        hasByokKey: hasKey,
      );

  String get activeLabel => mode == AiMode.managed ? engineLabel : '${byokProvider.label} (your key)';
}

class AiSettingsController extends AsyncNotifier<AiSettings> {
  static const _file = 'ai_settings.json';

  @override
  Future<AiSettings> build() async {
    final store = ref.watch(localStoreProvider);
    final hasKey = (await ref.read(vaultProvider).readByokKey())?.isNotEmpty ?? false;
    final j = await store.readJson(_file);
    if (j is Map) return AiSettings.fromJson(j, hasKey);
    // Without a managed gateway the app can only run on the user's own key.
    return AiSettings(mode: AppConfig.hasManagedAi ? AiMode.managed : AiMode.byok, hasByokKey: hasKey);
  }

  Future<void> save(AiSettings s) async {
    await ref.read(localStoreProvider).writeJson(_file, s.toJson());
    state = AsyncData(s);
  }

  Future<void> saveByok({required ByokProvider provider, required String model, required String baseUrl, required String key}) async {
    await ref.read(vaultProvider).writeByokKey(key);
    final cur = state.value ?? AiSettings();
    await save(cur.copyWith(mode: AiMode.byok, byokProvider: provider, byokModel: model, byokBaseUrl: baseUrl, hasByokKey: true));
  }

  Future<void> clearByok() async {
    await ref.read(vaultProvider).writeByokKey(null);
    final cur = state.value ?? AiSettings();
    await save(cur.copyWith(mode: AppConfig.hasManagedAi ? AiMode.managed : AiMode.byok, hasByokKey: false));
  }
}

final aiSettingsProvider = AsyncNotifierProvider<AiSettingsController, AiSettings>(AiSettingsController.new);

/// Builds the right LLM client for the current settings, enforcing the plan rules.
final aiServiceProvider = Provider<AiService>((ref) => AiService(ref));

class AiService {
  AiService(this.ref);
  final Ref ref;

  /// [allowFreeByok] lets onboarding parse a CV with the user's key before they subscribe.
  Future<LlmClient> client({bool allowFreeByok = false}) async {
    final s = await ref.read(aiSettingsProvider.future);
    if (s.mode == AiMode.byok) {
      final key = await ref.read(vaultProvider).readByokKey();
      if (key == null || key.isEmpty) throw LlmException('Add your API key in AI & Settings first.');
      if (!allowFreeByok && !ref.read(isProProvider)) {
        throw LlmException('Using your own API key is a Pro feature.', needsPro: true);
      }
      if (s.byokModel.isEmpty) throw LlmException('Set a model name for your API key in AI & Settings.');
      return ByokLlmClient(provider: s.byokProvider, apiKey: key, model: s.byokModel, baseUrl: s.byokBaseUrl);
    }
    if (!AppConfig.hasManagedAi) throw LlmException('Managed AI is not configured in this build. Add your own API key.');
    final user = ref.read(authProvider).value;
    if (user == null) throw LlmException('Sign in to use your free Apex AI credits.', needsSignIn: true);
    if (s.engine == 'apex-elite' && !ref.read(isProProvider)) {
      throw LlmException('Apex Elite is a Pro engine. Upgrade or switch to Apex Pro.', needsPro: true);
    }
    return ManagedLlmClient(
      gatewayUrl: AppConfig.gatewayUrl,
      tokenProvider: currentAccessToken,
      engine: s.engine,
      engineLabel: s.engineLabel,
      onBalance: (b) => ref.read(walletProvider.notifier).setBalance(b),
    );
  }
}

// ============================================================================ profile

class ProfileController extends AsyncNotifier<MasterProfile?> {
  static const _file = 'profile.json';

  @override
  Future<MasterProfile?> build() async {
    final j = await ref.watch(localStoreProvider).readJson(_file);
    return j is Map ? MasterProfile.fromJson(Map<String, dynamic>.from(j)) : null;
  }

  Future<void> save(MasterProfile p) async {
    p.updatedAt = DateTime.now();
    await ref.read(localStoreProvider).writeJson(_file, p.toJson());
    state = AsyncData(p);
  }

  /// Persist a user-confirmed skill ("I have this") so future tailoring can use it.
  Future<void> addEvidence(List<SkillEvidence> items) async {
    final p = state.value;
    if (p == null || items.isEmpty) return;
    final copy = p.copy();
    for (final e in items) {
      copy.evidence.removeWhere((x) => x.skill.toLowerCase() == e.skill.toLowerCase());
      copy.evidence.add(e);
      if (!copy.skills.any((s) => s.toLowerCase() == e.skill.toLowerCase())) copy.skills.add(e.skill);
      copy.learning.removeWhere((s) => s.toLowerCase() == e.skill.toLowerCase());
    }
    await save(copy);
  }

  Future<void> addLearning(List<String> skills) async {
    final p = state.value;
    if (p == null || skills.isEmpty) return;
    final copy = p.copy();
    for (final s in skills) {
      if (!copy.learning.any((x) => x.toLowerCase() == s.toLowerCase())) copy.learning.add(s);
    }
    await save(copy);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileController, MasterProfile?>(ProfileController.new);

// ============================================================================ artifacts (CV vault)

class ArtifactsController extends AsyncNotifier<List<TailoredArtifact>> {
  static const _index = 'artifacts.json';

  @override
  Future<List<TailoredArtifact>> build() async {
    final j = await ref.watch(localStoreProvider).readJson(_index);
    if (j is! List) return [];
    final list = j.whereType<Map>().map((e) => TailoredArtifact.fromJson(Map<String, dynamic>.from(e))).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> _persist(List<TailoredArtifact> list) async {
    await ref.read(localStoreProvider).writeJson(_index, list.map((e) => e.toJson()).toList());
    state = AsyncData(List.of(list));
  }

  Future<void> upsert(TailoredArtifact a) async {
    final list = [...(state.value ?? <TailoredArtifact>[])];
    final i = list.indexWhere((x) => x.id == a.id);
    i >= 0 ? list[i] = a : list.insert(0, a);
    await _persist(list);
  }

  Future<void> remove(String id) async {
    await _persist([...(state.value ?? <TailoredArtifact>[])]..removeWhere((x) => x.id == id));
  }

  TailoredArtifact? byId(String id) => state.value?.where((a) => a.id == id).firstOrNull;
}

final artifactsProvider = AsyncNotifierProvider<ArtifactsController, List<TailoredArtifact>>(ArtifactsController.new);

// ============================================================================ wipe

Future<void> wipeAllLocalData(WidgetRef ref) async {
  await ref.read(localStoreProvider).wipe();
  await ref.read(vaultProvider).wipe();
  ref.invalidate(profileProvider);
  ref.invalidate(artifactsProvider);
  ref.invalidate(aiSettingsProvider);
  if (kDebugMode) debugPrint('Local data wiped');
}
