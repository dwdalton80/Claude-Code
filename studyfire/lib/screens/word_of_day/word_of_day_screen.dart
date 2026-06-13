import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/constants/xp_rewards.dart';
import '../../core/services/xp_service.dart';
import '../../widgets/common/flame_cta_button.dart';
import '../../widgets/gamification/xp_burst.dart';

class WordOfDayData {
  final String word;
  final String originalWord;
  final String transliteration;
  final String pronunciation;
  final String strongsNumber;
  final String language; // 'greek' | 'hebrew'
  final String plainDefinition;
  final String funFact;
  final List<String> otherPassages;
  final String fromReference;

  const WordOfDayData({
    required this.word,
    required this.originalWord,
    required this.transliteration,
    required this.pronunciation,
    required this.strongsNumber,
    required this.language,
    required this.plainDefinition,
    required this.funFact,
    required this.otherPassages,
    required this.fromReference,
  });

  factory WordOfDayData.fromMap(Map<String, dynamic> m) => WordOfDayData(
        word: m['word'] ?? '',
        originalWord: m['originalWord'] ?? '',
        transliteration: m['transliteration'] ?? '',
        pronunciation: m['pronunciation'] ?? '',
        strongsNumber: m['strongsNumber'] ?? '',
        language: m['language'] ?? 'greek',
        plainDefinition: m['plainDefinition'] ?? '',
        funFact: m['funFact'] ?? '',
        otherPassages: List<String>.from(m['otherPassages'] ?? []),
        fromReference: m['fromReference'] ?? '',
      );
}

class WordOfDayScreen extends StatefulWidget {
  final WordOfDayData? data; // null = load from daily cache
  final String uid;
  final bool isPremium;

  const WordOfDayScreen({
    super.key,
    this.data,
    required this.uid,
    required this.isPremium,
  });

  @override
  State<WordOfDayScreen> createState() => _WordOfDayScreenState();
}

class _WordOfDayScreenState extends State<WordOfDayScreen> {
  WordOfDayData? _data;
  bool _loading = true;
  bool _reacted = false;
  bool _showXpBurst = false;
  bool _showExplorer = false;

  final _xpService = XpService();

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _data = widget.data;
      _loading = false;
      _trackWordExplored();
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Mock — production: load from dailycache
    _data = const WordOfDayData(
      word: 'love',
      originalWord: 'ἀγάπη',
      transliteration: 'agape',
      pronunciation: 'ah-GAH-pay',
      strongsNumber: 'G26',
      language: 'greek',
      plainDefinition: 'Unconditional, self-giving love — not based on feelings but on choice.',
      funFact: 'The word for "love" here is agape — not friendship love (phileo) or romantic love (eros), but a love that chooses to act regardless of how you feel. It\'s the word used in John 3:16 and 1 Corinthians 13.',
      otherPassages: ['John 3:16', '1 Corinthians 13:4', 'Romans 5:8'],
      fromReference: 'Romans 8:28',
    );
    setState(() => _loading = false);
    _trackWordExplored();
  }

  void _trackWordExplored() {
    if (widget.uid.isEmpty) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .update({'profile.wordsExplored': FieldValue.increment(1)})
        .catchError((_) {});
  }

  void _react() {
    if (_reacted) return;
    _xpService.accumulateXp(widget.uid, XpRewards.wordOfDayTap);
    setState(() {
      _reacted = true;
      _showXpBurst = true;
    });
  }

  void _share() {
    final d = _data!;
    Share.share(
      '${d.originalWord} (${d.transliteration}) — "${d.funFact}"\n\nFrom ${d.fromReference} · StudyFire 🔥',
    );
  }

  void _goDeeper() {
    setState(() => _showExplorer = true);
  }

  void _showPaywallPrompt() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔒 Full Greek/Hebrew Explorer', style: AppTypography.displaySmall),
            const SizedBox(height: 12),
            Text(
              'Unlock detailed parsing, verb tense, word history, and every passage using this word.',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FlameCTAButton(
              label: 'Unlock Premium — \$3.99/mo',
              onPressed: () {
                Navigator.pop(context);
                // Open RevenueCat paywall
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now', style: AppTypography.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.deepSlate,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final d = _data!;

    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: const Text('Word of the Day'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _showExplorer
                ? _FullExplorer(data: d, onPassageTap: (_) {})
                : _WordCard(
                    data: d,
                    reacted: _reacted,
                    onReact: _react,
                    onShare: _share,
                    onGoDeeper: _goDeeper,
                    isPremium: widget.isPremium,
                  ),
          ),
          if (_showXpBurst)
            XpBurstOverlay(
              xp: XpRewards.wordOfDayTap,
              onComplete: () => setState(() => _showXpBurst = false),
            ),
        ],
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  final WordOfDayData data;
  final bool reacted;
  final VoidCallback onReact;
  final VoidCallback onShare;
  final VoidCallback onGoDeeper;
  final bool isPremium;

  const _WordCard({
    required this.data,
    required this.reacted,
    required this.onReact,
    required this.onShare,
    required this.onGoDeeper,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'From ${data.fromReference}',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),

        // Big original word
        Center(
          child: Text(
            data.originalWord,
            style: AppTypography.greekHebrew,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${data.transliteration} · ${data.pronunciation}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            data.strongsNumber,
            style: AppTypography.labelSmall,
          ),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(data.funFact, style: AppTypography.bodyLarge),
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: onReact,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: reacted
                        ? AppColors.warmGold.withOpacity(0.2)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: reacted ? AppColors.warmGold : AppColors.surfaceVariant,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text('🔥', style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(
                        reacted ? 'Loved it!' : "That's cool",
                        style: AppTypography.labelSmall.copyWith(
                          color: reacted ? AppColors.warmGold : AppColors.warmWhite,
                        ),
                      ),
                      if (!reacted)
                        Text(
                          '+${XpRewards.wordOfDayTap} XP',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: onShare,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.surfaceVariant),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.share_outlined, color: AppColors.warmWhite, size: 22),
                      const SizedBox(height: 4),
                      const Text('Share', style: AppTypography.labelSmall),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onGoDeeper,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            side: BorderSide(
              color: isPremium ? AppColors.warmGold : AppColors.textSecondary,
            ),
            foregroundColor: isPremium ? AppColors.warmGold : AppColors.textSecondary,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isPremium)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.lock_outline, size: 16),
                ),
              Text('Go deeper${isPremium ? "" : " — Premium"}'),
            ],
          ),
        ),
      ],
    );
  }
}

class _FullExplorer extends StatelessWidget {
  final WordOfDayData data;
  final ValueChanged<String> onPassageTap;

  const _FullExplorer({required this.data, required this.onPassageTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Text(data.originalWord, style: AppTypography.greekHebrew)),
        const SizedBox(height: 8),
        Center(child: Text(data.transliteration, style: AppTypography.bodyMedium)),
        Center(
          child: Text(
            '${data.pronunciation} · ${data.strongsNumber}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 20),

        _ExplorerSection(
          title: 'Definition',
          child: Text(data.plainDefinition, style: AppTypography.bodyLarge),
        ),
        const SizedBox(height: 12),

        _ExplorerSection(
          title: 'Fun Fact',
          child: Text(data.funFact, style: AppTypography.bodyMedium),
        ),
        const SizedBox(height: 12),

        _ExplorerSection(
          title: 'Other passages using this word',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: data.otherPassages.map((ref) => GestureDetector(
              onTap: () => onPassageTap(ref),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.warmGold.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warmGold.withOpacity(0.4)),
                ),
                child: Text(ref, style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 12),

        _ExplorerSection(
          title: 'Scholar Mode',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ScholarRow('Language', data.language[0].toUpperCase() + data.language.substring(1)),
              _ScholarRow('Strong\'s', data.strongsNumber),
              _ScholarRow('Pronunciation', data.pronunciation),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExplorerSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _ExplorerSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.labelMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ScholarRow extends StatelessWidget {
  final String label;
  final String value;

  const _ScholarRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: AppTypography.bodySmall),
          const Spacer(),
          Text(value, style: AppTypography.labelSmall.copyWith(color: AppColors.warmGold)),
        ],
      ),
    );
  }
}
