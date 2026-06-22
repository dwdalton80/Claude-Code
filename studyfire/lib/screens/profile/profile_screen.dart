import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/services/firestore_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../../app.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/walkthrough/walkthrough_keys.dart';
import '../../models/user_profile.dart';
import '../../models/memory_verse.dart';
import '../../widgets/common/progress_bar.dart';
import '../../widgets/common/premium_gate.dart';
import '../../widgets/gamification/xp_burst.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../memory_verse/memory_verse_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final profileAsync = ref.watch(currentProfileProvider);

    final fallbackName = user?.displayName ?? user?.email?.split('@')[0] ?? 'Friend';
    final avatarUrl = user?.photoURL;

    return profileAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF0F1120),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _buildScaffold(context, ref, fallbackName, avatarUrl, null),
      data: (profile) => _buildScaffold(
        context, ref,
        (profile?.name?.isNotEmpty == true) ? profile!.name : fallbackName,
        avatarUrl, profile,
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, WidgetRef ref, String name, String? avatarUrl, dynamic profile) {
    final xp = profile?.xp ?? 0;
    final levelData = LevelThresholds.forXp(xp);
    final levelName = levelData['name'] as String? ?? 'Spark';
    final nextXp = LevelThresholds.nextThreshold(xp) ?? xp + 500;
    final streak = profile?.streak ?? 0;

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroSection(
                name: name,
                levelName: levelName,
                xp: xp,
                nextLevelXp: nextXp,
                avatarUrl: avatarUrl,
                onSettingsTap: () => showSettingsSheet(context, profile),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _StatsRow(
              key: WalkthroughKeys.profileHero,
              currentStreak: streak,
              longestStreak: profile?.longestStreak ?? 0,
              totalStudyDays: profile?.totalStudyDays ?? 0,
            ),
          ),
          SliverToBoxAdapter(
            child: _StreakFreezeBanner(
              isPremium: profile?.isPremium ?? false,
              freezeCount: profile?.streakFreezeCount ?? 0,
            ),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _BooksReadGrid(),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _BadgesGrid(key: WalkthroughKeys.profileBadges),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _StudyStats(),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _VerseVaultSection(
              key: WalkthroughKeys.profileVerseVault,
              uid: FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _NotesSection(
              key: WalkthroughKeys.profileNotes,
              uid: FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final String name;
  final String levelName;
  final int xp;
  final int nextLevelXp;
  final String? avatarUrl;
  final VoidCallback? onSettingsTap;

  const _HeroSection({
    required this.name,
    required this.levelName,
    required this.xp,
    required this.nextLevelXp,
    this.avatarUrl,
    this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cardDark, AppColors.deepSlate],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _pickAvatar(context),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.surface,
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                      child: avatarUrl == null
                          ? Text(name[0], style: AppTypography.displaySmall.copyWith(fontSize: 28))
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: AppColors.warmGold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTypography.labelLarge),
                    Row(
                      children: [
                        const Text('🔥', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text(levelName, style: AppTypography.bodySmall.copyWith(
                          color: AppColors.warmGold,
                        )),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
                onPressed: onSettingsTap,
              ),
            ],
          ),
          const SizedBox(height: 16),
          XpProgressBar(
            current: xp,
            max: nextLevelXp,
            label: '$xp / $nextLevelXp XP to ${_nextLevelName()}',
          ),
        ],
      ),
    );
  }

  String _nextLevelName() {
    final next = LevelThresholds.nextThreshold(xp);
    if (next == null) return 'Max Level';
    final nextData = LevelThresholds.forXp(next);
    return nextData['name'] as String;
  }

  void _pickAvatar(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final file = File(image.path);
      final ref = FirebaseStorage.instance.ref('avatars/${user.uid}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await user.updatePhotoURL(url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update photo: $e')),
      );
    }
  }
}

void _exportPdf(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF…')),
    );
    try {
      final entries = await FirestoreService().getJournalEntries(user.uid);
      final pdf = pw.Document();
      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (ctx) => [
            pw.Text('StudyFire Journal', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Exported $dateStr', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey)),
            pw.SizedBox(height: 20),
            ...entries.map((e) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text(e.title.isEmpty ? 'Untitled' : e.title,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('${e.date.month}/${e.date.day}/${e.date.year}',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                if (e.scriptureRefs.isNotEmpty)
                  pw.Text('Scripture: ' + e.scriptureRefs.join(', '),
                    style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.orange800)),
                pw.SizedBox(height: 8),
                pw.Text(e.content, style: const pw.TextStyle(fontSize: 13)),
                pw.SizedBox(height: 16),
              ],
            )),
          ],
        ),
      );
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'StudyFire_Journal_$dateStr.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
void showSettingsSheet(BuildContext context, dynamic profile) {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      backgroundColor: const Color(0xFF1E2235),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.person_outline, color: Colors.white70),
              title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () async {
                Navigator.pop(sheetContext);
                // Yield a frame so the sheet pop fully flushes before pushing.
                await Future<void>.delayed(Duration.zero);
                if (context.mounted) {
                  context.push('/profile/settings', extra: {'profile': profile});
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined, color: Colors.white70),
              title: const Text('Notifications', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () async {
                await launchUrl(Uri.parse('app-settings:'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.white70),
              title: const Text('Privacy Policy', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () async {
                await launchUrl(Uri.parse('https://dwdalton80.github.io/studyfire-site'), mode: LaunchMode.externalApplication);
              },
            ),
            const _FocusCompanionToggle(),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70),
              title: const Text('Export Journal as PDF', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportPdf(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                await AuthService().signOut();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
}

class _StatsRow extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final int totalStudyDays;

  const _StatsRow({
    super.key,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalStudyDays,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          _StatCard(
            value: currentStreak.toString(),
            label: 'Current\nStreak',
            suffix: '🔥',
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: longestStreak.toString(),
            label: 'Longest\nStreak',
          ),
          const SizedBox(width: 12),
          _StatCard(
            value: totalStudyDays.toString(),
            label: 'Days\nStudied',
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final String? suffix;

  const _StatCard({required this.value, required this.label, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: AppTypography.xpLabel.copyWith(fontSize: 28),
                ),
                if (suffix != null) Text(suffix!, style: const TextStyle(fontSize: 18)),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _BooksReadGrid extends StatefulWidget {
  @override
  State<_BooksReadGrid> createState() => _BooksReadGridState();
}

class _BooksReadGridState extends State<_BooksReadGrid> {
  Set<String> _engaged = {};

  // Maps Firestore book IDs (API.Bible format) → display abbreviations
  static const _bookIdToAbbr = {
    'gen': 'Gen',   'exo': 'Ex',    'lev': 'Lev',   'num': 'Num',   'deu': 'Deut',
    'jos': 'Josh',  'jdg': 'Judg',  'rut': 'Ruth',  '1sa': '1Sam',  '2sa': '2Sam',
    '1ki': '1Kgs',  '2ki': '2Kgs',  '1ch': '1Chr',  '2ch': '2Chr',  'ezr': 'Ezra',
    'neh': 'Neh',   'est': 'Est',   'job': 'Job',   'psa': 'Ps',    'pro': 'Prov',
    'ecc': 'Eccl',  'sng': 'Song',  'isa': 'Isa',   'jer': 'Jer',   'lam': 'Lam',
    'ezk': 'Ezek',  'dan': 'Dan',   'hos': 'Hos',   'jol': 'Joel',  'amo': 'Amos',
    'oba': 'Ob',    'jon': 'Jon',   'mic': 'Mic',   'nam': 'Nah',   'hab': 'Hab',
    'zep': 'Zeph',  'hag': 'Hag',  'zec': 'Zech',  'mal': 'Mal',
    'mat': 'Matt',  'mrk': 'Mark',  'luk': 'Luke',  'jhn': 'John',  'act': 'Acts',
    'rom': 'Rom',   '1co': '1Cor',  '2co': '2Cor',  'gal': 'Gal',   'eph': 'Eph',
    'php': 'Phil',  'col': 'Col',   '1th': '1Th',   '2th': '2Th',   '1ti': '1Tim',
    '2ti': '2Tim',  'tit': 'Titus', 'phm': 'Philem','heb': 'Heb',   'jas': 'Jas',
    '1pe': '1Pet',  '2pe': '2Pet',  '1jn': '1Jn',   '2jn': '2Jn',   '3jn': '3Jn',
    'jud': 'Jude',  'rev': 'Rev',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('highlights')
        .doc(uid)
        .collection('verses')
        .get();

    final books = <String>{};
    for (final doc in snap.docs) {
      // verseId format: book_chapter_verseNum e.g. jhn_3_16
      final parts = doc.id.split('_');
      if (parts.isNotEmpty) {
        final abbr = _bookIdToAbbr[parts[0]];
        if (abbr != null) books.add(abbr);
      }
    }

    if (mounted) setState(() => _engaged = books);
  }

  @override
  Widget build(BuildContext context) {
    const otBooks = [
      'Gen', 'Ex', 'Lev', 'Num', 'Deut', 'Josh', 'Judg', 'Ruth',
      '1Sam', '2Sam', '1Kgs', '2Kgs', '1Chr', '2Chr', 'Ezra', 'Neh',
      'Est', 'Job', 'Ps', 'Prov', 'Eccl', 'Song', 'Isa', 'Jer',
      'Lam', 'Ezek', 'Dan', 'Hos', 'Joel', 'Amos', 'Ob', 'Jon',
      'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech', 'Mal',
    ];
    const ntBooks = [
      'Matt', 'Mark', 'Luke', 'John', 'Acts', 'Rom', '1Cor', '2Cor',
      'Gal', 'Eph', 'Phil', 'Col', '1Th', '2Th', '1Tim', '2Tim',
      'Titus', 'Philem', 'Heb', 'Jas', '1Pet', '2Pet', '1Jn', '2Jn',
      '3Jn', 'Jude', 'Rev',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Books Read', style: AppTypography.labelLarge),
              const Spacer(),
              if (_engaged.isNotEmpty)
                Text(
                  '${_engaged.length} / 66',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Old Testament', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _BookGrid(books: otBooks, completedBooks: _engaged),
          const SizedBox(height: 12),
          Text('New Testament', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _BookGrid(books: ntBooks, completedBooks: _engaged),
        ],
      ),
    );
  }
}

class _BookGrid extends StatelessWidget {
  final List<String> books;
  final Set<String> completedBooks;

  const _BookGrid({required this.books, required this.completedBooks});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: books.map((book) {
        final completed = completedBooks.contains(book);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: completed ? AppColors.warmGold.withOpacity(0.2) : AppColors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: completed ? AppColors.warmGold : AppColors.surfaceVariant,
            ),
          ),
          child: Text(
            book,
            style: AppTypography.bodySmall.copyWith(
              color: completed ? AppColors.warmGold : AppColors.textSecondary,
              fontSize: 10,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BadgesGrid extends StatefulWidget {
  const _BadgesGrid({super.key});

  @override
  State<_BadgesGrid> createState() => _BadgesGridState();
}

class _BadgesGridState extends State<_BadgesGrid> {
  Set<String> _earned = {};

  static const _allBadges = [
    ('spark', 'assets/images/badges/badge_spark.png', 'Spark', '100 XP'),
    ('on_fire', 'assets/images/badges/badge_on_fire.png', 'On Fire', '500 XP'),
    ('burning_bright', 'assets/images/badges/badge_burning_bright.png', 'Burning Bright', '1,500 XP'),
    ('unquenchable', 'assets/images/badges/badge_unquenchable.png', 'Unquenchable', '3,500 XP'),
    ('flame_keeper', 'assets/images/badges/badge_flame_keeper.png', 'Flame Keeper', '7,000 XP'),
    ('eternal_flame', 'assets/images/badges/badge_eternal_flame.png', 'Eternal Flame', '12,000 XP'),
    ('first_verse', 'assets/images/badges/badge_first_verse.png', 'First Verse', 'Memorized 1 verse'),
    ('ten_verses', 'assets/images/badges/badge_ten_verses.png', 'Ten Verses', 'Memorized 10 verses'),
    ('comeback', 'assets/images/badges/badge_comeback.png', 'Comeback', 'Returned after 7+ days'),
  ];

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('badges')
        .doc(user.uid)
        .collection('earned')
        .get();
    if (mounted) setState(() => _earned = snap.docs.map((d) => d.id).toSet());
  }

  void _shareBadge(String imagePath, String name, String requirement) {
    Share.share(
      'I just earned the "$name" badge on StudyFire! 🔥\n\n$requirement\n\nJoin me at studyfire.app 🔥',
      subject: 'I earned a StudyFire badge!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Badges', style: AppTypography.labelLarge),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: _allBadges.length,
            itemBuilder: (_, i) {
              final badge = _allBadges[i];
              final isEarned = _earned.contains(badge.$1);
              return _BadgeCell(
                imagePath: badge.$2,
                name: badge.$3,
                isEarned: isEarned,
                onTap: isEarned ? () => _shareBadge(badge.$2, badge.$3, badge.$4) : null,
              );
            },
          ),
          if (_earned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Tap a badge to share it!',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _BadgeCell extends StatelessWidget {
  final String imagePath;
  final String name;
  final bool isEarned;
  final VoidCallback? onTap;

  const _BadgeCell({
    required this.imagePath,
    required this.name,
    required this.isEarned,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ColorFiltered(
            colorFilter: isEarned
                ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                : const ColorFilter.matrix([
                    0.3, 0.3, 0.3, 0, 0,
                    0.3, 0.3, 0.3, 0, 0,
                    0.3, 0.3, 0.3, 0, 0,
                    0, 0, 0, 0.4, 0,
                  ]),
            child: Image.asset(imagePath, width: 64, height: 64),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            style: AppTypography.bodySmall.copyWith(
              color: isEarned ? AppColors.warmWhite : AppColors.textSecondary,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _StudyStats extends StatefulWidget {
  @override
  State<_StudyStats> createState() => _StudyStatsState();
}

class _StudyStatsState extends State<_StudyStats> {
  int _journalEntries = 0;
  int _versesMemorized = 0;
  int _questionsAnswered = 0;
  int _wordsExplored = 0;
  int _versesRead = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final db = FirebaseFirestore.instance;

    try {
      final results = await Future.wait([
        db.collection('journal').doc(uid).collection('entries').get(),
        db.collection('memoryVerses').doc(uid).collection('verses').get(),
        db.collection('users').doc(uid).get(),
      ]);

      final journalCount = (results[0] as QuerySnapshot).docs.length;
      final masteredCount = (results[1] as QuerySnapshot).docs.length;
      final userSnap = results[2] as DocumentSnapshot;
      final data = userSnap.data() as Map<String, dynamic>? ?? {};
      final profile = data['profile'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _journalEntries = journalCount;
          _versesMemorized = masteredCount;
          _questionsAnswered = (profile['questionsAnswered'] as num?)?.toInt() ?? 0;
          _wordsExplored = (profile['wordsExplored'] as num?)?.toInt() ?? 0;
          _versesRead = (profile['versesRead'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      }

      // Retroactively award any verse badges the onCreate trigger may have missed.
      if (masteredCount > 0) {
        FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('checkVerseBadges')
            .call()
            .ignore();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Study Stats', style: AppTypography.labelLarge),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            _StatRow(label: 'Verses Read', value: _versesRead.toString()),
            _StatRow(label: 'Words Explored', value: _wordsExplored.toString()),
            _StatRow(label: 'Questions Answered', value: _questionsAnswered.toString()),
            _StatRow(label: 'Journal Entries', value: _journalEntries.toString()),
            _StatRow(label: 'Verses Memorized', value: _versesMemorized.toString()),
          ],
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: AppTypography.bodyMedium),
          const Spacer(),
          Text(value, style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 8, color: AppColors.surface.withOpacity(0.5));
  }
}

class _FocusCompanionToggle extends StatefulWidget {
  const _FocusCompanionToggle();
  @override
  State<_FocusCompanionToggle> createState() => _FocusCompanionToggleState();
}

class _FocusCompanionToggleState extends State<_FocusCompanionToggle> {
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final prefs = (doc.data()?['preferences'] as Map?) ?? {};
    if (mounted) setState(() {
      _enabled = prefs['focusCompanion'] == true;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.wb_sunny_outlined, color: Colors.white70),
      title: const Text('Morning Verse Notification', style: TextStyle(color: Colors.white)),
      subtitle: const Text('Daily at 9:30am', style: TextStyle(color: Colors.white38, fontSize: 12)),
      value: _enabled,
      activeColor: const Color(0xFFFF6B00),
      onChanged: (val) async {
        setState(() => _enabled = val);
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'preferences': {'focusCompanion': val}
        }, SetOptions(merge: true));
      },
    );
  }
}

// ── Verse Vault Section ────────────────────────────────────────────────────────

class _VerseVaultSection extends StatelessWidget {
  final String uid;
  const _VerseVaultSection({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Verse Vault', style: AppTypography.labelLarge),
              const Spacer(),
              IconButton(
                onPressed: () => _showAddSheet(context),
                icon: const Icon(Icons.add_circle_outline, color: AppColors.warmGold),
                tooltip: 'Add a verse',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<MemoryVerse>>(
            stream: FirestoreService().watchMemoryVerses(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final verses = snap.data ?? [];
              if (verses.isEmpty) {
                return GestureDetector(
                  onTap: () => _showAddSheet(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warmGold.withOpacity(0.3),
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text('📖', style: TextStyle(fontSize: 28)),
                        const SizedBox(height: 8),
                        Text(
                          'Start your Verse Vault',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.warmGold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap + to add a verse to memorize',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: verses.map((v) => Dismissible(
                  key: ValueKey(v.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.cardDark,
                        title: const Text('Remove verse?'),
                        content: Text('Remove ${v.reference} from your Vault?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('Remove', style: TextStyle(color: AppColors.error)),
                          ),
                        ],
                      ),
                    ) ?? false;
                  },
                  onDismissed: (_) {
                    FirebaseFirestore.instance
                        .collection('memoryVerses')
                        .doc(uid)
                        .collection('verses')
                        .doc(v.id)
                        .delete();
                  },
                  child: _VaultVerseRow(
                    verse: v,
                    onTap: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => MemoryVerseScreen(verse: v, uid: uid),
                      ),
                    ),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddVerseSheet(uid: uid),
    );
  }
}

// ── Notes Section ─────────────────────────────────────────────────────────────

class _NotesSection extends StatelessWidget {
  final String uid;
  const _NotesSection({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📝', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text('My Notes', style: AppTypography.labelLarge),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/notes'),
                child: Text(
                  'View All',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('journal')
                .doc(uid)
                .collection('entries')
                .orderBy('updatedAt', descending: true)
                .limit(3)
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.warmGold));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return GestureDetector(
                  onTap: () => context.push('/notes'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text('📝', style: TextStyle(fontSize: 28)),
                        const SizedBox(height: 8),
                        Text(
                          'No notes yet',
                          style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap to add your first note',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  ...docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final title = data['title'] as String? ?? '';
                    final passage = data['passage'] as String? ?? '';
                    final content = data['content'] as String? ?? '';
                    final label = passage.isNotEmpty ? passage : title;
                    return GestureDetector(
                      onTap: () => context.push('/notes'),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surface),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (label.isNotEmpty)
                                    Text(
                                      label,
                                      style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                                    ),
                                  if (label.isNotEmpty) const SizedBox(height: 4),
                                  Text(
                                    content,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite.withOpacity(0.85)),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => context.push('/notes'),
                      child: Text(
                        'See all notes →',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VaultVerseRow extends StatelessWidget {
  final MemoryVerse verse;
  final VoidCallback onTap;

  const _VaultVerseRow({required this.verse, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final mastered = verse.mastered || verse.currentStage == MemoryVerseStage.stage5;
    final filledBars = verse.currentStage.index + 1;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.surface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              verse.reference,
              style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
            ),
            const SizedBox(height: 4),
            Text(
              verse.text,
              style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite.withOpacity(0.85)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ...List.generate(5, (s) => Container(
                  width: 22, height: 5,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: s < filledBars ? AppColors.warmGold : AppColors.surface,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
                const SizedBox(width: 8),
                Text(
                  mastered ? '✅ Mastered' : 'Stage ${verse.currentStage.index + 1}/5',
                  style: AppTypography.bodySmall.copyWith(
                    color: mastered ? const Color(0xFF4CAF50) : AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 14, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Verse Bottom Sheet ─────────────────────────────────────────────────────

class _AddVerseSheet extends StatefulWidget {
  final String uid;
  const _AddVerseSheet({required this.uid});

  @override
  State<_AddVerseSheet> createState() => _AddVerseSheetState();
}

class _AddVerseSheetState extends State<_AddVerseSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() { _loading = true; _error = null; });

    try {
      final db = FirestoreService();
      final bibleVerse = await db.getVerse('kjv', input);

      if (bibleVerse == null) {
        if (mounted) setState(() {
          _error = 'Verse not found. Try "Book Chapter:Verse" (e.g. John 3:16)';
          _loading = false;
        });
        return;
      }

      // Auto-generate Firestore doc ID
      final docRef = FirebaseFirestore.instance
          .collection('memoryVerses')
          .doc(widget.uid)
          .collection('verses')
          .doc();

      final verse = MemoryVerse(
        id: docRef.id,
        reference: bibleVerse.reference,
        text: bibleVerse.text,
        currentStage: MemoryVerseStage.stage1,
        mastered: false,
        attemptHistory: const [],
        easeFactor: 250,
        interval: 1,
        repetitions: 0,
        nextReviewDate: DateTime.now().add(const Duration(days: 1)),
      );

      await docRef.set({
        ...verse.toFirestore(),
        'addedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Something went wrong. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Add a Verse to Memorize',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Enter a reference like "John 3:16" or "Romans 8:28"',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'e.g. Philippians 4:13',
              hintStyle: const TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.warmGold, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warmGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white,
                      ),
                    )
                  : const Text('Add to Vault', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Streak Freeze Banner ──────────────────────────────────────────────────────

class _StreakFreezeBanner extends StatelessWidget {
  final bool isPremium;
  final int freezeCount;

  const _StreakFreezeBanner({required this.isPremium, required this.freezeCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: isPremium
            ? null // premium users just see their count; freeze is auto-applied
            : () => showPaywallSheet(context, featureName: 'Streak Freeze'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isPremium
                ? AppColors.surface
                : AppColors.warmGold.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPremium
                  ? AppColors.surface
                  : AppColors.warmGold.withOpacity(0.4),
            ),
          ),
          child: Row(
            children: [
              const Text('🧊', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPremium ? 'Streak Freeze' : 'Streak Freeze — Premium',
                      style: AppTypography.labelMedium.copyWith(
                        color: isPremium ? AppColors.warmWhite : AppColors.warmGold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPremium
                          ? (freezeCount > 0
                              ? '$freezeCount freeze${freezeCount == 1 ? "" : "s"} available — auto-applied if you miss a day'
                              : 'No freezes remaining — keep your streak alive!')
                          : 'Protects your streak for up to 3 days when life gets busy',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warmGold,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('PRO',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
