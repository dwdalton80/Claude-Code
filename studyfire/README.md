# StudyFire 🔥

> Ignite your study. Every day.

A gamified, AI-assisted Bible study app for iOS (iPhone + iPad, iOS 16+), designed for evangelical Christians ages 16–30 with an ADD-first design philosophy.

## Stack

| Layer | Technology |
|---|---|
| **App** | Flutter (Dart) — iOS only, v1.0 |
| **Auth** | Firebase Authentication (Apple, Google, Email) |
| **Database** | Cloud Firestore |
| **Storage** | Firebase Storage |
| **Push Notifications** | Firebase Cloud Messaging |
| **Analytics** | Firebase Analytics |
| **AI** | Anthropic Claude API (Haiku 4.5) via Cloud Functions |
| **Bible Content** | API.Bible (KJV, CSB, NIV) + pre-loaded Firestore cache |
| **Payments** | RevenueCat (Monthly $3.99 / Annual $29.99 / Student $19.99) |
| **Spaced Repetition** | SM-2 algorithm in Cloud Functions |
| **Backend** | Firebase Cloud Functions (TypeScript/Node 20) |

## Project Structure

```
studyfire/
├── lib/                          # Flutter app
│   ├── main.dart                 # Entry point
│   ├── app.dart                  # App shell + router + auth guard
│   ├── core/
│   │   ├── theme/app_theme.dart  # Material 3 dark theme
│   │   ├── constants/            # Colors, typography, XP rewards, levels
│   │   └── services/             # Auth, Firestore, XP, Streak
│   ├── models/                   # UserProfile, JournalEntry, MemoryVerse, Group
│   ├── screens/
│   │   ├── onboarding/           # 5-step wizard
│   │   ├── quest/                # Home tab — mission card
│   │   ├── spark/                # 60-90 sec Spark Mode
│   │   ├── memory_verse/         # 5-stage SM-2 memory game
│   │   ├── journal/              # Sermon notes + AI debrief
│   │   └── profile/              # XP, levels, badges, books read
│   └── widgets/
│       ├── common/               # FlameCTAButton, ProgressBar
│       └── gamification/         # XpBurst, StreakDisplay
│
└── functions/                    # Firebase Cloud Functions
    └── src/
        ├── index.ts              # All function exports + schedulers
        ├── claude/
        │   ├── client.ts         # Anthropic client + model config
        │   ├── spark_questions.ts # Daily Spark question generation
        │   ├── ai_study.ts       # Full AI study session (per-passage)
        │   ├── quiz_generation.ts # Batch API quiz + Word of Day
        │   └── sermon_debrief.ts  # "Unpack This" journal AI
        ├── gamification/
        │   ├── sm2_algorithm.ts  # SM-2 spaced repetition math
        │   └── streak_manager.ts  # Streak logic, grace days
        └── notifications/
            └── push_notifications.ts  # FCM — streak, focus, digest
```

## Setup

### Prerequisites
- Flutter 3.16+ with iOS toolchain
- Firebase project with Blaze plan
- Anthropic API key
- RevenueCat account
- API.Bible key (for keyword search only — reading uses Firestore cache)

### 1. Flutter App

```bash
cd studyfire
flutter pub get

# Add your GoogleService-Info.plist to ios/Runner/
# Configure Firebase: flutterfire configure
```

### 2. Cloud Functions

```bash
cd functions
npm install

# Set environment variables
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set API_BIBLE_KEY

# Deploy
npm run build
firebase deploy --only functions
```

### 3. Firestore

```bash
# Deploy security rules and indexes
firebase deploy --only firestore
```

### 4. Bible Content Pre-load

Run the one-time data migration script to pre-load KJV/CSB/NIV into Firestore:

```bash
# (Script to be added — uses API.Bible to bulk-import bible/ collection)
node scripts/import-bible.js
```

## Cost Optimization

Following the spec's rules for minimal API spend:

1. **Full Bible in Firestore** — zero API.Bible calls for reading (only keyword search)
2. **Daily Spark pre-generated at 2am** — 1 Claude call per passage, cached for all free users
3. **Nightly Batch API** — quiz questions + Word of Day use Anthropic Batch API (50% savings)
4. **Free users: pull-to-refresh only** — no Firestore real-time listeners
5. **Batched XP writes** — all XP/streak/stats flushed once per session end
6. **Firebase billing alert** — $20/month threshold configured

## Gamification

- **XP System**: 5–50 XP per action, tracked in Firestore
- **Streaks**: Daily activity with grace day token (1/week), freeze (Premium)
- **Levels 1–7**: Seeker → Elder, with theme unlocks at each level
- **Badges**: XP milestones + memory verse milestones + streak milestones
- **Leaderboard**: Weekly XP reset within groups

## Freemium

| Feature | Free | Premium |
|---|---|---|
| Daily Reading + Spark | ✅ | ✅ |
| Bible versions | 1 | All 3 + comparison |
| AI study questions | 1/day | Unlimited |
| Memory Verses | 5/month | Unlimited + SM-2 |
| Topic Quiz | 3/week | Unlimited |
| AI Journal Debrief | 1/month | Unlimited |
| Greek/Hebrew Explorer | Preview only | Full |
| Streak Freeze | ❌ | ✅ (3 days) |
| PDF Export | ❌ | ✅ |

## Design Philosophy

**ADD-first**: Every screen has one job and one primary CTA. Sessions are 60–90 seconds by default. Progress is always visible. No guilt mechanics. No decision paralysis.

- Celebrate every win disproportionately (XP burst, confetti, haptics)
- All animations respect iOS Reduce Motion setting
- Max 2 push notifications per day
- Never show paywall mid-session

---

*StudyFire v1.0 — iOS only (iPhone + iPad, iOS 16+)*
