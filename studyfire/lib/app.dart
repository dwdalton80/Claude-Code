import 'package:flutter/material.dart';
import 'dart:async';
import 'screens/splash_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/colors.dart';
import 'core/constants/typography.dart';
import 'core/services/firestore_service.dart';
import 'core/walkthrough/walkthrough_service.dart';
import 'models/user_profile.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/quest/quest_screen.dart';
import 'screens/reader/reader_screen.dart';
import 'screens/quiz/quiz_screen.dart'; // QuizHomeScreen, QuizScreen
import 'screens/ai_study/ai_study_screen.dart';
import 'screens/word_of_day/word_of_day_screen.dart';
import 'screens/journal/journal_screen.dart';
import 'screens/groups/groups_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'widgets/walkthrough/walkthrough_scope.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final authStreamProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final currentProfileProvider = StreamProvider.autoDispose<UserProfile?>((ref) {
  final user = ref.watch(authStreamProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return FirestoreService().watchProfile(user.uid).map(
    (p) => p,
  );
});

// ── Notification deep-link support ────────────────────────────────────────────

/// Set by main.dart when a notification tap should navigate somewhere.
/// GoRouter listens to this and redirects on the next frame.
final pendingNotificationRoute = ValueNotifier<String?>(null);

/// Convert FCM message data to a GoRouter path.
String notificationRouteFor(Map<String, dynamic> data) {
  final type = data['type'] as String? ?? '';
  switch (type) {
    case 'group_digest':
    case 'prayer_request':
    case 'prayer_answered':
      return '/groups';
    case 'streak_reminder':
    case 'focus_companion':
    default:
      return '/quest';
  }
}

// ── Router ────────────────────────────────────────────────────────────────────

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStreamProvider);

  // Create a refresh notifier from the auth stream
  final authNotifier = _AuthNotifier(FirebaseAuth.instance.authStateChanges());
  ref.onDispose(authNotifier.dispose);

  return GoRouter(
    initialLocation: '/quest',
    refreshListenable: Listenable.merge([authNotifier, pendingNotificationRoute]),
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

      // Notification deep link — consume and navigate
      final pending = pendingNotificationRoute.value;
      if (pending != null && isAuthenticated) {
        pendingNotificationRoute.value = null;
        return pending;
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
            builder: (context, state) {
              final user = FirebaseAuth.instance.currentUser;
              final extra = state.extra as Map<String, dynamic>?;
              return _ReaderWrapper(
                uid: user?.uid ?? '',
                // Null means "no explicit destination — restore last position"
                book: extra?['book'] as String?,
                chapter: extra?['chapter'] as int?,
                startVerse: extra?['startVerse'] as int?,
                explicitVersion: extra?['version'] as String?,
                isPremium: extra?['isPremium'] as bool? ?? false,
              );
            },
          ),
          GoRoute(
            path: '/games',
            builder: (context, state) {
              final user = FirebaseAuth.instance.currentUser;
              return QuizHomeScreen(uid: user?.uid ?? '');
            },
            routes: [
              GoRoute(
                path: 'quiz/:topic',
                builder: (context, state) {
                  final user = FirebaseAuth.instance.currentUser;
                  return QuizScreen(
                    uid: user?.uid ?? '',
                    topicTag: state.pathParameters['topic'],
                  );
                },
              ),
              GoRoute(
                path: 'word-of-day',
                builder: (context, state) {
                  final user = FirebaseAuth.instance.currentUser;
                  final extra = state.extra as Map<String, dynamic>?;
                  return WordOfDayScreen(
                    uid: user?.uid ?? '',
                    isPremium: extra?['isPremium'] as bool? ?? false,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/notes',
            builder: (_, __) => const JournalScreen(),
          ),
          GoRoute(
            path: '/groups',
            builder: (_, __) => const _GroupsRouteWrapper(),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (context, state) {
                  final extra = state.extra as Map<String, dynamic>?;
                  final profile = extra?['profile'] as UserProfile?;
                  if (profile == null) {
                    return const _ProfileLoadingWrapper();
                  }
                  return SettingsScreen(profile: profile);
                },
              ),
            ],
          ),
        ],
      ),
      // Deep-link: open AI study from anywhere
      GoRoute(
        path: '/ai-study',
        builder: (context, state) {
          final user = FirebaseAuth.instance.currentUser;
          final extra = state.extra as Map<String, dynamic>?;
          return AiStudyScreen(
            passage: extra?['passage'] as String? ?? '',
            reference: extra?['reference'] as String? ?? '',
            version: extra?['version'] as String? ?? 'kjv',
            uid: user?.uid ?? '',
            passageId: extra?['passageId'] as String?,
          );
        },
      ),
    ],
  );
});

// ── App ───────────────────────────────────────────────────────────────────────

class StudyFireApp extends ConsumerWidget {
  const StudyFireApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStreamProvider);
    final router = ref.watch(routerProvider);

    if (authState.isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: SplashScreen(),
      );
    }

    return MaterialApp.router(
      title: 'StudyFire',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: child!,
      ),
    );
  }
}

// ── App Shell (Bottom Nav) ────────────────────────────────────────────────────

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    (path: '/quest',   label: 'Quest',   icon: Icons.flash_on),
    (path: '/groups',  label: 'Groups',  icon: Icons.group),
    (path: '/games',   label: 'Games',   icon: Icons.psychology),
    (path: '/reader',  label: 'Bible',   icon: Icons.menu_book),
    (path: '/profile', label: 'Profile', icon: Icons.person),
  ];

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _walkthroughTriggered = false;

  @override
  void initState() {
    super.initState();
    // Slight delay so the first screen finishes rendering before we
    // try to read GlobalKey positions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_walkthroughTriggered && mounted) {
        _walkthroughTriggered = true;
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) {
            ref.read(walkthroughProvider.notifier).maybeStart();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex =
        AppShell._tabs.indexWhere((t) => location.startsWith(t.path));

    return Scaffold(
      body: WalkthroughScope(child: widget.child),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex < 0 ? 0 : currentIndex,
        onTap: (i) => context.go(AppShell._tabs[i].path),
        items: AppShell._tabs
            .map((t) => BottomNavigationBarItem(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

// ── Groups Route Wrapper ──────────────────────────────────────────────────────

class _GroupsRouteWrapper extends ConsumerWidget {
  const _GroupsRouteWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final user = FirebaseAuth.instance.currentUser;
    return profileAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => GroupsScreen(uid: user?.uid ?? '', isPremium: false),
      data: (p) => GroupsScreen(uid: user?.uid ?? '', isPremium: p?.isPremium ?? false),
    );
  }
}

// ── Profile Loading Wrapper ───────────────────────────────────────────────────

class _ProfileLoadingWrapper extends ConsumerWidget {
  const _ProfileLoadingWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Center(child: Text('Error loading profile')),
      ),
      data: (profile) {
        if (profile == null) {
          return const Scaffold(
            backgroundColor: AppColors.deepSlate,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return SettingsScreen(profile: profile);
      },
    );
  }
}


// ── Reader Wrapper — resolves default Bible version + last reading position ────

class _ReaderWrapper extends ConsumerStatefulWidget {
  final String uid;
  final String? book;       // null = restore last position
  final int? chapter;       // null = restore last position
  final int? startVerse;
  final String? explicitVersion;
  final bool isPremium;

  const _ReaderWrapper({
    required this.uid,
    this.book,
    this.chapter,
    this.startVerse,
    this.explicitVersion,
    this.isPremium = false,
  });

  @override
  ConsumerState<_ReaderWrapper> createState() => _ReaderWrapperState();
}

class _ReaderWrapperState extends ConsumerState<_ReaderWrapper> {
  String? _resolvedBook;
  int? _resolvedChapter;
  bool _positionLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.book != null) {
      // Explicit destination — no prefs needed
      _resolvedBook = widget.book;
      _resolvedChapter = widget.chapter;
      _positionLoaded = true;
    } else {
      _loadLastPosition();
    }
  }

  Future<void> _loadLastPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final lastBook = prefs.getString('reader_last_book');
    final lastChapter = prefs.getInt('reader_last_chapter');
    if (mounted) {
      setState(() {
        _resolvedBook = lastBook ?? 'jhn';
        _resolvedChapter = lastChapter ?? 3;
        _positionLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_positionLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profileAsync = ref.watch(currentProfileProvider);
    final version = widget.explicitVersion
        ?? profileAsync.valueOrNull?.defaultVersion.name
        ?? 'kjv';
    final isPremium = widget.isPremium || (profileAsync.valueOrNull?.isPremium ?? false);

    return ReaderScreen(
      uid: widget.uid,
      book: _resolvedBook!,
      chapter: _resolvedChapter!,
      startVerse: widget.startVerse,
      version: version,
      isPremium: isPremium,
    );
  }
}

class _AuthNotifier extends ChangeNotifier {
  late final StreamSubscription<dynamic> _sub;
  _AuthNotifier(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
