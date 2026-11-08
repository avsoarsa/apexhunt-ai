import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/text_match.dart';
import 'job_sources.dart';

class TelemetryEvent {
  TelemetryEvent(this.message, {this.kind = 'INFO'}) : at = DateTime.now();
  final String message, kind; // INFO | JOB_FOUND | GAP_DETECTED | DONE | ERROR
  final DateTime at;
}

class MissionState {
  MissionState({MissionConfig? config, this.running = false, List<TelemetryEvent>? log, List<Opportunity>? opportunities, this.startedAt, this.scanned = 0})
      : config = config ?? MissionConfig(),
        log = log ?? [],
        opportunities = opportunities ?? [];
  final MissionConfig config;
  final bool running;
  final List<TelemetryEvent> log;
  final List<Opportunity> opportunities;
  final DateTime? startedAt;
  final int scanned;

  MissionState copyWith({MissionConfig? config, bool? running, List<TelemetryEvent>? log, List<Opportunity>? opportunities, DateTime? startedAt, int? scanned}) =>
      MissionState(
        config: config ?? this.config,
        running: running ?? this.running,
        log: log ?? this.log,
        opportunities: opportunities ?? this.opportunities,
        startedAt: startedAt ?? this.startedAt,
        scanned: scanned ?? this.scanned,
      );
}

class MissionController extends Notifier<MissionState> {
  static const _configFile = 'mission_config.json';
  static const _pipelineFile = 'pipeline.json';

  @override
  MissionState build() {
    _load();
    return MissionState();
  }

  Future<void> _load() async {
    final store = ref.read(localStoreProvider);
    final c = await store.readJson(_configFile);
    final p = await store.readJson(_pipelineFile);
    final profile = await ref.read(profileProvider.future);
    var config = c is Map ? MissionConfig.fromJson(Map<String, dynamic>.from(c)) : MissionConfig();
    if (config.keywords.isEmpty && profile != null) {
      config.keywords = [if (profile.headline.isNotEmpty) profile.headline, ...profile.targetRoles].take(3).toList();
    }
    final opps = p is List ? p.whereType<Map>().map((e) => Opportunity.fromJson(Map<String, dynamic>.from(e))).toList() : <Opportunity>[];
    state = state.copyWith(config: config, opportunities: opps);
  }

  Future<void> updateConfig(MissionConfig config) async {
    state = state.copyWith(config: config);
    await ref.read(localStoreProvider).writeJson(_configFile, config.toJson());
  }

  Future<void> _savePipeline() => ref.read(localStoreProvider).writeJson(_pipelineFile, state.opportunities.take(300).map((e) => e.toJson()).toList());

  void _log(String msg, [String kind = 'INFO']) => state = state.copyWith(log: [...state.log, TelemetryEvent(msg, kind: kind)]);

  /// Adds a pasted job description as a single-target opportunity (Quick Tailor).
  Future<Opportunity> addManual({required String title, required String company, required String description, String url = '', MissionMode kind = MissionMode.job}) async {
    final o = Opportunity(
      id: 'manual:${DateTime.now().millisecondsSinceEpoch}',
      source: 'Pasted',
      title: title.isEmpty ? 'Pasted job' : title,
      company: company,
      description: description,
      url: url,
      kind: kind,
      matchScore: 0,
    );
    final profile = ref.read(profileProvider).value;
    if (profile != null) {
      final s = TextMatch.scoreJob(profile, o, state.config.keywords);
      o.matchScore = s.score;
      o.matchedTerms = s.matched;
    }
    state = state.copyWith(opportunities: [o, ...state.opportunities]);
    await _savePipeline();
    return o;
  }

  Future<void> setStatus(String id, String status) async {
    for (final o in state.opportunities) {
      if (o.id == id) o.status = status;
    }
    state = state.copyWith(opportunities: [...state.opportunities]);
    await _savePipeline();
  }

  Future<void> dismiss(String id) async {
    state = state.copyWith(opportunities: state.opportunities.where((o) => o.id != id).toList());
    await _savePipeline();
  }

  Future<void> updateOpportunity(Opportunity o) async {
    state = state.copyWith(opportunities: [for (final x in state.opportunities) x.id == o.id ? o : x]);
    await _savePipeline();
  }

  Future<void> clearPipeline() async {
    state = state.copyWith(opportunities: state.opportunities.where((o) => o.status != 'NEW').toList());
    await _savePipeline();
  }

  Future<void> launch() async {
    if (state.running) return;
    final cfg = state.config;
    final profile = await ref.read(profileProvider.future);
    if (profile == null) {
      _log('Add your CV first.', 'ERROR');
      return;
    }
    final keywords = cfg.keywords.where((k) => k.trim().isNotEmpty).toList();
    if (keywords.isEmpty) {
      _log('Add at least one target role or keyword.', 'ERROR');
      return;
    }
    state = state.copyWith(running: true, log: [], startedAt: DateTime.now(), scanned: 0);
    final freelance = cfg.mode == MissionMode.freelance;
    final countries = cfg.countries.map((c) => countryNames[c] ?? c).join(', ');
    _log(freelance ? 'Scanning freelance briefs for ${keywords.join(', ')}…' : 'Scanning roles in $countries for ${keywords.join(', ')}…');

    final sources = <JobSource>[
      if (freelance) FreelancerSource() else ...[RemotiveSource(), JobicySource(), RemoteOkSource()],
      if (!freelance && cfg.countries.contains('DE')) ArbeitnowSource(),
      if (!freelance && cfg.watchedCompanies.isNotEmpty) CompanyBoardsSource(),
      if (freelance) RemotiveSource(),
    ];
    final api = ref.read(gatewayProvider);
    final signedIn = ref.read(authProvider).value != null;
    if (api != null && signedIn && !freelance) sources.add(GatewaySource(api));

    final found = <Opportunity>[];
    final seen = <String>{for (final o in state.opportunities) '${o.title.toLowerCase()}|${o.company.toLowerCase()}'};
    var scanned = 0;
    for (final kw in keywords.take(4)) {
      final batches = await Future.wait(sources.map((s) async {
        try {
          final r = await s.search(kw, cfg);
          return (s.name, r, null as Object?);
        } catch (e) {
          return (s.name, <Opportunity>[], e);
        }
      }));
      for (final (name, results, err) in batches) {
        if (err != null) {
          _log('$name unavailable right now — skipped.');
          continue;
        }
        scanned += results.length;
        for (var o in results) {
          if (freelance && o.kind != MissionMode.freelance) {
            // Remote contract roles are useful in freelance mode too.
            if (o.employmentType != 'CONTRACT' && o.employmentType != 'PART_TIME') continue;
            o.kind = MissionMode.freelance;
          }
          if (!matchesCountries(o, cfg.countries) || !matchesCommitment(o, cfg.commitments)) continue;
          if (!freelance && cfg.arrangements.length == 1 && cfg.arrangements.first == 'REMOTE' && !o.remote) continue;
          final key = '${o.title.toLowerCase()}|${o.company.toLowerCase()}';
          if (!seen.add(key)) continue;
          final s = TextMatch.scoreJob(profile, o, keywords);
          o.matchScore = s.score;
          o.matchedTerms = s.matched;
          if (o.matchScore < cfg.minMatch) continue;
          found.add(o);
        }
      }
      state = state.copyWith(scanned: scanned);
      _log('“$kw”: $scanned listings scanned, ${found.length} relevant so far.');
    }

    found.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    for (final o in found.take(5)) {
      _log('Match ${o.matchScore.round()}%: ${o.title}${o.company.isEmpty ? '' : ' @ ${o.company}'}', 'JOB_FOUND');
    }
    state = state.copyWith(running: false, opportunities: [...found, ...state.opportunities], scanned: scanned);
    await _savePipeline();
    _log(found.isEmpty ? 'No new matches. Try broader keywords or more countries.' : '${found.length} new opportunities added to your Pipeline.', 'DONE');
  }
}

final missionProvider = NotifierProvider<MissionController, MissionState>(MissionController.new);
