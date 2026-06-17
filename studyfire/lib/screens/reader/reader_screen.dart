import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/streak_service.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/progress_bar.dart';
import '../journal/journal_screen.dart';
import '../../models/memory_verse.dart';
import '../../models/memory_verse.dart';

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
  final Set<String> _countedChapters = {};
  bool _streakRecorded = false;

  // Compare mode
  bool _compareMode = false;
  String _compareVersionA = 'kjv';
  String _compareVersionB = 'niv';
  List<BibleVerse> _versesA = [];
  List<BibleVerse> _versesB = [];
  bool _loadingCompare = false;

  final _scrollController = ScrollController();
  final _db = FirestoreService();
  final _xpService = XpService();
  final _streakService = StreakService();

  bool _tapToReveal = false;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _currentVersion = widget.version;
    _currentChapter = widget.chapter;
    _currentBook = widget.book;
    _loadVerses();
    _loadHighlights();
    _loadNotes();
    _checkHint();

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

  Future<void> _checkHint() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('hint_reader_longpress') ?? false;
    if (!seen && mounted) setState(() => _showHint = true);
  }

  Future<void> _dismissHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hint_reader_longpress', true);
    if (mounted) setState(() => _showHint = false);
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

    // Track verses read — once per unique chapter per session
    final chapterKey = '${_currentVersion}_${_currentBook}_$_currentChapter';
    if (widget.uid.isNotEmpty && verses.isNotEmpty && !_countedChapters.contains(chapterKey)) {
      _countedChapters.add(chapterKey);
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({'profile.versesRead': FieldValue.increment(verses.length)})
          .catchError((_) {});
      if (!_streakRecorded) {
        _streakRecorded = true;
        _streakService.recordActivity(widget.uid).catchError((_) {});
      }
    }
  }

  Future<void> _loadCompareVerses() async {
    if (!mounted) return;
    setState(() => _loadingCompare = true);
    final results = await Future.wait([
      _db.getVerses(_compareVersionA, _currentBook, _currentChapter),
      _db.getVerses(_compareVersionB, _currentBook, _currentChapter),
    ]);
    if (!mounted) return;
    setState(() {
      _versesA = results[0];
      _versesB = results[1];
      _loadingCompare = false;
    });
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
    // Also mirror to SharedPreferences for instant local restore
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('reader_last_book', _currentBook);
      prefs.setInt('reader_last_chapter', _currentChapter);
      prefs.setString('reader_last_version', _currentVersion);
    });
  }

  void _onVerseTap(BibleVerse verse) {
    _toggleChrome();
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
          final existing = _highlights[verseKey];
          if (existing == color.name) {
            // Tap same color = remove highlight
            if (mounted) setState(() => _highlights.remove(verseKey));
            _db.clearHighlight(uid: widget.uid, verseId: verseKey);
          } else {
            if (mounted) setState(() => _highlights[verseKey] = color.name);
            _db.saveHighlight(uid: widget.uid, verseId: verseKey, color: color.name);
          }
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
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => NoteEditorScreen(
              verseRef: verse.reference,
              verseText: verse.text,
            ),
          ));
        },
        onAskAi: () {
          Navigator.pop(context);
          _openAiStudy(verse);
        },
        onAddToMemory: () {
          Navigator.pop(context);
          final mv = MemoryVerse(
            id: verse.reference.replaceAll(' ', '_').replaceAll(':', '_'),
            reference: verse.reference,
            text: verse.text,
            currentStage: MemoryVerseStage.stage1,
            mastered: false,
            attemptHistory: [],
            easeFactor: 250,
            interval: 1,
            repetitions: 0,
          );
          _db.saveMemoryVerse(widget.uid, mv);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Added to Memory Verses!')),
          );
        },
        onWordOfDay: () {
          Navigator.pop(context);
          _showWordOfDay(verse);
        },
      ),
    );
  }

  void _openAiStudy(BibleVerse verse) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AskAiSheet(verse: verse, uid: widget.uid),
    );
  }

  void _showWordOfDay(BibleVerse verse) {
    // Pick the most significant word from the verse (first noun/key word)
    final words = verse.text.replaceAll(RegExp(r'[^a-zA-Z ]'), '').split(' ')
        .where((w) => w.length > 4).toList();
    final word = words.isNotEmpty ? words[0] : verse.text.split(' ')[0];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _WordStudySheet(
        word: word,
        verseRef: verse.reference,
        verseText: verse.text,
      ),
    );
  }

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
                    child: Column(
                      children: [
                      if (_compareMode)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          color: AppColors.warmGold.withOpacity(0.12),
                          child: Row(
                            children: [
                              const Icon(Icons.compare_arrows, size: 16, color: AppColors.warmGold),
                              const SizedBox(width: 8),
                              Text(
                                '${_compareVersionA.toUpperCase()} vs ${_compareVersionB.toUpperCase()}',
                                style: const TextStyle(fontSize: 12, color: AppColors.warmGold, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () => setState(() => _compareMode = false),
                                child: const Text('Exit', style: TextStyle(fontSize: 12, color: AppColors.warmGold)),
                              ),
                            ],
                          ),
                        )
                      else if (_showHint)
                        GestureDetector(
                          onTap: _dismissHint,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: AppColors.warmGold.withOpacity(0.15),
                            child: Row(
                              children: [
                                const Text('💡 ', style: TextStyle(fontSize: 14)),
                                const Expanded(
                                  child: Text(
                                    'Long press any verse to highlight, ask AI, or add to journal',
                                    style: TextStyle(fontSize: 12, color: AppColors.warmGold),
                                  ),
                                ),
                                const Icon(Icons.close, size: 14, color: AppColors.warmGold),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: _compareMode
                            ? (_loadingCompare
                                ? const Center(child: CircularProgressIndicator())
                                : _CompareVerseList(
                                    versesA: _versesA,
                                    versesB: _versesB,
                                    versionA: _compareVersionA,
                                    versionB: _compareVersionB,
                                    scrollController: _scrollController,
                                  ))
                            : (_loading
                                ? const Center(child: CircularProgressIndicator())
                                : _VerseList(
                                    verses: _verses,
                                    highlights: _highlights,
                                    notes: _notes,
                                    onTap: _onVerseTap,
                                    onLongPress: _onVerseLongPress,
                                    scrollController: _scrollController,
                                  )),
                      ),
                    ],
                  )),
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
            const Divider(color: AppColors.surface),
            ListTile(
              leading: const Icon(Icons.compare_arrows, color: AppColors.warmGold),
              title: const Text('Compare two versions', style: AppTypography.bodyLarge),
              onTap: () {
                Navigator.pop(context);
                _showComparePicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showComparePicker() {
    String selA = _compareVersionA;
    String selB = _compareVersionB;
    const versions = ['kjv', 'niv', 'csb'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Compare Versions', style: AppTypography.labelLarge),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('First', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        ...versions.map((v) => GestureDetector(
                          onTap: () => setLocal(() => selA = v),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: selA == v ? AppColors.warmGold.withOpacity(0.15) : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selA == v ? AppColors.warmGold : Colors.transparent,
                              ),
                            ),
                            child: Text(v.toUpperCase(),
                              style: AppTypography.labelSmall.copyWith(
                                color: selA == v ? AppColors.warmGold : AppColors.warmWhite,
                              )),
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.compare_arrows, color: AppColors.textSecondary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Second', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        ...versions.map((v) => GestureDetector(
                          onTap: () => setLocal(() => selB = v),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: selB == v ? AppColors.warmGold.withOpacity(0.15) : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selB == v ? AppColors.warmGold : Colors.transparent,
                              ),
                            ),
                            child: Text(v.toUpperCase(),
                              style: AppTypography.labelSmall.copyWith(
                                color: selB == v ? AppColors.warmGold : AppColors.warmWhite,
                              )),
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selA == selB ? AppColors.surface : AppColors.warmGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: selA == selB ? null : () {
                    Navigator.pop(ctx);
                    setState(() {
                      _compareVersionA = selA;
                      _compareVersionB = selB;
                      _compareMode = true;
                    });
                    _loadCompareVerses();
                  },
                  child: Text(
                    selA == selB ? 'Pick two different versions' : 'Compare ${selA.toUpperCase()} & ${selB.toUpperCase()}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Compare Verse List ────────────────────────────────────────────────────────

class _CompareVerseList extends StatelessWidget {
  final List<BibleVerse> versesA;
  final List<BibleVerse> versesB;
  final String versionA;
  final String versionB;
  final ScrollController scrollController;

  const _CompareVerseList({
    required this.versesA,
    required this.versesB,
    required this.versionA,
    required this.versionB,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final count = versesA.length > versesB.length ? versesA.length : versesB.length;
    if (count == 0) {
      return Center(child: Text('No verses found', style: AppTypography.bodyMedium));
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: count,
      itemBuilder: (_, i) {
        final a = i < versesA.length ? versesA[i] : null;
        final b = i < versesB.length ? versesB[i] : null;
        final verseNum = (a?.verseNum ?? b?.verseNum ?? (i + 1)).toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Verse number header
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  verseNum,
                  style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                ),
              ),
              // Version A
              if (a != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardDark,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    ),
                    border: Border(
                      left: BorderSide(color: AppColors.warmGold.withOpacity(0.6), width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(versionA.toUpperCase(),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.warmGold, fontSize: 10, letterSpacing: 1.2,
                        )),
                      const SizedBox(height: 4),
                      Text(a.text, style: AppTypography.bodyMedium),
                    ],
                  ),
                ),
              // Version B
              if (b != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(10),
                      bottomRight: Radius.circular(10),
                    ),
                    border: Border(
                      left: BorderSide(color: AppColors.textSecondary.withOpacity(0.5), width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(versionB.toUpperCase(),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1.2,
                        )),
                      const SizedBox(height: 4),
                      Text(b.text, style: AppTypography.bodyMedium),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
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
        final verseKey = '${verse.book}_${verse.chapter}_${verse.id}';
        final highlightColor = _highlightColors[highlights[verseKey]];
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

// ── Word Study Sheet ──────────────────────────────────────────────────────────

class _WordStudySheet extends StatefulWidget {
  final String word;
  final String verseRef;
  final String verseText;

  const _WordStudySheet({
    required this.word,
    required this.verseRef,
    required this.verseText,
  });

  @override
  State<_WordStudySheet> createState() => _WordStudySheetState();
}

class _WordStudySheetState extends State<_WordStudySheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Track wordsExplored
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).set({
        'profile': {'wordsExplored': FieldValue.increment(1)}
      }, SetOptions(merge: true)).catchError((_) {});
    }
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getWordStudy');
      final result = await fn.call({
        'word': widget.word,
        'verseRef': widget.verseRef,
        'verseText': widget.verseText,
      });
      if (mounted) setState(() {
        _data = Map<String, dynamic>.from(result.data);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Word study unavailable right now — please try again later.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 24),
        child: _loading
            ? const Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ))
            : _error != null
                ? Center(child: Text(_error!, style: AppTypography.bodySmall))
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final d = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('📖 ', style: TextStyle(fontSize: 20)),
            Text('Word Study', style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
          ],
        ),
        const SizedBox(height: 16),
        Text(d['word'] ?? widget.word, style: AppTypography.displaySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(d['originalWord'] ?? '', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
            const SizedBox(width: 8),
            Text('(${d['language'] ?? ''} · ${d['strongsNumber'] ?? ''})',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        if (d['pronunciation'] != null) ...[
          const SizedBox(height: 4),
          Text('/${d['pronunciation']}/', style: AppTypography.bodySmall.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
        ],
        const Divider(height: 24),
        _Section(title: 'Definition', content: d['definition'] ?? ''),
        _Section(title: 'In This Verse', content: d['usageInContext'] ?? ''),
        _Section(title: 'Today', content: d['applicationToday'] ?? ''),
        if (d['otherVerses'] != null && (d['otherVerses'] as List).isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Also appears in', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: (d['otherVerses'] as List).map((ref) => Chip(
              label: Text(ref.toString(), style: AppTypography.bodySmall),
              backgroundColor: AppColors.surface,
            )).toList(),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String content;
  const _Section({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(content, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

// ── Ask AI Sheet ──────────────────────────────────────────────────────────────

class _AskAiSheet extends StatefulWidget {
  final BibleVerse verse;
  final String uid;
  const _AskAiSheet({required this.verse, required this.uid});

  @override
  State<_AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<_AskAiSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  static const _suggestions = [
    'What does this verse mean?',
    'What is the historical context?',
    'How can I apply this today?',
    'What comes before and after this?',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _ask(String question) async {
    if (question.trim().isEmpty) return;
    setState(() {
      _messages.add({'role': 'user', 'content': question});
      _loading = true;
    });
    _ctrl.clear();
    _scrollToBottom();

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('askVerseQuestion', options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await fn.call({
        'verseRef': widget.verse.reference,
        'verseText': widget.verse.text,
        'question': question,
      });
      final data = result.data;
      final answer = data is Map ? (data['answer'] ?? data.toString()) : data.toString();
      if (mounted) setState(() {
        _messages.add({'role': 'ai', 'content': answer});
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() {
        _messages.add({'role': 'ai', 'content': 'Sorry, I had trouble with that. Please try again.'});
        _loading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, __) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('🧠 ', style: TextStyle(fontSize: 18)),
                  Text('Ask AI', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
                ]),
                const SizedBox(height: 4),
                Text(widget.verse.reference, style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                Text(
                  '"${widget.verse.text.length > 80 ? '${widget.verse.text.substring(0, 77)}…' : widget.verse.text}"',
                  style: AppTypography.bodySmall.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _messages.isEmpty
                ? _buildSuggestions()
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            SizedBox(width: 8),
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Thinking…', style: TextStyle(color: AppColors.textSecondary)),
                          ]),
                        );
                      }
                      final msg = _messages[i];
                      final isUser = msg['role'] == 'user';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (!isUser) ...[
                              const CircleAvatar(radius: 14, backgroundColor: AppColors.warmGold,
                                  child: Text('✦', style: TextStyle(fontSize: 12, color: Colors.black))),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isUser ? AppColors.warmGold.withOpacity(0.15) : AppColors.surface,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(msg['content']!, style: AppTypography.bodyMedium),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
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
                      hintText: 'Ask anything about this verse…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    onSubmitted: _ask,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: AppColors.warmGold),
                  onPressed: () => _ask(_ctrl.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Suggested questions', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          ..._suggestions.map((q) => GestureDetector(
            onTap: () => _ask(q),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warmGold.withOpacity(0.2)),
              ),
              child: Text(q, style: AppTypography.bodyMedium),
            ),
          )),
        ],
      ),
    );
  }
}
