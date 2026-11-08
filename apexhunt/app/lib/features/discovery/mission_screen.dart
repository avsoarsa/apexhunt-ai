import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import 'job_sources.dart';
import 'mission_controller.dart';

/// Tab 1 — Mission Control.
class MissionScreen extends ConsumerStatefulWidget {
  const MissionScreen({super.key});
  @override
  ConsumerState<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends ConsumerState<MissionScreen> {
  final _kw = TextEditingController();

  MissionController get _ctrl => ref.read(missionProvider.notifier);

  void _update(void Function(MissionConfig c) fn) {
    final c = MissionConfig.fromJson(ref.read(missionProvider).config.toJson());
    fn(c);
    _ctrl.updateConfig(c);
  }

  void _toggle(List<String> list, String v) {
    if (!list.remove(v)) list.add(v);
  }

  Future<void> _addCountry() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scroll) => ListView(controller: scroll, children: [
          for (final e in countryNames.entries) ListTile(leading: Text(countryFlags[e.key] ?? '', style: const TextStyle(fontSize: 22)), title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (picked != null) {
      _update((c) {
        if (!c.countries.contains(picked)) c.countries.add(picked);
      });
    }
  }

  Future<void> _pasteJd() async {
    final title = TextEditingController(), company = TextEditingController(), body = TextEditingController(), url = TextEditingController();
    final mode = ref.read(missionProvider).config.mode;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(mode == MissionMode.freelance ? 'Paste a client brief' : 'Paste a job description', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Role / project title')),
            const SizedBox(height: 10),
            TextField(controller: company, decoration: const InputDecoration(labelText: 'Company / client (optional)')),
            const SizedBox(height: 10),
            TextField(controller: url, decoration: const InputDecoration(labelText: 'Link to posting (optional)')),
            const SizedBox(height: 10),
            TextField(controller: body, maxLines: 8, decoration: const InputDecoration(hintText: 'Paste the full description…')),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tailor for this')),
          ]),
        ),
      ),
    );
    if (ok != true || body.text.trim().length < 60) {
      if (ok == true && mounted) showSnack(context, 'Paste the full description (at least a few sentences).', error: true);
      return;
    }
    final o = await _ctrl.addManual(title: title.text.trim(), company: company.text.trim(), description: body.text.trim(), url: url.text.trim(), kind: mode);
    if (mounted) context.push('/tailor/${Uri.encodeComponent(o.id)}');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(missionProvider);
    final cfg = state.config;
    final profile = ref.watch(profileProvider).value;
    final artifacts = ref.watch(artifactsProvider).value ?? [];
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    final freelance = cfg.mode == MissionMode.freelance;
    final avgAts = artifacts.isEmpty ? 0.0 : artifacts.map((a) => a.atsAfter).reduce((a, b) => a + b) / artifacts.length;

    final commitments = freelance
        ? const [('HOURLY', 'Hourly'), ('FIXED_PRICE', 'Fixed-price'), ('CONTRACT', 'Contract')]
        : const [('FULL_TIME', 'Full-time'), ('PART_TIME', 'Part-time'), ('CONTRACT', 'Contract'), ('INTERNSHIP', 'Internship')];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: InkWell(
          onTap: () => context.push('/profile'),
          borderRadius: BorderRadius.circular(20),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 16, backgroundColor: Theme.of(context).colorScheme.primary, child: Text((profile?.contact.name.isNotEmpty ?? false) ? profile!.contact.name[0].toUpperCase() : 'A', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Command', style: t.titleLarge),
              Text('Base CV synced ✓', style: t.bodySmall?.copyWith(color: AppColors.emerald)),
            ]),
          ]),
        ),
        actions: const [EnginePill()],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        SegmentedButton<MissionMode>(
          segments: const [
            ButtonSegment(value: MissionMode.job, label: Text('Salaried jobs'), icon: Icon(Icons.work_outline)),
            ButtonSegment(value: MissionMode.freelance, label: Text('Freelance gigs'), icon: Icon(Icons.rocket_launch_outlined)),
          ],
          selected: {cfg.mode},
          onSelectionChanged: (v) => _update((c) {
            c.mode = v.first;
            c.commitments = v.first == MissionMode.freelance ? ['HOURLY', 'FIXED_PRICE'] : ['FULL_TIME'];
          }),
        ),
        if (!freelance) ...[
          const SectionLabel('Target countries'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in {...['REMOTE', 'US', 'GB', 'AE', 'DE', 'IN', 'CA', 'AU'], ...cfg.countries})
              FilterChip(
                label: Text('${countryFlags[c] ?? ''} ${c == 'REMOTE' ? 'Remote' : (countryNames[c] ?? c)}'),
                selected: cfg.countries.contains(c),
                onSelected: (_) => _update((x) => _toggle(x.countries, c)),
              ),
            ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Add country'), onPressed: _addCountry),
          ]),
        ],
        SectionLabel(freelance ? 'Contract type' : 'Work type'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (id, label) in commitments) FilterChip(label: Text(label), selected: cfg.commitments.contains(id), onSelected: (_) => _update((x) => _toggle(x.commitments, id))),
          if (!freelance)
            for (final (id, label) in const [('REMOTE', 'Remote only'), ('VISA', 'Visa sponsorship')])
              FilterChip(label: Text(label), selected: cfg.arrangements.contains(id), onSelected: (_) => _update((x) => _toggle(x.arrangements, id))),
        ]),
        SectionLabel('Target roles / keywords', trailing: TextButton.icon(onPressed: _pasteJd, icon: const Icon(Icons.content_paste, size: 16), label: Text(freelance ? 'Paste a brief' : 'Paste a JD'))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in cfg.keywords) InputChip(label: Text(k), onDeleted: () => _update((x) => x.keywords.remove(k))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _kw,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Add a role, e.g. Flutter Developer', prefixIcon: Icon(Icons.search)),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) _update((x) => x.keywords.add(v.trim()));
            _kw.clear();
          },
        ),
        if (!freelance)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Watch company career boards (${cfg.watchedCompanies.length})', style: t.titleSmall),
              subtitle: Text('Greenhouse or Lever slugs, e.g. greenhouse:stripe, lever:netflix', style: t.bodySmall?.copyWith(color: pal.muted)),
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final w in cfg.watchedCompanies) InputChip(label: Text(w), onDeleted: () => _update((x) => x.watchedCompanies.remove(w))),
                ]),
                TextField(
                  decoration: const InputDecoration(hintText: 'greenhouse:company or lever:company'),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _update((x) => x.watchedCompanies.add(v.trim().toLowerCase()));
                  },
                ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: state.running ? null : _ctrl.launch,
          icon: state.running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.rocket_launch),
          label: Text(state.running ? 'Agent mission running…' : 'Deploy agent mission'),
        ),
        const SizedBox(height: 16),
        TelemetryTerminal(events: state.log, startedAt: state.startedAt, running: state.running),
        if (!state.running && state.log.isNotEmpty && state.log.last.kind == 'DONE')
          Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(onPressed: () => context.go('/pipeline'), child: const Text('Open Pipeline'))),
        const SectionLabel('Your numbers'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            _Metric(value: '${state.scanned}', label: 'Listings scanned'),
            _Metric(value: '${artifacts.length}', label: 'Tailored CVs'),
            _Metric(value: artifacts.isEmpty ? '—' : '${avgAts.round()}%', label: 'Avg ATS match'),
            _Metric(value: '${artifacts.where((a) => a.applied).length}', label: 'Applications sent'),
          ],
        ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => ApexCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ApexPalette.of(context).muted)),
        ]),
      );
}
