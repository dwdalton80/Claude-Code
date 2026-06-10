import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/theme/app_theme.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/quest/quest_screen.dart';
import 'screens/spark/spark_screen.dart';
import 'screens/memory_verse/memory_verse_screen.dart';
import 'screens/journal/journal_screen.dart';
import 'screens/profile/profile_screen.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final authStreamProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

// ── Router ────────────────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStreamProvider);

  return GoRouter(
    initialLocation: '/quest',
    redirect: (context, state) {
      final isAuthenticated = authState.valueOrNull != null;
      final isLoading = authState.isLoading;

      if (isLoading) return null;

      if (!isAuthenticated && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      if (isAuthenticated && state.matchedLocation == '/onboarding') {
        return '/quest';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/quest',
            builder: (_, __) => const QuestScreen(),
          ),
          GoRoute(
            path: '/reader',
            builder: (_, __) => const _PlaceholderScreen(title: 'Bible Reader'),
          ),
          GoRoute(
            path: '/games',
            builder: (_, __) => const _PlaceholderScreen(title: 'Games'),
          ),
          GoRoute(
            path: '/notes',
            builder: (_, __) => const JournalScreen(),
          ),
          GoRoute(
            path: '/groups',
            builder: (_, __) => const _PlaceholderScreen(title: 'Groups'),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});

// ── App ───────────────────────────────────────────────────────────────────────

class StudyFireApp extends ConsumerWidget {
  const StudyFireApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'StudyFire',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ── App Shell (Bottom Nav) ────────────────────────────────────────────────────

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/quest', label: 'Quest', icon: Icons.flash_on),
    (path: '/reader', label: 'Reader', icon: Icons.menu_book),
    (path: '/games', label: 'Games', icon: Icons.psychology),
    (path: '/notes', label: 'Notes', icon: Icons.sticky_note_2),
    (path: '/groups', label: 'Groups', icon: Icons.group),
    (path: '/profile', label: 'Profile', icon: Icons.person),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _tabs.indexWhere((t) => location.startsWith(t.path));

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex < 0 ? 0 : currentIndex,
        onTap: (i) => context.go(_tabs[i].path),
        items: _tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          title,
          style: AppTypography.displaySmall,
        ),
      ),
    );
  }
}
