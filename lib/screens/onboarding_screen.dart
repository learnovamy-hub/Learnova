import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';

// Smart greeting helper (shared with home_tab logic)
const _kMuslimIndicators = [
  'muhammad', 'muhamad', 'mohd', 'mohamad', 'mohammad', 'ahmad', 'ahmed',
  'nur', 'nurul', 'siti', 'wan', 'nik', 'tengku',
  'sharifah', 'syed', 'said', 'abd', 'abdul', 'abu',
  'ali', 'umar', 'omar', 'osman', 'hassan', 'husain', 'hussain',
  'ibrahim', 'ismail', 'idris', 'izzat', 'izzah',
  'fatimah', 'khadijah', 'zainab', 'aisyah', 'aisha', 'aishah',
  'yusof', 'yusuf', 'yahya', 'zakaria', 'hafiz', 'hakim',
  'azman', 'azwan', 'azrul', 'azri', 'farid', 'farhan', 'faiz',
  'halim', 'irfan', 'luqman', 'razif', 'razak', 'zulkifli',
];

String _getSmartGreeting(String name) {
  if (name.isNotEmpty) {
    final parts = name.toLowerCase().split(RegExp(r'\s+'));
    final isMuslim = parts.any((p) =>
        _kMuslimIndicators.any((ind) =>
            p.startsWith(ind) || (ind.startsWith(p) && p.length >= 3)));
    if (isMuslim) return 'Assalamualaikum';
  }
  final h = DateTime.now().hour;
  if (h < 12) return 'Selamat pagi';
  if (h < 17) return 'Selamat petang';
  return 'Selamat malam';
}

// â”€â”€ Design tokens â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kBg        = Color(0xFF07080C);
const _kHeading   = Color(0xFFE8ECF8);
const _kMuted     = Color(0xFF4A5070);
const _kOptText   = Color(0xFF8B949E);
const _kOptBorder = Color(0xFF1C1F2B);
const _kAccent    = Color(0xFF5B6EF5);
const _kFree      = Color(0xFF22C55E);
const _kDivider   = Color(0xFF0E1018);
const _kUncheck   = Color(0xFF2A2D38);

class OnboardingScreen extends StatefulWidget {
  final String studentId;
  final String token;
  final String studentName;
  const OnboardingScreen({
    super.key,
    required this.studentId,
    required this.token,
    required this.studentName,
  });
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int    _step      = 0;
  String? _level;
  bool   _advancing = false;
  bool   _submitting = false;
  String _learnovaId = '';

  static const _levels = ['Form 4', 'Form 5', 'A-Level', 'Lain-lain'];

  // (display name, isFree, api name)
  static const _spmRows = [
    ('Bahasa Malaysia', true,  'Bahasa Malaysia'),
    ('English',         true,  'English'),
    ('Matematik',       false, 'Mathematics'),
    ('Add Maths',       false, 'Add Maths'),
    ('Fizik',           false, 'Physics'),
    ('Kimia',           false, 'Chemistry'),
    ('Biologi',         false, 'Biology'),
    ('Sejarah',         false, 'Sejarah'),
  ];
  static const _alRows = [
    ('Bahasa Malaysia', true,  'Bahasa Malaysia'),
    ('English',         true,  'English'),
    ('Mathematics',     false, 'Mathematics'),
    ('Physics',         false, 'Physics'),
    ('Chemistry',       false, 'Chemistry'),
    ('Biology',         false, 'Biology'),
  ];

  final Set<String> _selected = {'Bahasa Malaysia', 'English'};

  List<(String, bool, String)> get _rows =>
      _level == 'A-Level' ? _alRows : _spmRows;

  // â”€â”€ Level tap â€” select + auto-advance after 300ms â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _selectLevel(String level) async {
    if (_advancing) return;
    _advancing = true;
    setState(() => _level = level);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() { _step = 1; _advancing = false; });
  }

  // â”€â”€ Submit onboarding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final apiLevel = (_level == 'Lain-lain' || _level == null) ? 'Form 5' : _level!;

    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/student/onboard'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'level': apiLevel,
          'selectedSubjects': _selected.toList(),
        }),
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final prefs = await SharedPreferences.getInstance();
        final lrnId = d['learnova_id'] as String? ?? '';
        final active = (d['active_subjects'] as List?)
            ?.map((e) => e.toString()).toList() ?? [];
        await prefs.setString('learnova_id', lrnId);
        await prefs.setString('active_subjects', jsonEncode(active));
        await prefs.setString('form_level', _level ?? '');
        await prefs.setBool('onboarding_completed', true);
        if (mounted) setState(() { _learnovaId = lrnId; _step = 2; });
      } else {
        if (mounted) _snack('Ralat berlaku. Cuba lagi.');
      }
    } catch (_) {
      if (mounted) _snack('Tiada sambungan internet.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red[800]));

  void _goToApp() => Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const MainShell(initialTabIndex: 0)),
    (_) => false,
  );

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeIn,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: switch (_step) {
            0 => _LevelScreen(
                levels: _levels,
                selected: _level,
                onTap: _selectLevel,
              ),
            1 => _SubjectScreen(
                rows: _rows,
                selected: _selected,
                submitting: _submitting,
                onToggle: (name) => setState(() {
                  if (_selected.contains(name)) _selected.remove(name);
                  else _selected.add(name);
                }),
                onContinue: _submit,
              ),
            _ => _DoneScreen(
                learnovaId: _learnovaId,
                studentName: widget.studentName,
                onStart: _goToApp,
              ),
          },
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SCREEN 1 â€” LEVEL
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _LevelScreen extends StatelessWidget {
  final List<String> levels;
  final String? selected;
  final void Function(String) onTap;
  const _LevelScreen({required this.levels, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(flex: 2),
            const Text(
              'Kamu pelajar tahun berapa?',
              style: TextStyle(
                color: _kHeading,
                fontSize: 22,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 32),
            ...levels.map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _LevelOption(
                label: l,
                selected: selected == l,
                onTap: () => onTap(l),
              ),
            )),
            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}

class _LevelOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LevelOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kAccent : _kOptBorder,
            width: selected ? 1.0 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _kOptText,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SCREEN 2 â€” SUBJECTS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _SubjectScreen extends StatelessWidget {
  final List<(String, bool, String)> rows;
  final Set<String> selected;
  final bool submitting;
  final void Function(String) onToggle;
  final VoidCallback onContinue;
  const _SubjectScreen({
    required this.rows,
    required this.selected,
    required this.submitting,
    required this.onToggle,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 60),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              'Subjek kamu?',
              style: TextStyle(
                color: _kHeading,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              'BM dan English percuma untuk semua',
              style: TextStyle(color: _kMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 32),
          ...rows.asMap().entries.map((e) {
            final i = e.key;
            final (name, free, _) = e.value;
            final checked = free || selected.contains(name);
            return Column(children: [
              if (i > 0)
                const Divider(
                  color: _kDivider, height: 1,
                  indent: 28, endIndent: 28,
                ),
              _SubjectRow(
                name: name,
                free: free,
                checked: checked,
                onTap: free ? null : () => onToggle(name),
              ),
            ]);
          }),
          const Spacer(),
          AnimatedOpacity(
            opacity: selected.isNotEmpty ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                28, 0, 28,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              child: _PrimaryButton(
                label: 'Teruskan',
                loading: submitting,
                onTap: selected.isNotEmpty ? onContinue : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  final String name;
  final bool free, checked;
  final VoidCallback? onTap;
  const _SubjectRow({
    required this.name,
    required this.free,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(children: [
            _Circle(checked: checked, free: free),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: _kHeading,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (free)
              const Text(
                'percuma',
                style: TextStyle(
                  color: _kFree,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  final bool checked, free;
  const _Circle({required this.checked, required this.free});

  @override
  Widget build(BuildContext context) {
    final color = free ? _kFree : _kAccent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? color : Colors.transparent,
        border: Border.all(
          color: checked ? color : _kUncheck,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 12)
          : null,
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SCREEN 3 â€” DONE
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _DoneScreen extends StatelessWidget {
  final String learnovaId;
  final String studentName;
  final VoidCallback onStart;
  const _DoneScreen({required this.learnovaId, required this.studentName, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final firstName = studentName.split(' ').first;
    final greeting = _getSmartGreeting(studentName);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          28, 0, 28,
          MediaQuery.of(context).padding.bottom + 28,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$greeting, $firstName!',
              style: const TextStyle(
                color: _kHeading,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.5),
                children: [
                  const TextSpan(
                    text: 'ID Pelajar kamu: ',
                    style: TextStyle(color: _kMuted),
                  ),
                  TextSpan(
                    text: learnovaId.isNotEmpty ? learnovaId : '---',
                    style: const TextStyle(
                      color: _kHeading,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            _PrimaryButton(label: 'Mula Belajar', onTap: onStart),
          ],
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// SHARED â€” PRIMARY BUTTON
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _PrimaryButton({required this.label, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: onTap != null ? _kAccent : _kAccent.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: loading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
        ),
      ),
    );
  }
}
