import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';

/// Tab 4 — Prep Dojo: one study deck per application.
class DojoScreen extends ConsumerWidget {
  const DojoScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = (ref.watch(artifactsProvider).value ?? []).where((a) => a.prepCardCount > 0).toList();
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Prep Dojo'), actions: const [EnginePill()]),
      body: decks.isEmpty
          ? const EmptyState(icon: Icons.school_outlined, title: 'No prep decks yet', body: 'Every tailored application comes with STAR stories, likely questions and a plan for each skill gap. They show up here.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: decks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = decks[i];
                final progress = a.prepCardCount == 0 ? 0.0 : a.masteredCount / a.prepCardCount;
                return ApexCard(
                  onTap: () => context.push('/prep/${a.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.opportunity.title, style: t.titleMedium),
                    Text(a.opportunity.company.isEmpty ? a.opportunity.source : a.opportunity.company, style: t.bodySmall?.copyWith(color: pal.muted)),
                    const SizedBox(height: 10),
                    ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress, minHeight: 6, color: AppColors.emerald, backgroundColor: pal.line)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      Pill('${a.masteredCount}/${a.prepCardCount} mastered', color: AppColors.emerald),
                      if (a.prep.gaps.isNotEmpty) Pill('${a.prep.gaps.length} ${a.prep.gaps.length == 1 ? 'skill' : 'skills'} to learn', color: AppColors.amber, icon: Icons.school_outlined),
                    ]),
                  ]),
                );
              },
            ),
    );
  }
}

class PrepDeckScreen extends ConsumerStatefulWidget {
  const PrepDeckScreen({super.key, required this.artifactId});
  final String artifactId;
  @override
  ConsumerState<PrepDeckScreen> createState() => _PrepDeckScreenState();
}

class _PrepDeckScreenState extends ConsumerState<PrepDeckScreen> {
  final _tts = FlutterTts();
  String? _speaking;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String key, String text) async {
    if (kIsWeb) return;
    if (_speaking == key) {
      await _tts.stop();
      setState(() => _speaking = null);
      return;
    }
    setState(() => _speaking = key);
    _tts.setCompletionHandler(() => mounted ? setState(() => _speaking = null) : null);
    await _tts.setSpeechRate(0.48);
    await _tts.speak(text);
  }

  Future<void> _setMastery(TailoredArtifact a, String key, int v) async {
    a.mastery[key] = v;
    await ref.read(artifactsProvider.notifier).upsert(a);
    setState(() {});
  }

  Widget _masteryButton(TailoredArtifact a, String key) {
    final done = (a.mastery[key] ?? 0) >= 2;
    return TextButton.icon(
      onPressed: () => _setMastery(a, key, done ? 1 : 2),
      icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? AppColors.emerald : null, size: 20),
      label: Text(done ? 'Mastered' : 'Mark mastered'),
    );
  }

  Widget _listen(String key, String text) => IconButton(
        tooltip: 'Listen',
        icon: Icon(_speaking == key ? Icons.stop_circle_outlined : Icons.volume_up_outlined),
        onPressed: () => _speak(key, text),
      );

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(artifactsProvider).value?.where((x) => x.id == widget.artifactId).firstOrNull;
    if (a == null) return Scaffold(appBar: AppBar(), body: const SizedBox());
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    final p = a.prep;
    return Scaffold(
      appBar: AppBar(
        title: Text('Prep · ${a.opportunity.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [ReportAiButton(kind: 'prep', excerpt: p.pitch)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        if (p.pitch.isNotEmpty) ...[
          const SectionLabel('⏱ Your 60-second pitch'),
          ApexCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.pitch, style: t.bodyMedium),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [_listen('pitch', p.pitch), _masteryButton(a, 'pitch')]),
            ]),
          ),
        ],
        if (p.stories.isNotEmpty) const SectionLabel('🗣 STAR stories from your real work'),
        for (final (i, s) in p.stories.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ApexCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                title: Text(s.title, style: t.titleSmall),
                subtitle: Text('Proves: ${s.requirement} · ${s.source}', style: t.bodySmall?.copyWith(color: pal.muted)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (label, body) in [('Situation', s.situation), ('Task', s.task), ('Action', s.action), ('Result', s.result)]) ...[
                    Text(label.toUpperCase(), style: t.labelSmall?.copyWith(color: AppColors.emerald)),
                    Padding(padding: const EdgeInsets.only(top: 2, bottom: 10), child: Text(body, style: t.bodyMedium)),
                  ],
                  Text('Fill any [placeholders] with your real details before the interview.', style: t.bodySmall?.copyWith(color: pal.muted)),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [_listen('s$i', s.spoken), _masteryButton(a, 's$i')]),
                ],
              ),
            ),
          ),
        if (p.questions.isNotEmpty) const SectionLabel('🎯 Questions they\'ll likely ask'),
        for (final (i, q) in p.questions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FlipCard(
              front: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.question, style: t.titleSmall),
                const SizedBox(height: 6),
                Text('Why they ask: ${q.whyAsked}', style: t.bodySmall?.copyWith(color: pal.muted)),
                const SizedBox(height: 8),
                Text('Tap to see your answer outline', style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ]),
              back: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.answer, style: t.bodyMedium),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [_masteryButton(a, 'q$i')]),
              ]),
            ),
          ),
        if (p.gaps.isNotEmpty) const SectionLabel('🧠 Skill gaps — learn it, don\'t fake it'),
        for (final (i, g) in p.gaps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ApexCard(
              borderColor: AppColors.amber.withValues(alpha: 0.5),
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                leading: const Icon(Icons.school_outlined, color: AppColors.amber),
                title: Text(g.skill, style: t.titleSmall),
                subtitle: Text('Mental model · honest answer · 48h plan', style: t.bodySmall?.copyWith(color: pal.muted)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(t, '60-second mental model', g.mentalModel),
                  _block(t, 'If they ask “Have you used ${g.skill}?”', g.honestAnswer),
                  _block(t, 'Your closest real experience', g.bridge),
                  if (g.learnSteps.isNotEmpty) ...[
                    Text('LEARN THE BASICS IN 48 HOURS', style: t.labelSmall?.copyWith(color: AppColors.emerald)),
                    const SizedBox(height: 4),
                    for (final (n, step) in g.learnSteps.indexed) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${n + 1}. $step', style: t.bodyMedium)),
                    const SizedBox(height: 8),
                  ],
                  _block(t, 'Build this to get real hands-on experience', g.practiceTask),
                  if (g.vocabulary.isNotEmpty) ...[
                    Text('TERMS TO UNDERSTAND', style: t.labelSmall?.copyWith(color: AppColors.emerald)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final v in g.vocabulary) Pill(v)]),
                  ],
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [_listen('g$i', '${g.mentalModel} ${g.honestAnswer}'), _masteryButton(a, 'g$i')]),
                ],
              ),
            ),
          ),
        if (p.questionsToAsk.isNotEmpty) ...[
          const SectionLabel('❓ Questions to ask them'),
          for (final q in p.questionsToAsk) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $q', style: t.bodyMedium)),
        ],
      ]),
    );
  }

  Widget _block(TextTheme t, String label, String body) => body.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: t.labelSmall?.copyWith(color: AppColors.emerald)),
            const SizedBox(height: 2),
            Text(body, style: t.bodyMedium),
          ]),
        );
}

class _FlipCard extends StatefulWidget {
  const _FlipCard({required this.front, required this.back});
  final Widget front, back;
  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  bool _showBack = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          _showBack ? _c.reverse() : _c.forward();
          _showBack = !_showBack;
        },
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final angle = _c.value * math.pi;
            final back = angle > math.pi / 2;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(angle),
              child: back
                  ? Transform(alignment: Alignment.center, transform: Matrix4.identity()..rotateX(math.pi), child: ApexCard(borderColor: AppColors.emerald.withValues(alpha: 0.5), child: widget.back))
                  : ApexCard(child: widget.front),
            );
          },
        ),
      );
}
