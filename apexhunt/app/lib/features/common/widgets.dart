import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ai/llm.dart';
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../discovery/mission_controller.dart';

final money = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ApexPalette.of(context).muted))),
          ?trailing,
        ]),
      );
}

class ApexCard extends StatelessWidget {
  const ApexCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.borderColor});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color, borderColor;
  @override
  Widget build(BuildContext context) {
    final pal = ApexPalette.of(context);
    return Material(
      color: color ?? pal.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderColor ?? pal.line.withValues(alpha: 0.7))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Circular score gauge (0-100).
class ScoreGauge extends StatelessWidget {
  const ScoreGauge({super.key, required this.value, this.size = 56, this.label});
  final double value, size;
  final String? label;

  static Color colorFor(BuildContext context, double v) {
    final pal = ApexPalette.of(context);
    if (v >= 75) return pal.success;
    if (v >= 50) return Theme.of(context).colorScheme.primary;
    if (v >= 30) return pal.warning;
    return pal.danger;
  }

  @override
  Widget build(BuildContext context) {
    final c = colorFor(context, value);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(value / 100, c, ApexPalette.of(context).line),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${value.round()}', style: TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w800, fontSize: size * 0.3, color: c, height: 1)),
            if (label != null) Text(label!, style: TextStyle(fontSize: size * 0.14, color: ApexPalette.of(context).muted)),
          ]),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.fraction, this.color, this.track);
  final double fraction;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.09;
    final rect = Offset(stroke / 2, stroke / 2) & Size(size.width - stroke, size.height - stroke);
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, base);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction.clamp(0, 1), false, base
      ..color = color
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.fraction != fraction || old.color != color;
}

class AtsBoost extends StatelessWidget {
  const AtsBoost({super.key, required this.before, required this.after});
  final double before, after;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = ApexPalette.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${before.round()}%', style: t.titleMedium?.copyWith(color: pal.muted, decoration: TextDecoration.lineThrough)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward_rounded, size: 18, color: pal.muted)),
      Text('${after.round()}%', style: t.titleLarge?.copyWith(color: ScoreGauge.colorFor(context, after))),
      const SizedBox(width: 6),
      Text('ATS match', style: t.bodySmall?.copyWith(color: pal.muted)),
    ]);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 4)],
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c))),
      ]),
    );
  }
}

class TelemetryTerminal extends StatelessWidget {
  const TelemetryTerminal({super.key, required this.events, this.startedAt, this.running = false, this.maxLines = 8});
  final List<TelemetryEvent> events;
  final DateTime? startedAt;
  final bool running;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final pal = ApexPalette.of(context);
    final shown = events.length > maxLines ? events.sublist(events.length - maxLines) : events;
    Color colorFor(String k) => switch (k) {
          'JOB_FOUND' => pal.success,
          'GAP_DETECTED' => pal.warning,
          'ERROR' => pal.danger,
          'DONE' => const Color(0xFF93C5FD),
          _ => const Color(0xFFCBD5E1),
        };
    String stamp(DateTime at) {
      final s = startedAt == null ? 0 : at.difference(startedAt!).inSeconds;
      return '[${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}]';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: pal.terminal, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF1E293B))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: running ? pal.success : const Color(0xFF475569), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(running ? 'AGENT LIVE' : 'AGENT LOG', style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 11, color: Color(0xFF94A3B8), letterSpacing: 1)),
        ]),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          const Text('> Waiting for your first mission…', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 12, color: Color(0xFF64748B))),
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('> ${stamp(e.at)} ${e.message}', style: TextStyle(fontFamily: AppFonts.mono, fontSize: 12, height: 1.4, color: colorFor(e.kind))),
          ),
        if (running) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 2)),
      ]),
    );
  }
}

/// Top-bar pill: active AI engine + wallet balance. Opens AI settings.
class EnginePill extends ConsumerWidget {
  const EnginePill({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(aiSettingsProvider).value;
    final wallet = ref.watch(walletProvider).value;
    final byok = s?.mode == AiMode.byok;
    final label = s == null
        ? '…'
        : byok
            ? 'BYOK active'
            : '${s.engineLabel}${wallet == null ? '' : ' • ${money.format(wallet.balanceUsd)}'}';
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ActionChip(
        avatar: Icon(byok ? Icons.key_rounded : Icons.bolt_rounded, size: 16, color: byok ? AppColors.amber : Theme.of(context).colorScheme.primary),
        label: Text(label),
        onPressed: () => context.go('/settings'),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  final IconData icon;
  final String title, body;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: ApexPalette.of(context).muted),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ApexPalette.of(context).muted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? AppColors.rose : null));
}

/// Turns AI errors into the right next step (sign in, buy credits, upgrade).
void handleAiError(BuildContext context, Object error) {
  if (error is LlmException) {
    if (error.needsSignIn) {
      showSnack(context, error.message);
      context.go('/settings?signin=1');
      return;
    }
    if (error.needsCredits || error.needsPro) {
      showSnack(context, error.message);
      context.go('/settings?paywall=1');
      return;
    }
    showSnack(context, error.message, error: true);
    return;
  }
  showSnack(context, 'Something went wrong: $error', error: true);
}

Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Google Play generative-AI policy: every AI output has a visible report action.
class ReportAiButton extends ConsumerWidget {
  const ReportAiButton({super.key, required this.kind, required this.excerpt});
  final String kind, excerpt;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: 'Report AI output',
        icon: const Icon(Icons.flag_outlined),
        onPressed: () => showReportDialog(context, ref, kind: kind, excerpt: excerpt),
      );
}

Future<void> showReportDialog(BuildContext context, WidgetRef ref, {required String kind, required String excerpt}) async {
  const reasons = ['Inaccurate or made-up information', 'Offensive or harmful content', 'Privacy concern', 'Other'];
  var reason = reasons.first;
  final notes = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Report AI output'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            RadioGroup<String>(
              groupValue: reason,
              onChanged: (v) => set(() => reason = v ?? reason),
              child: Column(children: [for (final r in reasons) RadioListTile<String>(value: r, title: Text(r), dense: true, contentPadding: EdgeInsets.zero)]),
            ),
            TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(hintText: 'What went wrong? (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send report')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final api = ref.read(gatewayProvider);
  var sentMessage = 'Thanks — report sent. We review every report.';
  try {
    if (api != null && ref.read(authProvider).value != null) {
      await api.flag(kind: kind, reason: reason, notes: notes.text, excerpt: excerpt);
    } else if (AppConfig.hasSupportEmail) {
      final body = Uri.encodeComponent('Reason: $reason\n${notes.text}\n\n---\n${excerpt.length > 1500 ? excerpt.substring(0, 1500) : excerpt}');
      await openUrl('mailto:${AppConfig.supportEmail}?subject=${Uri.encodeComponent('ApexHunt AI output report')}&body=$body');
    } else {
      sentMessage = 'Report saved. Thanks for helping us improve.';
      await ref.read(localStoreProvider).writeJson('ai_reports/${DateTime.now().millisecondsSinceEpoch}.json', {'kind': kind, 'reason': reason, 'notes': notes.text, 'excerpt': excerpt});
    }
    if (context.mounted) showSnack(context, sentMessage);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not send the report. Please try again.', error: true);
  }
}
