import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/streak_service.dart';
import '../../models/journal_entry.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/premium_gate.dart';
import '../../models/memory_verse.dart';
import '../../app.dart';
import '../memory_verse/memory_verse_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final journalFilterProvider = StateProvider<String>((ref) => 'all');
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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('New Journal Entry', style: AppTypography.labelLarge),
            const SizedBox(height: 16),
            _NewEntryOption(
              emoji: '⛪',
              title: 'Sermon Notes',
              subtitle: 'Capture notes during a service — AI organizes them for you',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NoteEditorScreen(initialType: JournalType.sermon),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _NewEntryOption(
              emoji: '📖',
              title: 'Personal Study',
              subtitle: 'Reflect on a verse, passage, or topic',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NoteEditorScreen(initialType: JournalType.personalStudy),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  static const _filters = [
    ('all', 'All'),
    ('sermon', 'Sermon'),
    ('personalStudy', 'Personal Study'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(journalFilterProvider);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: _filters.map((f) {
          final isSelected = selected == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(f.$2),
              selected: isSelected,
              onSelected: (_) => ref.read(journalFilterProvider.notifier).state = f.$1,
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

class _JournalList extends ConsumerStatefulWidget {
  const _JournalList();

  @override
  ConsumerState<_JournalList> createState() => _JournalListState();
}

class _JournalListState extends ConsumerState<_JournalList> {
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
    final filter = ref.watch(journalFilterProvider);
    final filtered = filter == 'all' 
        ? _entries 
        : _entries.where((e) => e.type.name == filter).toList();
    if (filtered.isEmpty) {
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
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final e = filtered[i];
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
              setState(() => _entries.removeWhere((entry) => entry.id == e.id));
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
  final JournalType? initialType;

  const NoteEditorScreen({super.key, this.entry, this.verseRef, this.verseText, this.initialType});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  final _speakerCtrl = TextEditingController();
  final List<String> _scriptureRefs = [];
  late JournalType _type;
  DateTime _date = DateTime.now();
  bool _saved = false;

  // Stores imported verse text displayed as a card, keyed by ref
  final Map<String, String> _verseTexts = {};

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? JournalType.personalStudy;
    _contentCtrl.addListener(_onContentChanged);
    _contentCtrl.addListener(_onAnyEdit);
    _titleCtrl.addListener(_onAnyEdit);
    if (widget.entry != null) {
      final e = widget.entry!;
      _titleCtrl.text = e.title;
      // Strip legacy imported verse text from content if present
      final content = e.content;
      _contentCtrl.text = content;
      _speakerCtrl.text = e.speaker ?? '';
      _scriptureRefs.addAll(e.scriptureRefs);
      _type = e.type;
      _date = e.date;
    } else if (widget.verseRef != null) {
      _scriptureRefs.add(widget.verseRef!);
      _type = widget.initialType ?? JournalType.personalStudy;
      if (widget.verseText != null) {
        _verseTexts[widget.verseRef!] = widget.verseText!;
      }
    }
  }

  bool _atListening = false;

  void _onAnyEdit() {
    if (_saved) setState(() => _saved = false);
  }

  void _onContentChanged() {
    if (_atListening) return;
    final text = _contentCtrl.text;
    final cursor = _contentCtrl.selection.baseOffset;
    if (cursor > 0 && cursor <= text.length && text[cursor - 1] == '@') {
      _atListening = true;
      // Remove the @ and open the scripture picker
      final before = text.substring(0, cursor - 1);
      final after = text.substring(cursor);
      _contentCtrl.value = TextEditingValue(
        text: before + after,
        selection: TextSelection.collapsed(offset: before.length),
      );
      _addScriptureRefInline().then((_) => _atListening = false);
    }
  }

  Future<void> _addScriptureRefInline() async {
    final refCtrl = TextEditingController();
    String? errorText;
    bool loading = false;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Link Scripture', style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold)),
              const SizedBox(height: 4),
              Text('Single verse or range', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              TextField(
                controller: refCtrl,
                autofocus: true,
                style: AppTypography.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'e.g. John 3:16 or John 3:22-24',
                  hintStyle: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
                  errorText: errorText,
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.flameOrange),
                  onPressed: loading ? null : () async {
                    final ref = refCtrl.text.trim();
                    if (ref.isEmpty) return;
                    setSheetState(() { loading = true; errorText = null; });
                    try {
                      final verse = await FirestoreService().getVerseOrRange('kjv', ref);
                      if (verse == null) {
                        setSheetState(() { loading = false; errorText = 'Reference not found — try e.g. John 3:16 or John 3:22-24'; });
                        return;
                      }
                      if (mounted) {
                        Navigator.of(sheetCtx).pop();
                        // Insert reference inline at cursor
                        final cur = _contentCtrl.selection.baseOffset;
                        final t = _contentCtrl.text;
                        final newText = '${t.substring(0, cur)}[$ref] ${t.substring(cur)}';
                        _contentCtrl.value = TextEditingValue(
                          text: newText,
                          selection: TextSelection.collapsed(offset: cur + ref.length + 3),
                        );
                        // Also track for Personal Study cards
                        if (_type == JournalType.personalStudy) {
                          setState(() {
                            if (!_scriptureRefs.contains(ref)) _scriptureRefs.add(ref);
                            _verseTexts[ref] = verse.text;
                          });
                        }
                      }
                    } catch (_) {
                      setSheetState(() { loading = false; errorText = 'Could not load verse — try again'; });
                    }
                  },
                  child: loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Link'),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  void dispose() {
    _contentCtrl.removeListener(_onContentChanged);
    _contentCtrl.removeListener(_onAnyEdit);
    _titleCtrl.removeListener(_onAnyEdit);
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

            if (_type == JournalType.personalStudy) ...[
              // Title
              TextField(
                controller: _titleCtrl,
                style: AppTypography.displaySmall,
                decoration: const InputDecoration(
                  hintText: 'Title (optional)',
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
              const SizedBox(height: 8),
              // Scripture cards — one per added reference
              ..._scriptureRefs.map((ref) => _ScriptureCard(
                reference: ref,
                verseText: _verseTexts[ref],
                onRemove: () => setState(() {
                  _scriptureRefs.remove(ref);
                  _verseTexts.remove(ref);
                }),
              )),
              // Add Scripture button — uses OutlinedButton for reliable tap handling
              OutlinedButton.icon(
                onPressed: _addScriptureRef,
                icon: const Icon(Icons.add, size: 14, color: AppColors.warmGold),
                label: Text(
                  'Add Scripture',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.warmGold.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(height: 16),
              // Divider before notes
              if (_scriptureRefs.isNotEmpty) ...[
                const Divider(color: AppColors.surface, height: 1),
                const SizedBox(height: 12),
              ],
            ],

            // Body
            TextField(
              controller: _contentCtrl,
              maxLines: null,
              style: AppTypography.bodyLarge,
              decoration: InputDecoration(
                hintText: _type == JournalType.sermon
                    ? 'Notes…\n\n(Tip: type @ to link a scripture reference)'
                    : 'What stood out? What does this mean? What will I do?\n\n(Tip: type @ to link a scripture reference)',
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
    final refCtrl = TextEditingController();
    String? errorText;
    bool loading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add Scripture', style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold)),
                const SizedBox(height: 4),
                Text('Single verse or range', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  controller: refCtrl,
                  autofocus: true,
                  style: AppTypography.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'e.g. John 3:16 or John 3:22-24',
                    hintStyle: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary),
                    errorText: errorText,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.flameOrange),
                    onPressed: loading ? null : () async {
                      final ref = refCtrl.text.trim();
                      if (ref.isEmpty) return;
                      setSheetState(() { loading = true; errorText = null; });
                      try {
                        final verse = await FirestoreService().getVerseOrRange('kjv', ref);
                        if (verse == null) {
                          setSheetState(() { loading = false; errorText = 'Reference not found — try e.g. John 3:16 or John 3:22-24'; });
                          return;
                        }
                        if (mounted) {
                          Navigator.of(sheetCtx).pop();
                          setState(() {
                            if (!_scriptureRefs.contains(ref)) {
                              _scriptureRefs.add(ref);
                            }
                            _verseTexts[ref] = verse.text;
                          });
                        }
                      } catch (_) {
                        setSheetState(() { loading = false; errorText = 'Could not load verse — try again'; });
                      }
                    },
                    child: loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add'),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<bool> _checkDebriefAccess() async {
    final profile = ref.read(currentProfileProvider).valueOrNull;
    if (profile?.isPremium ?? false) return true;

    // Free: 1 debrief per calendar month
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final monthKey = DateTime.now().toIso8601String().substring(0, 7); // YYYY-MM
    final ref2 = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('aiUsage').doc('debrief_$monthKey');
    final snap = await ref2.get();
    final count = snap.data()?['count'] as int? ?? 0;
    if (count >= 1) {
      if (mounted) {
        showPaywallSheet(
          context,
          featureName: 'AI Sermon Debrief',
          limitMessage: "You've used your free AI debrief this month. Upgrade for unlimited access.",
        );
      }
      return false;
    }
    // Increment before calling — prevents race condition double-use
    await ref2.set(
      {'count': count + 1, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    return true;
  }

  void _unpackThis() async {
    if (_contentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some notes first')),
      );
      return;
    }
    final allowed = await _checkDebriefAccess();
    if (!allowed) return;
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
      if (mounted && dialogShowing) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShowing = false;
      }
      // Yield a frame so the pop fully flushes before pushing the result sheet.
      await Future<void>.delayed(Duration.zero);
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
            builder: (_, ctrl) {
              // Build plain text for copy/share
              final buf = StringBuffer();
              buf.writeln('✨ AI Debrief — ${_titleCtrl.text.trim()}');
              buf.writeln();
              if (data['bigIdea'] != null) {
                buf.writeln('Big Idea');
                buf.writeln(data['bigIdea'] as String);
                buf.writeln();
              }
              final points = data['applicationPoints'] as List? ?? [];
              if (points.isNotEmpty) {
                buf.writeln('Apply This Week');
                for (final p in points) {
                  final t = p is Map ? (p['text'] as String? ?? '') : (p as String? ?? '');
                  if (t.isNotEmpty) buf.writeln('• $t');
                }
                buf.writeln();
              }
              buf.write('— StudyFire · Based on Theological Christian Values');
              final plainText = buf.toString();

              return SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('✨ AI Debrief', style: AppTypography.labelLarge.copyWith(color: AppColors.warmGold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.textSecondary),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: plainText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                            );
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.share_rounded, size: 20, color: AppColors.textSecondary),
                          onPressed: () => Share.share(plainText),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (data['bigIdea'] != null) ...[
                      Text('Big Idea', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(data['bigIdea'] as String, style: AppTypography.bodyLarge),
                      const SizedBox(height: 16),
                    ],
                    if (points.isNotEmpty) ...[
                      Text('Apply This Week', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      ...points.map((p) {
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
              );
            },
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

// ── Scripture reference navigation helper ────────────────────────────────────

/// Parses "John 3:16" or "John 3:22-24" into reader route extra args.
Map<String, dynamic>? _readerArgsFromRef(String reference) {
  const bookIdMap = {
    'genesis': 'gen', 'exodus': 'exo', 'leviticus': 'lev', 'numbers': 'num',
    'deuteronomy': 'deu', 'joshua': 'jos', 'judges': 'jdg', 'ruth': 'rut',
    '1 samuel': '1sa', '2 samuel': '2sa', '1 kings': '1ki', '2 kings': '2ki',
    '1 chronicles': '1ch', '2 chronicles': '2ch', 'ezra': 'ezr', 'nehemiah': 'neh',
    'esther': 'est', 'job': 'job', 'psalms': 'psa', 'psalm': 'psa', 'proverbs': 'pro',
    'ecclesiastes': 'ecc', 'song of solomon': 'sng', 'isaiah': 'isa',
    'jeremiah': 'jer', 'lamentations': 'lam', 'ezekiel': 'ezk', 'daniel': 'dan',
    'hosea': 'hos', 'joel': 'jol', 'amos': 'amo', 'obadiah': 'oba',
    'jonah': 'jon', 'micah': 'mic', 'nahum': 'nam', 'habakkuk': 'hab',
    'zephaniah': 'zep', 'haggai': 'hag', 'zechariah': 'zec', 'malachi': 'mal',
    'matthew': 'mat', 'mark': 'mrk', 'luke': 'luk', 'john': 'jhn',
    'acts': 'act', 'romans': 'rom', '1 corinthians': '1co', '2 corinthians': '2co',
    'galatians': 'gal', 'ephesians': 'eph', 'philippians': 'php', 'colossians': 'col',
    '1 thessalonians': '1th', '2 thessalonians': '2th', '1 timothy': '1ti',
    '2 timothy': '2ti', 'titus': 'tit', 'philemon': 'phm', 'hebrews': 'heb',
    'james': 'jas', '1 peter': '1pe', '2 peter': '2pe', '1 john': '1jn',
    '2 john': '2jn', '3 john': '3jn', 'jude': 'jud', 'revelation': 'rev',
    // short IDs pass through
    'gen': 'gen', 'exo': 'exo', 'lev': 'lev', 'num': 'num', 'deu': 'deu',
    'jos': 'jos', 'jdg': 'jdg', 'rut': 'rut', '1sa': '1sa', '2sa': '2sa',
    '1ki': '1ki', '2ki': '2ki', '1ch': '1ch', '2ch': '2ch', 'ezr': 'ezr',
    'neh': 'neh', 'est': 'est', 'psa': 'psa', 'pro': 'pro',
    'ecc': 'ecc', 'sng': 'sng', 'isa': 'isa', 'jer': 'jer', 'lam': 'lam',
    'ezk': 'ezk', 'dan': 'dan', 'hos': 'hos', 'jol': 'jol', 'amo': 'amo',
    'oba': 'oba', 'jon': 'jon', 'mic': 'mic', 'nam': 'nam', 'hab': 'hab',
    'zep': 'zep', 'hag': 'hag', 'zec': 'zec', 'mal': 'mal', 'mat': 'mat',
    'mrk': 'mrk', 'luk': 'luk', 'jhn': 'jhn', 'act': 'act', 'rom': 'rom',
    '1co': '1co', '2co': '2co', 'gal': 'gal', 'eph': 'eph', 'php': 'php',
    'col': 'col', '1th': '1th', '2th': '2th', '1ti': '1ti', '2ti': '2ti',
    'tit': 'tit', 'phm': 'phm', 'heb': 'heb', 'jas': 'jas', '1pe': '1pe',
    '2pe': '2pe', '1jn': '1jn', '2jn': '2jn', '3jn': '3jn', 'jud': 'jud', 'rev': 'rev',
  };

  // Strip range suffix for parsing (John 3:22-24 → John 3:22)
  final stripped = reference.replaceAll(RegExp(r'-\d+$'), '').trim();
  final regex = RegExp(r'^(\d\s+)?([A-Za-z][A-Za-z\s]*?)\s+(\d+):(\d+)$');
  final m = regex.firstMatch(stripped);
  if (m == null) return null;

  final prefix = (m.group(1) ?? '').trim();
  final name = m.group(2)!.trim();
  final rawBook = prefix.isEmpty ? name.toLowerCase() : '$prefix $name'.toLowerCase();
  final bookId = bookIdMap[rawBook];
  if (bookId == null) return null;

  return {
    'book': bookId,
    'chapter': int.tryParse(m.group(3)!) ?? 1,
    'startVerse': int.tryParse(m.group(4)!) ?? 1,
  };
}

void _openInReader(BuildContext context, String reference) {
  final args = _readerArgsFromRef(reference);
  if (args == null) return;
  context.push('/reader', extra: args);
}

// ── Scripture Card (Personal Study) ──────────────────────────────────────────

class _ScriptureCard extends StatelessWidget {
  final String reference;
  final String? verseText;
  final VoidCallback onRemove;

  const _ScriptureCard({
    required this.reference,
    required this.verseText,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openInReader(context, reference),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.warmGold.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warmGold.withOpacity(0.25)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold accent bar
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: AppColors.warmGold,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            reference,
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.warmGold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.open_in_new, size: 11, color: AppColors.warmGold),
                        ],
                      ),
                      if (verseText != null && verseText!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '"$verseText"',
                          style: AppTypography.bodyMedium.copyWith(
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                onPressed: onRemove,
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scripture Ref Row (Sermon chips) ─────────────────────────────────────────

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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 14, color: AppColors.warmGold),
          label: Text(
            'Add Scripture',
            style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.warmGold.withOpacity(0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        ...refs.map((ref) => GestureDetector(
              onTap: () => _openInReader(context, ref),
              onLongPress: () => onRemove(ref),
              child: Chip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ref, style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
                    const SizedBox(width: 4),
                    const Icon(Icons.open_in_new, size: 10, color: AppColors.warmGold),
                  ],
                ),
                backgroundColor: AppColors.warmGold.withOpacity(0.15),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            )),
      ],
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

class _NewEntryOption extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NewEntryOption({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
