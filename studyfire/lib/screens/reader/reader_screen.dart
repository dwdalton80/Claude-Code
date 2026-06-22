import 'dart:async';
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
import '../../core/walkthrough/walkthrough_keys.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/streak_service.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/common/premium_gate.dart';
import '../../widgets/common/progress_bar.dart';
import '../journal/journal_screen.dart';
import '../../models/journal_entry.dart';
import '../../models/memory_verse.dart';

enum HighlightColor { yellow, orange, green, blue, purple, pink, red }

extension HighlightColorExt on HighlightColor {
  Color get color => switch (this) {
        HighlightColor.yellow => AppColors.highlightYellow,
        HighlightColor.orange => AppColors.highlightOrange,
        HighlightColor.green => AppColors.highlightGreen,
        HighlightColor.blue => AppColors.highlightBlue,
        HighlightColor.purple => AppColors.highlightPurple,
        HighlightColor.pink => AppColors.highlightPink,
        HighlightColor.red => AppColors.highlightRed,
      };

  String get name => switch (this) {
        HighlightColor.yellow => 'yellow',
        HighlightColor.orange => 'orange',
        HighlightColor.green => 'green',
        HighlightColor.blue => 'blue',
        HighlightColor.purple => 'purple',
        HighlightColor.pink => 'pink',
        HighlightColor.red => 'red',
      };
}

class ReaderScreen extends ConsumerStatefulWidget {
  final String book;
  final int chapter;
  final int? startVerse;
  final String version;
  final String uid;
  final bool isPremium;

  const ReaderScreen({
    super.key,
    required this.book,
    required this.chapter,
    this.startVerse,
    required this.version,
    required this.uid,
    this.isPremium = false,
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

  // Multi-verse selection state
  List<BibleVerse> _selectedVerses = [];
  bool _sheetOpen = false;
  final ValueNotifier<List<BibleVerse>> _selectionNotifier = ValueNotifier([]);

  StreamSubscription<void>? _positionSub;

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

    // Focus mode (chrome auto-hide) is no longer triggered automatically —
    // the toolbar stays always visible.

    _positionSub = Stream.periodic(const Duration(seconds: 10)).listen((_) {
      if (mounted) _savePosition();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _scrollController.dispose();
    _selectionNotifier.dispose();
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
    HapticFeedback.lightImpact();
    final idx = _selectedVerses.indexWhere((v) => v.id == verse.id);
    if (idx >= 0) {
      // Deselect — if last verse, close panel
      _selectedVerses.removeAt(idx);
      if (_selectedVerses.isEmpty) {
        setState(() { _sheetOpen = false; });
        _selectionNotifier.value = [];
        return;
      }
    } else {
      _selectedVerses.add(verse);
      _selectedVerses.sort((a, b) => a.id.compareTo(b.id));
    }
    setState(() => _sheetOpen = true);
    _selectionNotifier.value = List.from(_selectedVerses);
  }

  void _closeSelectionPanel() {
    setState(() { _selectedVerses = []; _sheetOpen = false; });
    _selectionNotifier.value = [];
  }

  Future<void> _showInlineNote(BibleVerse verse) async {
    final existing = _notes[verse.id] ?? '';
    final ctrl = TextEditingController(text: existing);
    try {
      await showModalBottomSheet(
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
    } finally {
      ctrl.dispose();
    }
  }

  static const _freeMemoryVerseLimit = 1;

  Future<void> _saveMemoryVerseGated(BibleVerse verse) async {
    // Premium users: unlimited
    if (widget.isPremium) {
      _doSaveMemoryVerse(verse);
      return;
    }
    // Free: check current count
    final existing = await _db.watchMemoryVerses(widget.uid).first;
    if (existing.length >= _freeMemoryVerseLimit) {
      if (mounted) {
        showPaywallSheet(
          context,
          featureName: 'Unlimited Memory Verses',
          limitMessage: "Free accounts can save 1 memory verse. Upgrade to memorize as many as you want.",
        );
      }
      return;
    }
    _doSaveMemoryVerse(verse);
  }

  void _doSaveMemoryVerse(BibleVerse verse) {
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to Memory Verses!')),
      );
    }
  }

  void _showAiQuestionPicker(BibleVerse verse) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AiQuestionPickerSheet(
        verse: verse,
        uid: widget.uid,
        isPremium: widget.isPremium,
      ),
    );
  }

  void _showDeepStudy(List<BibleVerse> verses) {
    final text = verses.map((v) => v.text).join(' ');
    final ref = verses.length == 1
        ? verses.first.reference
        : '${verses.first.reference}–${verses.last.verseNum}';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DeepStudySheet(
        verseRef: ref,
        verseText: text,
        uid: widget.uid,
        isPremium: widget.isPremium,
      ),
    );
  }

  void _showInterpretSheet(BibleVerse verse) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InterpretSheet(
        verse: verse,
        uid: widget.uid,
        isPremium: widget.isPremium,
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
      builder: (_) => _AskAiSheet(
        verse: verse,
        uid: widget.uid,
        isPremium: widget.isPremium,
      ),
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
          version: _currentVersion,
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
      onTap: _sheetOpen ? null : _toggleChrome,
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
                        key: WalkthroughKeys.readerToolbar,
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
                      key: WalkthroughKeys.readerContent,
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
                                      'Tap a verse to select • tap more to add • use the panel below',
                                      style: TextStyle(fontSize: 12, color: AppColors.warmGold),
                                    ),
                                  ),
                                  const Icon(Icons.close, size: 14, color: AppColors.warmGold),
                                ],
                              ),
                            ),
                          ),
                        Expanded(
                          child: GestureDetector(
                            onHorizontalDragEnd: (details) {
                              if (_sheetOpen) return;
                              const threshold = 80.0;
                              final v = details.primaryVelocity ?? 0;
                              if (v > threshold && _currentChapter > 1) {
                                _prevChapter();
                              } else if (v < -threshold) {
                                _nextChapter();
                              }
                            },
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
                                        selectedVerses: _selectedVerses,
                                        currentBook: _currentBook,
                                        currentChapter: _currentChapter,
                                        onTap: _onVerseTap,
                                        scrollController: _scrollController,
                                      )),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Persistent selection panel (non-modal so list stays tappable) ──
            if (!_sheetOpen)
              Positioned(
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: AnimatedOpacity(
                    opacity: _chromVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteEditorScreen(
                              initialType: JournalType.personalStudy,
                              verseRef: _verses.isNotEmpty
                                  ? '$_currentBook $_currentChapter'
                                  : null,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_note, size: 16, color: AppColors.warmWhite),
                            const SizedBox(width: 6),
                            Text(
                              'New Note',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.warmWhite,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_sheetOpen)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: SafeArea(
                  top: false,
                  child: ValueListenableBuilder<List<BibleVerse>>(
                    valueListenable: _selectionNotifier,
                    builder: (ctx, selectedVerses, __) {
                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          border: Border(top: BorderSide(color: Colors.white12, width: 1)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 16,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: _VerseSelectionSheet(
                        selectedVerses: selectedVerses,
                        highlights: _highlights,
                        currentBook: _currentBook,
                        currentChapter: _currentChapter,
                        onHighlight: (color) {
                          for (final v in selectedVerses) {
                            final key = '${_currentBook}_${_currentChapter}_${v.id}';
                            final existing = _highlights[key];
                            if (existing == color.name) {
                              if (mounted) setState(() => _highlights.remove(key));
                              _db.clearHighlight(uid: widget.uid, verseId: key);
                            } else {
                              if (mounted) setState(() => _highlights[key] = color.name);
                              _db.saveHighlight(uid: widget.uid, verseId: key, color: color.name);
                            }
                          }
                          _closeSelectionPanel();
                        },
                        onRemoveHighlight: () {
                          for (final v in selectedVerses) {
                            final key = '${_currentBook}_${_currentChapter}_${v.id}';
                            if (mounted) setState(() => _highlights.remove(key));
                            _db.clearHighlight(uid: widget.uid, verseId: key);
                          }
                          _closeSelectionPanel();
                        },
                        onCopy: () {
                          final text = selectedVerses.map((v) => v.text).join(' ');
                          final ref = selectedVerses.length == 1
                              ? selectedVerses.first.reference
                              : '${selectedVerses.first.reference}–${selectedVerses.last.id}';
                          Clipboard.setData(ClipboardData(text: '$text — $ref'));
                          _closeSelectionPanel();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verse copied')),
                          );
                        },
                        onShare: () {
                          final text = selectedVerses.map((v) => v.text).join(' ');
                          final ref = selectedVerses.length == 1
                              ? selectedVerses.first.reference
                              : '${selectedVerses.first.reference}–${selectedVerses.last.id}';
                          Share.share('$text\n— $ref\n\nStudyFire 🔥');
                          _xpService.accumulateXp(widget.uid, XpRewards.shareVerse);
                          _closeSelectionPanel();
                        },
                        onStudy: () {
                          _closeSelectionPanel();
                          _showDeepStudy(selectedVerses);
                        },
                        onInterpret: () {
                          _closeSelectionPanel();
                          _showInterpretSheet(selectedVerses.first);
                        },
                        onAsk: () {
                          _closeSelectionPanel();
                          _showAiQuestionPicker(selectedVerses.first);
                        },
                        onAddToJournal: () {
                          _closeSelectionPanel();
                          final v = selectedVerses.first;
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => NoteEditorScreen(
                              verseRef: v.reference,
                              verseText: selectedVerses.map((v) => v.text).join(' '),
                            ),
                          ));
                        },
                        onAddToMemory: () {
                          _closeSelectionPanel();
                          _saveMemoryVerseGated(selectedVerses.first);
                        },
                      ),
                      );
                    },
                  ),
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

// ── Verse List ────────────────────────────────────────────────────────────────

class _VerseList extends StatelessWidget {
  final List<BibleVerse> verses;
  final Map<String, String> highlights;
  final Map<String, String> notes;
  final List<BibleVerse> selectedVerses;
  final String currentBook;
  final int currentChapter;
  final void Function(BibleVerse) onTap;
  final ScrollController scrollController;

  const _VerseList({
    required this.verses,
    required this.highlights,
    required this.notes,
    required this.selectedVerses,
    required this.currentBook,
    required this.currentChapter,
    required this.onTap,
    required this.scrollController,
  });

  static const _highlightColors = {
    'yellow': AppColors.highlightYellow,
    'orange': AppColors.highlightOrange,
    'green':  AppColors.highlightGreen,
    'blue':   AppColors.highlightBlue,
    'purple': AppColors.highlightPurple,
    'pink':   AppColors.highlightPink,
    'red':    AppColors.highlightRed,
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      itemCount: verses.length,
      itemBuilder: (_, i) {
        final verse = verses[i];
        final isSelected = selectedVerses.any((v) => v.id == verse.id);
        final highlightKey = '${currentBook}_${currentChapter}_${verse.id}';
        final highlightName = highlights[highlightKey];
        final highlightColor = highlightName != null
            ? _highlightColors[highlightName]
            : null;
        final hasNote = notes.containsKey(verse.id);

        return GestureDetector(
          onTap: () => onTap(verse),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Verse number circle ──────────────────────────────────
                SizedBox(
                  width: 32,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppColors.warmGold
                            : Colors.transparent,
                        border: isSelected
                            ? null
                            : Border.all(
                                color: AppColors.warmGold.withOpacity(0.35),
                                width: 1,
                              ),
                      ),
                      child: Center(
                        child: Text(
                          '${verse.verseNum}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : AppColors.warmGold.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // ── Verse text ───────────────────────────────────────────
                Expanded(
                  child: Container(
                    decoration: highlightColor != null
                        ? BoxDecoration(
                            color: highlightColor.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(6),
                          )
                        : null,
                    padding: highlightColor != null
                        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                        : EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verse.text,
                          style: AppTypography.bodyMedium.copyWith(
                            height: 1.65,
                            color: isSelected
                                ? AppColors.warmWhite
                                : AppColors.warmWhite.withOpacity(0.88),
                          ),
                        ),
                        if (hasNote)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.sticky_note_2_outlined,
                                    size: 12,
                                    color: AppColors.warmGold.withOpacity(0.6)),
                                const SizedBox(width: 4),
                                Text(
                                  'Note',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warmGold.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

// ── Quick Verse Strip (single-tap) ────────────────────────────────────────────

class _VerseSelectionSheet extends StatelessWidget {
  final List<BibleVerse> selectedVerses;
  final Map<String, String> highlights;
  final String currentBook;
  final int currentChapter;
  final ValueChanged<HighlightColor> onHighlight;
  final VoidCallback onRemoveHighlight;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onStudy;
  final VoidCallback onInterpret;
  final VoidCallback onAsk;
  final VoidCallback onAddToJournal;
  final VoidCallback onAddToMemory;

  const _VerseSelectionSheet({
    required this.selectedVerses,
    required this.highlights,
    required this.currentBook,
    required this.currentChapter,
    required this.onHighlight,
    required this.onRemoveHighlight,
    required this.onCopy,
    required this.onShare,
    required this.onStudy,
    required this.onInterpret,
    required this.onAsk,
    required this.onAddToJournal,
    required this.onAddToMemory,
  });

  String get _referenceLabel {
    if (selectedVerses.isEmpty) return '';
    if (selectedVerses.length == 1) return selectedVerses.first.reference;
    final first = selectedVerses.first.reference;
    final lastNum = selectedVerses.last.id;
    return '$first–$lastNum';
  }

  bool get _hasHighlight {
    for (final v in selectedVerses) {
      final key = '${currentBook}_${currentChapter}_${v.id}';
      if (highlights.containsKey(key)) return true;
    }
    return false;
  }

  String? _activeColor() {
    if (selectedVerses.isEmpty) return null;
    final key = '${currentBook}_${currentChapter}_${selectedVerses.first.id}';
    return highlights[key];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: reference + copy/share ───────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected: $_referenceLabel',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.warmGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to select more verses.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'Copy',
              ),
              IconButton(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_outlined, size: 20),
                color: AppColors.textSecondary,
                tooltip: 'Share',
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Color swatches + remove ───────────────────────────────────────
          Row(
            children: [
              ...HighlightColor.values.map((c) {
                final active = _activeColor() == c.name;
                return GestureDetector(
                  onTap: () => onHighlight(c),
                  child: Container(
                    width: 34,
                    height: 34,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: c.color,
                      shape: BoxShape.circle,
                      border: active
                          ? Border.all(color: Colors.white, width: 2.5)
                          : Border.all(color: Colors.white24, width: 1),
                    ),
                  ),
                );
              }),
              if (_hasHighlight)
                GestureDetector(
                  onTap: onRemoveHighlight,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white38, width: 1),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.white54),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── AI action buttons ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _SheetActionBtn(
                  icon: Icons.auto_awesome_outlined,
                  label: 'Study',
                  onTap: onStudy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetActionBtn(
                  icon: Icons.menu_book_outlined,
                  label: 'Interpret',
                  onTap: onInterpret,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetActionBtn(
                  icon: Icons.chat_bubble_outline,
                  label: 'Ask',
                  onTap: onAsk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Secondary actions ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _SheetActionBtn(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Journal',
                  onTap: onAddToJournal,
                  secondary: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetActionBtn(
                  icon: Icons.layers_outlined,
                  label: 'Memorize',
                  onTap: onAddToMemory,
                  secondary: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool secondary;

  const _SheetActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: secondary ? AppColors.surface : AppColors.warmGold.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: secondary
              ? Border.all(color: Colors.white12)
              : Border.all(color: AppColors.warmGold.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: secondary ? AppColors.textSecondary : AppColors.warmGold),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: secondary ? AppColors.textSecondary : AppColors.warmGold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ── Search Sheet ──────────────────────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final String currentRef;
  final String version;
  final void Function(String book, int chapter, int verse) onNavigate;

  const _SearchSheet({
    required this.currentRef,
    required this.version,
    required this.onNavigate,
  });

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
              _KeywordTab(query: _ctrl.text, version: widget.version, onNavigate: widget.onNavigate),
              _BrowseTab(onNavigate: widget.onNavigate, currentRef: widget.currentRef),
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

  // Book name → Firestore book ID
  static const _bookIds = {
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
    'acts': 'act', 'romans': 'rom',
    '1 corinthians': '1co', '2 corinthians': '2co',
    'galatians': 'gal', 'ephesians': 'eph', 'philippians': 'php', 'colossians': 'col',
    '1 thessalonians': '1th', '2 thessalonians': '2th',
    '1 timothy': '1ti', '2 timothy': '2ti',
    'titus': 'tit', 'philemon': 'phm', 'hebrews': 'heb',
    'james': 'jas', '1 peter': '1pe', '2 peter': '2pe',
    '1 john': '1jn', '2 john': '2jn', '3 john': '3jn',
    'jude': 'jud', 'revelation': 'rev',
  };

  @override
  Widget build(BuildContext context) {
    final ref = _parseRef(query);
    if (ref != null) {
      return ListTile(
        title: Text('Jump to ${query.trim()}', style: AppTypography.bodyLarge),
        subtitle: Text('Chapter ${ref.chapter}, verse ${ref.verse}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        leading: const Icon(Icons.arrow_forward, color: AppColors.warmGold),
        onTap: () => onNavigate(ref.book, ref.chapter, ref.verse),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Type a reference like "Romans 8:28" or "1 Corinthians 13:4"',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  _Ref? _parseRef(String s) {
    // Matches: optional number + space + one-or-more words + space + chapter:verse
    // e.g. "John 3:16", "1 Corinthians 13:4", "Song of Solomon 2:3"
    final regex = RegExp(r'^(\d\s)?([A-Za-z](?:[A-Za-z\s]*[A-Za-z]))\s+(\d+):(\d+)$');
    final m = regex.firstMatch(s.trim());
    if (m == null) return null;
    final numPrefix = (m.group(1) ?? '').trim();
    final bookName = m.group(2)!.trim();
    final fullName = numPrefix.isNotEmpty ? '$numPrefix $bookName' : bookName;
    final bookId = _bookIds[fullName.toLowerCase()];
    if (bookId == null) return null;
    return _Ref(
      book: bookId,
      chapter: int.parse(m.group(3)!),
      verse: int.parse(m.group(4)!),
    );
  }
}

class _Ref {
  final String book;
  final int chapter;
  final int verse;
  _Ref({required this.book, required this.chapter, required this.verse});
}

class _KeywordTab extends StatefulWidget {
  final String query;
  final String version;
  final void Function(String book, int chapter, int verse) onNavigate;
  const _KeywordTab({required this.query, required this.version, required this.onNavigate});

  @override
  State<_KeywordTab> createState() => _KeywordTabState();
}

class _KeywordTabState extends State<_KeywordTab> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String _lastQuery = '';

  @override
  void didUpdateWidget(_KeywordTab old) {
    super.didUpdateWidget(old);
    if (widget.query != old.query) _search();
  }

  @override
  void initState() {
    super.initState();
    if (widget.query.length >= 3) _search();
  }

  Future<void> _search() async {
    final q = widget.query.trim().toLowerCase();
    if (q.length < 3 || q == _lastQuery) return;
    _lastQuery = q;
    setState(() { _loading = true; _results = []; });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
        'searchVerses',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final response = await callable.call({'version': widget.version, 'query': q});
      if (!mounted) return;
      final raw = (response.data['results'] as List<dynamic>? ?? []);
      final results = raw.map((r) {
        final m = r as Map<String, dynamic>;
        return {
          'reference': m['reference'] ?? '',
          'text': m['text'] ?? '',
          'book': m['book'] ?? '',
          'chapter': m['chapter'] ?? 0,
          'verse': m['verse'] ?? 0,
        };
      }).toList();
      setState(() { _results = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.query.length < 3) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Type at least 3 characters to search',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.warmGold));
    if (_results.isEmpty) {
      return Center(
        child: Text('No results for "${widget.query}"',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (ctx, i) {
        final r = _results[i];
        final text = r['text'] as String;
        final q = widget.query.toLowerCase();
        // Highlight the matching portion
        final lower = text.toLowerCase();
        final idx = lower.indexOf(q);
        Widget textWidget;
        if (idx >= 0) {
          textWidget = RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite.withOpacity(0.75)),
              children: [
                TextSpan(text: text.substring(0, idx)),
                TextSpan(
                  text: text.substring(idx, idx + q.length),
                  style: const TextStyle(
                      color: AppColors.warmGold, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text.substring(idx + q.length)),
              ],
            ),
          );
        } else {
          textWidget = Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite.withOpacity(0.75)));
        }
        return ListTile(
          title: Text(r['reference'] as String,
              style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
          subtitle: textWidget,
          onTap: () {
            widget.onNavigate(r['book'] as String, r['chapter'] as int, r['verse'] as int);
          },
        );
      },
    );
  }
}

class _BrowseTab extends StatefulWidget {
  final void Function(String book, int chapter, int verse) onNavigate;
  final String currentRef; // e.g. "rom 5"

  const _BrowseTab({required this.onNavigate, required this.currentRef});

  @override
  State<_BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<_BrowseTab> {
  String? _expandedBook;
  late ScrollController _scrollCtrl;

  // Reverse map: bookId -> display name
  static const _idToName = {
    'gen': 'Genesis', 'exo': 'Exodus', 'lev': 'Leviticus', 'num': 'Numbers',
    'deu': 'Deuteronomy', 'jos': 'Joshua', 'jdg': 'Judges', 'rut': 'Ruth',
    '1sa': '1 Samuel', '2sa': '2 Samuel', '1ki': '1 Kings', '2ki': '2 Kings',
    '1ch': '1 Chronicles', '2ch': '2 Chronicles', 'ezr': 'Ezra', 'neh': 'Nehemiah',
    'est': 'Esther', 'job': 'Job', 'psa': 'Psalms', 'pro': 'Proverbs',
    'ecc': 'Ecclesiastes', 'sng': 'Song of Solomon', 'isa': 'Isaiah',
    'jer': 'Jeremiah', 'lam': 'Lamentations', 'ezk': 'Ezekiel', 'dan': 'Daniel',
    'hos': 'Hosea', 'jol': 'Joel', 'amo': 'Amos', 'oba': 'Obadiah',
    'jon': 'Jonah', 'mic': 'Micah', 'nam': 'Nahum', 'hab': 'Habakkuk',
    'zep': 'Zephaniah', 'hag': 'Haggai', 'zec': 'Zechariah', 'mal': 'Malachi',
    'mat': 'Matthew', 'mrk': 'Mark', 'luk': 'Luke', 'jhn': 'John',
    'act': 'Acts', 'rom': 'Romans', '1co': '1 Corinthians', '2co': '2 Corinthians',
    'gal': 'Galatians', 'eph': 'Ephesians', 'php': 'Philippians', 'col': 'Colossians',
    '1th': '1 Thessalonians', '2th': '2 Thessalonians', '1ti': '1 Timothy',
    '2ti': '2 Timothy', 'tit': 'Titus', 'phm': 'Philemon', 'heb': 'Hebrews',
    'jas': 'James', '1pe': '1 Peter', '2pe': '2 Peter', '1jn': '1 John',
    '2jn': '2 John', '3jn': '3 John', 'jud': 'Jude', 'rev': 'Revelation',
  };

  static const _nameToId = {
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

  static const _chapterCounts = {
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

  static const _allBooks = [
    'Genesis', 'Exodus', 'Leviticus', 'Numbers', 'Deuteronomy',
    'Joshua', 'Judges', 'Ruth', '1 Samuel', '2 Samuel',
    '1 Kings', '2 Kings', '1 Chronicles', '2 Chronicles',
    'Ezra', 'Nehemiah', 'Esther', 'Job', 'Psalms', 'Proverbs',
    'Ecclesiastes', 'Song of Solomon', 'Isaiah', 'Jeremiah',
    'Lamentations', 'Ezekiel', 'Daniel', 'Hosea', 'Joel',
    'Amos', 'Obadiah', 'Jonah', 'Micah', 'Nahum', 'Habakkuk',
    'Zephaniah', 'Haggai', 'Zechariah', 'Malachi',
    'Matthew', 'Mark', 'Luke', 'John', 'Acts', 'Romans',
    '1 Corinthians', '2 Corinthians', 'Galatians', 'Ephesians',
    'Philippians', 'Colossians', '1 Thessalonians', '2 Thessalonians',
    '1 Timothy', '2 Timothy', 'Titus', 'Philemon', 'Hebrews',
    'James', '1 Peter', '2 Peter', '1 John', '2 John', '3 John',
    'Jude', 'Revelation',
  ];

  int get _currentChapter {
    final parts = widget.currentRef.trim().split(RegExp(r'\s+'));
    return int.tryParse(parts.last) ?? 1;
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    // Parse currentRef (e.g. "rom 5") to pre-expand current book
    final parts = widget.currentRef.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty) {
      final bookId = parts.first;
      _expandedBook = _idToName[bookId];
    }
    // Scroll to expanded book after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToExpanded());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToExpanded() {
    if (_expandedBook == null || !_scrollCtrl.hasClients) return;
    final idx = _allBooks.indexOf(_expandedBook!);
    if (idx < 0) return;
    // Approximate offset: each closed row ~52px, section headers ~40px each
    // OT has 39 books, NT starts at index 39 — add one header above NT
    final headerOffset = idx >= 39 ? 80.0 : 40.0;
    final approxOffset = (idx * 52.0) + headerOffset;
    _scrollCtrl.animateTo(
      approxOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: _allBooks.length + 2, // +2 for section headers
      itemBuilder: (ctx, i) {
        // Section header for OT
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Old Testament', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          );
        }
        // Section header for NT (after 39 OT books + 1 header = index 40)
        if (i == 40) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('New Testament', style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          );
        }
        // Map list index to book index (account for two headers)
        final bookIdx = i <= 39 ? i - 1 : i - 2;
        final bookName = _allBooks[bookIdx];
        final isExpanded = _expandedBook == bookName;
        final chapterCount = _chapterCounts[bookName] ?? 1;
        final currentChapter = _currentChapter;
        final bookId = _nameToId[bookName] ?? bookName.toLowerCase();
        final isCurrentBook = widget.currentRef.startsWith(bookId);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              // Book row
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _expandedBook = isExpanded ? null : bookName),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          bookName,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: isCurrentBook ? FontWeight.w600 : FontWeight.normal,
                            color: isCurrentBook ? AppColors.warmGold : AppColors.warmWhite,
                          ),
                        ),
                      ),
                      if (isExpanded && isCurrentBook)
                        Text(
                          '$currentChapter',
                          style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold),
                        ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              // Chapter chips (expanded)
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: List.generate(chapterCount, (ci) {
                      final chNum = ci + 1;
                      final isActive = isCurrentBook && chNum == currentChapter;
                      return GestureDetector(
                        onTap: () => widget.onNavigate(bookId, chNum, 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 44,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.warmGold : AppColors.cardDark,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              chNum.toString().padLeft(2, '0'),
                              style: AppTypography.labelSmall.copyWith(
                                color: isActive ? Colors.white : AppColors.warmWhite,
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        );
      },
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
      currentRef: '${currentBook} ${currentChapter}',
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

// ── Reader Toolbar ────────────────────────────────────────────────────────────

class _ReaderToolbar extends StatelessWidget {
  final String book;
  final int chapter;
  final String version;
  final VoidCallback onBack;
  final VoidCallback onTitleTap;
  final VoidCallback onSearch;
  final VoidCallback onVersionTap;

  const _ReaderToolbar({
    super.key,
    required this.book,
    required this.chapter,
    required this.version,
    required this.onBack,
    required this.onTitleTap,
    required this.onSearch,
    required this.onVersionTap,
  });

  String get _displayBook {
    if (book.isEmpty) return '';
    return book[0].toUpperCase() + book.substring(1).replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onTitleTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$_displayBook $chapter',
                    style: AppTypography.labelLarge.copyWith(color: AppColors.warmWhite),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 18, color: AppColors.warmWhite),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            color: AppColors.warmWhite,
            onPressed: onSearch,
          ),
          GestureDetector(
            onTap: onVersionTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.warmGold.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                version.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warmGold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Deep Study Sheet ──────────────────────────────────────────────────────────

class _DeepStudySheet extends StatefulWidget {
  final String verseRef;
  final String verseText;
  final String uid;
  final bool isPremium;

  const _DeepStudySheet({
    required this.verseRef,
    required this.verseText,
    required this.uid,
    required this.isPremium,
  });

  @override
  State<_DeepStudySheet> createState() => _DeepStudySheetState();
}

class _DeepStudySheetState extends State<_DeepStudySheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('deepStudyVerse',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 45)));
      final result = await fn.call({
        'verseRef': widget.verseRef,
        'verseText': widget.verseText,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['error'] == 'limit_reached') {
        if (mounted) setState(() {
          _error = 'You\'ve used your 1 free Deep Study today. Upgrade to Premium for unlimited access.';
          _loading = false;
        });
        return;
      }
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      debugPrint('deepStudyVerse error: $e');
      if (mounted) setState(() {
        _error = 'Unable to generate study right now. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      builder: (_, ctrl) => Column(
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(children: [
                  const Text('📚 ', style: TextStyle(fontSize: 18)),
                  Text('Deep Study', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
                  const Spacer(),
                  Text(widget.verseRef,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                  if (!_loading && _data != null) ...[
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'Copy',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _buildPlainText()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.share_rounded, size: 20, color: AppColors.textSecondary),
                      tooltip: 'Share',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Share.share(_buildPlainText()),
                    ),
                  ],
                ]),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.warmGold),
                        const SizedBox(height: 20),
                        Text(
                          'Generating your study…',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This may take a moment',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, style: AppTypography.bodyMedium.copyWith(color: AppColors.error)),
                      )
                    : _buildContent(ctrl),
          ),
        ],
      ),
    );
  }

  String _buildPlainText() {
    final d = _data!;
    final clarity = d['verseClarity'] as Map? ?? {};
    final words = (d['wordStudy'] as List? ?? []).cast<Map>();
    final theological = d['theologicalInsight'] as Map? ?? {};
    final support = (theological['scripturalSupport'] as List? ?? []).cast<Map>();

    final buf = StringBuffer();
    buf.writeln('📚 Deep Study — ${widget.verseRef}');
    buf.writeln();
    buf.writeln('VERSE CLARITY');
    buf.writeln('Context: ${clarity['context'] ?? ''}');
    buf.writeln('Meaning: ${clarity['meaning'] ?? ''}');
    buf.writeln();
    buf.writeln('WORD STUDY');
    for (final w in words) {
      buf.writeln('• ${w['word']} (${w['originalWord']} / ${w['transliteration']}, ${w['strongsNumber']})');
      buf.writeln('  ${w['definition']}');
      buf.writeln('  ${w['scholarsInsight']}');
    }
    buf.writeln();
    buf.writeln('THEOLOGICAL INSIGHT — ${theological['title'] ?? ''}');
    buf.writeln(theological['body'] ?? '');
    buf.writeln();
    for (final s in support) {
      buf.writeln('• ${s['reference']}: ${s['note']}');
    }
    buf.writeln();
    buf.writeln('💡 ${theological['intellectualTakeaway'] ?? ''}');
    buf.writeln();
    buf.writeln('— StudyFire · Based on Theological Christian Values');
    return buf.toString();
  }

  Widget _buildContent(ScrollController ctrl) {
    final d = _data!;
    final clarity = d['verseClarity'] as Map? ?? {};
    final words = (d['wordStudy'] as List? ?? []).cast<Map>();
    final theological = d['theologicalInsight'] as Map? ?? {};
    final support = (theological['scripturalSupport'] as List? ?? []).cast<Map>();

    return ListView(
      controller: ctrl,
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 32),
      children: [
        // ── Section 1: Verse Clarity ─────────────────────────────────────
        _StudySection(
          icon: '📌',
          title: 'The Context',
          child: Text(
            clarity['context'] ?? '',
            style: AppTypography.bodyMedium.copyWith(height: 1.7, color: AppColors.warmWhite.withOpacity(0.9)),
          ),
        ),
        _StudySection(
          icon: '📖',
          title: 'The Meaning',
          child: Text(
            clarity['meaning'] ?? '',
            style: AppTypography.bodyMedium.copyWith(height: 1.7, color: AppColors.warmWhite.withOpacity(0.9)),
          ),
        ),

        // ── Section 2: Word Study ─────────────────────────────────────────
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warmGold.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warmGold.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Text('🔍 ', style: TextStyle(fontSize: 16)),
            Text('Word Study', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
          ]),
        ),
        const SizedBox(height: 12),
        ...words.asMap().entries.map((e) {
          final i = e.key + 1;
          final w = e.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$i. ',
                      style: TextStyle(color: AppColors.warmGold, fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(w['word'] ?? '',
                          style: AppTypography.labelMedium.copyWith(color: AppColors.warmWhite)),
                      const SizedBox(height: 2),
                      Text(
                        '${w['originalWord'] ?? ''} | ${w['transliteration'] ?? ''}',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.warmGold.withOpacity(0.8),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if ((w['strongsNumber'] ?? '').isNotEmpty)
                        Text(
                          w['strongsNumber']!,
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 10),
                Text('Definition',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                Text(w['definition'] ?? '',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite.withOpacity(0.85), height: 1.5)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warmGold.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.school_outlined, size: 12, color: AppColors.warmGold),
                        const SizedBox(width: 4),
                        Text("Scholar's Insight",
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: AppColors.warmGold)),
                      ]),
                      const SizedBox(height: 4),
                      Text(w['scholarsInsight'] ?? '',
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.warmWhite.withOpacity(0.85), height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),

        // ── Section 3: Theological Insight ───────────────────────────────
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warmGold.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warmGold.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Text('🧠 ', style: TextStyle(fontSize: 16)),
            Text('Theological Insight', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(children: [
                const Icon(Icons.church_outlined, size: 16, color: AppColors.warmGold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    theological['title'] ?? '',
                    style: AppTypography.labelMedium.copyWith(color: AppColors.warmWhite),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text(
                theological['body'] ?? '',
                style: AppTypography.bodyMedium.copyWith(height: 1.7, color: AppColors.warmWhite.withOpacity(0.9)),
              ),
              const SizedBox(height: 14),
              // Scriptural support
              Text('Scriptural Support',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              ...support.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('• ', style: TextStyle(color: AppColors.warmGold)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTypography.bodySmall.copyWith(
                            color: AppColors.warmWhite.withOpacity(0.85), height: 1.5),
                        children: [
                          TextSpan(
                            text: '${s['reference'] ?? ''}: ',
                            style: const TextStyle(
                                color: AppColors.warmGold, fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: s['note'] ?? ''),
                        ],
                      ),
                    ),
                  ),
                ]),
              )),
              const SizedBox(height: 10),
              // Intellectual takeaway
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warmGold.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('💡 ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      theological['intellectualTakeaway'] ?? '',
                      style: AppTypography.bodySmall.copyWith(
                          color: AppColors.warmWhite, height: 1.5,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudySection extends StatelessWidget {
  final String icon;
  final String title;
  final Widget child;

  const _StudySection({required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('$icon ', style: const TextStyle(fontSize: 14)),
            Text(title,
                style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ── Interpret Sheet ───────────────────────────────────────────────────────────

class _InterpretSheet extends StatefulWidget {
  final BibleVerse verse;
  final String uid;
  final bool isPremium;

  const _InterpretSheet({required this.verse, required this.uid, required this.isPremium});

  @override
  State<_InterpretSheet> createState() => _InterpretSheetState();
}

class _InterpretSheetState extends State<_InterpretSheet> {
  String? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('interpretVerse',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await fn.call({
        'verseRef': widget.verse.reference,
        'verseText': widget.verse.text,
      });
      final data = result.data as Map?;
      if (data?['error'] == 'limit_reached') {
        if (mounted) setState(() {
          _error = 'You\'ve used your 2 free Interpretations today. Upgrade to Premium for unlimited access.';
          _loading = false;
        });
        return;
      }
      if (mounted) setState(() {
        _result = data?['answer'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      debugPrint('interpretVerse error: $e');
      if (mounted) setState(() {
        _error = 'Unable to interpret right now. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      builder: (_, ctrl) => SingleChildScrollView(
        controller: ctrl,
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Text('📖 ', style: TextStyle(fontSize: 18)),
                Text('Interpretation', style: AppTypography.labelMedium.copyWith(color: AppColors.warmGold)),
                const Spacer(),
                if (!_loading && _result != null) ...[
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.textSecondary),
                    tooltip: 'Copy',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                        text: '${widget.verse.reference}\n\n"${widget.verse.text}"\n\n$_result',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, size: 20, color: AppColors.textSecondary),
                    tooltip: 'Share',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Share.share('${widget.verse.reference}\n\n"${widget.verse.text}"\n\n$_result\n\n— StudyFire');
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.verse.reference,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            // Verse text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warmGold.withOpacity(0.2)),
              ),
              child: Text(
                '"${widget.verse.text}"',
                style: AppTypography.bodySmall.copyWith(
                  fontStyle: FontStyle.italic,
                  color: AppColors.warmWhite.withOpacity(0.85),
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.warmGold),
                ),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!, style: AppTypography.bodyMedium.copyWith(color: AppColors.error)),
              )
            else
              Text(
                _result ?? '',
                style: AppTypography.bodyMedium.copyWith(height: 1.7, color: AppColors.warmWhite),
              ),
            const SizedBox(height: 8),
            if (!_loading && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Based on Theological Christian Values',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.6)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── AI Question Picker ────────────────────────────────────────────────────────

class _AiQuestionPickerSheet extends StatefulWidget {
  final BibleVerse verse;
  final String uid;
  final bool isPremium;

  const _AiQuestionPickerSheet({
    required this.verse,
    required this.uid,
    required this.isPremium,
  });

  @override
  State<_AiQuestionPickerSheet> createState() => _AiQuestionPickerSheetState();
}

class _AiQuestionPickerSheetState extends State<_AiQuestionPickerSheet> {
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();

  static const _chips = [
    'What does this verse mean?',
    'What is the historical context?',
    'How can I apply this today?',
    'What verses are related?',
  ];

  @override
  void initState() {
    super.initState();
    // Auto-focus text field so keyboard appears
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send(String question) {
    if (question.trim().isEmpty) return;
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AskAiSheet(
        verse: widget.verse,
        uid: widget.uid,
        isPremium: widget.isPremium,
        initialQuestion: question,
      ),
    );
  }

  void _sendWordStudy() {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AskAiSheet(
        verse: widget.verse,
        uid: widget.uid,
        isPremium: widget.isPremium,
        startWordStudy: true,
      ),
    );
  }

  Future<void> _askBibleSays() async {
    final ctrl = TextEditingController();
    try {
      final topic = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.cardDark,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('What does the Bible say about…', style: AppTypography.labelLarge),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.warmWhite),
                decoration: InputDecoration(
                  hintText: 'e.g. anxiety, forgiveness, marriage',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send_rounded, color: AppColors.warmGold, size: 20),
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                textInputAction: TextInputAction.go,
              ),
            ],
          ),
        ),
      );
      if (topic == null || topic.isEmpty) return;
      _send('What does the Bible say about $topic?');
    } finally {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Verse card ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warmGold.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                const Icon(Icons.menu_book_outlined, size: 20, color: AppColors.warmGold),
                const SizedBox(height: 8),
                Text(
                  widget.verse.text.length > 120
                      ? '${widget.verse.text.substring(0, 120)}…'
                      : widget.verse.text,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.warmWhite.withOpacity(0.85),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.verse.reference,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.warmGold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Question chips ───────────────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._chips.map((q) => GestureDetector(
                onTap: () => _send(q),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(q, style: AppTypography.bodySmall.copyWith(color: AppColors.warmWhite)),
                      const SizedBox(width: 4),
                      const Icon(Icons.north_east, size: 12, color: Colors.white38),
                    ],
                  ),
                ),
              )),
              GestureDetector(
                onTap: _askBibleSays,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB39DDB).withOpacity(0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'What does the Bible say about…',
                        style: AppTypography.bodySmall.copyWith(color: const Color(0xFFD1C4E9)),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.north_east, size: 12, color: Color(0xFFD1C4E9)),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _sendWordStudy,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.warmGold.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Greek / Hebrew word study',
                        style: AppTypography.bodySmall.copyWith(
                          color: widget.isPremium ? AppColors.warmGold : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        widget.isPremium ? Icons.north_east : Icons.lock_outline,
                        size: 12,
                        color: AppColors.warmGold,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Free-text input ──────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.warmWhite),
                  decoration: InputDecoration(
                    hintText: 'Ask me anything…',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _send(_ctrl.text),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.warmGold,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Ask AI Sheet ──────────────────────────────────────────────────────────────

class _AskAiSheet extends StatefulWidget {
  final BibleVerse verse;
  final String uid;
  final bool isPremium;
  final String? initialQuestion;
  final bool startWordStudy;

  const _AskAiSheet({
    required this.verse,
    required this.uid,
    this.isPremium = false,
    this.initialQuestion,
    this.startWordStudy = false,
  });

  @override
  State<_AskAiSheet> createState() => _AskAiSheetState();
}

class _AskAiSheetState extends State<_AskAiSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  int _dailyRemaining = 3; // optimistic; updated by server response

  static const _suggestions = [
    'What does this verse mean?',
    'What is the historical context?',
    'How can I apply this today?',
    'What comes before and after this?',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.startWordStudy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askWordStudy());
    } else if (widget.initialQuestion != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(widget.initialQuestion!));
    }
  }

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
        'isPremium': widget.isPremium,
      });
      final data = result.data as Map?;

      // Check for server-side rate limit
      if (data?['error'] == 'limit_reached') {
        if (mounted) setState(() {
          _messages.removeLast(); // remove the user bubble
          _messages.add({'role': 'limit_reached', 'content': '2'});
          _loading = false;
        });
        return;
      }

      final answer = data?['answer'] as String? ?? data.toString();
      final remaining = data?['remaining'] as int?;
      if (mounted) setState(() {
        _messages.add({'role': 'ai', 'content': answer});
        if (remaining != null) _dailyRemaining = remaining;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('askVerseQuestion error: $e');
      if (mounted) setState(() {
        _messages.removeLast(); // remove orphaned user bubble
        _messages.add({'role': 'ai', 'content': 'Sorry, I had trouble with that. Please try again.'});
        _loading = false;
      });
    }
  }

  Future<void> _askWordStudy() async {
    if (!widget.isPremium) {
      // Show upsell inline — add a special message type
      setState(() {
        _messages.add({'role': 'upsell', 'content': 'word_study'});
      });
      return;
    }
    setState(() {
      _messages.add({'role': 'user', 'content': '🔤 Show Greek / Hebrew word study for this passage'});
      _loading = true;
    });
    _scrollToBottom();

    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getVerseWordStudy',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await fn.call({
        'verseRef': widget.verse.reference,
        'verseText': widget.verse.text,
        'isPremium': widget.isPremium,
      });
      final data = result.data as Map?;

      if (data?['error'] == 'limit_reached') {
        if (mounted) setState(() {
          _messages.removeLast();
          _messages.add({'role': 'limit_reached', 'content': '2'});
          _loading = false;
        });
        return;
      }

      final answer = data?['answer'] as String? ?? data.toString();
      final remaining = data?['remaining'] as int?;
      if (mounted) setState(() {
        _messages.add({'role': 'ai', 'content': answer});
        if (remaining != null) _dailyRemaining = remaining;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() {
        _messages.removeLast();
        _messages.add({'role': 'ai', 'content': 'Sorry, I had trouble fetching the word study. Please try again.'});
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
                  const Spacer(),
                  if (!widget.isPremium)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _dailyRemaining > 0
                            ? AppColors.surface
                            : AppColors.warmGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _dailyRemaining > 0
                              ? AppColors.warmGold.withOpacity(0.3)
                              : AppColors.warmGold.withOpacity(0.6),
                        ),
                      ),
                      child: Text(
                        _dailyRemaining > 0 ? '$_dailyRemaining left today' : 'Limit reached',
                        style: AppTypography.labelSmall.copyWith(
                          color: _dailyRemaining > 0 ? AppColors.textSecondary : AppColors.warmGold,
                          fontSize: 10,
                        ),
                      ),
                    ),
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
                      // Daily limit reached card
                      if (msg['role'] == 'limit_reached') {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.warmGold.withOpacity(0.12), AppColors.surface],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.warmGold.withOpacity(0.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('⚡ Daily limit reached', style: TextStyle(
                                  color: AppColors.warmGold, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 6),
                                Text(
                                  'Free users get 2 AI questions per day. Upgrade to Premium for unlimited questions, Greek/Hebrew word study, and more.',
                                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.warmGold,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      showPaywallSheet(
                                        context,
                                        featureName: 'AI Questions',
                                        limitMessage: "You've used your 2 free questions today.",
                                      );
                                    },
                                    child: const Text('Upgrade to Premium', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Upsell card (word study, premium-only feature)
                      if (msg['role'] == 'upsell') {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.warmGold.withOpacity(0.12), AppColors.surface],
                                begin: Alignment.topLeft, end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.warmGold.withOpacity(0.5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('🔑 Premium Feature', style: TextStyle(
                                  color: AppColors.warmGold, fontWeight: FontWeight.bold, fontSize: 14)),
                                const SizedBox(height: 6),
                                Text(
                                  'Greek & Hebrew word study unlocks key original-language terms, '
                                  'transliterations, and Strong\'s numbers for every verse.',
                                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.warmGold,
                                      foregroundColor: Colors.black,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      // TODO: navigate to premium upgrade screen
                                    },
                                    child: const Text('Upgrade to Premium', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
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
    return SingleChildScrollView(
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
          // Premium: Greek / Hebrew chip
          GestureDetector(
            onTap: _askWordStudy,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.warmGold.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warmGold.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Text('🔤 ', style: TextStyle(fontSize: 15)),
                  Expanded(
                    child: Text(
                      'Greek / Hebrew word study',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.warmGold),
                    ),
                  ),
                  if (!widget.isPremium)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warmGold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('PRO', style: TextStyle(
                        color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
