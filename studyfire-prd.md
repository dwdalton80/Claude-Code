# Product Requirements Document
## StudyFire — Game-Style Bible Study App
**Version:** 1.0
**Platform:** Apple devices only (iPhone + iPad, iOS 16+)
**Stack:** FlutterFlow · Firebase · Claude API · API.Bible
**Status:** Pre-Development · PRD Draft

> **Standalone app.** StudyFire is an independent product — separate FlutterFlow project, Firebase project, App Store listing, RevenueCat account, API.Bible key, and Claude API Cloud Functions deployment. No shared backend or codebase with any other project.

---

## 1. Vision & Purpose

**StudyFire** is a mobile Bible study app designed for evangelical believers who want to go beyond surface-level reading. It transforms personal Bible study into a gamified, AI-assisted experience — making deep engagement with Scripture feel rewarding, progressive, and addictive in the best possible way.

The core belief: serious study doesn't have to feel like homework. StudyFire borrows the motivational loops of great games — streaks, XP, levels, badges, challenges — and channels them toward genuine theological growth.

StudyFire is **ADD-first by design**. Every screen, session length, and interaction is built around the reality that many users struggle with sustained focus, task initiation, and working memory. This isn't an accessibility afterthought — it's a core design constraint that makes the app better for everyone.

**Tagline:** *Ignite your study. Every day.*

---

## 2. Target Audience

| Segment | Description |
|---|---|
| **Primary** | Evangelical Christians, ages 16–30, who want to engage Scripture but bounce off traditional study tools |
| **Secondary** | Small group leaders, youth pastors, and college ministry leaders |
| **Tertiary** | New believers wanting structured, guided Bible study with immediate wins |

**User motivation:** Users want to understand Scripture more deeply but traditional study tools feel like homework. They respond to progress, identity, and personalized discovery. The primary audience skews younger and a significant portion has ADD/ADHD — they've historically failed with dense study apps not because they lack interest, but because those apps have poor task initiation design, no immediate reward signals, and sessions that feel open-ended and overwhelming.

---

## 2b. ADD/ADHD Design Principles

These principles apply globally across every screen and interaction in StudyFire.

| Principle | Implementation |
|---|---|
| **Quest-first home screen** | Home is a mission card, not a dashboard. One passage, one time estimate, one XP reward, one button. |
| **Spark Mode default** | Default session is 60–90 seconds (one verse + one question). Longer sessions are opt-in, never default. |
| **Reward before the action** | Show XP earned *before* the user starts ("Complete this to earn 40 XP"). Deliver with full-screen celebration. |
| **Reduce task initiation friction** | One clear CTA per screen. The next action is always obvious. No decision paralysis. |
| **Chunk everything** | No reading block longer than 5 verses without a natural pause point or interaction opportunity. |
| **Immediate feedback loops** | Every action produces an instant visual/haptic reward — disproportionately big relative to the action. |
| **Protect focus mode** | Reader enters distraction-free mode by default; all UI chrome hides after 2 seconds. |
| **Progress always visible** | Users always know where they are, what's next, and how close they are to a reward. |
| **No guilt mechanics** | Missed days surface encouragement, not shame. Streaks broken gently. Grace is the brand voice. |
| **Hyperfocus support** | When a user is in flow, let them go deep — no forced stopping, no pop-up interruptions mid-session. |
| **Reduce working memory load** | AI summaries, auto-saved highlights, and session recaps mean users never have to remember what they did. |
| **Sensory options** | Font size, contrast, background color, and motion intensity are all user-controlled. |
| **Remove all decisions** | "Surprise Me" / Random Spark button eliminates choice paralysis entirely. |
| **Identity-driven progression** | Levels change what the user *looks like* in the app — new themes, icons, badges. Character grows visibly. |

---

## 3. Core Value Propositions

1. **Gamified growth** — XP, streaks, levels, badges, and daily challenges keep users coming back
2. **AI-powered insight** — Claude generates personalized study questions, commentary, and devotional prompts contextual to the passage
3. **Original language access** — Greek/Hebrew word exploration made approachable for non-scholars
4. **Multi-version comparison** — Side-by-side Bible translation views (KJV, CSB, NIV)
5. **Sermon & study journal** — Capture notes anywhere, anytime — in a service, a small group, or personal study
6. **Progress over time** — Visual journey through Scripture with bookmarks, highlights, and journal entries

---

## 4. Business Model

### Freemium (v1)

| Feature | Free | Premium |
|---|---|---|
| Daily Reading + Spark Mode (KJV, CSB, or NIV) | ✅ | ✅ |
| Single Bible version (user's choice) | ✅ | ✅ |
| Basic AI study questions (1/day, pre-cached) | ✅ | ✅ |
| Streaks & XP system | ✅ | ✅ |
| Memory Verse Game (5 verses/month) | ✅ | ✅ |
| Topic Quiz (3/week) | ✅ | ✅ |
| Group Study (create + join groups) | ✅ | ✅ |
| Focus Companion notifications | ✅ | ✅ |
| Multi-version comparison | ❌ | ✅ |
| Unlimited AI questions & prompts | ❌ | ✅ |
| Word of the Day + full Greek/Hebrew explorer | ❌ | ✅ |
| Unlimited Memory Verse + Spaced Repetition | ❌ | ✅ |
| Sermon notes journal + AI Debrief (1 free/month) | ✅ | ✅ |
| Streak freeze | ❌ | ✅ |
| Downloadable study notes | ❌ | ✅ |

**Premium Pricing (revised):**
- Monthly: $3.99/month
- Annual: $29.99/year *(best value — ~$2.50/month)*
- Student Plan: $19.99/year *(requires .edu email verification)*

> **Paywall philosophy:** The paywall is never surfaced mid-engagement. Premium features are clearly labeled *before* a user taps them — never a locked door after they've already committed. Freemium tier is genuinely useful on its own; premium deepens rather than gates the core experience.

---

## 5. Screens & Feature Specs

### 5.1 Onboarding (Streamlined 5-Step Wizard)

**Goal:** Get users to their first win as fast as possible. Collect only what's essential upfront — everything else is gathered progressively over the first week through in-app prompts.

**Steps:**
1. **Welcome** — Brand intro, value prop ("Ignite your study. Every day.") + estimated time: "Takes about 90 seconds"
2. **Bible version** — KJV / CSB / NIV (large tap cards, auto-advance on selection)
3. **One goal** — Pick just one: "I want to read more" / "I want to understand deeper" / "I want to memorize Scripture" / "I want to apply what I hear on Sundays" (sets initial home screen emphasis)
4. **Reminder time** — What time should we nudge you? (Pre-set options: Morning · Lunch · Evening · No thanks)
5. **Account creation** — Sign in with Apple · Google · Email

**Progressive collection (Days 1–7 via in-app prompts):**
- Day 2: "Pick topics you care about" (Topic tags for quiz personalization)
- Day 3: "What's your Bible background?" (Adjusts AI complexity)
- Day 5: "Start a reading plan?" (Reading plan selection)
- Day 7: "You're on a 7-day streak 🔥 — want to go Premium?"

**Design note:** Step count visible ("2 of 5"). Auto-advance after every selection — no "Next" button. Progress bar fills with satisfying animation. Total time to first session: under 2 minutes.

**ADD considerations:**
- One decision per screen, no compound choices
- Large tap cards (full-width), no small checkboxes or radio buttons
- Estimated time shown on welcome screen
- Skip available from step 3 onward
- First session begins immediately after account creation — no intermediate screens

---

### 5.2 Home / Quest Screen

**Goal:** Not a dashboard — a mission screen. One job: get the user started. Everything is organized around today's quest, not a feed of options.

**Primary zone — Today's Quest card (80% of screen):**
- Passage name + verse range
- "⚡ 40 XP" displayed prominently *before* the user taps — reward visible upfront
- Estimated time badge: **"~3 min"** (default Spark Mode)
- Session length toggle: **Spark (90s) · Short (5 min) · Deep (10 min)**
- One giant CTA button: **"Start Quest"**
- Difficulty badge: Beginner / Intermediate / Rich

**Secondary zone (below the fold, scrollable):**
- Streak counter — flame icon + current streak
- XP bar — today's progress toward daily goal
- "Continue where you left off" — if mid-session exists
- Recent badge earned

**Random Spark button:**
- Persistent floating button (bottom right, flame icon)
- One tap assigns a random verse, quiz, or memory verse game — weighted toward the user's selected topic tags; fully random until tags are set
- Copy: "Surprise me 🔥"
- Earns standard XP; counts toward streak

**XP sources (per session):**
| Action | XP | Notes |
|---|---|---|
| Open app (daily) | 5 XP | Shown on launch |
| Complete Spark session | 15 XP | 90-second default |
| Complete short session | 25 XP | 5-minute |
| Complete deep session | 40 XP | 10-minute |
| Answer a study question | 10 XP | |
| Add a journal entry | 15 XP | |
| Word of the Day tap | 10 XP | |
| 7-day streak | 50 XP bonus | Full-screen celebration |
| Share a verse | 5 XP | |
| Mark application point complete | 20 XP | |

**ADD considerations:**
- Quest card dominates the screen — impossible to miss, impossible to be paralyzed by choice
- XP shown *before* starting — motivates initiation
- Random Spark eliminates decision paralysis entirely
- No infinite scroll in primary zone
- Haptic feedback on streak tap
- "Where was I?" banner if mid-session exists from yesterday

---

### 5.2b Spark Mode

**Goal:** The minimum viable study session. 60–90 seconds. One verse, one question, one win. Keeps the streak alive on hard days and builds the habit before deepening it.

**Flow:**
1. One verse displayed (large, centered, beautiful typography)
2. Read it — tap "I've read it" to continue (5 XP)
3. One AI-generated question appears (observation level — simple, never intimidating)
4. User taps or types a short answer
5. **Full-screen celebration:** XP burst animation + haptic + sound + "Quest complete!" — feels disproportionately rewarding
6. Streak updated. Done. *(A completed Spark session counts as a full streak day.)*

**Design rules for Spark Mode:**
- No navigation chrome during the session — full screen, immersive
- Question is pre-generated and cached so there's zero loading wait
- Answer field accepts anything — there's no wrong answer, just engagement
- Celebration screen shows today's streak prominently and XP earned
- "Go deeper?" button on celebration screen — one tap to extend into a full session (never forced)

---

### 5.3 Bible Reader (DailyReader)

**Goal:** Core reading experience — clean, distraction-free, with study tools one tap away. Also serves as a full Bible lookup tool for users who want to find a specific verse or passage on demand.

**Verse Search & Lookup:**
- **Search bar** — Accessible via magnifying glass icon in the reader toolbar; also reachable from the home Quest Screen
- **Reference lookup** — Type any reference (e.g. "John 3:16", "Romans 8", "Psalm 23") and jump directly to it
- **Keyword search** — Full-text search across the entire Bible in the user's selected version; results show verse reference + snippet
- **Book/chapter browser** — Tap to browse by OT/NT → book → chapter if the user prefers navigating visually rather than typing
- **Recent** — Last 10 verses or passages visited, shown below the search bar before the user types anything
- **Saved verses** — Starred verses pinned at the top of the lookup screen for instant re-access
- **Search result actions** — Tap any result to jump to it in the reader; long-press to Copy, Share, Add to Journal, or Add to Memory Verse queue

**Search ADD considerations:**
- Search opens as a full-screen bottom sheet — focused, no navigation away from where the user was
- Recent verses visible immediately on open — zero typing required for common lookups
- Reference autocomplete as user types (e.g. typing "joh" surfaces John, 1 John, 2 John, 3 John instantly)
- Returns to exact reading position if user navigates away and comes back
- "Back to my reading" button always visible at the top of the lookup sheet

**Features:**
- Full Bible text via API.Bible (version switching in-session)
- **Highlight system** — 4 color options (yellow, green, blue, pink), stored in Firebase
- **Inline notes** — Tap any verse to add a personal note
- **Verse action menu** (long press):
  - Copy · Share · Add to Journal · Word of the Day · Ask AI · Add to Memory Verse queue
- **Multi-version toggle** — Slide up bottom sheet to compare 2 translations side-by-side
- **Reading progress indicator** — % of book complete, chapter position
- **Font controls** — Size and typeface preference (stored per user)
- **Audio mode** (v2) — Text-to-speech playback

**ADD considerations:**
- **Focus Mode** — All UI chrome auto-hides 2 seconds after reading begins; tap to reveal
- **Verse chunking** — Displays 3–5 verses at a time by default for all users (reduces overwhelm); opt-out available in Focus & Accessibility settings
- **Reading guide line** — Optional horizontal highlight line that follows the user's tap position
- **Session progress bar** — Subtle bar at top of screen showing session progress (how far you've come, not a countdown); fills toward completion
- **Auto-bookmark** — Position saved every 10 seconds; no manual saving needed
- **"That's enough for today" prompt** — At session end, affirming completion message + XP reward, never pushes to read more
- **Reduced motion option** — All animations can be disabled in settings for sensory sensitivity
- **High contrast mode** — Sepia + larger text preset for easier tracking

**Gamification:**
- First time in a new book → "New Territory" badge
- Complete a full book → "Book Completed" badge + XP burst animation
- Session end → **Full-screen celebration** (XP earned, streak updated, "That's enough for today" — never pushes to read more)
- "Go deeper?" optional prompt on completion screen — one tap to continue, never default

---

### 5.4 AI Study Mode

**Goal:** Turn passive reading into active learning through AI-generated questions and insights.

**Triggered by:** Completing a reading session, or tapping "Study This Passage" from reader

**AI Features (Claude API via Firebase Cloud Function):**

| Feature | Description |
|---|---|
| **Study Questions** | 3–5 questions ranging from observation → interpretation → application |
| **Context Brief** | 1-paragraph historical/cultural background for the passage |
| **Cross-Reference Suggestions** | 2–3 thematically linked passages |
| **Character Spotlight** | If the passage involves a named person, brief profile |
| **Theological Theme Tag** | 2–3 keyword themes (e.g., "Grace," "Covenant," "Redemption") |
| **Devotional Prompt** | A personal reflection prompt tied to the passage |

**ADD considerations:**
- Questions revealed **one at a time** — not all shown at once (reduces overwhelm)
- Answer input is a simple text field with no formatting pressure; bullet points optional
- "Skip this question" always available — no guilt, just move on
- **TL;DR mode** — Context brief can be collapsed to a single bolded sentence for users who want just the hook
- AI responses use **plain language by default** (adjustable to scholar mode)
- Study mode has a defined end — "You finished today's study!" screen with XP summary, not an open-ended experience

**XP for engagement:**
- Answer all 3 base questions: 30 XP
- Unlock and answer bonus questions: 15 XP each (Premium)

**Prompt architecture:**
- System prompt includes: user's faith background level, selected study goals, passage text, version, topic tag mastery levels, and recent quiz history — questions are skewed toward topics where the user has shown gaps or strong interest
- Response format: structured JSON → parsed into card UI
- All Scripture references in AI output rendered as tappable chips linking to the Bible reader bottom sheet

---

### 5.5 Word of the Day + Greek/Hebrew Explorer

**Goal:** Make original language study feel like discovering a fascinating secret, not doing academic homework. The entry point is a single, surfaced word — not a tool the user has to seek out.

**Word of the Day (free):**
Every session surfaces one interesting word from the day's passage as a fun-fact card — automatically chosen by Claude for theological or linguistic interest. Presented as discovery, not study:

> *"The word translated 'love' in John 3:16 is **agape** (ἀγάπη) — not the affection between friends, but a love that chooses to act regardless of feeling. It appears 320 times in the New Testament."*

- One tap to see the word card
- "That's cool 🔥" reaction earns 10 XP
- Share button to send to a friend
- Saved automatically to Word History

**Full Greek/Hebrew Explorer (Premium):**
For users who want to go deeper from the Word of the Day card, or via the verse action menu.

- **Word card:**
  - Original word (Greek/Hebrew) + transliteration + pronunciation
  - Strongs number
  - Definition in plain English
  - Usage frequency in Bible
  - Other passages using the same word (tappable links back to reader)
- **Word History** — All previously explored words saved to profile
- **Scholar mode** (Premium) — Expanded parsing details (verb tense, case, stem)

**Gamification:**
- Tap Word of the Day: 10 XP
- Explore 10 words in full explorer → "Word Nerd" badge
- Explore words across 5 books → "Linguist" badge

---

### 5.6 Sermon Notes Journal

**Goal:** A simple, frictionless place to capture notes wherever you are — in a service, a small group, a podcast, or personal study. No church account required, no calendar sync, no institutional tie-in. Just you and your notes.

**Modes:**
- **Sermon Notes** — Structured capture with title, date, speaker, scriptures, and free-form notes
- **Personal Study** — Passage, date, highlights summary, free-form notes, AI-generated summary toggle
- **Reading Plan Notes** — Auto-attached to reading plan entries

**Note Header Fields (Sermon Notes mode):**

| Field | Details |
|---|---|
| **Sermon Title** | Text input — required. AI auto-suggests a title if left blank on save. |
| **Date** | Date picker — defaults to today. Editable for past or future notes. |
| **Speaker** | Text input — optional. |
| **Scriptures** | Tag-style input — see full spec below. |

**Scripture Tagging & Linking:**

The scriptures field lets users attach one or more Bible references to a note. Each reference becomes a tappable chip that opens directly in the Bible reader.

- **Adding a reference:** Type a reference (e.g. "John 3:16") into the scripture input field — autocomplete suggests matching references as the user types. Tap to confirm and add as a chip.
- **Multiple references:** Unlimited scripture chips per note (e.g. a sermon may cover 4–5 passages). Chips appear as a horizontal scrollable row beneath the header.
- **Tap to open:** Tapping any scripture chip opens that passage in the Bible reader in a bottom sheet — the note stays open in the background. User can read, highlight, or copy the verse and return to the note in one tap.
- **Long-press chip options:** Remove reference · Copy reference text · Open in full reader
- **Inline scripture links in body text:** While typing notes, users can type "@" to trigger reference autocomplete inline — e.g. typing "@Romans 8:28" inserts a tappable scripture link directly inside the note body. Tapping it opens that verse in the same bottom sheet reader.
- **AI awareness:** All tagged scripture chips and inline links are passed to Claude as context when "Unpack This" is triggered — improving the quality and specificity of application points and discussion questions.

**Features:**
- Rich text formatting (bold, italic, bullet lists)
- Attach highlighted verses from reader
- Search by keyword, passage, date, speaker, or sermon title
- Export to PDF (Premium) — scripture chips render as formatted references in the export
- Share note as image card (styled, branded) — title and date displayed prominently

**AI Sermon Debrief** *(1 free use/month for free users · Unlimited for Premium — Claude API via Cloud Function)*

After saving any note, users can tap **"Unpack This"** to trigger an AI-assisted debrief. Claude reads the user's raw notes, title, date, and all linked scriptures and generates:

| Output | Description |
|---|---|
| **Real-Life Application Points** | 3–5 practical, specific ways to apply the message this week — grounded in what the user actually wrote, not generic |
| **Discussion Questions** | 5 questions suitable for a small group, Bible study, or personal reflection — ranging from personal to theological |
| **One Big Idea** | A single distilled sentence capturing the core message (useful for sharing or journaling) |
| **Follow-Up Scripture** | 2–3 passages to read this week that extend the theme — rendered as tappable chips |
| **Personal Challenge** | A specific, actionable step tailored to what the user wrote — e.g., if they noted "forgiveness," the challenge might be "Write a letter to one person you need to forgive (you don't have to send it)" |

**Prompt architecture:**
- Input: user's raw notes + sermon title + date + all linked scripture references + speaker (if provided)
- System prompt instructs Claude to be pastoral, practical, and specific — not generic devotional filler
- Response format: structured JSON → rendered as expandable cards
- All Scripture references in AI output (Follow-Up Scripture, Personal Challenge, Discussion Questions) render as tappable chips linking to the Bible reader bottom sheet
- If notes are sparse (< 50 words), Claude prompts with 2 quick questions before generating ("What was one thing that stood out?" / "Was there anything that challenged you?")

**XP for engagement:**
- Generate debrief: 15 XP
- Mark an application point as "Done this week": 20 XP each
- Share a discussion question: 5 XP
- Add 3+ scripture references to a single note: 10 XP bonus ("Well-Referenced" micro-reward)

**ADD considerations:**
- **Voice-to-text** input supported natively — capture thoughts in real time without typing
- **Quick capture mode** — One-tap to open a blank note; title, date, and scriptures can be filled in later
- **AI auto-title** — If user leaves title blank, Claude suggests one from note content on save
- **Date defaults to today** — one less thing to think about; easy to change if needed
- **Scripture autocomplete** — Reduces typing friction; "@" shortcut works mid-sentence
- **Structured templates** with pre-filled prompts (e.g., "What stood out? What does this mean for me? What will I do?") — reduces blank page paralysis
- Notes auto-save every keystroke; no "Save" button needed
- Application points displayed as a **checklist** — tapping one marks it complete and awards XP

---

### 5.7 Progress & Profile

**Goal:** Show users how far they've come and what's ahead — the "character sheet" of their study journey.

**Sections:**
- **Level & XP** — Current level name (e.g., "Seeker" → "Disciple" → "Scholar" → "Sage") + XP progress bar
- **Streak stats** — Current / longest / total study days
- **Books read** — Visual Bible map showing completed/in-progress books (OT/NT color-coded)
- **Badge collection** — Full grid of earned and locked badges; tap any earned badge to view detail and share
- **Study stats** — Total verses read, words explored, questions answered, journal entries
- **Reading plans** — Active and completed plans
- **Settings shortcut**

**Level progression — Identity & Unlockables:**

Levels don't just change a number — they visibly change the user's character and app experience. Each level unlocks something tangible.

| Level | Name | XP Required | Unlocks |
|---|---|---|---|
| 1 | Seeker | 0 | Default flame theme |
| 2 | Disciple | 500 | Gold accent profile badge + new profile frame |
| 3 | Scribe | 1,500 | Parchment theme + quill icon set |
| 4 | Scholar | 3,500 | Deep Indigo theme + scholar profile frame |
| 5 | Teacher | 7,000 | Crimson theme + ability to share study notes publicly |
| 6 | Sage | 12,000 | Obsidian theme + animated profile badge |
| 7 | Elder | 20,000 | Platinum theme + "Elder" crown badge |

**Level-up moment:** Full-screen cinematic animation + haptic burst + level name reveal. The copy uses the level's identity: *"A Scribe would know this passage by heart. You're becoming one."*

---

---

### 5.8 Group Study

**Goal:** A Strava-style social layer that adds accountability, community, and friendly competition to personal Bible study. Groups are private, invite-only spaces where members study a shared topic together, share notes and badges, and engage with each other's questions.

**Access:** Dedicated tab in bottom navigation (Group icon). Free for all users — no Premium required.

---

**Creating a Group:**

| Field | Details |
|---|---|
| **Group name** | Text input — required |
| **Topic** | Creator picks a study topic from the tag list, or enters a custom topic (e.g. "Anxiety & Fear", "Book of James", "Forgiveness") |
| **Description** | Optional — short bio of what the group is studying and why |
| **Duration** | Optional — set an end date for a focused study sprint (e.g. 4 weeks) or leave open-ended |
| **Cover image** | Optional — pick from a curated set of Scripture-themed illustrations |

**Invite flow:**
- Creator taps "Invite Members" → generates a unique invite link
- Link shared via iOS Share Sheet — iMessage, Instagram, WhatsApp, email, etc.
- Recipient taps link → deep links into StudyFire → joins group instantly (or prompted to download app first if not installed)
- Creator can revoke or regenerate the invite link at any time

---

**Group Feed:**

The heart of the group — a shared activity feed ordered by recency. Members see each other's activity as it happens.

| Feed Item | Description |
|---|---|
| **Shared Note** | Member shares a sermon note or study note from their journal — title, date, and excerpt visible; tap to read full note |
| **Earned Badge** | Member earns a badge → auto-posted to feed with the badge card — bragging rights, one-tap to congratulate |
| **Shared Question** | Member posts a study question to the group — can be from AI Study Mode or written manually |
| **Streak Milestone** | Member hits a streak milestone (7, 30, 100 days) → auto-posted to feed |
| **Memory Verse Mastered** | Member masters a verse → posted to feed with the verse text |

**Feed interactions:**
- **🔥 React** — One-tap fire emoji reaction on any feed item (like Strava's Kudos)
- **💬 Comment** — Reply to any feed item; threaded comments; all group members can comment
- **Share** — Re-share any feed item outside the group via iOS Share Sheet

**ADD considerations for feed:**
- Feed is reverse chronological — newest first, no algorithmic reordering
- Reactions are one tap — no typing required to encourage someone
- Comment composer is minimal — plain text, no formatting pressure
- Notification for reactions/comments on your posts — max 1 digest notification per day per group

---

**Group Questions:**

Members can post study questions to the group for discussion. Questions are the primary discussion unit — separate from the feed.

- **Post a question** — Write manually or share directly from AI Study Mode ("Post to Group" button on any AI-generated question)
- **Question card** — Question text + posted by + date + scripture reference (if attached)
- **Comments** — All members can reply; threaded; reactions on comments
- **Resolved** — Creator or poster can mark a question as resolved (collapses thread, keeps it accessible)
- **AI Study Mode integration** — When a group has an active topic, AI Study Mode surfaces a "Group Question" option after generating questions — one tap to share to the group

---

**Group Leaderboard:**

A friendly competition tab within each group showing member standings.

| Stat | Description |
|---|---|
| **XP This Week** | XP earned in the current 7-day period |
| **Current Streak** | Active daily streak |
| **Badges Earned** | Total badges earned since joining the group |
| **Verses Memorized** | Memory verse count |

- Leaderboard resets weekly (XP column only — streaks and badges are cumulative)
- Top 3 members highlighted with flame icons (🥇🥈🥉)
- Your own position always visible even if outside top 3

---

**Group Management (Creator controls):**

- Remove a member
- Transfer ownership to another member
- Edit group name, topic, description
- Regenerate or revoke invite link
- Archive group (freezes feed, members can still view history)
- Delete group

**Member controls:**
- Leave group
- Mute notifications for a specific group
- Control what activity auto-posts to the group feed (badges, streaks, memory verses — each toggleable)

---

**Notifications for Groups:**
- New comment on your post: 1 digest per day per group (not per comment)
- New question posted to group: 1 per day
- Leaderboard update (weekly): Sunday evening summary
- All group notifications respect the global 2/day cap — group digests count toward the limit

---

**Data Model additions:**
```
groups/{groupId}
  ├── info (name, topic, description, duration, creatorUid, createdAt, inviteCode)
  ├── members/{uid} (joinedAt, role: creator/member, autoPostSettings)
  └── feed/{feedItemId} (type, authorUid, content, timestamp, reactions, commentCount)

groupComments/{groupId}/{feedItemId}/{commentId}
  └── (authorUid, text, timestamp, reactions)

groupQuestions/{groupId}/{questionId}
  └── (authorUid, question, scriptureRef, resolved, timestamp)

groupQuestionComments/{groupId}/{questionId}/{commentId}
  └── (authorUid, text, timestamp, reactions)
```

**XP for group activity:**
| Action | XP |
|---|---|
| Share a note to group | 10 XP |
| Post a question to group | 10 XP |
| Comment on a group question | 5 XP |
| Receive 5 reactions on a post | 15 XP bonus |
| 7-day group participation streak | 25 XP bonus |

**ADD considerations:**
- One-tap reactions (🔥) mean engagement requires zero friction
- Auto-posting of badges and streaks means members stay visible without having to remember to share
- Weekly leaderboard summary is a single notification — not a daily pressure point
- "Mute group" option prevents notification overload for users in multiple groups

---

### 5.9 Settings

**Goal:** Personalization controls without friction.

**Sections:**
- **Account** — Profile info, subscription status, manage plan
- **Reading preferences** — Default version, font size, reading speed calibration
- **Focus & Accessibility** — Session length default, verse chunking on/off, reading guide line, reduced motion, high contrast, font weight
- **Notifications** — Daily reminder time, streak reminder, challenge alerts; frequency controls to prevent notification fatigue
- **Study level** — Adjust AI response complexity
- **Theme** — Light / Dark / Sepia / Auto
- **Data** — Export highlights, export journal, clear cache
- **About** — App version, privacy policy, terms, feedback link

---

## 6. Gamification System Design

### Badge Philosophy
Badges in StudyFire are earned through XP milestones and activity achievements. Every badge is **shareable** — users can share any earned badge as a beautifully designed image card to social media, iMessage, or anywhere via the iOS Share Sheet. Sharing a badge is a natural word-of-mouth moment and a key growth mechanic.

**Badge sharing spec:**
- Each badge has a unique branded image card — dark background, StudyFire flame logo, badge icon, badge name, and a one-line description (e.g. *"I just memorized 10 Bible verses on StudyFire 🔥"*)
- Share button appears on the badge detail screen and on the earn celebration screen
- Sharing earns 5 XP
- Cards are generated dynamically and sized for Instagram Stories, Twitter/X, and iMessage

### Badge Categories

| Category | Badges | XP Milestone Trigger |
|---|---|---|
| **XP Milestones** | Spark (100 XP), On Fire (500 XP), Burning Bright (1,500 XP), Unquenchable (3,500 XP), Flame Keeper (7,000 XP), Eternal Flame (12,000 XP) | Awarded automatically at each XP threshold |
| **Streaks** | 7 Days, 30 Days, 100 Days, 365 Days | Streak count |
| **Reading** | First Chapter, Book Completed, NT Complete, Bible Complete | Reading progress |
| **Study** | First AI Question, 50 Questions, Deep Diver (all 5 questions in one session) | Study actions |
| **Language** | First Word of the Day, Word Nerd (10 words), Linguist (5 books) | Word explorer |
| **Journal** | First Entry, 10 Entries, Sermon Faithful (10 sermon notes) | Journal actions |
| **Quiz** | First Quiz, Topic Master, 7-Day Quiz Streak, Perfect Score | Quiz activity |
| **Memory Verse** | First Verse Memorized, 10 Verses, 50 Verses, Full Chapter, Memory Champion | Memory game |
| **Group Study** | Group Founder (create first group), Team Player (join a group), Discussion Leader (10 comments), Group Streak (7-day group participation) | Group activity |
| **Special** | Christmas Reading (Dec 25), Easter Week, New Year New Plan, Comeback Kid | Dates + re-engagement |

**XP Milestone badges** are the primary shareable achievement — every major XP threshold produces a celebration-worthy moment with a unique badge designed to be posted. They also align with the level system so users hit a badge and a level unlock at the same time at key thresholds.

### Badge Data Model Addition
```
badges/{uid}/{badgeId}
  └── (earnedAt, shared, shareCount)
```

### Streak Protection
- Users can "protect" a streak with a **Grace Day token** (1 free/week, purchasable)
- Notification sent at 8pm if daily reading not complete
- **Missed day messaging:** Never shame-based. Copy reads: "Yesterday slipped by — your streak is safe. Pick up where you left off."
- **Streak freeze** (Premium): Pause streak for up to 3 days (travel, illness, hard seasons)
- **Comeback badge:** Awarded for returning after a 7+ day gap — rewards re-engagement, not just perfection

### Notification Strategy

**Max 2 push notifications per day.** This audience is overstimulated. Notification fatigue causes uninstalls.

| Notification | Timing | Notes |
|---|---|---|
| **Focus Companion** | Mid-morning (9–11am) | A single verse + one-line reflection. No action required. No app open needed. Pure value, zero friction. |
| **Streak Reminder** | 8pm (if no session today) | Rotates through 15 different messages — never the same copy twice in a row. Mix of funny, warm, and Scripture-based. |

**Focus Companion philosophy:** This is not a reminder — it's a gift. It delivers spiritual nourishment to users who may not open the app that day. It keeps the relationship alive passively and drives re-engagement over time. **Opt-in during onboarding** (Step 4 — reminder time) so users consciously choose it and expectations are set from day one. Sample copy rotation:

- *"'Be still and know that I am God.' — Psalm 46:10. Take 10 seconds. Breathe."*
- *"Quick thought: grace isn't earned. It just is. 🔥"*
- *"Today's word: **Shalom**. Not just peace — wholeness. Everything as it should be."*
- *"Someone needed to hear this today: you are not behind. Open StudyFire when you're ready."*

**Streak reminder copy rotation (sample):**
- *"Your streak is waiting. 90 seconds. That's all. 🔥"*
- *"Don't let today be the day the flame goes out."*
- *"Romans 8 isn't going to read itself. (Okay, technically it will — tap here.)"*
- *"You've got a 12-day streak. Don't let tonight be the night you find out what happens when it breaks."*

---

### 6.1 Personalized Topic Quiz

**Goal:** Use AI to direct users toward studies that match their real spiritual interests and current life needs — making the path to deeper study feel personally relevant, not arbitrary.

**Access:** Home Dashboard ("Take Today's Quiz") or dedicated Games tab

**How it works:**

1. **Topic Discovery** — During onboarding (and editable anytime in settings), users select interest/need tags from a curated list:

   **v1 tags (10):** *Anxiety & fear · Identity · Purpose & calling · Forgiveness · Prayer · Relationships · Doubt & faith · The Holy Spirit · Suffering · Spiritual growth*

   *(Full list of 18 available post-launch — expand based on engagement data)*

2. **Quiz Generation** — Claude generates a 5-question quiz daily (or on-demand) tailored to the user's selected topics + reading history. Question types:
   - Multiple choice (4 options)
   - True/False with explanation
   - Fill-in-the-blank verse completion
   - "Which passage best describes…" matching

3. **Study Recommendation Engine** — After each quiz, Claude analyzes answers and surfaces a targeted study:
   - Questions answered correctly → affirm the topic and suggest a deeper dive
   - Questions answered incorrectly or skipped → flag as a gap and recommend a focused study plan or passage series
   - Example output: *"You're strong on Grace but had some gaps around Forgiveness. Here's a 3-day study on Matthew 18 we think you'll love."*

4. **Topic Progress Map** *(Profile screen)* — Visual grid of all topic tags showing mastery level (Exploring / Growing / Strong) based on quiz history

**Quiz mechanics:**
| Detail | Spec |
|---|---|
| Questions per session | 5 (ADD-friendly — defined end) |
| Time limit | Optional — can be enabled by user |
| Reveal style | One question at a time; answer before seeing next |
| Feedback | Immediate after each answer — correct/wrong + a 1-sentence explanation |
| Retry | Can retake with fresh questions anytime |

**XP:**
- Complete a quiz: 25 XP
- Perfect score: 50 XP bonus
- 7-day quiz streak: 75 XP bonus
- Follow a quiz recommendation to a study: 10 XP

**ADD considerations:**
- 5 questions maximum — always a defined finish line
- Immediate answer feedback prevents rumination
- No timer by default — pressure is opt-in
- Study recommendations are one tap to start — no navigation required

---

### 6.2 Memory Verse Game

**Goal:** Make Scripture memorization feel like a game, not a chore — using progressive reveal mechanics to build genuine retention over time.

**Access:** Home Dashboard ("Today's Verse") or dedicated Games tab

**Memorization Flow — Progressive Mastery Levels:**

Each verse moves through 5 stages. Users must pass each stage before advancing:

| Stage | Name | Mechanic | Description |
|---|---|---|---|
| 1 | **Read It** | Full verse visible | User reads the verse 3 times; taps "I've read it" to advance |
| 2 | **Fill the Gaps** | Every 4th word blacked out | Tap a blacked-out word to reveal; builds pattern recognition |
| 3 | **Half Gone** | Every other word blacked out | Type the missing words into blank fields |
| 4 | **Almost There** | Only first letter of each word shown | Type full words using first-letter hints |
| 5 | **Write It** | Blank screen, no hints | Type the full verse from memory; fuzzy match scoring allows 1–2 character errors per word |

**Scoring per stage:**
| Stage | XP on Pass | Bonus XP (no errors) |
|---|---|---|
| Read It | 5 XP | — |
| Fill the Gaps | 10 XP | +5 XP |
| Half Gone | 15 XP | +10 XP |
| Almost There | 20 XP | +15 XP |
| Write It | 30 XP | +20 XP |

**Verse Bank:**
- **Daily Verse** — One new verse each day (auto-assigned, tied to reading plan or topic)
- **Custom Verse** — User picks any verse from the Bible reader to add to memory queue
- **Classic 100** — A curated list of 100 foundational verses (John 3:16, Psalm 23:1, Phil 4:13, etc.)

**Review Mode — Spaced Repetition (SM-2 algorithm):**
- Verses already mastered cycle back for review on an SM-2 spaced repetition schedule — intervals adjust based on performance (easier recalls push the next review further out; failed recalls reset sooner)
- Review prompts a quick Stage 5 "Write It" test — pass keeps the streak; fail drops back to Stage 4
- **"Vault"** — All mastered verses stored here; user can browse, search, and re-test any time

**Passage Mode** *(Premium):*
- String multiple consecutive verses into a single memory challenge (e.g., John 1:1–5 or Psalm 23)
- Passage unlocked after all individual verses in the set are at Stage 5
- Completing a full passage awards a **Chapter Badge** + major XP burst

**Leaderboard** *(v2):*
- Friend challenges — challenge a friend to memorize the same verse and compare scores
- Global leaderboard — most verses memorized across all StudyFire users

**ADD considerations:**
- Each stage session < 3 minutes — always a clear stopping point
- Fuzzy match on "Write It" stage (1–2 character errors per word accepted) — reduces frustration from typos
- Satisfying haptic + animation on each correct answer
- "Come back tomorrow" prompt after daily verse is mastered — no pressure to do more
- Spaced repetition handled automatically — user never has to manage a review schedule

---

## 7. Technical Architecture

### Stack
| Layer | Technology |
|---|---|
| Frontend | FlutterFlow (iPhone + iPad, iOS 16+) |
| Auth | Firebase Authentication (Email + Google) |
| Database | Firestore (user data, highlights, notes, XP) |
| Storage | Firebase Storage (journal exports, profile images) |
| Bible Content | API.Bible — KJV, CSB, NIV (5,000 calls/month free tier) |
| AI | Claude API (Anthropic) via Firebase Cloud Functions |
| Notifications | Firebase Cloud Messaging |
| Analytics | Firebase Analytics |
| Payments | RevenueCat (in-app subscriptions) |

### Firebase Data Model (key collections)

```
users/{uid}
  ├── profile (name, email, level, xp, streak, studyLevel)
  ├── preferences (version, font, theme, reminderTime)
  ├── topicTags (selected interest/need tags, mastery levels)
  └── stats (totalVerses, wordsExplored, questionsAnswered, journalEntries, versesMemorized)

highlights/{uid}/{verseId}
  └── (color, note, timestamp)

journal/{uid}/{entryId}
  └── (type, passage, content, aiSummary, aiApplicationPoints, aiDiscussionQuestions, tags, timestamp)

badges/{uid}/{badgeId}
  └── (earnedAt)

readingPlans/{uid}/{planId}
  └── (planName, startDate, progress, currentDay)

quizHistory/{uid}/{quizId}
  └── (topicTags, questions, answers, score, studyRecommendation, timestamp)

memoryVerses/{uid}/{verseId}
  └── (reference, text, currentStage, mastered, lastReviewed, nextReviewDate, attemptHistory)

bible/{version}/{bookId}/{chapterId}/{verseId}
  └── (text, reference) — pre-loaded full Bible; eliminates API.Bible calls

sparkcache/{date}/{passageId}/{version}
  └── (question, verseText, reference) — pre-generated daily Spark question; shared across all free users

dailycache/{date}
  └── (wordOfDay, quizQuestions, readingPlanQuestions) — nightly Batch API pre-generation
```

### Claude API Cloud Function
- Triggered per study session
- Inputs: passage text, version, user study level, study goals
- Outputs: structured JSON (questions, context, cross-refs, themes, prompt)
- **Free user AI calls reduced to 1/day** (down from 3) — Spark Mode question only; unlimited for Premium
- Response cached per passage per day — same passage never generates twice in one day regardless of user count

### AI Cost Optimization Strategy

**Pre-cached Spark Mode question (highest impact):**
- A single Cloud Function runs each morning and generates the day's Spark question for each scheduled daily passage
- Stored in Firestore at `sparkcache/{date}/{passageId}/{version}`
- Every free user who opens Spark Mode receives the same cached response — cost is **1 Claude call per passage per day**, not 1 per user
- Reduces free user AI cost from `freeUsers × costPerCall` to `~30 × costPerCall` per month

**Anthropic Batch API for non-realtime generation:**
- Daily quiz questions, Word of the Day, reading plan study questions, and topic quiz sets are all pre-generated nightly via the Batch API
- Batch API is 50% cheaper than standard API calls across all models
- Scheduled Cloud Function runs at 2am daily; results stored in Firestore for instant retrieval
- Only Sermon Debrief and on-demand AI Study Mode questions use real-time API calls

**Model selection — Claude Haiku 4.5:**
- All StudyFire AI features use Claude Haiku 4.5 ($1.00 input / $5.00 output per million tokens)
- Haiku 4.5 is sufficient quality for study questions, quiz generation, sermon debrief, and Word of the Day
- Do not upgrade to Sonnet 4.6 ($3/$15) unless user feedback clearly demands better quality — it triples AI cost with marginal user-facing benefit

**Firestore write batching:**
- XP updates, streak increments, and session stats are batched and written once per session end
- Reduces writes from dozens per session to 1–2 per session

**Free user Firestore listeners:**
- Free users use pull-to-refresh on Group Study feeds — no real-time listeners
- Real-time listeners (live group feed updates) are Premium-only
- Prevents read amplification from Group Study at scale

**Firebase billing protection:**
- Hard monthly budget cap set in Google Cloud Billing
- Alert at $20/month, hard cap at $50/month during development and early launch
- Prevents runaway costs from bugs or unexpected traffic spikes

### API.Bible Call Management

**Pre-load full Bible into Firestore (eliminates API.Bible calls almost entirely):**
- One-time setup script fetches all 31,102 verses × 3 versions (KJV, CSB, NIV) = ~93,306 documents
- Stored in Firestore at `bible/{version}/{bookId}/{chapterId}/{verseId}`
- One-time write cost: ~$0.17 (93K writes × $0.18/100K)
- After pre-load, API.Bible is only called for keyword search (not available in Firestore) and new version additions
- Estimated API.Bible calls drop from thousands/month to under 500/month — well within the 5,000 free tier

**Remaining API.Bible usage:**
- Full-text keyword search (no Firestore equivalent) — API.Bible search endpoint
- Version additions post-launch
- Monitor usage in Firebase Analytics; alert at 80% of 5,000 monthly limit

**Reading plan pre-fetch:**
- Next 3 days of reading plan passages pre-fetched from Firestore cache on app open over WiFi
- Stored locally for offline access

**Offline fallback:**
- Last 7 days of readings cached locally on device
- Reader works fully offline for cached content

---

## 8. Design System

### Tone
Reverent but alive. Serious depth without academic stuffiness. The visual language should feel premium, focused, and energetic — like a well-worn study Bible crossed with a great game. Copy speaks to the user's *identity*, not just their actions. "A Scribe would know this." "You're becoming someone who knows this Word." The app believes in the user before they believe in themselves.

### Voice & Copy Rules
- Active, present tense: "You're on a 7-day streak" not "Streak: 7 days"
- Identity language at every level: refer to the user by their level title in contextual moments
- Notification copy rotates — never the same message twice in a row
- Failure states are never shame: "Slipped yesterday. Still here. That matters."
- Celebrate small wins disproportionately — a 90-second Spark session deserves a real celebration

### Color Palette (proposed)
| Role | Color | Hex |
|---|---|---|
| Primary | Deep Indigo | `#2D3A8C` |
| Accent | Warm Gold | `#C9942A` |
| Success / XP | Emerald | `#2E7D5E` |
| Background (light) | Warm White | `#FAFAF7` |
| Background (dark) | Deep Slate | `#1A1D2E` |
| Text primary | Near Black | `#1C1C1E` |
| Text secondary | Mid Gray | `#6E6E73` |

### Typography
- **Display / Headings:** Lora (serif — evokes Scripture heritage)
- **Body / UI:** Inter (clean, readable at small sizes)
- **Greek/Hebrew words:** Noto Serif (full Unicode language support)

### Iconography
- Line icons with 1.5px stroke weight
- Scripture-adjacent iconography: scroll, quill, flame (streak), key, crown
- No generic SaaS iconography

---

## 9. Non-Functional Requirements

| Requirement | Target |
|---|---|
| Cold launch time | < 2.5 seconds |
| Bible text load time | < 1 second |
| AI response time | < 4 seconds (with loading state) |
| Offline access | Last 7 days of readings cached locally |
| Accessibility | WCAG AA — font scaling, VoiceOver support |
| Reduced motion | All animations respect iOS Reduce Motion setting |
| Session interruption recovery | Resume exactly where left off, every time |
| Auto-save | User data saved continuously — nothing lost from unexpected exits |
| Notification limits | Max 2 push notifications/day; user controls all |
| Data privacy | No third-party ad SDKs; Firebase data stays within user account |
| App size | < 60MB initial download |

---

## 10. v1 Scope vs. Future Roadmap

### v1 (Apple Launch — iPhone + iPad)
- ✅ Streamlined 5-step onboarding + progressive collection (Days 1–7)
- ✅ Quest Screen (mission-first home, not dashboard)
- ✅ Spark Mode (60–90 second micro-session)
- ✅ Random Spark button
- ✅ Full-screen session celebration (XP burst, haptic, sound)
- ✅ Daily Reader with highlights & notes
- ✅ Multi-version comparison
- ✅ AI study questions (Claude API)
- ✅ Word of the Day (free) + full Greek/Hebrew explorer (Premium)
- ✅ Sermon notes journal + AI Debrief
- ✅ Personalized Topic Quiz
- ✅ Memory Verse Game (Stages 1–5 + Review Mode)
- ✅ Identity-driven level system with unlockable themes + icons
- ✅ Group Study (invite-only groups, shared feed, questions + comments, leaderboard)
- ✅ Focus Companion notification (daily verse, no action required)
- ✅ Streak reminder with rotating copy (15+ variants)
- ✅ Profile / progress screen
- ✅ Freemium with RevenueCat (new pricing: $3.99/mo, $29.99/yr, Student $19.99/yr)
- ✅ Sign in with Apple (Firebase Auth)
- ✅ iOS native dictation for journal voice-to-text
- ✅ Haptic feedback via iOS Taptic Engine
- ✅ iOS Share Sheet integration (share verse, share note)
- ✅ Dynamic Type support (respects iOS accessibility font sizing)

### v2 (Post-Launch)
- 🔲 Android
- 🔲 Apple Watch — streak glance + daily verse complication
- 🔲 Home screen widget — streak + verse of day + memory verse prompt
- 🔲 iPad split-view — Bible reader + journal side by side
- 🔲 Reading plan community challenges
- 🔲 Group Study — public/searchable groups directory (v2 expansion of v1 private groups)
- 🔲 Audio Bible playback
- 🔲 AI sermon prep mode (for pastors/leaders)
- 🔲 Memory Verse — Passage Mode (multi-verse chains)
- 🔲 Memory Verse — Friend challenges + global leaderboard
- 🔲 Topic Quiz — expand to full 18 tags based on engagement data
- 🔲 Alternate app icons unlockable by level

---

## 11. Success Metrics

| Metric | 30-Day Target | 90-Day Target |
|---|---|---|
| Downloads | 500 | 2,500 |
| D7 Retention | 40% | 45% |
| D30 Retention | 20% | 25% |
| Free → Premium conversion | 5% | 8% |
| Avg. session length | 6 min | 8 min |
| Daily streak (avg. active user) | 5 days | 12 days |
| AI questions answered/user/week | 5 | 10 |

---

## 12. Open Questions

- [x] ~~API.Bible translations~~ — confirmed: KJV, CSB, NIV for v1. 5,000 API calls/month on free tier. **Note:** Cache aggressively — store fetched passages in Firestore to avoid repeat API calls. Monitor usage closely; upgrade API tier if call volume approaches limit post-launch.
- [ ] Should Strongs data come from API.Bible or a separate lexicon API?
- [x] ~~Grace Day token~~ — confirmed: 1 free per week (auto-replenishes). Streak Freeze (3-day pause) remains Premium-only.
- [x] ~~Inline Scripture references in AI responses~~ — confirmed: all Scripture references in AI-generated content render as tappable links opening in the Bible reader bottom sheet.
- [ ] RevenueCat integration approach in FlutterFlow — custom action or native widget?
- [x] ~~Session length timer~~ — confirmed: subtle progress bar (shows how far you've come, not how much time is left).
- [x] ~~Sermon Debrief access~~ — confirmed: 1 free use per month for free users; unlimited for Premium.
- [x] ~~Sermon Debrief sparse notes~~ — confirmed: if notes < 50 words, prompt with 2 quick follow-up questions before generating.
- [x] ~~Topic Quiz tags~~ — confirmed: curated starter set of 10 tags for v1; expand post-launch based on engagement data.
- [x] ~~Topic Quiz shared intelligence~~ — confirmed: quiz history feeds into AI Study Mode question generation. Both systems share topic tag data and mastery levels.
- [x] ~~Memory Verse fuzzy match~~ — confirmed: 1–2 character errors per word accepted on "Write It" stage.
- [x] ~~Memory Verse spaced repetition~~ — confirmed: SM-2 algorithm.
- [x] ~~Student plan verification~~ — confirmed: .edu email verification required.
- [x] ~~Level unlockables — app icons~~ — confirmed: pushed to v2. v1 unlocks in-app profile themes and badges only.

**Resolved:**
- [x] ~~Voice-to-text~~ — native iOS dictation for v1
- [x] ~~Focus & Accessibility placement~~ — surfaced in progressive onboarding
- [x] ~~Spark session streak~~ — counts as a full streak day
- [x] ~~Verse chunking~~ — on by default; opt-out in settings
- [x] ~~Random Spark~~ — weighted toward user's topic tags; fully random until tags are set
- [x] ~~Focus Companion~~ — opt-in during onboarding Step 4 (reminder time screen)
- [x] ~~Memory Verse Passage Mode~~ — confirmed v2

---

*PRD authored for StudyFire v1.0 · June 2026*
