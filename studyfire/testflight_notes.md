# StudyFire — TestFlight Build 1.0.0 (2)
## What's New in This Build

This build contains a significant round of bug fixes and new features across AI Study, Groups, Quest, Settings, and Word of the Day. Thank you for testing!

### Bug Fixes
- Cross-reference chips in AI Study now navigate to the correct passage in the Reader
- Passage chips in Word of the Day full explorer now navigate correctly
- Group leaderboard and comments now show members' real display names instead of "Member"
- Study level badge on the Quest screen now reflects your actual level (Beginner / Growing / Scholar)

### New Features

**Quest — Session Lengths**
- Spark (~90 sec), Short (~5 min), and Deep (~10 min) sessions now have distinct completion flows
- Short sessions offer a "Go Deeper" button to continue into AI Study
- Deep sessions add a "Add Journal Entry" option to capture your reflection immediately after

**Settings**
- You can now edit your display name directly in Settings — changes propagate to all groups you belong to
- New **Legal** section with Bible translation license attributions (KJV, NIV, CSB)

**Groups — major update**
- Share icon now opens the real iOS share sheet with your group name and invite code
- Feed items show relative timestamps ("2h ago", "Yesterday", "Jun 14")
- Comment and question author names now pull from your profile instead of your email
- New **Members** tab listing all members with name, streak, weekly XP, and a Leader badge for the creator
- Group creator can now **delete their own questions** from the Questions tab
- Group creator popup menu now includes:
  - **Edit Group** — update the group name, topic, and description
  - **Reading Plan** — set a schedule of passages and dates shown at the top of the Feed
  - **Pin Announcement** — pin a message to the top of the Feed visible to all members; can be edited or removed
- Group creator can **remove members** from the Members tab
- Group name and topic now appear in the app bar subtitle

---

## What to Test

### 1. Onboarding
- Sign up with email or Google
- Complete the onboarding flow and confirm your profile is created

### 2. Daily Quest (Home)
- Open the app and start today's Spark Session
- Read the passage and complete the quiz questions
- Verify XP is awarded and your streak increments
- If you complete a streak milestone (7, 30, 100 days), confirm the badge celebration appears
- Check the **study level badge** in the top-right of the Quest card — it should say Beginner, Growing, or Scholar based on your profile
- Try switching between **Spark**, **Short**, and **Deep** session lengths and confirm the completion screen changes accordingly

### 3. AI Study Screen
- After a Spark Session, tap "Go Deeper" to open AI Study
- Answer the reflection questions and confirm XP bursts appear
- Tap any **cross-reference chip** (e.g. "Romans 8:28") — it should navigate to that passage in the Reader
- Tap "Done" to confirm the completion screen works

### 4. Reader
- Browse to any book/chapter from the Reader tab
- Try switching Bible versions (KJV, NIV, CSB)
- Long-press a verse to share it

### 5. Word of the Day
- Tap the Word of the Day card on the Quest screen
- Confirm the Greek/Hebrew word, definition, and fun fact load correctly
- Tap "That's cool 🔥" and verify XP is awarded
- Tap "Share" and confirm the share sheet opens
- If you have premium: tap "Go deeper" and confirm the full explorer opens, and tap a passage chip to navigate to it

### 6. Quiz / Games
- Open the Games tab and start a quiz
- Complete a full quiz and confirm the result screen shows your score and XP

### 7. Groups
- Create a group and confirm it appears in your list
- Tap the **share icon** — confirm the iOS share sheet opens with your group name and invite code
- Invite another tester and confirm they can join; confirm their **real name** (not email) appears in the Members tab and Leaderboard
- Open the **Feed** tab — confirm activity items show author names and relative timestamps
- Open the **Questions** tab and post a question — confirm your display name appears as the author (not your email)
- Reply to a question — confirm your display name appears on the comment
- Post a question, then tap the **trash icon** on it to delete it — confirm the confirmation dialog appears and the question is removed
- Open the **Members** tab — confirm all members are listed with name, streak, weekly XP, and the creator has a "Leader" badge
- Open the **Leaderboard** tab — confirm member names appear correctly
- As group creator, tap the **⋮ menu** and test:
  - **Edit Group** — change the name and topic, save, and confirm the app bar updates immediately
  - **Reading Plan** — add a few passage/date rows, save, and confirm the plan appears at the top of the Feed
  - **Pin Announcement** — write a message, pin it, and confirm it appears pinned at the top of the Feed for all members; edit and remove it
- As group creator, go to the **Members** tab and tap the remove icon on a member — confirm the dialog appears and the member is removed
- Confirm the group creator does **not** see a "Leave Group" option
- Delete a group you created and confirm it disappears

### 8. Settings
- Update your **display name** and save — confirm it changes in groups you belong to
- Change your default Bible version and study level, tap Save — confirm changes persist
- Tap **Bible translation licenses** under Legal and confirm the NIV and CSB attribution notices appear
- Tap **Delete my account** — confirm the warning dialog appears (do not confirm unless intentional)

### 9. Journal
- Write a journal entry with a scripture reference
- Save it and confirm it appears in your journal list
- Tap "Export as PDF" in Settings and confirm you receive a PDF

### 10. Memory Verses
- Add a verse to Memory Verses
- Complete a review session

### 11. Notifications
- Go to Settings → Notifications
- Toggle streak reminders and morning focus companion on/off
- Confirm the settings persist when you close and reopen the app

---

## Known Limitations in This Build
- **Premium upgrade** button is a placeholder — RevenueCat is not yet connected. Use the free experience or ask Derek to enable premium on your account.
- **Word of the Day** requires today's cache to have been generated server-side. If it shows "Grace / charis" that is the fallback and is expected.
- Streak counts are live — studying today will increment your real streak.
- The `printing` and `flutter_local_notifications` plugins have not yet adopted Swift Package Manager; this is a third-party issue and does not affect functionality.

---

## How to Report Issues
Please note the screen you were on, what you tapped, and what happened (vs. what you expected). Screenshots are very helpful.
