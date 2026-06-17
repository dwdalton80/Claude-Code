import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/services/xp_service.dart';
import '../../core/constants/xp_rewards.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
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

final groupDocProvider =
    StreamProvider.family<Group?, String>((ref, groupId) {
  return FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .snapshots()
      .map((s) => s.exists ? Group.fromFirestore(s) : null);
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
    } catch (e) {
      setState(() => _submitting = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().contains('Invalid') ? 'Invalid invite code. Check and try again.' : 'Could not join group. Please try again.')),
        );
      }
    }
  }
}

// ── Group Detail Screen ───────────────────────────────────────────────────────

class GroupDetailScreen extends ConsumerStatefulWidget {
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
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDocProvider(widget.group.id));
    final group = groupAsync.valueOrNull ?? widget.group;
    final isCreator = group.creatorUid == widget.uid;

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name),
            if (group.topic.isNotEmpty)
              Text(
                group.topic,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _shareInvite(group),
          ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'edit') _showEditGroupSheet(context, group);
              if (val == 'plan') _showReadingPlanSheet(context, group);
              if (val == 'announce') _showPinAnnouncementSheet(context, group);
              if (val == 'leave') _confirmLeave(context, group);
              if (val == 'delete') _confirmDelete(context, group);
            },
            itemBuilder: (_) => [
              if (isCreator) ...[
                const PopupMenuItem(value: 'edit', child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Edit Group'),
                  ],
                )),
                const PopupMenuItem(value: 'plan', child: Row(
                  children: [
                    Icon(Icons.calendar_month_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Reading Plan'),
                  ],
                )),
                const PopupMenuItem(value: 'announce', child: Row(
                  children: [
                    Icon(Icons.push_pin_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Pin Announcement'),
                  ],
                )),
                const PopupMenuItem(value: 'delete', child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Delete Group', style: TextStyle(color: Colors.redAccent)),
                  ],
                )),
              ],
              if (!isCreator)
                const PopupMenuItem(value: 'leave', child: Row(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.redAccent, size: 18),
                    SizedBox(width: 8),
                    Text('Leave Group', style: TextStyle(color: Colors.redAccent)),
                  ],
                )),
            ],
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
            Tab(text: 'Members'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FeedTab(group: group, uid: widget.uid,
              onPinAnnouncement: isCreator ? () => _showPinAnnouncementSheet(context, group) : null,
              onUnpinAnnouncement: isCreator ? () => _removePinnedAnnouncement(group) : null),
          _QuestionsTab(group: group, uid: widget.uid),
          _LeaderboardTab(group: group),
          _MembersTab(group: group, currentUid: widget.uid,
              onRemoveMember: isCreator ? (memberUid) => _confirmRemoveMember(context, group, memberUid) : null),
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

  // ── Edit Group ──────────────────────────────────────────────────────────────

  void _showEditGroupSheet(BuildContext context, Group group) {
    final nameCtrl = TextEditingController(text: group.name);
    final topicCtrl = TextEditingController(text: group.topic);
    final descCtrl = TextEditingController(text: group.description ?? '');
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit Group', style: AppTypography.displaySmall),
              const SizedBox(height: 20),
              const Text('Group name', style: AppTypography.labelSmall),
              const SizedBox(height: 6),
              TextField(
                controller: nameCtrl,
                style: AppTypography.bodyLarge,
                decoration: const InputDecoration(hintText: 'e.g. Sunday Morning Bible Study'),
              ),
              const SizedBox(height: 16),
              const Text('Topic / focus', style: AppTypography.labelSmall),
              const SizedBox(height: 6),
              TextField(
                controller: topicCtrl,
                style: AppTypography.bodyLarge,
                decoration: const InputDecoration(hintText: 'e.g. Book of John, Prayer & Fasting'),
              ),
              const SizedBox(height: 16),
              const Text('Description (optional)', style: AppTypography.labelSmall),
              const SizedBox(height: 6),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: AppTypography.bodyLarge,
                decoration: const InputDecoration(hintText: 'What is this group studying?'),
              ),
              const SizedBox(height: 24),
              FlameCTAButton(
                label: 'Save',
                isLoading: saving,
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  setModalState(() => saving = true);
                  try {
                    await FirestoreService().updateGroupInfo(
                      group.id,
                      name: name,
                      topic: topicCtrl.text.trim(),
                      description: descCtrl.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (_) {
                    setModalState(() => saving = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reading Plan ─────────────────────────────────────────────────────────────

  void _showReadingPlanSheet(BuildContext context, Group group) {
    final entries = group.readingPlan
        .map((e) => _PlanEntry(
              date: e['date'] as String? ?? '',
              passage: e['passage'] as String? ?? '',
            ))
        .toList();
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Reading Plan', style: AppTypography.displaySmall)),
                  TextButton.icon(
                    onPressed: () => setModalState(() => entries.add(_PlanEntry())),
                    icon: const Icon(Icons.add, size: 16, color: AppColors.warmGold),
                    label: const Text('Add', style: TextStyle(color: AppColors.warmGold)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Set passages and dates for your group\'s study schedule.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No entries yet — tap Add to create your first reading.',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: e.dateCtrl,
                              style: AppTypography.bodyMedium,
                              decoration: const InputDecoration(
                                hintText: 'Jun 18',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: e.passageCtrl,
                              style: AppTypography.bodyMedium,
                              decoration: const InputDecoration(
                                hintText: 'Romans 5:1-21',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                            onPressed: () => setModalState(() => entries.removeAt(i)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 20),
              FlameCTAButton(
                label: 'Save Plan',
                isLoading: saving,
                onPressed: () async {
                  setModalState(() => saving = true);
                  try {
                    final plan = entries
                        .where((e) => e.passageCtrl.text.trim().isNotEmpty)
                        .map((e) => {
                              'date': e.dateCtrl.text.trim(),
                              'passage': e.passageCtrl.text.trim(),
                            })
                        .toList();
                    await FirestoreService().updateReadingPlan(group.id, plan);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (_) {
                    setModalState(() => saving = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pin Announcement ─────────────────────────────────────────────────────────

  void _showPinAnnouncementSheet(BuildContext context, Group group) {
    final existing = group.pinnedAnnouncement?['text'] as String? ?? '';
    final ctrl = TextEditingController(text: existing);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📌 Pin Announcement', style: AppTypography.displaySmall),
              const SizedBox(height: 4),
              Text(
                'Pinned to the top of the Feed for all members.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                style: AppTypography.bodyLarge,
                decoration: const InputDecoration(
                  hintText: 'e.g. This week we\'re studying Romans 5–8. See you Sunday!',
                ),
              ),
              const SizedBox(height: 20),
              FlameCTAButton(
                label: 'Pin',
                isLoading: saving,
                onPressed: () async {
                  if (ctrl.text.trim().isEmpty) return;
                  setModalState(() => saving = true);
                  try {
                    await FirestoreService().pinAnnouncement(group.id, ctrl.text.trim(), widget.uid);
                    if (ctx.mounted) Navigator.pop(ctx);
                  } catch (_) {
                    setModalState(() => saving = false);
                  }
                },
              ),
              if (existing.isNotEmpty) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    await FirestoreService().unpinAnnouncement(group.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Remove pinned announcement',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removePinnedAnnouncement(Group group) async {
    await FirestoreService().unpinAnnouncement(group.id);
  }

  // ── Remove Member ─────────────────────────────────────────────────────────────

  Future<void> _confirmRemoveMember(BuildContext context, Group group, String memberUid) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Remove member?'),
        content: const Text('This person will be removed from the group and will need a new invite code to rejoin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirestoreService().removeGroupMember(group.id, memberUid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove member: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Group group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Delete Group?'),
        content: Text('This will permanently delete ${group.name} and all its content. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(group.id);

      // Delete subcollections before the parent doc
      for (final sub in ['members', 'questions', 'activity', 'feed']) {
        final snap = await groupRef.collection(sub).get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      }

      await groupRef.delete();
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting group: $e')),
      );
    }
  }

  Future<void> _confirmLeave(BuildContext context, Group group) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Leave Group?'),
        content: Text('Are you sure you want to leave ${group.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final groupRef = FirebaseFirestore.instance.collection('groups').doc(group.id);
      await Future.wait([
        groupRef.collection('members').doc(widget.uid).delete(),
        groupRef.update({'memberIds': FieldValue.arrayRemove([widget.uid])}),
      ]);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error leaving group: $e')),
      );
    }
  }

  void _shareInvite(Group group) {
    HapticFeedback.lightImpact();
    Share.share('Join my StudyFire Bible study group "${group.name}"! Use invite code: ${group.inviteCode}');
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
  final Group group;
  final String uid;
  final VoidCallback? onPinAnnouncement;
  final VoidCallback? onUnpinAnnouncement;

  const _FeedTab({
    required this.group,
    required this.uid,
    this.onPinAnnouncement,
    this.onUnpinAnnouncement,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(groupFeedProvider(group.id));
    final isCreator = group.creatorUid == uid;
    final announcement = group.pinnedAnnouncement;
    final plan = group.readingPlan;

    return feedAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load feed')),
      data: (items) {
        final hasHeader = announcement != null || plan.isNotEmpty || isCreator;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: (hasHeader ? 1 : 0) + (items.isEmpty ? 1 : items.length),
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            // Header slot: pinned announcement + reading plan
            if (hasHeader && i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (announcement != null)
                    _PinnedAnnouncementCard(
                      text: announcement['text'] as String? ?? '',
                      isCreator: isCreator,
                      onEdit: onPinAnnouncement,
                      onRemove: onUnpinAnnouncement,
                    )
                  else if (isCreator)
                    GestureDetector(
                      onTap: onPinAnnouncement,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.surfaceVariant),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.push_pin_outlined, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text('Pin an announcement for the group',
                                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  if (plan.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ReadingPlanCard(plan: plan),
                  ],
                  if (hasHeader && items.isNotEmpty) const SizedBox(height: 4),
                ],
              );
            }

            final feedIdx = hasHeader ? i - 1 : i;
            if (items.isEmpty) {
              return Center(
                child: Text(
                  'No activity yet — be the first to post!',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                ),
              );
            }
            return _FeedItemCard(item: items[feedIdx], currentUid: uid, groupId: group.id);
          },
        );
      },
    );
  }
}

// ── Plan Entry Helper ──────────────────────────────────────────────────────────

class _PlanEntry {
  final TextEditingController dateCtrl;
  final TextEditingController passageCtrl;

  _PlanEntry({String date = '', String passage = ''})
      : dateCtrl = TextEditingController(text: date),
        passageCtrl = TextEditingController(text: passage);
}

// ── Pinned Announcement Card ──────────────────────────────────────────────────

class _PinnedAnnouncementCard extends StatelessWidget {
  final String text;
  final bool isCreator;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  const _PinnedAnnouncementCard({
    required this.text,
    required this.isCreator,
    this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.indigoAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.indigoAccent.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.push_pin, size: 14, color: AppColors.indigoAccent),
              const SizedBox(width: 6),
              Text('Pinned',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.indigoAccent, fontSize: 11)),
              const Spacer(),
              if (isCreator) ...[
                GestureDetector(
                  onTap: onEdit,
                  child: const Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

// ── Reading Plan Card ─────────────────────────────────────────────────────────

class _ReadingPlanCard extends StatelessWidget {
  final List<Map<String, dynamic>> plan;

  const _ReadingPlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warmGold.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warmGold.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, size: 14, color: AppColors.warmGold),
              const SizedBox(width: 6),
              Text('Reading Plan',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          ...plan.take(5).map((entry) {
            final passage = entry['passage'] as String? ?? '';
            final date = entry['date'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(date,
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(passage, style: AppTypography.bodyMedium),
                  ),
                ],
              ),
            );
          }),
          if (plan.length > 5)
            Text('+ ${plan.length - 5} more',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[dt.month - 1]} ${dt.day}';
}

class _FeedItemCard extends StatelessWidget {
  final FeedItem item;
  final String currentUid;
  final String groupId;

  const _FeedItemCard({
    required this.item,
    required this.currentUid,
    required this.groupId,
  });

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

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.deepSlate,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _FeedThreadSheet(
          item: item,
          groupId: groupId,
          uid: currentUid,
        ),
      ),
      child: Container(
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
                  Row(
                    children: [
                      Expanded(child: Text(item.authorName, style: AppTypography.labelSmall)),
                      Text(
                        _timeAgo(item.timestamp),
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(displayText, style: AppTypography.bodyMedium),
                  if (item.commentCount > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${item.commentCount} ${item.commentCount == 1 ? 'reply' : 'replies'}',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'Reply…',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
            final isOwner = q.authorUid == uid;
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => _QuestionDetailScreen(question: q, groupId: group.id, uid: uid),
              )),
              child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.indigoAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(q.question, style: AppTypography.bodyLarge)),
                      if (isOwner)
                        GestureDetector(
                          onTap: () => _confirmDeleteQuestion(context, group.id, q.id),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
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
            ));
          },
        );
      },
    );
  }
}

Future<void> _confirmDeleteQuestion(BuildContext context, String groupId, String questionId) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardDark,
      title: const Text('Delete question?'),
      content: const Text('This will remove your question and all its replies. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );
  if (confirm != true) return;
  try {
    final questionRef = FirebaseFirestore.instance
        .collection('groupQuestions')
        .doc(groupId)
        .collection('questions')
        .doc(questionId);

    // Delete comments subcollection first
    final commentsSnap = await FirebaseFirestore.instance
        .collection('groupComments')
        .doc('${groupId}_$questionId')
        .collection('comments')
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in commentsSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(questionRef);
    await batch.commit();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete question: $e')),
      );
    }
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

// ── Members Tab ───────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final Group group;
  final String currentUid;
  final void Function(String memberUid)? onRemoveMember;

  const _MembersTab({
    required this.group,
    required this.currentUid,
    this.onRemoveMember,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(group.id));

    return membersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Could not load members')),
      data: (members) {
        // Sort: creator first, then by name
        final sorted = [...members]..sort((a, b) {
          if (a.role == GroupRole.creator) return -1;
          if (b.role == GroupRole.creator) return 1;
          return a.name.compareTo(b.name);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final m = sorted[i];
            final isCreator = m.role == GroupRole.creator;
            final isMe = m.uid == currentUid;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isCreator
                        ? AppColors.warmGold.withOpacity(0.2)
                        : AppColors.indigoAccent.withOpacity(0.2),
                    child: Text(
                      m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: isCreator ? AppColors.warmGold : AppColors.indigoAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isMe ? '${m.name} (you)' : m.name,
                              style: AppTypography.labelSmall,
                            ),
                            if (isCreator) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warmGold.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Leader',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.warmGold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text(
                              '${m.streak} day streak',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text('${m.weeklyXp} XP', style: AppTypography.xpLabel),
                  if (onRemoveMember != null && !isMe && !isCreator)
                    GestureDetector(
                      onTap: () => onRemoveMember!(m.uid),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.person_remove_outlined, size: 18, color: Colors.redAccent),
                      ),
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
                final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
                final profileData = userDoc.data()?['profile'] as Map<String, dynamic>? ?? {};
                final authorName = (profileData['name'] as String?)?.isNotEmpty == true
                    ? profileData['name'] as String
                    : FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? 'Member';
                final qUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                if (qUid.isNotEmpty) { final xs = XpService(); xs.accumulateXp(qUid, XpRewards.postQuestionToGroup); xs.flushSession(qUid).catchError((_){}); }
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

// ── Question Detail Screen ────────────────────────────────────────────────────

class _QuestionDetailScreen extends StatefulWidget {
  final GroupQuestion question;
  final String groupId;
  final String uid;

  const _QuestionDetailScreen({
    required this.question,
    required this.groupId,
    required this.uid,
  });

  @override
  State<_QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<_QuestionDetailScreen> {
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _postComment() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
      final profileData = userDoc.data()?['profile'] as Map<String, dynamic>? ?? {};
      final authorName = (profileData['name'] as String?)?.isNotEmpty == true
          ? profileData['name'] as String
          : FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? 'Member';
      final batch = FirebaseFirestore.instance.batch();
      
      final commentRef = FirebaseFirestore.instance
          .collection('groupComments')
          .doc(widget.groupId + '_' + widget.question.id)
          .collection('comments')
          .doc();
      
      batch.set(commentRef, {
        'authorId': widget.uid,
        'authorName': authorName,
        'text': _ctrl.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Increment comment count
      batch.update(
        FirebaseFirestore.instance
            .collection('groupQuestions')
            .doc(widget.groupId)
            .collection('questions')
            .doc(widget.question.id),
        {'commentCount': FieldValue.increment(1)},
      );

      await batch.commit();
      _ctrl.clear();
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      debugPrint('Comment error: \$e');
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(title: const Text('Discussion')),
      body: Column(
        children: [
          // Question header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: AppColors.cardDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.question.question, style: AppTypography.bodyLarge),
                if (widget.question.scriptureRef != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warmGold.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined, size: 14, color: AppColors.warmGold),
                        const SizedBox(width: 6),
                        Text(widget.question.scriptureRef!, style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text('Asked by ${widget.question.authorName}',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Comments list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groupComments')
                  .doc(widget.groupId + '_' + widget.question.id)
                  .collection('comments')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text('No replies yet — be the first!',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.warmGold.withOpacity(0.2),
                            child: Text(
                              (data['authorName'] as String? ?? 'M')[0].toUpperCase(),
                              style: const TextStyle(color: AppColors.warmGold, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.cardDark,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(data['authorName'] ?? 'Member',
                                      style: AppTypography.labelSmall),
                                  const SizedBox(height: 4),
                                  Text(data['text'] ?? '',
                                      style: AppTypography.bodyMedium),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Comment input
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              border: Border(top: BorderSide(color: AppColors.surface)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: AppTypography.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Add a reply…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (_) => _postComment(),
                  ),
                ),
                _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: AppColors.warmGold),
                        onPressed: _postComment,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feed Thread Sheet ──────────────────────────────────────────────────────────

class _FeedThreadSheet extends StatefulWidget {
  final FeedItem item;
  final String groupId;
  final String uid;

  const _FeedThreadSheet({
    required this.item,
    required this.groupId,
    required this.uid,
  });

  @override
  State<_FeedThreadSheet> createState() => _FeedThreadSheetState();
}

class _FeedThreadSheetState extends State<_FeedThreadSheet> {
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _postReply() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final profileData = userDoc.data()?['profile'] as Map<String, dynamic>? ?? {};
      final authorName = (profileData['name'] as String?)?.isNotEmpty == true
          ? profileData['name'] as String
          : FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? 'Member';

      final batch = FirebaseFirestore.instance.batch();

      final replyRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('feed')
          .doc(widget.item.id)
          .collection('replies')
          .doc();

      batch.set(replyRef, {
        'authorUid': widget.uid,
        'authorName': authorName,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });

      batch.update(
        FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.groupId)
            .collection('feed')
            .doc(widget.item.id),
        {'commentCount': FieldValue.increment(1)},
      );

      await batch.commit();
      _ctrl.clear();
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = (widget.item.content['text'] as String?) ??
        (widget.item.content['message'] as String?) ??
        '${widget.item.authorName} shared something.';

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Original post
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.surface)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.warmGold.withOpacity(0.2),
                      child: Text(
                        widget.item.authorName.isNotEmpty
                            ? widget.item.authorName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(color: AppColors.warmGold, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.item.authorName, style: AppTypography.labelSmall),
                    ),
                    Text(
                      _timeAgo(widget.item.timestamp),
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(displayText, style: AppTypography.bodyMedium),
              ],
            ),
          ),

          // Replies list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('feed')
                  .doc(widget.item.id)
                  .collection('replies')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No replies yet — be the first!',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final name = data['authorName'] as String? ?? 'Member';
                    final text = data['text'] as String? ?? '';
                    final ts = (data['timestamp'] as Timestamp?)?.toDate();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: AppColors.indigoAccent.withOpacity(0.2),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppColors.indigoAccent, fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.cardDark,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: Text(name, style: AppTypography.labelSmall)),
                                      if (ts != null)
                                        Text(
                                          _timeAgo(ts),
                                          style: AppTypography.bodySmall.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(text, style: AppTypography.bodyMedium),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Reply input
          Container(
            padding: EdgeInsets.fromLTRB(
              12, 8, 12, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardDark,
              border: Border(top: BorderSide(color: AppColors.surface)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: false,
                    style: AppTypography.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Add a reply…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: (_) => _postReply(),
                  ),
                ),
                _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send_rounded, color: AppColors.warmGold),
                        onPressed: _postReply,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
