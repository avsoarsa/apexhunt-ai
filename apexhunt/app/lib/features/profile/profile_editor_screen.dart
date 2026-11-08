import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';

/// Edit the Master Profile — the single source of truth for every tailored CV.
class ProfileEditorScreen extends ConsumerStatefulWidget {
  const ProfileEditorScreen({super.key});
  @override
  ConsumerState<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
  MasterProfile? _p;
  final _skillInput = TextEditingController();
  final _learnInput = TextEditingController();

  @override
  void initState() {
    super.initState();
    _p = ref.read(profileProvider).value?.copy();
  }

  Future<void> _save() async {
    await ref.read(profileProvider.notifier).save(_p!);
    if (mounted) {
      showSnack(context, 'Profile saved');
      Navigator.of(context).maybePop();
    }
  }

  Widget _field(String label, String value, ValueChanged<String> onChanged, {int maxLines = 1, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: value,
          maxLines: maxLines,
          minLines: 1,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label),
          onChanged: onChanged,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const Scaffold(body: Center(child: Text('No profile yet')));
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Master profile'), actions: [TextButton(onPressed: _save, child: const Text('Save'))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        const SectionLabel('Contact'),
        _field('Full name', p.contact.name, (v) => p.contact.name = v),
        _field('Email', p.contact.email, (v) => p.contact.email = v, keyboard: TextInputType.emailAddress),
        _field('Phone', p.contact.phone, (v) => p.contact.phone = v, keyboard: TextInputType.phone),
        _field('Location', p.contact.location, (v) => p.contact.location = v),
        _field('Links (comma separated)', p.contact.links.join(', '), (v) => p.contact.links = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
        const SectionLabel('Positioning'),
        _field('Headline', p.headline, (v) => p.headline = v),
        _field('Summary', p.summary, (v) => p.summary = v, maxLines: 5),
        _field('Target roles (comma separated)', p.targetRoles.join(', '), (v) => p.targetRoles = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
        _field('Freelance hourly rate (USD, optional)', p.hourlyRateUsd == 0 ? '' : p.hourlyRateUsd.toStringAsFixed(0), (v) => p.hourlyRateUsd = double.tryParse(v) ?? 0, keyboard: TextInputType.number),
        SectionLabel('Experience', trailing: TextButton.icon(onPressed: () => setState(() => p.roles.insert(0, WorkRole())), icon: const Icon(Icons.add, size: 18), label: const Text('Add role'))),
        for (final r in p.roles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ApexCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                title: Text(r.label.trim() == '@' ? 'New role' : r.label, style: t.titleSmall),
                subtitle: Text(r.dates, style: t.bodySmall?.copyWith(color: pal.muted)),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  _field('Company', r.company, (v) => r.company = v),
                  _field('Title', r.title, (v) => r.title = v),
                  Row(children: [
                    Expanded(child: _field('Start (YYYY-MM)', r.start, (v) => r.start = v)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('End (blank = present)', r.end, (v) => r.end = v)),
                  ]),
                  _field('Location', r.location, (v) => r.location = v),
                  _field('Bullets (one per line)', r.bullets.join('\n'), (v) => r.bullets = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(), maxLines: 10),
                  _field('Tools used (comma separated)', r.skills.join(', '), (v) => r.skills = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(onPressed: () => setState(() => p.roles.remove(r)), icon: const Icon(Icons.delete_outline), label: const Text('Remove role')),
                  ),
                ],
              ),
            ),
          ),
        const SectionLabel('Skills'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in p.skills) InputChip(label: Text(s), onDeleted: () => setState(() => p.skills.remove(s))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _skillInput,
          decoration: const InputDecoration(hintText: 'Add a skill you genuinely have', suffixIcon: Icon(Icons.add)),
          onSubmitted: (v) => setState(() {
            if (v.trim().isNotEmpty) p.skills.add(v.trim());
            _skillInput.clear();
          }),
        ),
        if (p.evidence.isNotEmpty) ...[
          const SectionLabel('Skills you confirmed during check-ins'),
          for (final e in p.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.skill),
              subtitle: Text(e.context),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => p.evidence.remove(e))),
            ),
        ],
        const SectionLabel('Currently learning'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in p.learning) InputChip(label: Text(s), onDeleted: () => setState(() => p.learning.remove(s))),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _learnInput,
          decoration: const InputDecoration(hintText: 'Add a skill you are learning', suffixIcon: Icon(Icons.add)),
          onSubmitted: (v) => setState(() {
            if (v.trim().isNotEmpty) p.learning.add(v.trim());
            _learnInput.clear();
          }),
        ),
        SectionLabel('Education', trailing: TextButton.icon(onPressed: () => setState(() => p.education.add(Education())), icon: const Icon(Icons.add, size: 18), label: const Text('Add'))),
        for (final e in p.education)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ApexCard(
              child: Column(children: [
                _field('Degree', e.degree, (v) => e.degree = v),
                _field('Institution', e.institution, (v) => e.institution = v),
                _field('Year', e.year, (v) => e.year = v),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => p.education.remove(e)), child: const Text('Remove'))),
              ]),
            ),
          ),
        SectionLabel('Projects', trailing: TextButton.icon(onPressed: () => setState(() => p.projects.add(Project())), icon: const Icon(Icons.add, size: 18), label: const Text('Add'))),
        for (final pr in p.projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ApexCard(
              child: Column(children: [
                _field('Project name', pr.name, (v) => pr.name = v),
                _field('Description', pr.description, (v) => pr.description = v, maxLines: 3),
                _field('Bullets (one per line)', pr.bullets.join('\n'), (v) => pr.bullets = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(), maxLines: 6),
                _field('Tech used (comma separated)', pr.skills.join(', '), (v) => pr.skills = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
                _field('Link', pr.link, (v) => pr.link = v),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => p.projects.remove(pr)), child: const Text('Remove'))),
              ]),
            ),
          ),
        const SectionLabel('Certifications & languages'),
        _field('Certifications (one per line)', p.certifications.join('\n'), (v) => p.certifications = v.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(), maxLines: 4),
        _field('Spoken languages (comma separated)', p.languages.join(', '), (v) => p.languages = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Save profile')),
      ]),
    );
  }
}
