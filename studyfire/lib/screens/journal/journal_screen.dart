import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/firestore_service.dart';
import '../../models/journal_entry.dart';
import '../../widgets/common/flame_cta_button.dart';

class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearch(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterChips(),
          const Expanded(child: _JournalList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openNewNote(context),
        backgroundColor: AppColors.flameOrange,
        child: const Icon(Icons.add, color: Colors.white),
      ),
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

class _JournalList extends StatelessWidget {
  const _JournalList();

  @override
  Widget build(BuildContext context) {
    // TODO: wire to Firestore stream provider
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 0,
      itemBuilder: (_, i) => const SizedBox.shrink(),
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

  const NoteEditorScreen({super.key, this.entry});

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
    }
    // Auto-save on content change
    _contentCtrl.addListener(_autoSave);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _speakerCtrl.dispose();
    super.dispose();
  }

  void _autoSave() {
    // Debounce: save after 500ms of inactivity
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _contentCtrl.text.isNotEmpty) _save();
    });
  }

  Future<void> _save() async {
    // TODO: save to Firestore
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(
        title: Text(_type == JournalType.sermon ? 'Sermon Notes' : 'Study Notes'),
        actions: [
          if (_saved)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Saved',
                style: AppTypography.bodySmall.copyWith(color: AppColors.emerald),
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

  void _unpackThis() {
    // Call Cloud Function — check free/premium limit
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
