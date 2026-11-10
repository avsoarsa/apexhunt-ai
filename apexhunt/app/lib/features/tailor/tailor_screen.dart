import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ai/llm.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/text_match.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import '../discovery/mission_controller.dart';
import 'tailor_engine.dart';

/// Opportunity → JD audit → skill check-in → honest tailoring → prep.
class TailorScreen extends ConsumerStatefulWidget {
  const TailorScreen({super.key, required this.opportunityId});
  final String opportunityId;
  @override
  ConsumerState<TailorScreen> createState() => _TailorScreenState();
}

class _CheckIn {
  _CheckIn(this.decision);
  SkillDecision decision;
  final context = TextEditingController();
  String? roleId;
}

class _TailorScreenState extends ConsumerState<TailorScreen> {
  int _step = 0;
  bool _busy = false;
  final _jd = TextEditingController();
  JdAnalysis? _analysis;
  final Map<String, _CheckIn> _checkIns = {};
  final List<TelemetryEvent> _log = [];
  DateTime? _startedAt;
  TailorEngine? _engine;
  final Map<String, EvidenceSuggestion> _suggested = {};
  final Map<String, GlobalKey> _cardKeys = {};
  bool _suggesting = false, _showErrors = false;

  static bool _needsLine(_CheckIn c) => c.decision == SkillDecision.haveIt && c.context.text.trim().length < 8;

  /// "Fill from my CV": the AI finds where the CV already shows each open skill and drafts the line.
  Future<void> _fillFromCv() async {
    final a = _analysis!;
    final profile = ref.read(profileProvider).value!;
    final open = [for (final r in a.requirements) if (_checkIns[r.skill]?.decision != SkillDecision.matched) r];
    setState(() => _suggesting = true);
    try {
      final engine = _engine ??= TailorEngine(await ref.read(aiServiceProvider).client());
      final found = await engine.suggestEvidence(profile, open);
      setState(() {
        for (final s in found.values) {
          final c = _checkIns[s.skill]!;
          c.decision = SkillDecision.haveIt;
          if (c.context.text.trim().isEmpty) c.context.text = s.line;
          c.roleId ??= s.roleId;
          _suggested[s.skill] = s;
        }
      });
      if (mounted) {
        final rest = open.length - found.length;
        showSnack(
            context,
            found.isEmpty
                ? "Your CV doesn't clearly show any of these. They stay as Don't have, unless you add your own line."
                : 'Found ${found.length} in your CV and drafted the lines. Please check them.${rest > 0 ? ' $rest not found: they stay as Don\'t have.' : ''}');
      }
    } catch (e) {
      if (mounted) handleAiError(context, e);
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  Opportunity? get _opp => ref.read(missionProvider).opportunities.where((o) => o.id == widget.opportunityId).firstOrNull;

  @override
  void initState() {
    super.initState();
    final o = _opp;
    if (o != null) _jd.text = o.description;
  }

  void _log_(String m, [String kind = 'INFO']) => setState(() => _log.add(TelemetryEvent(m, kind: kind)));

  Future<void> _analyze() async {
    final o = _opp;
    if (o == null) return;
    if (_jd.text.trim().length < 80) {
      showSnack(context, 'The description is too short to tailor against. Paste the full posting.', error: true);
      return;
    }
    if (_jd.text != o.description) {
      o.description = _jd.text.trim();
      o.descriptionComplete = true;
      await ref.read(missionProvider.notifier).updateOpportunity(o);
    }
    setState(() => _busy = true);
    try {
      final llm = await ref.read(aiServiceProvider).client();
      _engine = TailorEngine(llm);
      final a = await _engine!.analyze(o);
      final profile = ref.read(profileProvider).value!;
      final decisions = TailorEngine.initialDecisions(profile, a);
      _checkIns
        ..clear()
        ..addAll(decisions.map((k, v) => MapEntry(k, _CheckIn(v))));
      _suggested.clear();
      _showErrors = false;
      setState(() {
        _analysis = a;
        _step = 1;
      });
    } catch (e) {
      if (mounted) handleAiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run() async {
    final o = _opp!;
    final a = _analysis!;
    final missing = [for (final r in a.requirements) if (_checkIns[r.skill] != null && _needsLine(_checkIns[r.skill]!)) r.skill];
    if (missing.isNotEmpty) {
      setState(() => _showErrors = true);
      final ctx = _cardKeys[missing.first]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), alignment: 0.1);
      final more = missing.length > 1 ? ' (and ${missing.length - 1} more)' : '';
      showSnack(context, 'Add one line for ${missing.first}$more, or switch it to Learning or Don\'t have.', error: true);
      return;
    }
    setState(() {
      _step = 2;
      _busy = true;
      _log.clear();
      _startedAt = DateTime.now();
    });

    final profileCtrl = ref.read(profileProvider.notifier);
    // Persist what the user confirmed so it's reused (truthfully) next time.
    await profileCtrl.addEvidence([
      for (final e in _checkIns.entries)
        if (e.value.decision == SkillDecision.haveIt) SkillEvidence(skill: e.key, context: e.value.context.text.trim(), roleId: e.value.roleId),
    ]);
    await profileCtrl.addLearning([for (final e in _checkIns.entries) if (e.value.decision == SkillDecision.learning) e.key]);
    final profile = ref.read(profileProvider).value!;
    final decisions = {for (final e in _checkIns.entries) e.key: e.value.decision == SkillDecision.haveIt ? SkillDecision.matched : e.value.decision};
    final engine = _engine ?? TailorEngine(await ref.read(aiServiceProvider).client());

    try {
      final matched = decisions.values.where((d) => d == SkillDecision.matched).length;
      _log_('JD audit: ${a.requirements.length} requirements, $matched backed by your experience.');
      final gaps = decisions.entries.where((e) => e.value != SkillDecision.matched).map((e) => e.key).toList();
      if (gaps.isNotEmpty) _log_('Honest gaps (kept off your CV): ${gaps.take(5).join(', ')}${gaps.length > 5 ? '…' : ''}', 'GAP_DETECTED');
      _log_('Tailoring your real experience to “${a.title}”…');
      final cv = await engine.tailor(profile: profile, opportunity: o, analysis: a, decisions: decisions);
      final reverted = cv.roles.expand((r) => r.bullets).where((b) => b.flags.isNotEmpty).length + cv.skillFlags.length;
      _log_(reverted == 0 ? 'Truth Guard: every line traces back to your profile ✓' : 'Truth Guard: reverted $reverted AI additions not backed by your profile.', reverted == 0 ? 'JOB_FOUND' : 'GAP_DETECTED');
      final before = TextMatch.atsScore(TailorEngine.baseCvText(profile), a.requirements, keywords: a.keywords, skills: profile.skills);
      final after = TextMatch.atsScore(TailorEngine.tailoredCvText(profile, cv), a.requirements, keywords: a.keywords, skills: cv.skills);
      _log_('ATS keyword match: ${before.round()}% → ${after.round()}%', 'JOB_FOUND');

      _log_(o.kind == MissionMode.freelance ? 'Drafting your client proposal…' : 'Drafting your cover letter…');
      final noteF = engine.applicationNote(profile: profile, opportunity: o, analysis: a, cv: cv, decisions: decisions);
      _log_('Building your interview prep: STAR stories, likely questions, gap plans…');
      final prepF = engine.prep(profile: profile, opportunity: o, analysis: a, cv: cv, decisions: decisions);
      var note = '';
      try {
        note = await noteF;
      } catch (e) {
        // #17: a failed letter must not throw away the tailored CV and prep the user already paid for.
        _log_('${o.kind == MissionMode.freelance ? 'Proposal' : 'Cover letter'} failed (${e is LlmException ? e.message : e}). Your CV is saved; tap Generate in the Vault to retry.', 'ERROR');
      }
      PrepDossier prep;
      try {
        prep = await prepF;
      } catch (e) {
        prep = PrepDossier();
        _log_('Prep dossier failed ($e) — you can regenerate it from the Vault.', 'ERROR');
      }

      final artifact = TailoredArtifact(
        opportunity: o,
        analysis: a,
        decisions: decisions,
        cv: cv,
        atsBefore: before,
        atsAfter: after,
        applicationNote: note,
        prep: prep,
        engineLabel: engine.llm.label,
        costUsd: engine.spentUsd,
      );
      await ref.read(artifactsProvider.notifier).upsert(artifact);
      await ref.read(missionProvider.notifier).setStatus(o.id, 'TAILORED');
      _log_('Done${engine.spentUsd > 0 ? ' · cost ${money.format(engine.spentUsd)}' : ''}. Review before you send.', 'DONE');
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) context.pushReplacement('/artifact/${artifact.id}');
      }
    } catch (e) {
      _log_(e is LlmException ? e.message : 'Failed: $e', 'ERROR');
      if (mounted) {
        setState(() => _step = 1);
        handleAiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(missionProvider).opportunities.where((x) => x.id == widget.opportunityId).firstOrNull;
    if (o == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Opportunity not found', body: 'It may have been cleared from your pipeline.'));
    final settings = ref.watch(aiSettingsProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(o.kind == MissionMode.freelance ? 'Tailor for this gig' : 'Tailor for this job'), actions: const [EnginePill()]),
      body: switch (_step) {
        0 => _overview(o, settings),
        1 => _checkIn(),
        _ => _running(),
      },
    );
  }

  Widget _overview(Opportunity o, AiSettings? s) {
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Text(o.title, style: t.headlineSmall),
      const SizedBox(height: 4),
      Text([o.company, o.location, o.salary].where((e) => e.isNotEmpty).join(' · '), style: t.bodyMedium?.copyWith(color: pal.muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        Pill('via ${o.source}', color: pal.muted),
        Pill('${o.matchScore.round()}% quick match'),
        if (o.url.isNotEmpty) ActionChip(avatar: const Icon(Icons.open_in_new, size: 16), label: Text('Open on ${o.source}'), onPressed: () => openUrl(o.url)),
      ]),
      if (!o.descriptionComplete) ...[
        const SizedBox(height: 14),
        ApexCard(
          color: AppColors.amber.withValues(alpha: 0.1),
          borderColor: AppColors.amber.withValues(alpha: 0.5),
          child: const Text('This source only shares a snippet. Open the listing and paste the full description below for an accurate tailor.'),
        ),
      ],
      const SectionLabel('Description'),
      TextField(controller: _jd, maxLines: 14, minLines: 6, style: t.bodySmall),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _busy ? null : _analyze,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.manage_search),
        label: Text(_busy ? 'Reading the requirements…' : 'Analyze requirements'),
      ),
      const SizedBox(height: 8),
      Text('Uses ${s?.activeLabel ?? 'your AI engine'}. A full tailored application is usually about 4 AI steps.', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: pal.muted)),
    ]);
  }

  Widget _checkIn() {
    final a = _analysis!;
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    final profile = ref.watch(profileProvider).value!;
    final matched = a.requirements.where((r) => _checkIns[r.skill]?.decision == SkillDecision.matched).toList();
    final open = a.requirements.where((r) => _checkIns[r.skill]?.decision != SkillDecision.matched).toList();
    final cs = Theme.of(context).colorScheme;
    int count(SkillDecision d) => _checkIns.values.where((c) => c.decision == d).length;
    final missing = _checkIns.values.where(_needsLine).length;
    // A plain Column (not a lazy list) so every card exists and "scroll to the first missing line" works.
    return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Skill check-in', style: t.headlineSmall),
      const SizedBox(height: 6),
      Text(a.summary, style: t.bodyMedium?.copyWith(color: pal.muted)),
      SectionLabel('Backed by your CV (${matched.length})'),
      if (matched.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text("Not really yours? Tap × and it's treated as a gap: kept off your CV, added to your prep plan.", style: t.bodySmall?.copyWith(color: pal.muted)),
        ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in matched)
          InputChip(
            avatar: const Icon(Icons.check, size: 16, color: AppColors.emerald),
            label: Text(r.skill),
            deleteButtonTooltipMessage: "I don't have this",
            onDeleted: () => setState(() => _checkIns[r.skill]!.decision = SkillDecision.gap),
          ),
      ]),
      SectionLabel('Not found in your CV (${open.length})'),
      if (open.isEmpty) const Text('Nothing missing — great fit.'),
      if (open.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('Tell us honestly. Skills you have get added with your own words. Everything else stays off the CV and goes into your prep plan.', style: t.bodySmall?.copyWith(color: pal.muted)),
        ),
      if (open.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: OutlinedButton.icon(
            onPressed: _suggesting || _busy ? null : _fillFromCv,
            icon: _suggesting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
            label: Text(_suggesting ? 'Reading your CV…' : 'Fill from my CV'),
          ),
        ),
      for (final r in open)
        Padding(
          key: _cardKeys.putIfAbsent(r.skill, GlobalKey.new),
          padding: const EdgeInsets.only(bottom: 10),
          child: ApexCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.skill, style: t.titleMedium)),
                Pill(r.importance == Importance.must ? 'Must-have' : 'Nice-to-have', color: r.importance == Importance.must ? AppColors.amber : pal.muted),
              ]),
              if (r.evidence.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${r.evidence}”', style: t.bodySmall?.copyWith(color: pal.muted, fontStyle: FontStyle.italic))),
              const SizedBox(height: 10),
              SegmentedButton<SkillDecision>(
                style: SegmentedButton.styleFrom(selectedBackgroundColor: cs.primary, selectedForegroundColor: cs.onPrimary),
                segments: const [
                  ButtonSegment(value: SkillDecision.haveIt, label: Text('I have it')),
                  ButtonSegment(value: SkillDecision.learning, label: Text('Learning')),
                  ButtonSegment(value: SkillDecision.gap, label: Text("Don't have")),
                ],
                selected: {_checkIns[r.skill]!.decision == SkillDecision.matched ? SkillDecision.haveIt : _checkIns[r.skill]!.decision},
                onSelectionChanged: (v) => setState(() => _checkIns[r.skill]!.decision = v.first),
              ),
              if (_checkIns[r.skill]!.decision == SkillDecision.haveIt) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _checkIns[r.skill]!.context,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Where and how did you use ${r.skill}? Your words, real details.',
                    helperText: _suggested[r.skill] != null ? null : 'One real line. It becomes your CV line for this skill.',
                    helperMaxLines: 2,
                    errorText: _showErrors && _needsLine(_checkIns[r.skill]!) ? "Add one line, or choose Learning or Don't have" : null,
                  ),
                ),
                if (_suggested[r.skill] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.auto_awesome, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Drafted from your CV: “${_suggested[r.skill]!.quote}”. Edit it if needed.', style: t.bodySmall?.copyWith(color: pal.muted))),
                    ]),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _checkIns[r.skill]!.roleId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'In which role? (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Side project / course / other')),
                    for (final role in profile.roles) DropdownMenuItem(value: role.id, child: Text(role.label, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => _checkIns[r.skill]!.roleId = v,
                ),
              ],
            ]),
          ),
        ),
      const SizedBox(height: 12),
      Text(
        '${matched.length} backed by your CV · ${count(SkillDecision.haveIt)} I have it · ${count(SkillDecision.learning)} learning · ${count(SkillDecision.gap)} don\'t have',
        textAlign: TextAlign.center,
        style: t.bodySmall?.copyWith(color: pal.muted),
      ),
      if (missing > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$missing marked "I have it" still ${missing == 1 ? 'needs' : 'need'} a line', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: AppColors.amber)),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: _busy ? null : _run, icon: const Icon(Icons.auto_fix_high), label: const Text('Tailor my CV & build prep')),
      TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Back to description')),
    ]));
  }

  Widget _running() => ListView(padding: const EdgeInsets.all(16), children: [
        Text('Agent at work', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        TelemetryTerminal(events: _log, startedAt: _startedAt, running: _busy, maxLines: 14),
      ]);
}
