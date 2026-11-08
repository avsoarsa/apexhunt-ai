import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_state.dart';
import 'features/dojo/dojo_screen.dart';
import 'features/discovery/mission_screen.dart';
import 'features/pipeline/pipeline_screen.dart';
import 'features/profile/onboarding_screen.dart';
import 'features/profile/profile_editor_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/tailor/tailor_screen.dart';
import 'features/vault/artifact_screen.dart';
import 'features/vault/vault_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

String _param(GoRouterState s, String name) {
  final raw = s.pathParameters[name] ?? '';
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(profileProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final profile = ref.read(profileProvider);
      if (profile.isLoading) return null;
      final onboarding = state.matchedLocation == '/onboarding';
      final hasProfile = profile.value != null;
      if (!hasProfile && !onboarding && !state.matchedLocation.startsWith('/settings')) return '/onboarding';
      if (hasProfile && onboarding) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/profile', parentNavigatorKey: _rootKey, builder: (_, _) => const ProfileEditorScreen()),
      GoRoute(path: '/tailor/:id', parentNavigatorKey: _rootKey, builder: (_, s) => TailorScreen(opportunityId: _param(s, 'id'))),
      GoRoute(path: '/artifact/:id', parentNavigatorKey: _rootKey, builder: (_, s) => ArtifactScreen(artifactId: s.pathParameters['id']!)),
      GoRoute(path: '/prep/:id', parentNavigatorKey: _rootKey, builder: (_, s) => PrepDeckScreen(artifactId: s.pathParameters['id']!)),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard', builder: (_, _) => const MissionScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/pipeline', builder: (_, _) => const PipelineScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/vault', builder: (_, _) => const VaultScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/dojo', builder: (_, _) => const DojoScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (_, s) => SettingsScreen(openSignIn: s.uri.queryParameters['signin'] == '1', openPaywall: s.uri.queryParameters['paywall'] == '1'),
            ),
          ]),
        ],
      ),
    ],
  );
});

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.radar_outlined), selectedIcon: Icon(Icons.radar), label: 'Command'),
            NavigationDestination(icon: Icon(Icons.view_agenda_outlined), selectedIcon: Icon(Icons.view_agenda), label: 'Pipeline'),
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'CV Vault'),
            NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Prep Dojo'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'AI & Settings'),
          ],
        ),
      );
}
