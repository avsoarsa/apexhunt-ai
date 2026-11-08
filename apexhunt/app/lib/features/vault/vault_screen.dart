import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';

/// Tab 3 — every tailored CV, cover letter and proposal, available offline.
class VaultScreen extends ConsumerWidget {
  const VaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(artifactsProvider).value ?? [];
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('CV Vault'), actions: const [EnginePill()]),
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.folder_open,
              title: 'Your vault is empty',
              body: 'Tailor a CV for any job in your Pipeline. Each one is saved here with its cover letter or proposal — available offline.',
              action: FilledButton(onPressed: () => context.go('/pipeline'), child: const Text('Open Pipeline')),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = list[i];
                return ApexCard(
                  onTap: () => context.push('/artifact/${a.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.opportunity.title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text('${a.opportunity.company.isEmpty ? a.opportunity.source : a.opportunity.company} · ${DateFormat.MMMd().format(a.createdAt)}',
                              style: t.bodySmall?.copyWith(color: pal.muted)),
                        ]),
                      ),
                      ScoreGauge(value: a.atsAfter, size: 50, label: 'ATS'),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      AtsBoost(before: a.atsBefore, after: a.atsAfter),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      Pill(a.isFreelance ? 'CV + proposal' : 'CV + cover letter', icon: Icons.description_outlined),
                      if (a.reviewed) const Pill('Reviewed', color: AppColors.emerald, icon: Icons.verified_outlined) else const Pill('Needs review', color: AppColors.amber),
                      if (a.applied) const Pill('Applied', color: AppColors.emerald, icon: Icons.send),
                      if (a.prepCardCount > 0) Pill('Prep ${a.masteredCount}/${a.prepCardCount}', color: pal.muted, icon: Icons.school_outlined),
                    ]),
                  ]),
                );
              },
            ),
    );
  }
}
