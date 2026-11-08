import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/ai/llm.dart';
import '../../core/app_state.dart';
import '../../core/billing.dart';
import '../../core/config.dart';
import '../../core/gateway.dart';
import '../../core/theme.dart';
import '../common/widgets.dart';
import 'ai_widgets.dart';

final catalogProvider = FutureProvider<EngineCatalog?>((ref) async {
  final api = ref.watch(gatewayProvider);
  if (api == null) return null;
  try {
    return await api.catalog();
  } catch (_) {
    return null;
  }
});

final _versionProvider = FutureProvider<String>((ref) async {
  final i = await PackageInfo.fromPlatform();
  return '${i.version} (${i.buildNumber})';
});

/// Tab 5 — AI engine, wallet, Pro, account and compliance.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.openSignIn = false, this.openPaywall = false});
  final bool openSignIn, openPaywall;
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openSignIn && AppConfig.hasAuth) _signInSheet();
      if (widget.openPaywall) showPaywall(context, ref);
    });
  }

  @override
  void didUpdateWidget(covariant SettingsScreen old) {
    super.didUpdateWidget(old);
    if (widget.openPaywall && !old.openPaywall) WidgetsBinding.instance.addPostFrameCallback((_) => showPaywall(context, ref));
    if (widget.openSignIn && !old.openSignIn) WidgetsBinding.instance.addPostFrameCallback((_) => _signInSheet());
  }

  void _signInSheet() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Sign in', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('New accounts get free Apex AI credits.', style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 16),
            SignInForm(onSignedIn: () => Navigator.pop(ctx)),
          ]),
        ),
      );

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete account & wipe data?'),
        content: const Text(
            'This permanently deletes your account, AI credit balance and usage history from our servers, and wipes your CV, applications and keys from this phone. Cancel any subscription in Google Play first.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.rose), onPressed: () => Navigator.pop(c, true), child: const Text('Delete everything')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final api = ref.read(gatewayProvider);
      if (api != null && ref.read(authProvider).value != null) await api.deleteAccount();
      await AuthActions.signOut();
      await wipeAllLocalData(ref);
      if (mounted) {
        showSnack(context, 'Your account and data were deleted.');
        context.go('/onboarding');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Deletion failed: $e. You can also request it at ${AppConfig.deleteAccountUrl}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    final user = ref.watch(authProvider).value;
    final settings = ref.watch(aiSettingsProvider).value ?? AiSettings();
    final wallet = ref.watch(walletProvider).value;
    final isPro = ref.watch(isProProvider);
    final billingOn = ref.watch(billingServiceProvider).enabled;
    final catalog = ref.watch(catalogProvider).value;
    final tiers = (catalog?.tiers.isNotEmpty ?? false) ? catalog!.tiers : EngineTier.defaults;

    return Scaffold(
      appBar: AppBar(title: const Text('AI & Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        // ------------------------------------------------------------ account
        if (AppConfig.hasAuth)
          ApexCard(
            child: Row(children: [
              const Icon(Icons.account_circle_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.email ?? 'Not signed in', style: t.titleMedium),
                  Text(user == null ? 'Sign in for free Apex AI credits' : (isPro ? 'Pro member' : 'Free plan'), style: t.bodySmall?.copyWith(color: pal.muted)),
                ]),
              ),
              user == null ? FilledButton(onPressed: _signInSheet, child: const Text('Sign in')) : TextButton(onPressed: AuthActions.signOut, child: const Text('Sign out')),
            ]),
          ),
        // ------------------------------------------------------------ pro
        if (billingOn) ...[
          const SizedBox(height: 12),
          ApexCard(
            color: isPro ? AppColors.emerald.withValues(alpha: 0.08) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            onTap: isPro ? null : () => showPaywall(context, ref),
            child: Row(children: [
              Icon(isPro ? Icons.workspace_premium : Icons.workspace_premium_outlined, color: isPro ? AppColors.emerald : Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(isPro ? 'ApexHunt Pro is active' : 'Go Pro: your own AI key, Apex Elite engine and monthly bonus credits', style: t.bodyMedium)),
              if (!isPro) const Icon(Icons.chevron_right),
            ]),
          ),
        ],
        // ------------------------------------------------------------ AI engine
        const SectionLabel('AI engine'),
        if (AppConfig.hasManagedAi)
          SegmentedButton<AiMode>(
            segments: const [
              ButtonSegment(value: AiMode.managed, label: Text('Apex Cloud'), icon: Icon(Icons.bolt)),
              ButtonSegment(value: AiMode.byok, label: Text('Your own key'), icon: Icon(Icons.key)),
            ],
            selected: {settings.mode},
            onSelectionChanged: (v) => ref.read(aiSettingsProvider.notifier).save(settings.copyWith(mode: v.first)),
          ),
        const SizedBox(height: 12),
        if (settings.mode == AiMode.managed && AppConfig.hasManagedAi) ...[
          ApexCard(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Apex AI credits', style: t.bodySmall?.copyWith(color: pal.muted)),
                  Text(wallet == null ? '—' : money.format(wallet.balanceUsd), style: t.headlineMedium),
                ]),
              ),
              if (billingOn) FilledButton.tonal(onPressed: () => showPaywall(context, ref, creditsFirst: true), child: const Text('Top up')),
            ]),
          ),
          const SizedBox(height: 10),
          RadioGroup<String>(
            groupValue: settings.engine,
            onChanged: (id) {
              final tier = tiers.firstWhere((x) => x.id == id);
              if (id == 'apex-elite' && !isPro) {
                showPaywall(context, ref);
                return;
              }
              ref.read(aiSettingsProvider.notifier).save(settings.copyWith(engine: tier.id, engineLabel: tier.name));
            },
            child: Column(children: [
              for (final tier in tiers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ApexCard(
                    padding: EdgeInsets.zero,
                    child: RadioListTile<String>(
                      value: tier.id,
                      title: Row(children: [
                        Text(tier.name, style: t.titleSmall),
                        if (tier.id == 'apex-elite' && !isPro) const Padding(padding: EdgeInsets.only(left: 8), child: Pill('Pro', icon: Icons.lock_outline)),
                      ]),
                      subtitle: Text(
                        '${tier.description}${tier.costPerApp != null ? '\n≈ ${money.format(tier.costPerApp)} per tailored application' : ''}',
                        style: t.bodySmall?.copyWith(color: pal.muted),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ] else ...[
          if (!isPro)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ApexCard(
                color: AppColors.amber.withValues(alpha: 0.1),
                onTap: () => showPaywall(context, ref),
                child: const Text('Using your own key for tailoring is a Pro feature. You can still import your CV with it for free.'),
              ),
            ),
          if (settings.hasByokKey)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ApexCard(
                child: Row(children: [
                  const Icon(Icons.key, color: AppColors.amber),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${settings.byokProvider.label} · ${settings.byokModel}\nKey stored in device keystore', style: t.bodyMedium)),
                  TextButton(onPressed: () => ref.read(aiSettingsProvider.notifier).clearByok(), child: const Text('Remove')),
                ]),
              ),
            ),
          ByokForm(onSaved: () => setState(() {})),
        ],
        // ------------------------------------------------------------ profile
        const SectionLabel('Career profile'),
        ApexCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Edit master profile'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/profile')),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Re-import CV'),
              subtitle: const Text('Replaces your profile; tailored applications stay in the Vault'),
              onTap: () async {
                await ref.read(localStoreProvider).delete('profile.json');
                ref.invalidate(profileProvider);
                if (context.mounted) context.go('/onboarding');
              },
            ),
          ]),
        ),
        // ------------------------------------------------------------ legal
        const SectionLabel('Privacy & legal'),
        ApexCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy policy'), onTap: () => openUrl(AppConfig.privacyUrl)),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.gavel_outlined), title: const Text('Terms of use'), onTap: () => openUrl(AppConfig.termsUrl)),
            const Divider(height: 1),
            if (AppConfig.hasSupportEmail) ...[
              ListTile(leading: const Icon(Icons.mail_outline), title: const Text('Contact support'), subtitle: const Text(AppConfig.supportEmail), onTap: () => openUrl('mailto:${AppConfig.supportEmail}')),
              const Divider(height: 1),
            ],
            ListTile(leading: const Icon(Icons.article_outlined), title: const Text('Open-source licences'), onTap: () => showLicensePage(context: context, applicationName: AppConfig.appName)),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.rose, side: const BorderSide(color: AppColors.rose)),
          onPressed: _deleteAccount,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete account & wipe data'),
        ),
        const SizedBox(height: 16),
        Center(child: Text('${AppConfig.appName} ${ref.watch(_versionProvider).value ?? ''}', style: t.bodySmall?.copyWith(color: pal.muted))),
      ]),
    );
  }
}

/// Pro subscription + credit packs (Google Play Billing via RevenueCat).
Future<void> showPaywall(BuildContext context, WidgetRef ref, {bool creditsFirst = false}) async {
  final svc = ref.read(billingServiceProvider);
  if (!svc.enabled) {
    showSnack(context, 'In-app purchases are not configured in this build.');
    return;
  }
  if (AppConfig.hasAuth && ref.read(authProvider).value == null) {
    showSnack(context, 'Sign in first so your purchase is linked to your account.');
    context.go('/settings?signin=1');
    return;
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _PaywallSheet(),
  );
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet();
  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn, String success) async {
    setState(() => _busy = true);
    try {
      await fn();
      await ref.read(billingProvider.notifier).reload();
      await ref.read(walletProvider.notifier).syncAfterPurchase();
      if (mounted) {
        showSnack(context, success);
        Navigator.pop(context);
      }
    } on PurchaseCancelled {
      // user closed the Play sheet
    } catch (e) {
      if (mounted) showSnack(context, 'Purchase failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    final snap = ref.watch(billingProvider);
    final svc = ref.read(billingServiceProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: snap.when(
          loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => SizedBox(height: 160, child: Center(child: Text('Store unavailable: $e'))),
          data: (b) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ApexHunt Pro', style: t.headlineSmall),
            const SizedBox(height: 10),
            for (final perk in const [
              'Use your own AI key (OpenAI, Anthropic, Gemini, Groq, OpenRouter, local)',
              'Apex Elite engine for senior roles and high-value bids',
              'Bonus Apex credits every month',
              'Support an independent, honest career tool',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check, color: AppColors.emerald, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(perk, style: t.bodyMedium)),
                ]),
              ),
            const SizedBox(height: 12),
            if (b.isPro)
              const ApexCard(child: Text('You are Pro. Thank you!'))
            else ...[
              if (b.monthly != null)
                FilledButton(
                  onPressed: _busy ? null : () => _run(() => svc.buyPackage(b.monthly!), 'Welcome to Pro!'),
                  child: Text('Subscribe · ${b.monthly!.storeProduct.priceString}/month'),
                ),
              if (b.annual != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(() => svc.buyPackage(b.annual!), 'Welcome to Pro!'),
                  child: Text('Yearly · ${b.annual!.storeProduct.priceString}/year'),
                ),
              ],
              if (b.monthly == null && b.annual == null) Text('Subscriptions are not available in your region yet.', style: t.bodySmall),
            ],
            if (b.credits.isNotEmpty) ...[
              const SectionLabel('Apex AI credit packs'),
              Row(children: [
                for (final c in b.credits)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _run(() => svc.buyCredits(c), 'Credits added'),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [Text('+\$${c.usd.toStringAsFixed(0)}', style: t.titleMedium), Text(c.priceString, style: t.bodySmall)]),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('A tailored application usually costs a few cents on Apex Pro.', style: t.bodySmall?.copyWith(color: pal.muted), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: _busy ? null : () => _run(() async => svc.restore(), 'Purchases restored'), child: const Text('Restore purchases')),
            Text('Subscriptions renew automatically until cancelled in Google Play → Payments & subscriptions.', style: t.bodySmall?.copyWith(color: pal.muted), textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}
