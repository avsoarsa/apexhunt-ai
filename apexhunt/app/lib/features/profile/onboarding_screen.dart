import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import '../settings/ai_widgets.dart';
import 'cv_import.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  bool _useByok = !AppConfig.hasManagedAi;
  String? _cvText, _fileName;
  final _paste = TextEditingController();
  final _roles = TextEditingController();
  bool _busy = false;
  String _busyLabel = '';
  MasterProfile? _parsed;
  String? _parseNote;

  bool get _aiReady {
    final s = ref.watch(aiSettingsProvider).value;
    if (_useByok) return s?.hasByokKey == true && s?.mode == AiMode.byok;
    return ref.watch(authProvider).value != null;
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'docx', 'txt']);
      if (files.isEmpty) return;
      final f = files.first;
      setState(() {
        _busy = true;
        _busyLabel = 'Reading ${f.name}…';
      });
      final bytes = await f.xFile.readAsBytes();
      final text = await CvTextExtractor.extract(bytes, f.name);
      setState(() {
        _cvText = text;
        _fileName = f.name;
      });
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open that file: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _build() async {
    final text = (_cvText ?? _paste.text).trim();
    if (text.length < 80) {
      showSnack(context, 'Upload your CV or paste at least a few lines of it.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = 'Building your career profile…';
      _parseNote = null;
    });
    MasterProfile profile;
    try {
      final llm = await ref.read(aiServiceProvider).client(allowFreeByok: true);
      profile = await ProfileParser.parseWithAi(llm, text);
    } catch (e) {
      profile = ProfileParser.parseHeuristic(text);
      _parseNote = 'AI parsing was unavailable ($e), so we did a basic import. Review and complete your profile next.';
    }
    profile.targetRoles = _roles.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (mounted) {
      setState(() {
        _parsed = profile;
        _busy = false;
        _step = 3;
      });
    }
  }

  Future<void> _finish({bool edit = false}) async {
    await ref.read(profileProvider.notifier).save(_parsed!);
    if (edit && mounted) context.push('/profile');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 32), children: [
            Row(children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(color: i <= _step ? Theme.of(context).colorScheme.primary : pal.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
            ]),
            const SizedBox(height: 28),
            ...switch (_step) {
              0 => _welcome(t, pal),
              1 => _power(t, pal),
              2 => _import(t, pal),
              _ => _review(t, pal),
            },
          ]),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: ApexCard(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      const SizedBox(width: 16),
                      Text(_busyLabel),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  List<Widget> _welcome(TextTheme t, ApexPalette pal) => [
        Image.asset('assets/images/icon.png', width: 72, height: 72),
        const SizedBox(height: 20),
        Text('Land interviews with your real experience.', style: t.displaySmall),
        const SizedBox(height: 12),
        Text('ApexHunt finds jobs and freelance gigs worldwide, tailors your CV to each one, and preps you for the interview.', style: t.bodyLarge?.copyWith(color: pal.muted)),
        const SizedBox(height: 24),
        for (final (icon, title, body) in [
          (Icons.radar, 'Discover', 'Live roles and gigs from 30+ countries, ranked against your skills.'),
          (Icons.auto_fix_high, 'Tailor', 'Your real experience, rewritten in each job\'s language. ATS-clean PDF and DOCX.'),
          (Icons.record_voice_over_outlined, 'Prep', 'STAR stories from your own work, likely questions, and a plan for every gap.'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ApexCard(
              child: Row(children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.titleMedium), Text(body, style: t.bodyMedium?.copyWith(color: pal.muted))])),
              ]),
            ),
          ),
        ApexCard(
          color: AppColors.emerald.withValues(alpha: 0.08),
          borderColor: AppColors.emerald.withValues(alpha: 0.4),
          child: Row(children: [
            const Icon(Icons.verified_outlined, color: AppColors.emerald),
            const SizedBox(width: 14),
            Expanded(child: Text('Our promise: ApexHunt never invents skills, employers or numbers. Every line on your CV stays true — so you can defend it.', style: t.bodyMedium)),
          ]),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Get started')),
      ];

  List<Widget> _power(TextTheme t, ApexPalette pal) => [
        Text('Power your AI', style: t.headlineMedium),
        const SizedBox(height: 8),
        Text(
          AppConfig.hasManagedAi ? 'Sign in to get free Apex AI credits — enough for your first tailored applications. Or use your own API key.' : 'Connect your own AI provider key. Google Gemini offers free keys.',
          style: t.bodyLarge?.copyWith(color: pal.muted),
        ),
        const SizedBox(height: 20),
        if (AppConfig.hasManagedAi)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Free credits'), icon: Icon(Icons.bolt)),
              ButtonSegment(value: true, label: Text('My own key'), icon: Icon(Icons.key)),
            ],
            selected: {_useByok},
            onSelectionChanged: (v) => setState(() => _useByok = v.first),
          ),
        const SizedBox(height: 20),
        if (!_useByok && ref.watch(authProvider).value != null)
          ApexCard(child: Row(children: [
            const Icon(Icons.check_circle, color: AppColors.emerald),
            const SizedBox(width: 12),
            Expanded(child: Text('Signed in as ${ref.watch(authProvider).value!.email}')),
          ]))
        else if (!_useByok)
          SignInForm(onSignedIn: () => setState(() {}))
        else if (_aiReady)
          ApexCard(child: Row(children: [
            const Icon(Icons.check_circle, color: AppColors.emerald),
            const SizedBox(width: 12),
            Expanded(child: Text('Key saved: ${ref.watch(aiSettingsProvider).value?.byokProvider.name}')),
          ]))
        else
          ByokForm(onSaved: () => setState(() {})),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _aiReady
              ? () async {
                  final s = ref.read(aiSettingsProvider).value ?? AiSettings();
                  await ref.read(aiSettingsProvider.notifier).save(s.copyWith(mode: _useByok ? AiMode.byok : AiMode.managed));
                  setState(() => _step = 2);
                }
              : null,
          child: const Text('Continue'),
        ),
        TextButton(onPressed: () => setState(() => _step = 2), child: const Text('Skip for now (basic import only)')),
      ];

  List<Widget> _import(TextTheme t, ApexPalette pal) => [
        Text('Add your CV', style: t.headlineMedium),
        const SizedBox(height: 8),
        Text('PDF, DOCX or text. It stays on your phone; only the text is sent to the AI to structure it.', style: t.bodyLarge?.copyWith(color: pal.muted)),
        const SizedBox(height: 20),
        ApexCard(
          onTap: _pickFile,
          child: Row(children: [
            Icon(_fileName == null ? Icons.upload_file : Icons.description, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fileName ?? 'Upload CV file', style: t.titleMedium),
                Text(_cvText == null ? 'Tap to choose a PDF, DOCX or TXT' : '${_cvText!.length} characters read', style: t.bodySmall?.copyWith(color: pal.muted)),
              ]),
            ),
          ]),
        ),
        const SectionLabel('or paste it'),
        TextField(controller: _paste, maxLines: 6, decoration: const InputDecoration(hintText: 'Paste your CV text here…')),
        const SectionLabel('Roles you want'),
        TextField(controller: _roles, decoration: const InputDecoration(hintText: 'e.g. Flutter Developer, AI Engineer')),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _busy ? null : _build, icon: const Icon(Icons.auto_awesome), label: const Text('Build my profile')),
        TextButton(onPressed: () => setState(() => _step = 1), child: const Text('Back')),
      ];

  List<Widget> _review(TextTheme t, ApexPalette pal) {
    final p = _parsed!;
    return [
      Text('Check your profile', style: t.headlineMedium),
      const SizedBox(height: 8),
      Text('Company names, titles and dates are locked — tailoring never changes them. Fix anything that looks wrong now.', style: t.bodyLarge?.copyWith(color: pal.muted)),
      if (_parseNote != null) ...[const SizedBox(height: 12), ApexCard(color: AppColors.amber.withValues(alpha: 0.1), child: Text(_parseNote!))],
      const SizedBox(height: 16),
      ApexCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.contact.name.isEmpty ? 'Name not found' : p.contact.name, style: t.titleLarge),
          if (p.headline.isNotEmpty) Text(p.headline, style: t.bodyMedium?.copyWith(color: pal.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill('${p.roles.length} roles', icon: Icons.work_outline),
            Pill('${p.skills.length} skills', icon: Icons.bolt),
            Pill('${p.education.length} education', icon: Icons.school_outlined),
            if (p.projects.isNotEmpty) Pill('${p.projects.length} projects', icon: Icons.code),
          ]),
        ]),
      ),
      const SectionLabel('Experience (locked anchors)'),
      for (final r in p.roles.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ApexCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(Icons.lock_outline, size: 18, color: pal.muted),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.label, style: t.titleSmall), Text(r.dates, style: t.bodySmall?.copyWith(color: pal.muted))])),
              Text('${r.bullets.length} bullets', style: t.bodySmall?.copyWith(color: pal.muted)),
            ]),
          ),
        ),
      const SectionLabel('Skills'),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in p.skills.take(30)) Chip(label: Text(s), visualDensity: VisualDensity.compact)]),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => _finish(), child: const Text('Looks good — start hunting')),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => _finish(edit: true), child: const Text('Save and edit details')),
    ];
  }
}
