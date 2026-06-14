import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/firestore_service.dart';
import '../../models/group.dart';
import '../../widgets/common/flame_cta_button.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final groupsProvider = StreamProvider.family<List<Group>, String>((ref, uid) {
  return FirestoreService().watchMyGroups(uid);
});

final groupFeedProvider =
    StreamProvider.family<List<FeedItem>, String>((ref, groupId) {
  return FirestoreService().watchGroupFeed(groupId);
});

final groupMembersProvider =
    FutureProvider.family<List<GroupMember>, String>((ref, groupId) async {
  return FirestoreService().getGroupMembers(groupId);
});

final groupQuestionsProvider =
    StreamProvider.family<List<GroupQuestion>, String>((ref, groupId) {
  return FirestoreService().watchGroupQuestions(groupId);
});

// ── Groups Screen ─────────────────────────────────────────────────────────────

class GroupsScreen extends ConsumerWidget {
  final String uid;
  final bool isPremium;

  const GroupsScreen({super.key, required this.uid, required this.isPremium});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider(uid));

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateOrJoin(context),
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading groups', style: AppTypography.bodyLarge)),
        data: (groups) {
          if (groups.isEmpty) {
            return _EmptyGroupsView(onCreateOrJoin: () => _showCreateOrJoin(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _GroupCard(
              group: groups[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupDetailScreen(
                    group: groups[i],
                    uid: uid,
                    isPremium: isPremium,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateOrJoin(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => _CreateOrJoinSheet(uid: uid),
    );
  }
}

// ── Group Card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  final Group group;
  final VoidCallback onTap;

  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.indigoAccent.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.group, color: AppColors.warmWhite),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: AppTypography.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${group.memberCount} members',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Empty State ────────────────────────────────────────────────────────────────

class _EmptyGroupsView extends StatelessWidget {
  final VoidCallback onCreateOrJoin;
  const _EmptyGroupsView({required this.onCreateOrJoin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('👥', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('No groups yet', style: AppTypography.displaySmall),
          const SizedBox(height: 8),
          Text(
            'Study together with friends, a small group, or Bible study class.',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FlameCTAButton(label: 'Create or join a group', onPressed: onCreateOrJoin),
        ],
      ),
    );
  }
}

// ── Create or Join Sheet ──────────────────────────────────────────────────────

class _CreateOrJoinSheet extends StatefulWidget {
  final String uid;
  const _CreateOrJoinSheet({required this.uid});

  @override
  State<_CreateOrJoinSheet> createState() => _CreateOrJoinSheetState();
}

class _CreateOrJoinSheetState extends State<_CreateOrJoinSheet> {
  bool _creating = false;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _creating = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: !_creating ? AppColors.warmGold.withOpacity(0.2) : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: !_creating ? AppColors.warmGold : AppColors.surfaceVariant,
                    ),
                  ),
                  child: Text(
                    'Join a group',
                    style: AppTypography.labelSmall.copyWith(
                      color: !_creating ? AppColors.warmGold : AppColors.warmWhite,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _creating = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _creating ? AppColors.warmGold.withOpacity(0.2) : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _creating ? AppColors.warmGold : AppColors.surfaceVariant,
                    ),
                  ),
                  child: Text(
                    'Create a group',
                    style: AppTypography.labelSmall.copyWith(
                      color: _creating ? AppColors.warmGold : AppColors.warmWhite,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_creating) ...[
            const Text('Group name', style: AppTypography.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              style: AppTypography.bodyLarge,
              decoration: const InputDecoration(hintText: 'e.g. Sunday Morning Bible Study'),
              autofocus: true,
            ),
            const SizedBox(height: 24),
            FlameCTAButton(
              label: 'Create group',
              isLoading: _submitting,
              onPressed: () => _createGroup(context),
            ),
          ] else ...[
            const Text('Invite code', style: AppTypography.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _codeCtrl,
              style: AppTypography.bodyLarge,
              decoration: const InputDecoration(hintText: 'Paste 6-digit code'),
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 24),
            FlameCTAButton(
              label: 'Join group',
              isLoading: _submitting,
              onPressed: () => _joinGroup(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await FirestoreService().createGroupSimple(widget.uid, _nameCtrl.text.trim());
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _joinGroup(BuildContext context) async {
    if (_codeCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await FirestoreService().joinGroupByCode(widget.uid, _codeCtrl.text.trim());
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _submitting = false);
    }
  }
}

// ── Group Detail Screen ───────────────────────────────────────────────────────

class GroupDetailScreen extends StatefulWidget {
  final Group group;
  final String uid;
  final bool isPremium;

  const GroupDetailScreen({
    super.key,
    required this.group,
    required this.uid,
    required this.isPremium,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareInvite(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.warmGold,
          labelStyle: AppTypography.labelSmall,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Questions'),
            Tab(text: 'Leaderboard'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FeedTab(groupId: widget.group.id, uid: widget.uid),
          _QuestionsTab(group: widget.group, uid: widget.uid),
          _LeaderboardTab(group: widget.group),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _postQuestion(context),
        backgroundColor: AppColors.warmGold,
        foregroundColor: AppColors.deepSlate,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Ask group'),
      ),
    );
  }

  void _shareInvite() {
    final code = widget.group.inviteCode;
    HapticFeedback.lightImpact();
    // Share.share('Join my StudyFire group "$name" with code: $code');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invite code: $code  (tap to copy)'),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
        ),
      ),
    );
  }

  void _postQuestion(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PostQuestionSheet(
        groupId: widget.group.id,
        uid: widget.uid,
      ),
    );
  }
}

// ── Feed Tab ──────────────────────────────────────────────────────────────────

class _FeedTab extends ConsumerWidget {
  final String groupId;
  final String uid;

  const _FeedTab({required this.groupId, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupFeedProvider(groupId));

    return feedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load feed')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No activity yet — be the first to post!',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _FeedItemCard(item: items[i], currentUid: uid),
        );
      },
    );
  }
}

class _FeedItemCard extends StatelessWidget {
  final FeedItem item;
  final String currentUid;

  const _FeedItemCard({required this.item, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;

    switch (item.type) {
      case FeedItemType.sharedNote:
        icon = Icons.sticky_note_2_outlined;
        iconColor = AppColors.indigoAccent;
      case FeedItemType.badgeEarned:
        icon = Icons.emoji_events_outlined;
        iconColor = AppColors.warmGold;
      case FeedItemType.sharedQuestion:
        icon = Icons.question_answer_outlined;
        iconColor = AppColors.emerald;
      case FeedItemType.streakMilestone:
        icon = Icons.local_fire_department_outlined;
        iconColor = AppColors.flameOrange;
      case FeedItemType.memoryVerseMastered:
        icon = Icons.psychology_outlined;
        iconColor = AppColors.warmGold;
    }

    final displayText = (item.content['text'] as String?) ??
        (item.content['message'] as String?) ??
        '${item.authorName} shared something.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.authorName, style: AppTypography.labelSmall),
                const SizedBox(height: 4),
                Text(displayText, style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Questions Tab ──────────────────────────────────────────────────────────────

class _QuestionsTab extends ConsumerWidget {
  final Group group;
  final String uid;

  const _QuestionsTab({required this.group, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(groupQuestionsProvider(group.id));

    return questionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load questions')),
      data: (questions) {
        if (questions.isEmpty) {
          return Center(
            child: Text(
              'No discussion questions yet.',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: questions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final q = questions[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.indigoAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.question, style: AppTypography.bodyLarge),
                  if (q.scriptureRef != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warmGold.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_outlined, size: 14, color: AppColors.warmGold),
                          const SizedBox(width: 6),
                          Text(q.scriptureRef!, style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Asked by ${q.authorName}',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Leaderboard Tab ───────────────────────────────────────────────────────────

class _LeaderboardTab extends ConsumerWidget {
  final Group group;

  const _LeaderboardTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(group.id));

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load leaderboard')),
      data: (members) {
        final sorted = [...members]..sort((a, b) => b.weeklyXp.compareTo(a.weeklyXp));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Weekly XP — resets every Monday',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final m = sorted[i];
                  final medalEmoji =
                      i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}.';
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: i == 0
                          ? AppColors.warmGold.withOpacity(0.1)
                          : AppColors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: i == 0
                          ? Border.all(color: AppColors.warmGold.withOpacity(0.3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            medalEmoji,
                            style: const TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.name, style: AppTypography.labelSmall),
                              Text(
                                '${m.streak} day streak',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text('${m.weeklyXp} XP', style: AppTypography.xpLabel),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Post Question Sheet ───────────────────────────────────────────────────────

class _PostQuestionSheet extends StatefulWidget {
  final String groupId;
  final String uid;

  const _PostQuestionSheet({required this.groupId, required this.uid});

  @override
  State<_PostQuestionSheet> createState() => _PostQuestionSheetState();
}

class _PostQuestionSheetState extends State<_PostQuestionSheet> {
  final _ctrl = TextEditingController();
  final _verseRefCtrl = TextEditingController();
  final _verseTextCtrl = TextEditingController();
  bool _submitting = false;
  bool _attachVerse = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _verseRefCtrl.dispose();
    _verseTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ask the group', style: AppTypography.displaySmall),
          const SizedBox(height: 4),
          Text(
            'Post a reflection question or discussion starter.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            style: AppTypography.bodyLarge,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'What question is on your heart?',
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _attachVerse = !_attachVerse),
            child: Row(
              children: [
                Icon(_attachVerse ? Icons.check_box : Icons.check_box_outline_blank,
                    color: AppColors.warmGold, size: 20),
                const SizedBox(width: 8),
                Text('Attach a verse', style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold)),
              ],
            ),
          ),
          if (_attachVerse) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _verseRefCtrl,
              style: AppTypography.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Reference (e.g. John 3:16)',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _verseTextCtrl,
              maxLines: 3,
              style: AppTypography.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Verse text (optional)',
              ),
            ),
          ],
          const SizedBox(height: 16),
          FlameCTAButton(
            label: 'Post question',
            isLoading: _submitting,
            onPressed: () async {
              if (_ctrl.text.trim().isEmpty) return;
              setState(() => _submitting = true);
              try {
                final user = FirebaseAuth.instance.currentUser;
                final authorName = user?.displayName ?? user?.email?.split('@')[0] ?? 'Member';
                await FirebaseFirestore.instance
                    .collection('groupQuestions')
                    .doc(widget.groupId)
                    .collection('questions')
                    .add({
                  'question': _ctrl.text.trim(),
                  'authorId': widget.uid,
                  'authorName': authorName,
                  'timestamp': FieldValue.serverTimestamp(),
                  if (_attachVerse && _verseRefCtrl.text.trim().isNotEmpty)
                    'scriptureRef': _verseRefCtrl.text.trim(),
                  if (_attachVerse && _verseTextCtrl.text.trim().isNotEmpty)
                    'verseText': _verseTextCtrl.text.trim(),
                });
                if (context.mounted) Navigator.pop(context);
              } catch (_) {
                setState(() => _submitting = false);
              }
            },
          ),
        ],
      ),
    );
  }
}
