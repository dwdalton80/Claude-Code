import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../models/user_profile.dart';
import '../../widgets/common/flame_cta_button.dart';

// ── Settings Screen ───────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  final UserProfile profile;

  const SettingsScreen({super.key, required this.profile});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late BibleVersion _version;
  late SessionLength _sessionLength;
  late StudyLevel _studyLevel;
  late StudyGoal _goal;
  bool _notificationsEnabled = true;
  bool _streakReminderEnabled = true;
  bool _morningFocusEnabled = true;
  bool _reduceMotion = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _version = widget.profile.defaultVersion;
    _sessionLength = widget.profile.sessionLength;
    _studyLevel = widget.profile.studyLevel;
    _goal = widget.profile.goal ?? StudyGoal.readMore;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSlate,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Account ────────────────────────────────────────────────────────
          _SectionHeader('Account'),
          _InfoTile(
            label: 'Name',
            value: widget.profile.name,
          ),
          _InfoTile(
            label: 'Email',
            value: widget.profile.email,
          ),
          if (!widget.profile.isPremium)
            _ActionTile(
              icon: Icons.workspace_premium,
              label: 'Upgrade to Premium',
              color: AppColors.warmGold,
              onTap: () => _showPaywall(),
            ),
          _ActionTile(
            icon: Icons.logout,
            label: 'Sign out',
            color: AppColors.textSecondary,
            onTap: () => _confirmSignOut(context),
          ),

          const SizedBox(height: 24),

          // ── Reading Preferences ────────────────────────────────────────────
          _SectionHeader('Reading Preferences'),
          _DropdownTile<BibleVersion>(
            label: 'Default Bible Version',
            value: _version,
            items: BibleVersion.values,
            itemLabel: (v) => v.name.toUpperCase(),
            onChanged: (v) => setState(() => _version = v!),
          ),
          _DropdownTile<SessionLength>(
            label: 'Default Session Length',
            value: _sessionLength,
            items: SessionLength.values,
            itemLabel: (s) => _sessionLengthLabel(s),
            onChanged: (s) => setState(() => _sessionLength = s!),
          ),

          const SizedBox(height: 24),

          // ── Study Level ────────────────────────────────────────────────────
          _SectionHeader('Study Depth'),
          _SegmentedTile<StudyLevel>(
            label: 'Study Level',
            current: _studyLevel,
            options: StudyLevel.values,
            labelFor: (l) => _studyLevelLabel(l),
            onSelect: (l) => setState(() => _studyLevel = l),
          ),

          const SizedBox(height: 24),

          // ── Study Goal ─────────────────────────────────────────────────────
          _SectionHeader('Study Goal'),
          _SegmentedTile<StudyGoal>(
            label: 'My goal',
            current: _goal,
            options: StudyGoal.values,
            labelFor: (g) => _goalLabel(g),
            onSelect: (g) => setState(() => _goal = g),
          ),

          const SizedBox(height: 24),

          // ── Notifications ──────────────────────────────────────────────────
          _SectionHeader('Notifications'),
          _SwitchTile(
            label: 'Notifications',
            subtitle: 'Allow StudyFire to send you notifications',
            value: _notificationsEnabled,
            onChanged: (v) => setState(() => _notificationsEnabled = v),
          ),
          _SwitchTile(
            label: 'Streak reminders',
            subtitle: 'Daily reminder at 8pm if you haven\'t studied',
            value: _streakReminderEnabled && _notificationsEnabled,
            onChanged: _notificationsEnabled
                ? (v) => setState(() => _streakReminderEnabled = v)
                : null,
          ),
          _SwitchTile(
            label: 'Morning focus companion',
            subtitle: 'A short thought at 9:30am',
            value: _morningFocusEnabled && _notificationsEnabled,
            onChanged: _notificationsEnabled
                ? (v) => setState(() => _morningFocusEnabled = v)
                : null,
          ),

          const SizedBox(height: 24),

          // ── Accessibility ──────────────────────────────────────────────────
          _SectionHeader('Focus & Accessibility'),
          _SwitchTile(
            label: 'Reduce motion',
            subtitle: 'Minimize animations and transitions',
            value: _reduceMotion,
            onChanged: (v) => setState(() => _reduceMotion = v),
          ),

          const SizedBox(height: 24),

          // ── Data ───────────────────────────────────────────────────────────
          _SectionHeader('Data'),
          _ActionTile(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Export journal as PDF',
              color: AppColors.warmWhite,
              onTap: () => _exportPdf(),
            ),
          _ActionTile(
            icon: Icons.delete_outline,
            label: 'Delete my account',
            color: Colors.redAccent,
            onTap: () => _confirmDeleteAccount(context),
          ),

          const SizedBox(height: 32),

          FlameCTAButton(
            label: 'Save preferences',
            isLoading: _saving,
            onPressed: _save,
          ),

          const SizedBox(height: 40),

          Center(
            child: Text(
              'StudyFire v1.0',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FirestoreService().updatePreferences(
        widget.profile.uid,
        version: _version,
        sessionLength: _sessionLength,
        studyLevel: _studyLevel,
        goal: _goal,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showPaywall() {
    // Opened via RevenueCat SDK in production
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Upgrade to Premium', style: AppTypography.displaySmall),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unlock unlimited AI study, all Bible versions, memory verse SM-2, streak freeze, and more.',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('\$3.99/month or \$29.99/year', style: AppTypography.labelMedium),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: RevenueCat.presentPaywall()
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Sign out?', style: AppTypography.labelMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService().signOut();
            },
            child: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text('Delete account?', style: AppTypography.labelMedium),
        content: Text(
          'This permanently deletes your profile, XP, streaks, and journal. This cannot be undone.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Cloud Function to delete user data + Firebase Auth delete
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _exportPdf() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generating PDF…')),
    );
    try {
      final uid = widget.profile.uid;
      final entries = await FirestoreService().getJournalEntries(uid);
      
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text('StudyFire Journal',
                style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Text('Exported on \${DateTime.now().toString().split(' ')[0]}',
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey)),
            pw.SizedBox(height: 20),
            ...entries.map((e) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text(e.title.isEmpty ? 'Untitled' : e.title,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('\${e.date.month}/\${e.date.day}/\${e.date.year}',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600)),
                if (e.scriptureRefs.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text('Scripture: ' + e.scriptureRefs.join(', '),
                    style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic, color: PdfColors.orange800)),
                ],
                pw.SizedBox(height: 8),
                pw.Text(e.content, style: const pw.TextStyle(fontSize: 13)),
                pw.SizedBox(height: 16),
              ],
            )),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'StudyFire_Journal_\${DateTime.now().toString().split(' ')[0]}.pdf',
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: \$e')),
      );
    }
  }

  String _sessionLengthLabel(SessionLength s) {
    switch (s) {
      case SessionLength.spark:
        return 'Spark (60–90 sec)';
      case SessionLength.short:
        return 'Short (5–10 min)';
      case SessionLength.deep:
        return 'Deep (15–20 min)';
    }
  }

  String _studyLevelLabel(StudyLevel l) {
    switch (l) {
      case StudyLevel.beginner:
        return 'Beginner';
      case StudyLevel.growing:
        return 'Growing';
      case StudyLevel.scholar:
        return 'Scholar';
    }
  }

  String _goalLabel(StudyGoal g) {
    switch (g) {
      case StudyGoal.readMore:
        return 'Read more';
      case StudyGoal.understandDeeper:
        return 'Go deeper';
      case StudyGoal.memorize:
        return 'Memorize';
      case StudyGoal.applySermons:
        return 'Apply sermons';
    }
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Info Tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label, style: AppTypography.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Action Tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label, style: AppTypography.bodyMedium.copyWith(color: color)),
            const Spacer(),
            Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Dropdown Tile ─────────────────────────────────────────────────────────────

class _DropdownTile<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label, style: AppTypography.bodyMedium),
          const Spacer(),
          DropdownButton<T>(
            value: value,
            dropdownColor: AppColors.cardDark,
            underline: const SizedBox(),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.warmGold),
            items: items
                .map((i) => DropdownMenuItem<T>(
                      value: i,
                      child: Text(itemLabel(i)),
                    ))
                .toList(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Segmented Tile ────────────────────────────────────────────────────────────

class _SegmentedTile<T> extends StatelessWidget {
  final String label;
  final T current;
  final List<T> options;
  final String Function(T) labelFor;
  final ValueChanged<T> onSelect;

  const _SegmentedTile({
    required this.label,
    required this.current,
    required this.options,
    required this.labelFor,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.bodyMedium),
          const SizedBox(height: 10),
          Row(
            children: options.map((opt) {
              final selected = opt == current;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(opt),
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.warmGold.withOpacity(0.2)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? AppColors.warmGold
                            : AppColors.surfaceVariant,
                      ),
                    ),
                    child: Text(
                      labelFor(opt),
                      textAlign: TextAlign.center,
                      style: AppTypography.labelSmall.copyWith(
                        color: selected ? AppColors.warmGold : AppColors.warmWhite,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Switch Tile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchTile({
    required this.label,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.warmGold,
          ),
        ],
      ),
    );
  }
}
