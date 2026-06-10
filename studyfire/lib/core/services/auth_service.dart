import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_profile.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;

    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await _createUserIfNew(result.user!);
    return result.user;
  }

  Future<User?> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );

    final result = await _auth.signInWithCredential(oauthCredential);

    // Apple only returns name on first sign-in
    final displayName = appleCredential.givenName != null
        ? '${appleCredential.givenName} ${appleCredential.familyName ?? ''}'.trim()
        : null;

    await _createUserIfNew(result.user!, displayName: displayName);
    return result.user;
  }

  Future<User?> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _createUserIfNew(result.user!);
    return result.user;
  }

  Future<User?> createAccountWithEmail(String email, String password, String name) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await result.user!.updateDisplayName(name);
    await _createUserIfNew(result.user!, displayName: name);
    return result.user;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> _createUserIfNew(User user, {String? displayName}) async {
    final ref = _firestore.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      final profile = UserProfile(
        uid: user.uid,
        name: displayName ?? user.displayName ?? 'Friend',
        email: user.email ?? '',
        avatarUrl: user.photoURL,
        level: 1,
        xp: 0,
        streak: 0,
        longestStreak: 0,
        totalStudyDays: 0,
        studyLevel: StudyLevel.beginner,
        defaultVersion: BibleVersion.niv,
        lastActiveDate: DateTime.now(),
        hasGraceDayAvailable: true,
        streakFreezeCount: 0,
        isPremium: false,
      );

      await ref.set({
        'profile': profile.toFirestore(),
        'preferences': {
          'version': 'niv',
          'font': 'lora',
          'theme': 'dark',
          'reminderTime': null,
          'verseChunking': true,
          'reducedMotion': false,
        },
        'topicTags': {
          'selected': [],
          'mastery': {},
        },
        'stats': {
          'totalVerses': 0,
          'wordsExplored': 0,
          'questionsAnswered': 0,
          'journalEntries': 0,
          'versesMemorized': 0,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }
}
