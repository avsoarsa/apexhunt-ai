import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/demo_seed.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final store = await LocalStore.open();
  await DemoSeed.apply(store);
  if (!kIsWeb) await pdfrxFlutterInitialize();
  if (AppConfig.hasAuth) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }
  runApp(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const ApexHuntApp()));
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, file) in [('Inter', 'OFL-Inter.txt'), ('Plus Jakarta Sans', 'OFL-PlusJakartaSans.txt'), ('JetBrains Mono', 'OFL-JetBrainsMono.txt')]) {
      yield LicenseEntryWithLineBreaks([pkg], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

class ApexHuntApp extends ConsumerWidget {
  const ApexHuntApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en')],
    );
  }
}
