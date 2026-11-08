import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/text_match.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import '../tailor/tailor_engine.dart';
import 'cv_documents.dart';

class ArtifactScreen extends ConsumerStatefulWidget {
  const ArtifactScreen({super.key, required this.artifactId});
  final String artifactId;
  @override
  ConsumerState<ArtifactScreen> createState() => _ArtifactScreenState();
}

class _ArtifactScreenState extends ConsumerState<ArtifactScreen> {
  int _version = 0;
  Future<Uint8List>? _pdf;
  bool _regenBusy = false;

  TailoredArtifact? get _a => ref.watch(artifactsProvider).value?.where((x) => x.id == widget.artifactId).firstOrNull;

  Future<void> _save(TailoredArtifact a) async {
    await ref.read(artifactsProvider.notifier).upsert(a);
    setState(() {
      _version++;
      _pdf = null;
    });
  }

  void _recomputeAts(TailoredArtifact a) {
    final p = ref.read(profileProvider).value;
    if (p == null) return;
    a.atsAfter = TextMatch.atsScore(TailorEngine.tailoredCvText(p, a.cv), a.analysis.requirements, keywords: a.analysis.keywords, skills: a.cv.skills);
  }

  Future<Uint8List> _buildPdf(TailoredArtifact a) {
    final p = ref.read(profileProvider).value!;
    return CvPdfBuilder.build(CvDocument(profile: p, cv: a.cv));
  }

  bool _gate(TailoredArtifact a) {
    if (a.reviewed) return true;
    showSnack(context, 'Tick “I have reviewed this draft” first.', error: true);
    return false;
  }

  Future<void> _share(TailoredArtifact a, {required bool docx}) async {
    if (!_gate(a)) return;
    final p = ref.read(profileProvider).value!;
    final doc = CvDocument(profile: p, cv: a.cv);
    final bytes = docx ? CvDocxBuilder.build(doc) : await CvPdfBuilder.build(doc);
    final name = '${doc.fileStem(a.opportunity)}.${docx ? 'docx' : 'pdf'}';
    final mime = docx ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/pdf';
    XFile file;
    if (kIsWeb) {
      file = XFile.fromData(bytes, name: name, mimeType: mime);
    } else {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      file = XFile(f.path, mimeType: mime, name: name);
    }
    await SharePlus.instance.share(ShareParams(files: [file], subject: '${p.contact.name} — ${a.opportunity.title}', fileNameOverrides: [name]));
  }

  Future<void> _editBullet(TailoredArtifact a, TailoredBullet b) async {
    final c = TextEditingController(text: b.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit bullet'),
        content: TextField(controller: c, maxLines: 6, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
      ),
    );
    if (ok == true) {
      b.text = c.text.trim();
      b.flags = [];
      b.enabled = b.text.isNotEmpty;
      a.reviewed = false;
      _recomputeAts(a);
      await _save(a);
    }
  }

  Future<void> _regeneratePrep(TailoredArtifact a) async {
    setState(() => _regenBusy = true);
    try {
      final engine = TailorEngine(await ref.read(aiServiceProvider).client());
      final p = ref.read(profileProvider).value!;
      a.prep = await engine.prep(profile: p, opportunity: a.opportunity, analysis: a.analysis, cv: a.cv, decisions: a.decisions);
      if (a.applicationNote.isEmpty) {
        a.applicationNote = await engine.applicationNote(profile: p, opportunity: a.opportunity, analysis: a.analysis, cv: a.cv, decisions: a.decisions);
      }
      a.costUsd += engine.spentUsd;
      await _save(a);
      if (mounted) showSnack(context, 'Prep dossier ready');
    } catch (e) {
      if (mounted) handleAiError(context, e);
    } finally {
      if (mounted) setState(() => _regenBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Not found', body: 'This application was deleted.'));
    final noteLabel = a.isFreelance ? 'Proposal' : 'Cover letter';
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(a.opportunity.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            ReportAiButton(kind: 'cv', excerpt: '${a.cv.summary}\n${a.cv.roles.expand((r) => r.bullets).map((b) => b.text).join('\n')}'),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete') {
                  await ref.read(artifactsProvider.notifier).remove(a.id);
                  if (context.mounted) context.pop();
                } else if (v == 'open' && a.opportunity.url.isNotEmpty) {
                  openUrl(a.opportunity.url);
                }
              },
              itemBuilder: (_) => [
                if (a.opportunity.url.isNotEmpty) PopupMenuItem(value: 'open', child: Text('Open on ${a.opportunity.source}')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [const Tab(text: 'Changes'), const Tab(text: 'Requirements'), const Tab(text: 'Document'), Tab(text: noteLabel)]),
        ),
        body: TabBarView(children: [_changes(a), _requirements(a), _document(a), _note(a, noteLabel)]),
      ),
    );
  }

  Widget _prepBanner(TailoredArtifact a) {
    final t = Theme.of(context).textTheme;
    if (a.prepCardCount == 0) {
      return ApexCard(
        color: AppColors.amber.withValues(alpha: 0.1),
        borderColor: AppColors.amber.withValues(alpha: 0.5),
        child: Row(children: [
          const Icon(Icons.school_outlined, color: AppColors.amber),
          const SizedBox(width: 12),
          const Expanded(child: Text('Interview prep isn\'t generated yet.')),
          TextButton(onPressed: _regenBusy ? null : () => _regeneratePrep(a), child: Text(_regenBusy ? 'Working…' : 'Generate')),
        ]),
      );
    }
    final gaps = a.prep.gaps.length;
    return ApexCard(
      onTap: () => context.push('/prep/${a.id}'),
      color: AppColors.amber.withValues(alpha: 0.1),
      borderColor: AppColors.amber.withValues(alpha: 0.5),
      child: Row(children: [
        const Icon(Icons.school, color: AppColors.amber),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${a.prep.stories.length} STAR stories, ${a.prep.questions.length} likely questions${gaps > 0 ? ' and $gaps gap plans' : ''}. Tap for your 10-minute prep.',
            style: t.bodyMedium,
          ),
        ),
        const Icon(Icons.chevron_right),
      ]),
    );
  }

  Widget _changes(TailoredArtifact a) {
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    final profile = ref.watch(profileProvider).value;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      AtsBoost(before: a.atsBefore, after: a.atsAfter),
      const SizedBox(height: 12),
      _prepBanner(a),
      const SectionLabel('Headline & summary'),
      ApexCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a.cv.headline, style: t.titleMedium),
        const SizedBox(height: 6),
        Text(a.cv.summary, style: t.bodyMedium),
      ])),
      const SectionLabel('Skills order'),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in a.cv.skills) Pill(s)]),
      if (a.cv.skillFlags.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Truth Guard removed: ${a.cv.skillFlags.join(', ')} (not in your profile)', style: t.bodySmall?.copyWith(color: AppColors.rose)),
      ],
      if (a.cv.metricPrompts.isNotEmpty) ...[
        const SectionLabel('Make it stronger with real numbers'),
        for (final m in a.cv.metricPrompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ApexCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.tips_and_updates_outlined, color: AppColors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('${m['question'] ?? ''}', style: t.bodySmall)),
              ]),
            ),
          ),
        Text('Edit the bullet below with the real figure — ApexHunt never makes numbers up.', style: t.bodySmall?.copyWith(color: pal.muted)),
      ],
      for (final tr in a.cv.roles) ...[
        SectionLabel(profile?.roles.where((r) => r.id == tr.roleId).map((r) => '${r.title} @ ${r.company}').firstOrNull ?? 'Role'),
        for (final b in tr.bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ApexCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              borderColor: b.flags.isNotEmpty ? AppColors.rose.withValues(alpha: 0.6) : (b.change == BulletChange.unchanged ? null : AppColors.emerald.withValues(alpha: 0.5)),
              onTap: () => _editBullet(a, b),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.text, style: t.bodyMedium?.copyWith(color: b.enabled ? null : pal.muted, decoration: b.enabled ? null : TextDecoration.lineThrough)),
                    if (b.change != BulletChange.unchanged && b.original.isNotEmpty && b.original != b.text)
                      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Was: ${b.original}', style: t.bodySmall?.copyWith(color: pal.muted, decoration: TextDecoration.lineThrough))),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      Pill(switch (b.change) {
                        BulletChange.unchanged => 'Original',
                        BulletChange.fromUserContext => 'From your check-in',
                        BulletChange.reordered => 'Reordered',
                        BulletChange.rephrased => 'Reworded',
                      }, color: b.change == BulletChange.unchanged ? pal.muted : AppColors.emerald),
                      for (final k in b.keywords.take(3)) Pill('+ $k', color: AppColors.emerald),
                      for (final f in b.flags) Pill(f, color: AppColors.rose, icon: Icons.shield_outlined),
                    ]),
                  ]),
                ),
                Switch(
                  value: b.enabled,
                  onChanged: (v) async {
                    b.enabled = v;
                    a.reviewed = false;
                    _recomputeAts(a);
                    await _save(a);
                  },
                ),
              ]),
            ),
          ),
      ],
    ]);
  }

  Widget _requirements(TailoredArtifact a) {
    final profile = ref.watch(profileProvider).value;
    final text = profile == null ? '' : TextMatch.normalize(TailorEngine.tailoredCvText(profile, a.cv));
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    bool covered(Requirement r) => TextMatch.covers(text, r.skill, skills: a.cv.skills);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Text(a.analysis.summary, style: t.bodyMedium?.copyWith(color: pal.muted)),
      const SizedBox(height: 8),
      for (final r in a.analysis.requirements)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            covered(r) ? Icons.check_circle : (a.decisions[r.skill] == SkillDecision.learning ? Icons.school_outlined : Icons.radio_button_unchecked),
            color: covered(r) ? AppColors.emerald : (a.decisions[r.skill] == SkillDecision.learning ? AppColors.amber : pal.muted),
          ),
          title: Text(r.skill),
          subtitle: Text(
            covered(r)
                ? 'Covered on your CV'
                : a.decisions[r.skill] == SkillDecision.learning
                    ? 'Learning — listed honestly, prep plan ready'
                    : 'Gap — kept off your CV, prep plan ready',
            style: t.bodySmall?.copyWith(color: pal.muted),
          ),
          trailing: Pill(r.importance == Importance.must ? 'Must' : 'Nice', color: r.importance == Importance.must ? AppColors.amber : pal.muted),
        ),
      if (a.analysis.notes.isNotEmpty) ...[
        const SectionLabel('Worth knowing'),
        for (final n in a.analysis.notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $n', style: t.bodyMedium)),
      ],
    ]);
  }

  Widget _document(TailoredArtifact a) {
    _pdf ??= _buildPdf(a);
    final pal = ApexPalette.of(context);
    return Column(children: [
      Expanded(
        child: FutureBuilder<Uint8List>(
          key: ValueKey(_version),
          future: _pdf,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Could not render: ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            if (kIsWeb) return const Center(child: Text('PDF preview is available in the Android app.'));
            return Container(color: pal.raised, child: PdfViewer.data(snap.data!, sourceName: 'cv-${a.id}-$_version.pdf'));
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CheckboxListTile(
              value: a.reviewed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I have reviewed this AI-tailored draft and everything in it is true.'),
              onChanged: (v) async {
                a.reviewed = v ?? false;
                await ref.read(artifactsProvider.notifier).upsert(a);
                setState(() {});
              },
            ),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: () => _share(a, docx: false), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Share PDF'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: () => _share(a, docx: true), icon: const Icon(Icons.description_outlined), label: const Text('DOCX'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              if (a.opportunity.url.isNotEmpty)
                Expanded(child: TextButton.icon(onPressed: () => _gate(a) ? openUrl(a.opportunity.url) : null, icon: const Icon(Icons.open_in_new), label: const Text('Apply on site'))),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    a.applied = !a.applied;
                    await ref.read(artifactsProvider.notifier).upsert(a);
                    setState(() {});
                  },
                  icon: Icon(a.applied ? Icons.check_circle : Icons.send_outlined),
                  label: Text(a.applied ? 'Applied' : 'Mark applied'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _note(TailoredArtifact a, String label) {
    final t = Theme.of(context).textTheme;
    if (a.applicationNote.isEmpty) {
      return EmptyState(
        icon: Icons.edit_note,
        title: 'No $label yet',
        body: 'Generate it together with your prep dossier.',
        action: FilledButton(onPressed: _regenBusy ? null : () => _regeneratePrep(a), child: Text(_regenBusy ? 'Working…' : 'Generate')),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Row(children: [
        Expanded(child: Text(label, style: t.titleLarge)),
        ReportAiButton(kind: a.isFreelance ? 'proposal' : 'cover_letter', excerpt: a.applicationNote),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy),
          onPressed: () {
            if (!_gate(a)) return;
            Clipboard.setData(ClipboardData(text: a.applicationNote));
            showSnack(context, 'Copied');
          },
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: () {
            if (_gate(a)) SharePlus.instance.share(ShareParams(text: a.applicationNote, subject: a.opportunity.title));
          },
        ),
      ]),
      const SizedBox(height: 8),
      ApexCard(child: SelectableText(a.applicationNote.replaceAll('**', ''), style: t.bodyMedium)),
      const SizedBox(height: 8),
      Text('Review and personalise before sending. Use the Document tab to confirm your review.', style: t.bodySmall?.copyWith(color: ApexPalette.of(context).muted)),
    ]);
  }
}
