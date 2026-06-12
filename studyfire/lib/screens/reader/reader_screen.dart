import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/progress_bar.dart';

enum HighlightColor { yellow, green, blue, pink }

extension HighlightColorExt on HighlightColor {
  Color get color => switch (this) {
        HighlightColor.yellow => AppColors.highlightYellow,
        HighlightColor.green => AppColors.highlightGreen,
        HighlightColor.blue => AppColors.highlightBlue,
        HighlightColor.pink => AppColors.highlightPink,
      };

  String get name => switch (this) {
        HighlightColor.yellow => 'yellow',
        HighlightColor.green => 'green',
        HighlightColor.blue => 'blue',
        HighlightColor.pink => 'pink',
      };
}

class ReaderScreen extends ConsumerStatefulWidget {
  final String book;
  final int chapter;
  final int? startVerse;
  final String version;
  final String uid;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.chapter,
    this.startVerse,
    required this.version,
    required this.uid,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _focusMode = false;
  bool _chromVisible = true;
  late String _currentVersion;
  late int _currentChapter;
  String _currentBook = '';
  List<BibleVerse> _verses = [];
  bool _loading = true;
  final Map<String, String> _highlights = {};
  final Map<String, String> _notes = {};
  int _sessionVerseCount = 0;
  double _sessionProgress = 0.0;

  final _scrollController = ScrollController();
  final _db = FirestoreService();
  final _xpService = XpService();

  bool _tapToReveal = false;

  @override
  void initState() {
    super.initState();
    _currentVersion = widget.version;
    _currentChapter = widget.chapter;
    _currentBook = widget.book;
    _loadVerses();
    _loadHighlights();
    _loadNotes();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _enterFocusMode();
    });

    Stream.periodic(const Duration(seconds: 10)).listen((_) {
      if (mounted) _savePosition();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVerses() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final verses = await _db.getVerses(_currentVersion, _currentBook, _currentChapter);
    if (!mounted) return;
    setState(() {
      _verses = verses;
      _loading = false;
    });
    _xpService.accumulateXp(widget.uid, XpRewards.openAppDaily);
  }

  Future<void> _loadHighlights() async {
    if (widget.uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('highlights')
          .doc(widget.uid)
          .collection('verses')
          .get();
      if (!mounted) return;
      final highlights = Map<String, String>.fromEntries(
        snap.docs.map((d) {
          final data = d.data();
          return MapEntry(d.id, data['color'] as String? ?? '');
        }),
      );
      debugPrint('Loaded highlights: ${highlights.length} items');
      setState(() => _highlights.addAll(highlights));
    } catch (e) {
      debugPrint('Error loading highlights: $e');
    }
  }

  Future<void> _loadNotes() async {
    final notes = await _db.loadNotes(widget.uid);
    if (mounted) setState(() => _notes.addAll(notes));
  }

  void _enterFocusMode() {
    setState(() {
      _focusMode = true;
      _chromVisible = false;
    });
  }

  void _toggleChrome() {
    if (_focusMode) {
      setState(() => _chromVisible = !_chromVisible);
    }
  }

  void _savePosition() {
    if (_verses.isEmpty) return;
    _db.saveReadingPosition(
      widget.uid,
      _currentVersion,
      _currentBook,
      _currentChapter,
      1,
    );
  }

  void _onVerseTap(BibleVerse verse) {
    _toggleChrome();
    _showInlineNote(verse);
  }

  void _onVerseLongPress(BibleVerse verse) {
    HapticFeedback.mediumImpact();
    _showVerseActionMenu(verse);
  }

  void _showInlineNote(BibleVerse verse) {
    final existing = _notes[verse.id] ?? '';
    final ctrl = TextEditingController(text: existing);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(verse.reference,
                style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
            const SizedBox(height: 8),
            Text('"${verse.text}"',
                style: AppTypography.bodySmall.copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              style: AppTypography.bodyMedium,
              decoration: const InputDecoration(hintText: 'Add a note…'),
            ),
            const SizedBox(height: 12),
            FlameCTAButton(
              label: 'Save Note',
              height: 44,
              onPressed: () {
                if (mounted) setState(() => _notes[verse.id] = ctrl.text);
                _db.saveNote(
                  uid: widget.uid,
                  verseId: verse.id,
                  note: ctrl.text,
                  reference: verse.reference,
                );
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVerseActionMenu(BibleVerse verse) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VerseActionSheet(
        verse: verse,
        highlights: _highlights,
        onHighlight: (color) {
          final verseKey = '${_currentBook}_${_currentChapter}_${verse.id}';
          if (mounted) setState(() => _highlights[verseKey] = color.name);
          _db.saveHighlight(uid: widget.uid, verseId: verseKey, color: color.name);
          Navigator.pop(context);
        },
        onCopy: () {
          Clipboard.setData(ClipboardData(text: '${verse.text} — ${verse.reference}'));
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verse copied')),
          );
        },
        onShare: () {
          Share.share('${verse.text}\n— ${verse.reference}\n\nStudyFire 🔥');
          _xpService.accumulateXp(widget.uid, XpRewards.shareVerse);
          Navigator.pop(context);
        },
        onAddToJournal: () {
          Navigator.pop(context);
        },
        onAskAi: () {
          Navigator.pop(context);
          _openAiStudy(verse);
        },
        onAddToMemory: () {
          Navigator.pop(context);
        },
        onWordOfDay: () {
          Navigator.pop(context);
          _showWordOfDay(verse);
        },
      ),
    );
  }

  void _openAiStudy(BibleVerse verse) {}

  void _showWordOfDay(BibleVerse verse) {}

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        builder: (__, scrollCtrl) => _SearchSheet(
          currentRef: '$_currentBook $_currentChapter',
          onNavigate: (book, chapter, verse) {
            if (mounted) setState(() {
              _currentBook = book;
              _currentChapter = chapter;
            });
            _loadVerses();
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _showChapterPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ChapterPicker(
        currentBook: _currentBook,
        currentChapter: _currentChapter,
        onPick: (book, chapter) {
          if (mounted) setState(() {
            _currentBook = book;
            _currentChapter = chapter;
          });
          _loadVerses();
          Navigator.pop(context);
        },
      ),
    );
  }

  void _prevChapter() {
    if (_currentChapter > 1) {
      setState(() => _currentChapter--);
      _loadVerses();
    }
  }

  void _nextChapter() {
    setState(() => _currentChapter++);
    _loadVerses();
    _sessionVerseCount++;
    setState(() => _sessionProgress = (_sessionProgress + 0.1).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleChrome,
      child: Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: Stack(
          children: [
            Positioned(
              top: 0, left: 0, right: 0,
              child: SessionProgressBar(progress: _sessionProgress),
            ),
            SafeArea(
              child: Column(
                children: [
                  AnimatedSlide(
                    offset: _chromVisible ? Offset.zero : const Offset(0, -1),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: AnimatedOpacity(
                      opacity: _chromVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _ReaderToolbar(
                        book: _currentBook,
                        chapter: _currentChapter,
                        version: _currentVersion,
                        onBack: () { if (context.canPop()) context.pop(); },
                        onTitleTap: _showChapterPicker,
                        onSearch: _showSearchSheet,
                        onVersionTap: _showVersionPicker,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _VerseList(
                            verses: _verses,
                            highlights: _highlights,
                            notes: _notes,
                            onTap: _onVerseTap,
                            onLongPress: _onVerseLongPress,
                            scrollController: _scrollController,
                          ),
                  ),
                  AnimatedSlide(
                    offset: _chromVisible ? Offset.zero : const Offset(0, 1),
                    duration: const Duration(milliseconds: 250),
                    child: AnimatedOpacity(
                      opacity: _chromVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: _ChapterNav(
                        onPrev: _currentChapter > 1 ? _prevChapter : null,
                        onNext: _nextChapter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVersionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bible Version', style: AppTypography.labelLarge),
            const SizedBox(height: 16),
            ...['kjv', 'csb', 'niv'].map((v) => ListTile(
                  title: Text(v.toUpperCase(), style: AppTypography.bodyLarge),
                  trailing: _currentVersion == v
                      ? const Icon(Icons.check, color: AppColors.warmGold)
                      : null,
                  onTap: () {
                    if (mounted) setState(() => _currentVersion = v);
                    _loadVerses();
                    Navigator.pop(context);
                  },
                )),
            ListTile(
              title: const Text('Compare All 3 🔒', style: AppTypography.bodyLarge),
              subtitle: Text('Premium', style: AppTypography.bodySmall.copyWith(color: AppColors.warmGold)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Verse List ────────────────────────────────────────────────────────────────

class _VerseList extends StatelessWidget {
  final List<BibleVerse> verses;
  final Map<String, String> highlights;
  final Map<String, String> notes;
  final ValueChanged<BibleVerse> onTap;
  final ValueChanged<BibleVerse> onLongPress;
  final ScrollController scrollController;

  const _VerseList({
    required this.verses,
    required this.highlights,
    required this.notes,
    required this.onTap,
    required this.onLongPress,
    required this.scrollController,
  });

  static const _highlightColors = {
    'yellow': AppColors.highlightYellow,
    'green': AppColors.highlightGreen,
    'blue': AppColors.highlightBlue,
    'pink': AppColors.highlightPink,
  };

  @override
  Widget build(BuildContext context) {
    if (verses.isEmpty) {
      return Center(
        child: Text('No verses found', style: AppTypography.bodyMedium),
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: verses.length,
      itemBuilder: (_, i) {
        final verse = verses[i];
        // Look up highlight using book_chapter_verseId key
        final verseKey = highlights.keys
            .where((k) => k.endsWith('_${verse.id}'))
            .firstOrNull;
        final highlightColor = _highlightColors[
            verseKey != null ? highlights[verseKey] : highlights[verse.id]];
        final hasNote = notes.containsKey(verse.id);

        return GestureDetector(
          onTap: () => onTap(verse),
          onLongPress: () => onLongPress(verse),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: highlightColor?.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: highlightColor != null
                  ? Border(left: BorderSide(color: highlightColor, width: 3))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${verse.verseNum} ',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.warmGold,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      TextSpan(
                        text: verse.text,
                        style: AppTypography.verseText,
                      ),
                    ],
                  ),
                ),
                if (hasNote) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      notes[verse.id]!,
                      style: AppTypography.bodySmall.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _ReaderToolbar extends StatelessWidget {
  final String book;
  final int chapter;
  final String version;
  final VoidCallback onBack;
  final VoidCallback onTitleTap;
  final VoidCallback onSearch;
  final VoidCallback onVersionTap;

  const _ReaderToolbar({
    required this.book,
    required this.chapter,
    required this.version,
    required this.onBack,
    required this.onTitleTap,
    required this.onSearch,
    required this.onVersionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: onBack,
            color: AppColors.warmWhite,
          ),
          Expanded(
            child: GestureDetector(
              onTap: onTitleTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_formatBook(book)} $chapter',
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onVersionTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.surface),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(version.toUpperCase(), style: AppTypography.labelSmall),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: onSearch,
            color: AppColors.warmWhite,
          ),
        ],
      ),
    );
  }

  String _formatBook(String b) {
    if (b.isEmpty) return '';
    return b[0].toUpperCase() + b.substring(1).replaceAll('_', ' ');
  }
}

// ── Chapter Nav ───────────────────────────────────────────────────────────────

class _ChapterNav extends StatelessWidget {
  final VoidCallback? onPrev;
  final VoidCallback onNext;

  const _ChapterNav({this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Prev'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          ),
          TextButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
            style: TextButton.styleFrom(foregroundColor: AppColors.warmGold),
            iconAlignment: IconAlignment.end,
          ),
        ],
      ),
    );
  }
}

// ── Verse Action Sheet ────────────────────────────────────────────────────────

class _VerseActionSheet extends StatelessWidget {
  final BibleVerse verse;
  final Map<String, String> highlights;
  final ValueChanged<HighlightColor> onHighlight;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onAddToJournal;
  final VoidCallback onAskAi;
  final VoidCallback onAddToMemory;
  final VoidCallback onWordOfDay;

  const _VerseActionSheet({
    required this.verse,
    required this.highlights,
    required this.onHighlight,
    required this.onCopy,
    required this.onShare,
    required this.onAddToJournal,
    required this.onAskAi,
    required this.onAddToMemory,
    required this.onWordOfDay,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(verse.reference,
                style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
            const SizedBox(height: 6),
            Text(
              '"${verse.text.length > 100 ? '${verse.text.substring(0, 97)}…' : verse.text}"',
              style: AppTypography.bodySmall.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Highlight:', style: AppTypography.labelSmall),
                const SizedBox(width: 12),
                ...HighlightColor.values.map((c) => GestureDetector(
                      onTap: () => onHighlight(c),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: highlights.values.contains(c.name)
                              ? Border.all(color: Colors.white, width: 2)
                              : null,
                        ),
                      ),
                    )),
              ],
            ),
            const Divider(height: 24),
            _ActionTile(icon: Icons.copy_outlined, label: 'Copy', onTap: onCopy),
            _ActionTile(icon: Icons.share_outlined, label: 'Share  +${XpRewards.shareVerse} XP', onTap: onShare),
            _ActionTile(icon: Icons.sticky_note_2_outlined, label: 'Add to Journal', onTap: onAddToJournal),
            _ActionTile(icon: Icons.auto_stories, label: 'Word of the Day', onTap: onWordOfDay),
            _ActionTile(icon: Icons.psychology, label: 'Ask AI', onTap: onAskAi),
            _ActionTile(icon: Icons.layers_outlined, label: 'Add to Memory Verse', onTap: onAddToMemory),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 16),
            Text(label, style: AppTypography.bodyLarge),
          ],
        ),
      ),
    );
  }
}

// ── Search Sheet ──────────────────────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final String currentRef;
  final void Function(String book, int chapter, int verse) onNavigate;

  const _SearchSheet({required this.currentRef, required this.onNavigate});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                label: const Text('Back to my reading'),
                style: TextButton.styleFrom(foregroundColor: AppColors.warmGold),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            style: AppTypography.bodyLarge,
            decoration: const InputDecoration(
              hintText: 'Search or jump to passage…',
              prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: AppColors.warmGold,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.warmGold,
          tabs: const [
            Tab(text: 'Reference'),
            Tab(text: 'Keyword'),
            Tab(text: 'Browse'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ReferenceTab(query: _ctrl.text, onNavigate: widget.onNavigate),
              _KeywordTab(query: _ctrl.text),
              _BrowseTab(onNavigate: widget.onNavigate),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReferenceTab extends StatelessWidget {
  final String query;
  final void Function(String book, int chapter, int verse) onNavigate;

  const _ReferenceTab({required this.query, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final ref = _parseRef(query);
    if (ref != null) {
      return ListTile(
        title: Text('Jump to ${query.trim()}', style: AppTypography.bodyLarge),
        leading: const Icon(Icons.arrow_forward, color: AppColors.warmGold),
        onTap: () => onNavigate(ref.book, ref.chapter, ref.verse),
      );
    }
    return Center(
      child: Text(
        'Type a reference like "Romans 8:28"',
        style: AppTypography.bodySmall,
      ),
    );
  }

  _Ref? _parseRef(String s) {
    final regex = RegExp(r'^(\d?\s?[A-Za-z]+)\s+(\d+):(\d+)$');
    final m = regex.firstMatch(s.trim());
    if (m == null) return null;
    return _Ref(
      book: m.group(1)!.trim().toLowerCase().replaceAll(' ', '_'),
      chapter: int.parse(m.group(2)!),
      verse: int.parse(m.group(3)!),
    );
  }
}

class _Ref {
  final String book;
  final int chapter;
  final int verse;
  _Ref({required this.book, required this.chapter, required this.verse});
}

class _KeywordTab extends StatelessWidget {
  final String query;
  const _KeywordTab({required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.length < 3) {
      return Center(child: Text('Type at least 3 characters', style: AppTypography.bodySmall));
    }
    return Center(child: Text('Searching "$query"…', style: AppTypography.bodySmall));
  }
}

class _BrowseTab extends StatefulWidget {
  final void Function(String book, int chapter, int verse) onNavigate;
  const _BrowseTab({required this.onNavigate});

  @override
  State<_BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<_BrowseTab> {
  String? _selectedBook;

  String _bookNameToId(String name) {
    const map = {
      'Genesis': 'gen', 'Exodus': 'exo', 'Leviticus': 'lev', 'Numbers': 'num',
      'Deuteronomy': 'deu', 'Joshua': 'jos', 'Judges': 'jdg', 'Ruth': 'rut',
      '1 Samuel': '1sa', '2 Samuel': '2sa', '1 Kings': '1ki', '2 Kings': '2ki',
      '1 Chronicles': '1ch', '2 Chronicles': '2ch', 'Ezra': 'ezr', 'Nehemiah': 'neh',
      'Esther': 'est', 'Job': 'job', 'Psalms': 'psa', 'Proverbs': 'pro',
      'Ecclesiastes': 'ecc', 'Song of Solomon': 'sng', 'Isaiah': 'isa',
      'Jeremiah': 'jer', 'Lamentations': 'lam', 'Ezekiel': 'ezk', 'Daniel': 'dan',
      'Hosea': 'hos', 'Joel': 'jol', 'Amos': 'amo', 'Obadiah': 'oba',
      'Jonah': 'jon', 'Micah': 'mic', 'Nahum': 'nam', 'Habakkuk': 'hab',
      'Zephaniah': 'zep', 'Haggai': 'hag', 'Zechariah': 'zec', 'Malachi': 'mal',
      'Matthew': 'mat', 'Mark': 'mrk', 'Luke': 'luk', 'John': 'jhn',
      'Acts': 'act', 'Romans': 'rom', '1 Corinthians': '1co', '2 Corinthians': '2co',
      'Galatians': 'gal', 'Ephesians': 'eph', 'Philippians': 'php', 'Colossians': 'col',
      '1 Thessalonians': '1th', '2 Thessalonians': '2th', '1 Timothy': '1ti',
      '2 Timothy': '2ti', 'Titus': 'tit', 'Philemon': 'phm', 'Hebrews': 'heb',
      'James': 'jas', '1 Peter': '1pe', '2 Peter': '2pe', '1 John': '1jn',
      '2 John': '2jn', '3 John': '3jn', 'Jude': 'jud', 'Revelation': 'rev',
    };
    return map[name] ?? name.toLowerCase().replaceAll(' ', '_');
  }

  static const _otBooks = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
    'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
    '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles',
    'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs',
    'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah',
    'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel',
    'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk',
    'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
  ];

  static const _ntBooks = [
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans',
    '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
    'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
    '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews',
    'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
    'Jude', 'Revelation',
  ];

  @override
  Widget build(BuildContext context) {
    if (_selectedBook == null) {
      return ListView(
        children: [
          _BookSection(title: 'Old Testament', books: _otBooks, onSelect: (b) => setState(() => _selectedBook = b)),
          _BookSection(title: 'New Testament', books: _ntBooks, onSelect: (b) => setState(() => _selectedBook = b)),
        ],
      );
    }
    return _ChapterGrid(
      book: _selectedBook!,
      onSelect: (ch) => widget.onNavigate(
        _bookNameToId(_selectedBook!),
        ch,
        1,
      ),
      onBack: () => setState(() => _selectedBook = null),
    );
  }
}

class _BookSection extends StatelessWidget {
  final String title;
  final List<String> books;
  final ValueChanged<String> onSelect;

  const _BookSection({required this.title, required this.books, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: AppTypography.labelSmall),
        ),
        ...books.map((b) => ListTile(
              dense: true,
              title: Text(b, style: AppTypography.bodyMedium),
              onTap: () => onSelect(b),
              trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
            )),
      ],
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  final String book;
  final ValueChanged<int> onSelect;
  final VoidCallback onBack;

  const _ChapterGrid({required this.book, required this.onSelect, required this.onBack});

  @override
  Widget build(BuildContext context) {
    const chapterCounts = {
      'Genesis': 50, 'Exodus': 40, 'Leviticus': 27, 'Numbers': 36,
      'Deuteronomy': 34, 'Joshua': 24, 'Judges': 21, 'Ruth': 4,
      '1 Samuel': 31, '2 Samuel': 24, '1 Kings': 22, '2 Kings': 25,
      '1 Chronicles': 29, '2 Chronicles': 36, 'Ezra': 10, 'Nehemiah': 13,
      'Esther': 10, 'Job': 42, 'Psalms': 150, 'Proverbs': 31,
      'Ecclesiastes': 12, 'Song of Solomon': 8, 'Isaiah': 66,
      'Jeremiah': 52, 'Lamentations': 5, 'Ezekiel': 48, 'Daniel': 12,
      'Hosea': 14, 'Joel': 3, 'Amos': 9, 'Obadiah': 1,
      'Jonah': 4, 'Micah': 7, 'Nahum': 3, 'Habakkuk': 3,
      'Zephaniah': 3, 'Haggai': 2, 'Zechariah': 14, 'Malachi': 4,
      'Matthew': 28, 'Mark': 16, 'Luke': 24, 'John': 21,
      'Acts': 28, 'Romans': 16, '1 Corinthians': 16, '2 Corinthians': 13,
      'Galatians': 6, 'Ephesians': 6, 'Philippians': 4, 'Colossians': 4,
      '1 Thessalonians': 5, '2 Thessalonians': 3, '1 Timothy': 6,
      '2 Timothy': 4, 'Titus': 3, 'Philemon': 1, 'Hebrews': 13,
      'James': 5, '1 Peter': 5, '2 Peter': 3, '1 John': 5,
      '2 John': 1, '3 John': 1, 'Jude': 1, 'Revelation': 22,
    };
    final count = chapterCounts[book] ?? 30;

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.arrow_back_ios_new, size: 14),
          title: Text(book, style: AppTypography.labelLarge),
          onTap: onBack,
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: count,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => onSelect(i + 1),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text('${i + 1}', style: AppTypography.labelSmall),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterPicker extends StatelessWidget {
  final String currentBook;
  final int currentChapter;
  final void Function(String book, int chapter) onPick;

  const _ChapterPicker({
    required this.currentBook,
    required this.currentChapter,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return _BrowseTab(
      onNavigate: (book, ch, _) {
        onPick(book, ch);
        if (Navigator.canPop(context)) Navigator.pop(context);
      },
    );
  }
}
