import 'package:flutter/material.dart';

/// "Cyber-Executive" design tokens (see ui_ux_design_system_wireframe_specification.md).
class AppColors {
  static const obsidian = Color(0xFF0F172A);
  static const slateCard = Color(0xFF1E293B);
  static const slateRaised = Color(0xFF273449);
  static const cobalt = Color(0xFF2563EB);
  static const cobaltBright = Color(0xFF3B82F6);
  static const emerald = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFEF4444);
  static const ink = Color(0xFFE2E8F0);
  static const muted = Color(0xFF94A3B8);
  static const line = Color(0xFF334155);

  // Light theme counterparts.
  static const paper = Color(0xFFF8FAFC);
  static const paperCard = Color(0xFFFFFFFF);
  static const inkDark = Color(0xFF0F172A);
  static const mutedDark = Color(0xFF475569);
  static const lineLight = Color(0xFFE2E8F0);
}

class AppFonts {
  static const display = 'PlusJakartaSans';
  static const body = 'Inter';
  static const mono = 'JetBrainsMono';
}

/// Semantic colours that differ between light and dark.
@immutable
class ApexPalette extends ThemeExtension<ApexPalette> {
  const ApexPalette({
    required this.card,
    required this.raised,
    required this.line,
    required this.muted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.terminal,
  });

  final Color card, raised, line, muted, success, warning, danger, terminal;

  static ApexPalette of(BuildContext context) => Theme.of(context).extension<ApexPalette>()!;

  @override
  ApexPalette copyWith({Color? card}) => this;

  @override
  ApexPalette lerp(ApexPalette? other, double t) => other ?? this;
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.cobalt,
    brightness: brightness,
  ).copyWith(
    primary: dark ? AppColors.cobaltBright : AppColors.cobalt,
    onPrimary: Colors.white,
    secondary: AppColors.emerald,
    tertiary: AppColors.amber,
    error: AppColors.rose,
    surface: dark ? AppColors.obsidian : AppColors.paper,
    onSurface: dark ? AppColors.ink : AppColors.inkDark,
    surfaceContainerHighest: dark ? AppColors.slateRaised : const Color(0xFFEFF3F8),
    surfaceContainerHigh: dark ? AppColors.slateCard : AppColors.paperCard,
    surfaceContainer: dark ? AppColors.slateCard : AppColors.paperCard,
    surfaceContainerLow: dark ? const Color(0xFF162033) : const Color(0xFFF1F5F9),
    outline: dark ? AppColors.line : AppColors.lineLight,
    outlineVariant: dark ? AppColors.line : AppColors.lineLight,
  );

  final palette = ApexPalette(
    card: dark ? AppColors.slateCard : AppColors.paperCard,
    raised: dark ? AppColors.slateRaised : const Color(0xFFF1F5F9),
    line: dark ? AppColors.line : AppColors.lineLight,
    muted: dark ? AppColors.muted : AppColors.mutedDark,
    success: AppColors.emerald,
    warning: AppColors.amber,
    danger: AppColors.rose,
    terminal: dark ? const Color(0xFF0B1222) : const Color(0xFF0F172A),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: AppFonts.body);
  final text = base.textTheme.copyWith(
    displaySmall: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w800, fontSize: 34, height: 1.1),
    headlineMedium: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w800, fontSize: 26, height: 1.15),
    headlineSmall: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w700, fontSize: 22, height: 1.2),
    titleLarge: const TextStyle(fontFamily: AppFonts.display, fontWeight: FontWeight.w700, fontSize: 19),
    titleMedium: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    titleSmall: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    bodyLarge: const TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: const TextStyle(fontSize: 14, height: 1.5),
    bodySmall: const TextStyle(fontSize: 12.5, height: 1.45),
    labelLarge: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    labelSmall: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.8),
  ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [palette],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: palette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.line.withValues(alpha: dark ? 0.6 : 1)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF0B1222) : AppColors.paperCard,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall?.copyWith(letterSpacing: 0.2)),
      height: 68,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: palette.line),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: palette.line),
      labelStyle: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.raised.withValues(alpha: dark ? 0.6 : 1),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? AppColors.obsidian : AppColors.paper,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dividerTheme: DividerThemeData(color: palette.line, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
