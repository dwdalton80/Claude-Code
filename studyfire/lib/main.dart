import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';
import 'screens/splash_screen.dart';

// Top-level FCM background handler (required by firebase_messaging)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Request notification permissions (iOS)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  // Show notifications as banners when the app is in the foreground (iOS)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // ── Notification tap routing ───────────────────────────────────────────────

  // Cold start: app was terminated when notification was tapped
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    // Store route — will be consumed once the router is ready
    pendingNotificationRoute.value = notificationRouteFor(initialMessage.data);
  }

  // Background: app was backgrounded, user tapped notification
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    pendingNotificationRoute.value = notificationRouteFor(message.data);
  });

  // Register FCM token with backend on sign-in
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    await Future.delayed(const Duration(seconds: 1));
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('fcmTokens')
            .doc(token)
            .set({
          'token': token,
          'registeredAt': FieldValue.serverTimestamp(),
          'platform': 'ios',
        });
        debugPrint('FCM token saved directly to Firestore');
      }
    } catch (e) {
      debugPrint('FCM registration error: ' + e.toString());
    }
  });

  // Refresh FCM token when it rotates
  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'registeredAt': FieldValue.serverTimestamp(),
        'platform': 'ios',
      });
    } catch (_) {}
  });

  // Show splash immediately while app initializes
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashScreen(),
  ));

  // Wait for minimum splash time + Firebase init
  await Future.delayed(const Duration(milliseconds: 3000));

  runApp(
    const ProviderScope(
      child: StudyFireApp(),
    ),
  );
}
