# StudyFire — Project Summary for Claude

## Overview
StudyFire is a gamified AI-assisted Bible study iOS app for Christians aged 16-30.
Built with Flutter/Dart, Firebase, Claude API (Anthropic), and RevenueCat.
Target audience: Christian young adults 16-30 who want a quick, engaging daily Bible study habit.

## Tech Stack
- **Frontend:** Flutter/Dart (iOS only)
- **Backend:** Firebase (Firestore, Auth, Storage, Cloud Functions, FCM)
- **AI:** Anthropic Claude API (claude-haiku-4-5 for all real-time calls)
- **Payments:** RevenueCat (not yet integrated — pre-launch task)
- **Repo:** https://github.com/dwdalton80/Claude-Code
- **Branch:** claude/new-session-fwgt22
- **Project path:** ~/Claude-Code/studyfire
- **Firebase project:** studyfire-11710
- **Bundle ID:** com.derekdalton.studyfire

## Session Transcripts
Previous session transcripts are stored at:
- /mnt/transcripts/ (accessible via bash_tool)
- journal.txt in the same directory lists all transcripts

## API Keys & Config
- API.Bible key: Fk1XmwXtjR-L_mUuV-Rg7
- Anthropic key: NEEDS ROTATION — was exposed in git (scripts/gen_quiz.js commit)
- RevenueCat project: proj36f4a898, entitlement: "StudyFire Pro"
- Service account key: ~/Claude-Code/studyfire/serviceAccountKey.json
  - WARNING: Expires frequently — regenerate from Firebase console when node scripts fail
- Functions env: ~/Claude-Code/studyfire/functions/.env
  - WARNING: Never commit this file — contains ANTHROPIC_API_KEY
  - Contains: ANTHROPIC_API_KEY and API_BIBLE_KEY

## App Structure
```
lib/
  main.dart                         # Firebase init, FCM setup, splash then app
  app.dart                          # Router, auth stream, providers, StudyFireApp
  screens/
    splash_screen.dart              # Animated splash (3.5s minimum via _minTimeElapsed)
    onboarding/onboarding_screen.dart
    quest/
      quest_screen.dart             # Daily Spark quest, Random Spark FAB
      spark_session_screen.dart     # 90-second study session
    reader/reader_screen.dart       # Bible reader, highlights, AI features
    journal/journal_screen.dart     # Notes + AI Debrief (Unpack This)
    quiz/quiz_screen.dart           # Games/Quiz with 10 topics
    profile/profile_screen.dart     # Profile, badges, settings sheet
    word_of_day/word_of_day_screen.dart
    memory_verse/memory_verse_screen.dart
    groups/groups_screen.dart       # Placeholder only
  core/
    services/
      firestore_service.dart
      auth_service.dart
      xp_service.dart               # accumulateXp() + flushSession() pattern
    constants/
      colors.dart
      typography.dart
      xp_rewards.dart               # XpRewards, XpMilestones, LevelThresholds
  models/
    user_profile.dart               # UserProfile with xp, streak, level fields
    memory_verse.dart
functions/src/
  index.ts                          # All Cloud Function exports
  claude/
    client.ts                       # getClaudeClient(), MODELS constant
    sermon_debrief.ts               # generateSermonDebrief(), suggestSermonTitle()
    ai_study.ts                     # generateAiStudy(), StudyContext interface
    quiz_generation.ts              # generateQuizBatch() uses Batch API
    spark_questions.ts              # generateSparkQuestion()
  notifications/
    push_notifications.ts           # sendFocusCompanion(), sendGroupDigests()
  gamification/
    streak_manager.ts               # recordStudyActivity(), replenishGraceDays()
```

## Firestore Structure
```
users/{uid}
  - xp, streak, level, longestStreak, totalStudyDays
  - preferences.focusCompanion (bool) morning verse notification opt-in
  - profile.xp, profile.streak, profile.level (nested under profile key)
  - NOTE: XP stored at both root and profile.xp levels, use profile.xp

highlights/{uid}/verses/{verseId}
  - verseId format: book_chapter_verseNum e.g. jhn_3_16
  - color: 'yellow' | 'green' | 'blue' | 'pink'
  - OLD BAD FORMAT: just numbers like "2","3" cause highlights everywhere, delete these

journal/{uid}/entries/{entryId}
  - title, content, scriptureRefs[], type, date, speaker

memoryVerses/{uid}/verses/{verseId}
badges/{uid}/earned/{badgeId}
  - earnedAt, name, xpAtEarning

bible/{version}/books/{bookId}/chapters/{chapterNum}/verses/{verseNum}
  - text, reference, verseNumber (NOT verseNum), bookId, chapterNumber

sparkcache/{date}/{passageId}/{version}
  - e.g. sparkcache/2026-06-13/rom_8_28/kjv

dailycache/{date}
  - quizQuestions: { 'Identity': [...], 'Prayer': [...], ... }
  - focusVerse: { text, reference }
  - generatedAt

studycache/{uid}/passages/{passageId}
  - Cached AI study (7 day TTL)

groups/{groupId}
  - memberIds[] array
```

## Cloud Functions (all us-central1, Node.js 20)

### Scheduled
- generateDailyCache — 2am daily — seeds sparkcache + dailycache
- generateDailySpark — scheduled spark generation
- sendMorningFocusCompanion — 9:30am daily — verse notification to opted-in users
- sendDailyGroupDigests — group activity summary
- weeklyGraceReplenish — streak grace days

### Callable (HTTPS)
- generateDebrief — AI study debrief — PREMIUM CHECK REMOVED, re-enable before launch
- askVerseQuestion — AI chat about a verse
- getWordStudy — Hebrew/Greek word study
- getAiStudy — full AI study session (cached 7 days)
- suggestTitle — auto-suggests note title
- registerFcmToken — saves FCM push tokens

### Firestore Triggers
- onStreakMilestone, onBadgeEarned, onMemoryVerseMastered

### Important: Cloud Function Data Access Pattern
Due to firebase-functions v4, use this pattern in callable functions:
```typescript
const raw = (request as any).data ?? (request as any).body?.data ?? request ?? {};
```

## Features Built

### Quest Screen
- Daily passage from sparkcache (not hardcoded)
- Real XP/streak from Firestore stream
- Random Spark FAB
- Compact card layout (Spacer replaced with SizedBox)
- First-time hint (SharedPreferences key: hint_spark_session)

### Spark Session
- 90-second timer
- AI question from Cloud Function
- XP via xpService.accumulateXp() then flushSession()
- Response saved to journal

### Bible Reader
- KJV, NIV, CSB
- Single tap = toggle focus/chrome mode
- Long press = highlight, Ask AI, Word of Day, Add to Journal, Copy, Share, Memory Verse
- Highlights stored as book_chapter_verseId
- Tap same highlight color to CLEAR it
- Highlights load on initState
- First-time hint (SharedPreferences key: hint_reader_longpress)
- Ask AI: chat interface, calls askVerseQuestion
- Word of Day: Hebrew/Greek, calls getWordStudy
- Add to Journal: pre-fills verse in NoteEditorScreen

### Notes/Journal
- Save, swipe left to delete
- AI Debrief (Unpack This): calls generateDebrief
- Add from Reader pre-fills verse
- Empty state explains AI Debrief

### Quiz/Games
- 10 topics with AI-generated questions from dailycache
- Falls back to hardcoded questions if unavailable
- Shuffled, topic-strict filtering
- Manual gen script: scripts/gen_quiz.js (DO NOT COMMIT)

### Profile
- Real user data, photo upload
- XP/streak real-time stream
- Badges from Firestore, tap to share
- Study Stats: HARDCODED (pre-launch task)
- Books Read: HARDCODED (pre-launch task)

### Settings Sheet
- Notifications (opens iOS Settings)
- Privacy Policy
- Morning Verse toggle (preferences.focusCompanion via set+merge)
- Export Journal as PDF (printing package)
- Sign Out

### Splash Screen
- Animated flame, 3.5s minimum
- iOS launch screen dark (#080808)
- Known: brief main screen flash on some cold launches

### Contextual Hints (one-time, dismissible)
- Reader: hint_reader_longpress
- Quest: hint_spark_session
- Notes: empty state card

### Other Features
- Greek/Hebrew Explorer: unlocked (re-gate before launch)
- Focus Companion: toggle in settings
- PDF Export: journal via printing package
- Shareable Badges: tap earned badge to share
- Clear Highlights: tap same color

## XP System
- Complete Spark: 15 XP
- Share verse: 5 XP
- IMPORTANT: must call flushSession() after accumulateXp() or XP is lost
- Levels: Seeker(0), Disciple(500), Scribe(1500), Scholar(3500), Teacher(7000), Sage(12000), Elder(20000)
- Badges at: 100, 500, 1500, 3500, 7000, 12000 XP

## Bible Data
- Imported: KJV, NIV, CSB via API.Bible
- Path: bible/{version}/books/{bookId}/chapters/{chapterNum}/verses/{verseNum}
- Field: verseNumber (NOT verseNum)
- Book IDs: 3-letter lowercase (jhn, rom, gen, psa, 1jn, 1co, etc.)

## Known Bugs & Issues

### Active
- Streak shows 0 — needs consecutive daily sessions to verify
- Study Stats hardcoded — pre-launch fix needed
- Books Read hardcoded — pre-launch fix needed
- Splash brief flash — main screen shows fraction of second before splash
- Old highlight keys (just numbers) may still exist in Firestore — delete manually

### Warnings (non-critical)
- Node.js 20 deprecated, upgrade to 22 before Oct 2026
- firebase-functions 4.6.0, upgrade to 5.1.0+
- functions.config() deprecated, migrate to params before March 2027
- flutter_local_notifications and printing don't support Swift Package Manager

### Security
- Anthropic API key needs rotation (exposed in commit f018196)
- generateDebrief auth check removed — re-enable before launch
- getAiStudy premium check — re-enable before launch

## Pre-Launch Checklist

### Monetization
- [ ] RevenueCat SDK integration (purchases_flutter in pubspec, not configured)
- [ ] Implement paywall UI
- [ ] Re-enable premium check in generateDebrief
- [ ] Re-enable premium check in getAiStudy
- [ ] Re-gate Greek/Hebrew Explorer (word_of_day_screen.dart ~line 120)

### Security
- [ ] Rotate Anthropic API key
- [ ] Update functions/.env with new key
- [ ] Confirm scripts/gen_quiz.js in .gitignore

### Data
- [ ] Wire Study Stats to real Firestore data
- [ ] Wire Books Read to reading history
- [ ] Verify streak logic over multiple days

### Content
- [ ] Larger quiz question bank (20+ per topic)
- [ ] Seed sparkcache for coming week
- [ ] Verify focusVerse in dailycache

### Infrastructure
- [ ] Upgrade Node.js 20 to 22
- [ ] Upgrade firebase-functions 4.6.0 to 5.1.0+
- [ ] Migrate functions.config() to params

### App Store
- [ ] Screenshots all device sizes
- [ ] App description and keywords
- [ ] Age rating questionnaire
- [ ] Complete App Store Connect listing

### Testing
- [ ] Full TestFlight run with checklist
- [ ] Test streak over multiple days
- [ ] Test scheduled Cloud Functions (2am, 9:30am)
- [ ] Test push notifications

## TestFlight Test Checklist
1. Sign in / sign out
2. Complete Spark → verify XP increases
3. Long press verse → highlight → navigate away → verify persists
4. Long press verse → Ask AI → ask question → verify response
5. Long press verse → Word of Day → verify Hebrew/Greek appears
6. Long press verse → Add to Journal → verify verse pre-filled
7. Write note (20+ chars) → Unpack This → verify AI Debrief
8. Games → 3 different topics → verify different questions
9. Profile → gear → Morning Verse toggle → verify saves
10. Profile → gear → Export PDF → verify share sheet
11. Profile → Badges → tap earned badge → verify share
12. Profile photo → pick image → verify updates
13. Random Spark FAB → verify opens Reader
14. Clear highlight: long press highlighted verse → same color → verify removed
15. Study Stats — note which are real vs hardcoded (known issue)
16. Books Read — note which are real vs hardcoded (known issue)

## Common Commands
```bash
# Run app
cd ~/Claude-Code/studyfire && flutter run

# Deploy all functions
firebase deploy --only functions

# Deploy single function
firebase deploy --only functions:generateDebrief

# View function logs
firebase functions:log --only generateDebrief 2>&1 | tail -10

# Build for TestFlight
flutter build ipa --release

# Generate quiz questions manually (from studyfire directory)
node scripts/gen_quiz.js

# Check today's dailycache
node -e "
const admin = require('./scripts/node_modules/firebase-admin');
admin.initializeApp({ credential: admin.credential.cert(require('./serviceAccountKey.json')) });
const today = new Date().toISOString().split('T')[0];
admin.firestore().collection('dailycache').doc(today).get().then(d => {
  console.log(Object.keys(d.data() || {}));
  process.exit();
});
"
```

## Key Dependencies
- purchases_flutter — RevenueCat (in pubspec, not configured)
- printing + pdf — PDF export
- share_plus — sharing badges and verses
- image_picker + firebase_storage — profile photo
- shared_preferences — contextual hints
- cloud_functions — callable Cloud Functions
- firebase_messaging — FCM push notifications
