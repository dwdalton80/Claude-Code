import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/streak_service.dart';
import '../../models/journal_entry.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../models/memory_verse.dart';
import '../memory_verse/memory_verse_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: const Text('Study'),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _showSearch(context),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.warmGold,
          labelColor: AppColors.warmGold,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Journal'),
            Tab(text: 'Memory Verses'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              _FilterChips(),
              const Expanded(child: _JournalList()),
            ],
          ),
          const _MemoryVerseList(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () => _openNewNote(context),
              backgroundColor: AppColors.flameOrange,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _JournalSearch());
  }

  void _openNewNote(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
    );
  }
}

class _FilterChips extends StatefulWidget {
  @override
  State<_FilterChips> createState() => _FilterChipsState();
}

class _FilterChipsState extends State<_FilterChips> {
  String _selected = 'all';

  static const _filters = [
    ('all', 'All'),
    ('sermon', 'Sermon'),
    ('personalStudy', 'Personal Study'),
    ('readingPlan', 'Reading Plan'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: _filters.map((f) {
          final isSelected = _selected == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f.$2),
              selected: isSelected,
              onSelected: (_) => setState(() => _selected = f.$1),
              selectedColor: AppColors.warmGold.withOpacity(0.2),
              labelStyle: AppTypography.labelSmall.copyWith(
                color: isSelected ? AppColors.warmGold : AppColors.textSecondary,
              ),
              side: BorderSide(
                color: isSelected ? AppColors.warmGold : AppColors.surface,
              ),
              backgroundColor: AppColors.surface,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _JournalList extends StatefulWidget {
  const _JournalList();

  @override
  State<_JournalList> createState() => _JournalListState();
}

class _JournalListState extends State<_JournalList> {
  List<JournalEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) { setState(() => _loading = false); return; }
    final entries = await FirestoreService().getJournalEntries(uid);
    if (mounted) setState(() { _entries = entries; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📝', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text('No notes yet', style: AppTypography.bodyLarge),
            const SizedBox(height: 8),
            Text('Tap + to create your first note', style: AppTypography.bodySmall),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warmGold.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text('AI Debrief', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
                    const SizedBox(height: 4),
                    Text(
                      'Write sermon or study notes and tap "Unpack This" to get AI-powered insights, application points, and discussion questions.',
                      style: AppTypography.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _entries.length,
        itemBuilder: (_, i) {
          final e = _entries[i];
          return Dismissible(
            key: Key(e.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            onDismissed: (_) async {
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              await FirestoreService().deleteJournalEntry(uid, e.id);
              setState(() => _entries.removeAt(i));
            },
            child: Card(
              color: AppColors.cardDark,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(e.title, style: AppTypography.labelMedium),
                subtitle: Text(
                  e.content.substring(0, e.content.length.clamp(0, 80)),
                  style: AppTypography.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${e.date.month}/${e.date.day}/${e.date.year}',
                  style: AppTypography.bodySmall,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => NoteEditorScreen(entry: e)),
                ).then((_) => _load()),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _JournalSearch extends SearchDelegate<String> {
  @override
  List<Widget> buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, ''),
      );

  @override
  Widget buildResults(BuildContext context) => const SizedBox.shrink();

  @override
  Widget buildSuggestions(BuildContext context) => const SizedBox.shrink();
}

// ── Note Editor ───────────────────────────────────────────────────────────────

class NoteEditorScreen extends ConsumerStatefulWidget {
  final JournalEntry? entry;
  final String? verseRef;
  final String? verseText;

  const NoteEditorScreen({super.key, this.entry, this.verseRef, this.verseText});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _speakerCtrl = TextEditingController();
  final List<String> _scriptureRefs = [];
  JournalType _type = JournalType.personalStudy;
  DateTime _date = DateTime.now();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    if (widget.entry != null) {
      final e = widget.entry!;
      _titleCtrl.text = e.title;
      _contentCtrl.text = e.content;
      _speakerCtrl.text = e.speaker ?? '';
      _scriptureRefs.addAll(e.scriptureRefs);
      _type = e.type;
      _date = e.date;
    } else if (widget.verseRef != null) {
      _scriptureRefs.add(widget.verseRef!);
      _type = JournalType.personalStudy;
      if (widget.verseText != null) {
        _contentCtrl.text = '"${widget.verseText}"\n\n';
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _speakerCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || _contentCtrl.text.trim().isEmpty) return;
    final db = FirestoreService();
    final now = DateTime.now();
    final entry = JournalEntry(
      id: widget.entry?.id ?? '',
      title: _titleCtrl.text.trim().isEmpty
          ? _contentCtrl.text.trim().substring(0, _contentCtrl.text.trim().length.clamp(0, 40))
          : _titleCtrl.text.trim(),
      content: _contentCtrl.text.trim(),
      type: _type,
      date: _date,
      speaker: _speakerCtrl.text.trim().isEmpty ? null : _speakerCtrl.text.trim(),
      scriptureRefs: _scriptureRefs,
      aiApplicationPoints: widget.entry?.aiApplicationPoints ?? [],
      aiDiscussionQuestions: widget.entry?.aiDiscussionQuestions ?? [],
      aiBigIdea: widget.entry?.aiBigIdea,
      aiPersonalChallenge: widget.entry?.aiPersonalChallenge,
      aiDebriefGenerated: widget.entry?.aiDebriefGenerated ?? false,
      aiDebriefUsedThisMonth: widget.entry?.aiDebriefUsedThisMonth ?? 0,
      createdAt: widget.entry?.createdAt ?? now,
      updatedAt: now,
    );
    await db.saveJournalEntry(uid, entry);
    StreakService().recordActivity(uid).catchError((_) {});
    if (mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Text(_type == JournalType.sermon ? 'Sermon Notes' : 'Study Notes'),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              _saved ? 'Saved ✓' : 'Save',
              style: AppTypography.bodyMedium.copyWith(
                color: _saved ? AppColors.emerald : AppColors.warmGold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type toggle
            _TypeToggle(
              selected: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 16),

            if (_type == JournalType.sermon) ...[
              // Sermon title
              TextField(
                controller: _titleCtrl,
                style: AppTypography.displaySmall,
                decoration: const InputDecoration(
                  hintText: 'Sermon title',
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
              const SizedBox(height: 8),
              // Speaker
              TextField(
                controller: _speakerCtrl,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                decoration: const InputDecoration(
                  hintText: 'Speaker (optional)',
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
              const SizedBox(height: 8),
              // Date
              GestureDetector(
                onTap: _pickDate,
                child: Text(
                  _formatDate(_date),
                  style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold),
                ),
              ),
              const SizedBox(height: 16),
              // Scripture refs chips
              _ScriptureRefRow(
                refs: _scriptureRefs,
                onAdd: _addScriptureRef,
                onRemove: (ref) => setState(() => _scriptureRefs.remove(ref)),
              ),
              const SizedBox(height: 16),
            ],

            // Body
            TextField(
              controller: _contentCtrl,
              maxLines: null,
              style: AppTypography.bodyLarge,
              decoration: InputDecoration(
                hintText: _type == JournalType.sermon
                    ? 'Notes…\n\nTip: Type @ to link a scripture reference'
                    : 'What stood out? What does this mean? What will I do?',
                border: InputBorder.none,
                filled: false,
              ),
            ),

            const SizedBox(height: 32),
            if (_contentCtrl.text.length >= 20) ...[
              FlameCTAButton(
                label: '✨ Unpack This',
                onPressed: _unpackThis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.warmGold),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _addScriptureRef() {
    // Show scripture search bottom sheet
  }

  void _unpackThis() async {
    if (_contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some notes first')),
      );
      return;
    }
    bool dialogShowing = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ).then((_) => dialogShowing = false);
    dialogShowing = true;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'generateDebrief',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await fn.call({
        'noteContent': _contentCtrl.text.trim(),
        'sermonTitle': _titleCtrl.text.trim(),
        'speaker': _speakerCtrl.text.trim(),
        'scriptureRefs': _scriptureRefs,
        'studyLevel': 'intermediate',
      });
      if (mounted && dialogShowing) Navigator.of(context, rootNavigator: true).pop();
      final data = result.data as Map<String, dynamic>;
      if (mounted) {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.cardDark,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (_, ctrl) => SingleChildScrollView(
              controller: ctrl,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('✨ AI Debrief', style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold)),
                  const SizedBox(height: 16),
                  if (data['bigIdea'] != null) ...[
                    Text('Big Idea', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(data['bigIdea'] as String, style: AppTypography.bodyLarge),
                    const SizedBox(height: 16),
                  ],
                  if (data['applicationPoints'] != null && (data['applicationPoints'] as List).isNotEmpty) ...[
                    Text('Apply This Week', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    ...(data['applicationPoints'] as List).map((p) {
                      final text = p is Map ? (p['text'] as String? ?? '') : (p as String? ?? '');
                      if (text.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: AppColors.warmGold)),
                            Expanded(child: Text(text, style: AppTypography.bodyMedium)),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && dialogShowing) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI is unavailable right now — please try again later.')),
      );
    }
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _TypeToggle extends StatelessWidget {
  final JournalType selected;
  final ValueChanged<JournalType> onChanged;

  const _TypeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(
          label: 'Sermon',
          selected: selected == JournalType.sermon,
          onTap: () => onChanged(JournalType.sermon),
        ),
        const SizedBox(width: 8),
        _Chip(
          label: 'Personal Study',
          selected: selected == JournalType.personalStudy,
          onTap: () => onChanged(JournalType.personalStudy),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.warmGold.withOpacity(0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.warmGold : AppColors.surfaceVariant,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: selected ? AppColors.warmGold : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ScriptureRefRow extends StatelessWidget {
  final List<String> refs;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  const _ScriptureRefRow({
    required this.refs,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.warmGold.withOpacity(0.5), style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 14, color: AppColors.warmGold),
                  const SizedBox(width: 4),
                  Text(
                    'Add Scripture',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                  ),
                ],
              ),
            ),
          ),
          ...refs.map((ref) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onLongPress: () => onRemove(ref),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.warmGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      ref,
                      style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Memory Verse List ─────────────────────────────────────────────────────────

class _MemoryVerseList extends StatefulWidget {
  const _MemoryVerseList();

  @override
  State<_MemoryVerseList> createState() => _MemoryVerseListState();
}

class _MemoryVerseListState extends State<_MemoryVerseList> {
  List<dynamic> _verses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('memoryVerses')
        .doc(uid)
        .collection('verses')
        .get();
    final verses = snap.docs.map((d) => MemoryVerse.fromFirestore(d)).toList();
    if (mounted) setState(() {
      _verses = verses;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_verses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🧠', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text('No memory verses yet', style: AppTypography.bodyLarge),
              const SizedBox(height: 8),
              Text(
                'Long press any verse in the Reader and tap "Add to Memory Verse" to start memorizing.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _verses.length,
      itemBuilder: (_, i) {
        final verse = _verses[i];
        final mastered = verse.currentStage == MemoryVerseStage.stage5;
        return Card(
          color: AppColors.cardDark,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(verse.reference, style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(verse.text, style: AppTypography.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ...List.generate(5, (s) => Container(
                      width: 24, height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: s < verse.currentStage.index + 1
                            ? AppColors.warmGold
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
                    const SizedBox(width: 8),
                    Text(
                      mastered ? '✅ Mastered' : 'Stage ${verse.currentStage.index}/5',
                      style: AppTypography.bodySmall.copyWith(
                        color: mastered ? Colors.green : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: mastered
                ? null
                : IconButton(
                    icon: const Icon(Icons.play_arrow, color: AppColors.warmGold),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => MemoryVerseScreen(verse: verse, uid: FirebaseAuth.instance.currentUser!.uid),
                      )).then((_) => _load());
                    },
                  ),
          ),
        );
      },
    );
  }
}
