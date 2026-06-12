import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../models/user_profile.dart';
import '../../widgets/common/progress_bar.dart';
import '../../widgets/gamification/xp_burst.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/auth_service.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: wire to user profile provider
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroSection(
                name: 'Alex',
                levelName: 'Scribe',
                xp: 1850,
                nextLevelXp: 3500,
                avatarUrl: null,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _StatsRow(
              currentStreak: 12,
              longestStreak: 30,
              totalStudyDays: 45,
            ),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _BooksReadGrid(),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _BadgesGrid(),
          ),
          const SliverToBoxAdapter(child: _SectionDivider()),
          SliverToBoxAdapter(
            child: _StudyStats(
              totalVerses: 342,
              wordsExplored: 28,
              questionsAnswered: 89,
              journalEntries: 15,
              versesMemorized: 7,
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

  const _HeroSection({
    required this.name,
    required this.levelName,
    required this.xp,
    required this.nextLevelXp,
    this.avatarUrl,
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
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.surface,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                child: avatarUrl == null
                    ? Text(name[0], style: AppTypography.displaySmall.copyWith(fontSize: 28))
                    : null,
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
                onPressed: () => _showSettings(context),
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

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2235),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.notifications_outlined, color: Colors.white70),
              title: const Text('Notifications', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.white70),
              title: const Text('Privacy Policy', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await AuthService().signOut();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

}

class _StatsRow extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final int totalStudyDays;

  const _StatsRow({
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

class _BooksReadGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 66 books of the Bible — OT 39, NT 27
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
          const Text('Books Read', style: AppTypography.labelLarge),
          const SizedBox(height: 4),
          Text('Old Testament', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _BookGrid(books: otBooks, completedBooks: {'Gen', 'John'}),
          const SizedBox(height: 12),
          Text('New Testament', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _BookGrid(books: ntBooks, completedBooks: {'John'}),
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

class _BadgesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const allBadges = [
      ('spark', '⚡', 'Spark', '100 XP'),
      ('on_fire', '🔥', 'On Fire', '500 XP'),
      ('burning_bright', '✨', 'Burning Bright', '1,500 XP'),
      ('unquenchable', '💪', 'Unquenchable', '3,500 XP'),
      ('flame_keeper', '🛡️', 'Flame Keeper', '7,000 XP'),
      ('eternal_flame', '👑', 'Eternal Flame', '12,000 XP'),
      ('first_verse', '📖', 'First Verse', 'Memorized 1 verse'),
      ('ten_verses', '🧠', 'Ten Verses', 'Memorized 10 verses'),
      ('comeback', '🌅', 'Comeback', 'Returned after 7+ days'),
    ];

    const earned = {'spark', 'on_fire'};

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
            itemCount: allBadges.length,
            itemBuilder: (_, i) {
              final badge = allBadges[i];
              final isEarned = earned.contains(badge.$1);
              return _BadgeCell(
                emoji: badge.$2,
                name: badge.$3,
                isEarned: isEarned,
                onTap: isEarned ? () {} : null,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BadgeCell extends StatelessWidget {
  final String emoji;
  final String name;
  final bool isEarned;
  final VoidCallback? onTap;

  const _BadgeCell({
    required this.emoji,
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
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isEarned ? AppColors.warmGold.withOpacity(0.15) : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: isEarned ? AppColors.warmGold : AppColors.surfaceVariant,
              ),
            ),
            child: Center(
              child: ColorFiltered(
                colorFilter: isEarned
                    ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                    : const ColorFilter.matrix([
                        0.2, 0.2, 0.2, 0, 0,
                        0.2, 0.2, 0.2, 0, 0,
                        0.2, 0.2, 0.2, 0, 0,
                        0, 0, 0, 0.5, 0,
                      ]),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
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

class _StudyStats extends StatelessWidget {
  final int totalVerses;
  final int wordsExplored;
  final int questionsAnswered;
  final int journalEntries;
  final int versesMemorized;

  const _StudyStats({
    required this.totalVerses,
    required this.wordsExplored,
    required this.questionsAnswered,
    required this.journalEntries,
    required this.versesMemorized,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Study Stats', style: AppTypography.labelLarge),
          const SizedBox(height: 12),
          _StatRow(label: 'Verses Read', value: totalVerses.toString()),
          _StatRow(label: 'Words Explored', value: wordsExplored.toString()),
          _StatRow(label: 'Questions Answered', value: questionsAnswered.toString()),
          _StatRow(label: 'Journal Entries', value: journalEntries.toString()),
          _StatRow(label: 'Verses Memorized', value: versesMemorized.toString()),
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
