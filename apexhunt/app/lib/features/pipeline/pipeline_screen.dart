import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import '../discovery/mission_controller.dart';

/// Tab 2 — discovered opportunities ranked by match.
class PipelineScreen extends ConsumerStatefulWidget {
  const PipelineScreen({super.key});
  @override
  ConsumerState<PipelineScreen> createState() => _PipelineScreenState();
}

class _PipelineScreenState extends ConsumerState<PipelineScreen> {
  String _filter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(missionProvider);
    final artifacts = ref.watch(artifactsProvider).value ?? [];
    final byOpp = {for (final a in artifacts) a.opportunity.id: a};
    var list = [...state.opportunities];
    list = switch (_filter) {
      'NEW' => list.where((o) => !byOpp.containsKey(o.id)).toList(),
      'TAILORED' => list.where((o) => byOpp.containsKey(o.id)).toList(),
      'FREELANCE' => list.where((o) => o.kind == MissionMode.freelance).toList(),
      _ => list,
    };
    list.sort((a, b) => b.matchScore.compareTo(a.matchScore));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipeline'),
        actions: [
          if (state.opportunities.isNotEmpty)
            IconButton(
              tooltip: 'Clear untailored',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Clear untailored matches?'),
                    content: const Text('Tailored applications stay in your Vault.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Clear'))],
                  ),
                );
                if (ok == true) ref.read(missionProvider.notifier).clearPipeline();
              },
            ),
          const EnginePill(),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (final (id, label) in const [('ALL', 'All'), ('NEW', 'Not tailored'), ('TAILORED', 'Tailored'), ('FREELANCE', 'Freelance')])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id))),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.radar,
                  title: 'No opportunities yet',
                  body: 'Deploy a mission from Command, or paste a job description to tailor for a specific role.',
                  action: FilledButton(onPressed: () => context.go('/dashboard'), child: const Text('Go to Command')),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    final a = byOpp[o.id];
                    return Dismissible(
                      key: ValueKey(o.id),
                      direction: a == null ? DismissDirection.endToStart : DismissDirection.none,
                      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_outline)),
                      onDismissed: (_) => ref.read(missionProvider.notifier).dismiss(o.id),
                      child: OpportunityCard(opportunity: o, artifact: a),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class OpportunityCard extends StatelessWidget {
  const OpportunityCard({super.key, required this.opportunity, this.artifact});
  final Opportunity opportunity;
  final TailoredArtifact? artifact;

  @override
  Widget build(BuildContext context) {
    final o = opportunity;
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return ApexCard(
      onTap: () => artifact != null ? context.push('/artifact/${artifact!.id}') : context.push('/tailor/${Uri.encodeComponent(o.id)}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([o.company, o.location].where((e) => e.isNotEmpty).join(' · '), style: t.bodySmall?.copyWith(color: pal.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 10),
          ScoreGauge(value: artifact?.atsAfter ?? o.matchScore, size: 50, label: artifact != null ? 'ATS' : 'match'),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill('via ${o.source}', color: pal.muted),
          if (o.kind == MissionMode.freelance) const Pill('Freelance', color: AppColors.amber, icon: Icons.rocket_launch_outlined),
          if (o.remote) const Pill('Remote', icon: Icons.public),
          if (o.salary.isNotEmpty) Pill(o.salary, color: AppColors.emerald),
          if (artifact != null) Pill('Tailored · ${artifact!.atsBefore.round()}→${artifact!.atsAfter.round()}%', color: AppColors.emerald, icon: Icons.check),
          if (!o.descriptionComplete) const Pill('Snippet only', color: AppColors.amber),
        ]),
        if (o.matchedTerms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Your skills it mentions: ${o.matchedTerms.take(6).join(', ')}', style: t.bodySmall?.copyWith(color: pal.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}
