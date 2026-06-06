import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'home_tab.dart';
import 'subject_screen.dart';
import 'ai_tutor_tab.dart';
import 'profile_tab.dart';
import 'notifications_screen.dart';

class MainShell extends StatefulWidget {
  final String initialSubject;
  final int initialTabIndex;
  const MainShell({super.key, this.initialSubject = 'Mathematics', this.initialTabIndex = 0});
  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int currentIndex = 0;
  String _selectedSubject = 'Mathematics';
  String? _preReadTopic;
  bool _preRead = false;
  bool _inTutorMode = false;

  void setTutorMode(bool active) {
    if (mounted) setState(() => _inTutorMode = active);
  }

  static const int _maxSeconds   = 75 * 60;
  static const int _warnSeconds  = 60 * 60;
  static const int _breakSeconds = 33 * 60;
  static const int _breakDuration =  8 * 60;

  Timer? _timer;
  int    _elapsed      = 0;
  bool   _onBreak      = false;
  int    _breakElapsed = 0;
  Timer? _breakTimer;
  bool   _breakShown   = false;
  bool   _warnShown    = false;
  bool   _hardStopped  = false;

  int _unreadCount = 0;
  Timer? _notifTimer;

  @override
  void initState() {
    super.initState();
    _selectedSubject = widget.initialSubject;
    currentIndex = widget.initialTabIndex;
    _startTimer();
    _pollNotifications();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollNotifications());
  }

  Future<void> _pollNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      if (token.isEmpty) return;
      final r = await http.get(
        Uri.parse('$kApiUrl/api/student/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final count = (data['unread_count'] as num?)?.toInt() ?? 0;
        if (mounted && count != _unreadCount) setState(() => _unreadCount = count);
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_onBreak || _hardStopped) return;
      setState(() => _elapsed++);
      if (!_breakShown && _elapsed >= _breakSeconds) {
        _breakShown = true;
        _showBreakReminder();
      } else if (!_warnShown && _elapsed >= _warnSeconds) {
        _warnShown = true;
        _showWarningBanner();
      } else if (_elapsed >= _maxSeconds) {
        _hardStop();
      }
    });
  }

  void _showBreakReminder() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isDismissible: false,
      enableDrag: false,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('⏸️', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          const Text('Time for a quick break!',
            style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text("You've been studying for 33 minutes — great focus! Grab some water, stretch, or take a toilet break. Your session is paused.",
            textAlign: TextAlign.center,
            style: TextStyle(color: kMuted, fontSize: 13, height: 1.55)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () { Navigator.pop(context); _startBreak(); },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kPrimary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Take a break 🧃', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: kSurface2,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Keep going', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
            )),
          ]),
        ]),
      ),
    );
  }

  void _startBreak() {
    setState(() { _onBreak = true; _breakElapsed = 0; });
    _breakTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _breakTimer?.cancel(); return; }
      setState(() => _breakElapsed++);
      if (_breakElapsed >= _breakDuration) _endBreak(auto: true);
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Session paused — enjoy your break! 🧃'),
      backgroundColor: kSurface2,
      duration: Duration(seconds: 3),
    ));
  }

  void _endBreak({bool auto = false}) {
    _breakTimer?.cancel();
    if (!mounted) return;
    setState(() => _onBreak = false);
    if (auto) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Break over — welcome back! Let's continue 💪"),
        backgroundColor: Color(0xFF059669),
        duration: Duration(seconds: 3),
      ));
    }
  }

  void _showWarningBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('⏰ 15 minutes left — let\'s wrap up this topic strong!'),
      backgroundColor: Color(0xFFD97706),
      duration: Duration(seconds: 6),
    ));
  }

  void _hardStop() {
    if (_hardStopped) return;
    _hardStopped = true;
    _timer?.cancel();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Session complete! 🎉", style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
        content: Text(
          "You've hit 75 minutes — amazing dedication, $_selectedSubject warrior!\n\nTime for your end-of-session quiz to lock in what you learned.",
          style: const TextStyle(color: kMuted, height: 1.55)),
        actions: [
          ElevatedButton(
            onPressed: () { Navigator.pop(context); setState(() => currentIndex = 2); },
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary),
            child: const Text('Start quiz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void setSubject(String s) => setState(() => _selectedSubject = s);

  void startTopicWithPreRead(String subject, String topic) {
    setState(() {
      _selectedSubject = subject;
      _preReadTopic = topic;
      _preRead = true;
      currentIndex = 2;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _preRead = false; _preReadTopic = null; });
    });
  }

  List<Widget> get _screens => [
    const HomeTab(),
    const SubjectScreen(),
    AITutorTab(
      selectedSubject: _selectedSubject,
      initialTopic: _preReadTopic,
      preRead: _preRead,
    ),
    const ProfileTab(),
  ];

  void _openNotifications() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => NotificationsScreen(onRead: () {
        if (mounted) setState(() => _unreadCount = 0);
      }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      body: Stack(children: [
        _screens[currentIndex],
        // Back to Home button — top-left on all non-home tabs
        if (currentIndex != 0)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => setState(() => currentIndex = 0),
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: kMuted, size: 20),
              ),
            ),
          ),
        // Notification bell overlay in top-right (hidden on Profil tab)
        if (currentIndex != 3)
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: GestureDetector(
            onTap: _openNotifications,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
                child: const Icon(Icons.notifications_rounded, color: kMuted, size: 20),
              ),
              if (_unreadCount > 0) Positioned(
                top: -4, right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: kRed, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    _unreadCount > 9 ? '9+' : '$_unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kBorder))),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (i) => setState(() => currentIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: kPrimary,
          unselectedItemColor: kMuted,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded),          label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded),     label: 'Learn'),
            BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded),  label: 'Nova'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded),        label: 'Profil'),
          ],
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breakTimer?.cancel();
    _notifTimer?.cancel();
    super.dispose();
  }
}

class SubjectSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const SubjectSelector({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kSubjects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final s = kSubjects[i];
          final isSelected = s['name'] == selected;
          final color = Color(s['color'] as int);
          return GestureDetector(
            onTap: () => onChanged(s['name'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? color.withOpacity(0.2) : kSurface2,
                border: Border.all(color: isSelected ? color : kBorder, width: isSelected ? 1.5 : 1),
                borderRadius: BorderRadius.circular(22)),
              child: Text(s['name'] as String,
                style: TextStyle(
                  color: isSelected ? color : kMuted,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
            ),
          );
        },
      ),
    );
  }
}
