import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/llm.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';

/// Passwordless email sign-in (6-digit code) for managed AI credits.
class SignInForm extends ConsumerStatefulWidget {
  const SignInForm({super.key, this.onSignedIn});
  final VoidCallback? onSignedIn;
  @override
  ConsumerState<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends ConsumerState<SignInForm> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false, _busy = false;

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showSnack(context, 'Enter a valid email address.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AuthActions.sendCode(email);
      setState(() => _sent = true);
      if (mounted) showSnack(context, 'We sent a 6-digit code to $email');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not send the code: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    try {
      await AuthActions.verifyCode(_email.text, _code.text);
      ref.invalidate(walletProvider);
      widget.onSignedIn?.call();
    } catch (e) {
      if (mounted) showSnack(context, 'That code did not work. Check it and try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _email,
        enabled: !_sent,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
      ),
      if (_sent) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 8,
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Code from your email', prefixIcon: Icon(Icons.password_rounded), counterText: ''),
        ),
      ],
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _busy ? null : (_sent ? _verify : _send),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_sent ? 'Verify & sign in' : 'Email me a sign-in code'),
      ),
      if (_sent) TextButton(onPressed: _busy ? null : () => setState(() => _sent = false), child: const Text('Use a different email')),
    ]);
  }
}

/// Bring-your-own-key configuration with a live connection test.
class ByokForm extends ConsumerStatefulWidget {
  const ByokForm({super.key, this.onSaved});
  final VoidCallback? onSaved;
  @override
  ConsumerState<ByokForm> createState() => _ByokFormState();
}

class _ByokFormState extends ConsumerState<ByokForm> {
  late ByokProvider _provider;
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _base = TextEditingController();
  bool _busy = false, _obscure = true;

  @override
  void initState() {
    super.initState();
    final s = ref.read(aiSettingsProvider).value ?? AiSettings();
    _provider = s.byokProvider;
    _model.text = s.byokModel.isEmpty ? _defaultModel(_provider) : s.byokModel;
    _base.text = s.byokBaseUrl;
  }

  String _defaultModel(ByokProvider p) => switch (p) {
        ByokProvider.gemini => 'gemini-2.5-flash',
        ByokProvider.openRouter => 'anthropic/claude-haiku-5.5',
        ByokProvider.groq => 'llama-3.3-70b-versatile',
        _ => '',
      };

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty && _provider != ByokProvider.custom) {
      showSnack(context, 'Paste your API key.', error: true);
      return;
    }
    if (_model.text.trim().isEmpty) {
      showSnack(context, 'Enter a model name.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ByokLlmClient(provider: _provider, apiKey: key, model: _model.text.trim(), baseUrl: _base.text.trim()).ping();
      await ref.read(aiSettingsProvider.notifier).saveByok(provider: _provider, model: _model.text.trim(), baseUrl: _base.text.trim(), key: key);
      if (mounted) showSnack(context, 'Key verified and saved to your device keystore.');
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) showSnack(context, 'Connection test failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = ApexPalette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<ByokProvider>(
        initialValue: _provider,
        decoration: const InputDecoration(labelText: 'Provider'),
        items: [for (final p in ByokProvider.values) DropdownMenuItem(value: p, child: Text(p.label))],
        onChanged: (p) => setState(() {
          _provider = p!;
          _model.text = _defaultModel(p);
        }),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _key,
        obscureText: _obscure,
        style: const TextStyle(fontFamily: AppFonts.mono),
        decoration: InputDecoration(
          labelText: 'API key',
          suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
        ),
      ),
      const SizedBox(height: 12),
      TextField(controller: _model, decoration: InputDecoration(labelText: 'Model', hintText: _provider.modelHint)),
      if (_provider == ByokProvider.custom || _provider == ByokProvider.openRouter) ...[
        const SizedBox(height: 12),
        TextField(controller: _base, decoration: InputDecoration(labelText: 'Base URL (optional)', hintText: _provider.defaultBaseUrl)),
      ],
      const SizedBox(height: 8),
      Text(
        _provider == ByokProvider.gemini
            ? 'Tip: Google AI Studio gives free Gemini API keys.'
            : 'Your key is stored only in this phone\'s encrypted keystore and sent only to ${_provider.label}.',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: pal.muted),
      ),
      if (_provider.keyHelpUrl.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => openUrl(_provider.keyHelpUrl), icon: const Icon(Icons.open_in_new, size: 16), label: Text('Get a ${_provider.label} key')),
        ),
      const SizedBox(height: 4),
      FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_user_outlined),
        label: const Text('Test connection & save to keystore'),
      ),
    ]);
  }
}
