import 'dart:convert';
import 'dart:math' as math;
import '../config/disclaimers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'main_shell.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const _cities = {
    'Kuala Lumpur': [3.1390, 101.6869],
    'Petaling Jaya': [3.1073, 101.6067],
    'Shah Alam': [3.0733, 101.5185],
    'Johor Bahru': [1.4927, 103.7414],
    'Pulau Pinang': [5.4141, 100.3288],
    'Ipoh': [4.5975, 101.0901],
    'Kota Bharu': [6.1248, 102.2388],
    'Kuantan': [3.8077, 103.3260],
    'Kuching': [1.5497, 110.3593],
    'Kota Kinabalu': [5.9804, 116.0735],
    'Melaka': [2.1896, 102.2501],
    'Seremban': [2.7297, 101.9381],
    'Alor Setar': [6.1248, 100.3658],
  };

  Map<String, dynamic>? _dash;
  bool _loading = true;

  // Weather
  double? _temp;
  String? _weatherDesc;
  IconData _weatherIcon = Icons.wb_sunny_rounded;
  bool _weatherLoading = false;
  String? _selectedCity;

  String _name = '';
  String _token = '';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _initWeather();
  }

  Future<void> _initWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final city = prefs.getString('weather_city');
    if (city != null && _cities.containsKey(city)) {
      setState(() => _selectedCity = city);
      _loadWeather(city);
    }
  }

  Future<void> _loadDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
    _name = prefs.getString('student_name') ?? prefs.getString('name') ?? '';

    // 30-min cache
    final cached = prefs.getString('home_dash_cache');
    final cachedAt = prefs.getInt('home_dash_cached_at') ?? 0;
    if (cached != null && (DateTime.now().millisecondsSinceEpoch - cachedAt) < 1800000) {
      setState(() { _dash = jsonDecode(cached); _loading = false; });
      return;
    }

    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/home/dashboard'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        await prefs.setString('home_dash_cache', r.body);
        await prefs.setInt('home_dash_cached_at', DateTime.now().millisecondsSinceEpoch);
        setState(() => _dash = d);
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('home_dash_cache');
    await prefs.remove('home_dash_cached_at');
    setState(() { _loading = true; _dash = null; });
    await _loadDashboard();
    if (_selectedCity != null) _loadWeather(_selectedCity!);
  }

  void _loadWeather(String city) {
    setState(() => _weatherLoading = true);
    _fetchWeatherForCity(city);
  }

  Future<void> _fetchWeatherForCity(String city) async {
    final coords = _cities[city];
    if (coords == null) { if (mounted) setState(() => _weatherLoading = false); return; }
    try {
      final lat = coords[0];
      final lon = coords[1];
      final r = await http.get(Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weathercode'));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final code = (d['current']?['weathercode'] as num?)?.toInt() ?? 0;
        final temp = (d['current']?['temperature_2m'] as num?)?.toDouble();
        if (mounted) setState(() {
          _temp = temp;
          _weatherDesc = _codeToDesc(code);
          _weatherIcon = _codeToIcon(code);
          _weatherLoading = false;
        });
      } else {
        if (mounted) setState(() => _weatherLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  void _showCityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kBorder, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('Pilih Bandar', style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Pilih untuk mendapatkan ramalan cuaca tempatan', style: TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: _cities.keys.map((city) {
            final sel = city == _selectedCity;
            return GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('weather_city', city);
                setState(() { _selectedCity = city; _temp = null; });
                _loadWeather(city);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? kPrimary.withOpacity(0.2) : kSurface2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? kPrimary : kBorder, width: sel ? 1.5 : 1)),
                child: Text(city, style: TextStyle(color: sel ? kPrimary : kText, fontSize: 13,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              ),
            );
          }).toList()),
        ]),
      ),
    );
  }

  String _codeToDesc(int c) {
    if (c == 0) return 'Cerah';
    if (c <= 3) return 'Berawan';
    if (c <= 48) return 'Kabus';
    if (c <= 67) return 'Hujan Renyai';
    if (c <= 82) return 'Hujan';
    return 'Ribut Petir';
  }

  IconData _codeToIcon(int c) {
    if (c == 0) return Icons.wb_sunny_rounded;
    if (c <= 3) return Icons.cloud_rounded;
    if (c <= 48) return Icons.cloud_rounded;
    if (c <= 67) return Icons.grain_rounded;
    if (c <= 82) return Icons.water_drop_rounded;
    return Icons.thunderstorm_rounded;
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Selamat pagi';
    if (h < 17) return 'Selamat petang';
    return 'Selamat malam';
  }

  String get _firstName {
    if (_name.isEmpty) return 'Pelajar';
    return _name.split(' ').first;
  }

  void _goToTutor({String? subject}) {
    final shell = context.findAncestorStateOfType<MainShellState>();
    if (shell == null) return;
    if (subject != null) shell.setSubject(subject);
    shell.setState(() => shell.currentIndex = 2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: RefreshIndicator(
        color: kPrimary,
        backgroundColor: kSurface,
        onRefresh: _refresh,
        child: CustomScrollView(slivers: [
          _buildAppBar(),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: kPrimary)))
          else
            SliverList(delegate: SliverChildListDelegate([
              _buildSpmCountdown(),
              if (_dash?['resume_session'] != null) _buildResumeSession(),
              _buildWeeklyStats(),
              _buildStreak(),
              _buildBreakGames(),
              _buildQuoteOfDay(),
              _buildWeatherCard(),
              _buildNewsSection(),
              // Footer disclaimer
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  LearnovaDisclaimers.shortNotice,
                  style: const TextStyle(fontSize: 11, color: kMuted),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 100),
            ])),
        ]),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: const Color(0xFF1E1B4B),
      expandedHeight: 120,
      floating: true,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1E1B4B), Color(0xFF0D1B2A)])),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 60, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(_greeting, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
                const SizedBox(height: 2),
                Text(_firstName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              ]),
            ),
          ),
        ),
      ),
      actions: [
        if (_weatherLoading)
          const Padding(padding: EdgeInsets.only(right: 16, top: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)))
        else if (_temp != null)
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 6),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Icon(_weatherIcon, color: Colors.white70, size: 18),
              Text('${_temp!.round()}°C', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
      ],
    );
  }

  // ─── Section 1: SPM Countdown ─────────────────────────────────────────────
  Widget _buildSpmCountdown() {
    final days = (_dash?['spm_days_remaining'] as num?)?.toInt() ?? 0;
    final pct = (_dash?['prep_percent'] as num?)?.toInt() ?? 0;
    final urgency = days < 90;
    final color1 = urgency ? const Color(0xFFEF4444) : kPrimary;
    final color2 = urgency ? const Color(0xFFB91C1C) : kPrimary2;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color1, color2]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color1.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: const Text('COUNTDOWN SPM 2026',
              style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          ),
          const Spacer(),
          const Icon(Icons.school_rounded, color: Colors.white60, size: 18),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$days', style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, height: 1)),
          const SizedBox(width: 8),
          const Padding(padding: EdgeInsets.only(bottom: 8),
            child: Text('hari lagi', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: pct / 100, backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white), minHeight: 6)),
        const SizedBox(height: 8),
        Text('$pct% masa persediaan telah digunakan',
          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11)),
      ]),
    );
  }

  // ─── Section 2: Resume Last Session ──────────────────────────────────────
  Widget _buildResumeSession() {
    final r = _dash!['resume_session'] as Map<String, dynamic>;
    final subject = r['subject'] as String? ?? '';
    final topic = r['topic'] as String? ?? '';
    final lastSeen = r['last_seen'] as String? ?? '';
    String timeAgo = '';
    if (lastSeen.isNotEmpty) {
      try {
        final dt = DateTime.parse(lastSeen);
        final diff = DateTime.now().difference(dt);
        if (diff.inHours < 1) timeAgo = '${diff.inMinutes} minit lepas';
        else if (diff.inHours < 24) timeAgo = '${diff.inHours} jam lepas';
        else timeAgo = '${diff.inDays} hari lepas';
      } catch (_) {}
    }

    return GestureDetector(
      onTap: () => _goToTutor(subject: subject),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kPrimary.withOpacity(0.4), width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sambung Sesi', style: TextStyle(color: kPrimary, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(topic.isNotEmpty ? topic : subject,
              style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('$subject${timeAgo.isNotEmpty ? ' · $timeAgo' : ''}',
              style: const TextStyle(color: kMuted, fontSize: 11)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: kMuted, size: 14),
        ]),
      ),
    );
  }

  // ─── Section 3: Weekly Stats ──────────────────────────────────────────────
  Widget _buildWeeklyStats() {
    final ws = _dash?['weekly_stats'] as Map<String, dynamic>? ?? {};
    final score = ws['avg_quiz_score'];
    final mins = (ws['study_minutes'] as num?)?.toInt() ?? 0;
    final topics = (ws['topics_completed'] as num?)?.toInt() ?? 0;
    final weak = ws['weakest_subject'] as String?;
    final hours = mins ~/ 60;
    final remMins = mins % 60;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Minggu Ini', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _statCard(
            label: 'Skor Kuiz',
            value: score != null ? '$score%' : '--',
            icon: Icons.quiz_rounded,
            color: kGreen,
          )),
          const SizedBox(width: 10),
          Expanded(child: _statCard(
            label: 'Masa Belajar',
            value: mins == 0 ? '--' : hours > 0 ? '${hours}j ${remMins}m' : '${remMins}m',
            icon: Icons.timer_rounded,
            color: const Color(0xFF06B6D4),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _statCard(
            label: 'Topik Selesai',
            value: '$topics',
            icon: Icons.check_circle_rounded,
            color: kPrimary,
          )),
          const SizedBox(width: 10),
          Expanded(child: _statCard(
            label: 'Perlu Perhatian',
            value: weak ?? '--',
            icon: Icons.warning_amber_rounded,
            color: kYellow,
            small: true,
          )),
        ]),
      ]),
    );
  }

  Widget _statCard({required String label, required String value, required IconData icon, required Color color, bool small = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 14)),
          const Spacer(),
        ]),
        const SizedBox(height: 10),
        Text(value,
          style: TextStyle(color: kText, fontSize: small ? 13 : 20, fontWeight: FontWeight.w900, height: 1.1),
          maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    );
  }

  // ─── Section 4: Daily Streak ──────────────────────────────────────────────
  Widget _buildStreak() {
    final s = _dash?['streak'] as Map<String, dynamic>? ?? {};
    final days = (s['days'] as num?)?.toInt() ?? 0;
    final weekDays = (s['week_days'] as List?)?.cast<bool>() ?? List.filled(7, false);
    const dayLabels = ['I', 'S', 'R', 'K', 'J', 'S', 'A'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C00)]),
              borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text('$days', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Streak Harian', style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w800)),
            Text(days == 0 ? 'Mula hari ini!' : days == 1 ? '1 hari berturut-turut' : '$days hari berturut-turut',
              style: const TextStyle(color: kMuted, fontSize: 12)),
          ])),
          const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF6B35), size: 28),
        ]),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            final active = i < weekDays.length && weekDays[i];
            return Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 32, height: 32,
                decoration: BoxDecoration(
                  gradient: active ? const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF8C00)]) : null,
                  color: active ? null : kSurface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: active ? Colors.transparent : kBorder, width: 1.5),
                ),
                child: active ? const Icon(Icons.check, color: Colors.white, size: 14) : null,
              ),
              const SizedBox(height: 4),
              Text(dayLabels[i], style: TextStyle(color: active ? const Color(0xFFFF6B35) : kMuted, fontSize: 10, fontWeight: FontWeight.w700)),
            ]);
          }),
        ),
      ]),
    );
  }

  // ─── Section 6: Break Games ───────────────────────────────────────────────
  Widget _buildBreakGames() {
    final games = [
      {'icon': Icons.calculate_rounded, 'label': 'Nombor Cepat', 'desc': 'Matematik pantas', 'color': 0xFF6366F1},
      {'icon': Icons.lightbulb_rounded, 'label': 'Teka Istilah', 'desc': 'Teka kata kunci', 'color': 0xFF10B981},
      {'icon': Icons.flash_on_rounded, 'label': 'Kilat Kuiz', 'desc': '10 soalan segera', 'color': 0xFFF59E0B},
      {'icon': Icons.history_edu_rounded, 'label': 'Sejarah Hari Ini', 'desc': 'Fakta Sejarah', 'color': 0xFFD97706},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Permainan Rehat', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Segarkan minda dengan mini-games', style: TextStyle(color: kMuted, fontSize: 11)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _gameCard(games[0])),
          const SizedBox(width: 10),
          Expanded(child: _gameCard(games[1])),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _gameCard(games[2])),
          const SizedBox(width: 10),
          Expanded(child: _gameCard(games[3])),
        ]),
      ]),
    );
  }

  Widget _gameCard(Map<String, dynamic> game) {
    final color = Color(game['color'] as int);
    return GestureDetector(
      onTap: () => _launchGame(game['label'] as String),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(game['icon'] as IconData, color: color, size: 20)),
          const SizedBox(height: 10),
          Text(game['label'] as String,
            style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(game['desc'] as String, style: const TextStyle(color: kMuted, fontSize: 10)),
        ]),
      ),
    );
  }

  void _launchGame(String name) {
    switch (name) {
      case 'Nombor Cepat': _showMathGame(); break;
      case 'Teka Istilah': _showTermGame(); break;
      case 'Kilat Kuiz': _showFlashQuiz(); break;
      case 'Sejarah Hari Ini': _showHistoryFact(); break;
    }
  }

  // ── Nombor Cepat (Math Game) ─────────────────────────────────────────────
  void _showMathGame() {
    showDialog(context: context, builder: (_) => const _MathGameDialog());
  }

  // ── Teka Istilah ─────────────────────────────────────────────────────────
  void _showTermGame() async {
    final chunks = await _fetchGameChunks(limit: 20);
    if (!mounted) return;
    showDialog(context: context, builder: (_) => _TermGameDialog(chunks: chunks, token: _token));
  }

  // ── Kilat Kuiz ───────────────────────────────────────────────────────────
  void _showFlashQuiz() async {
    final chunks = await _fetchGameChunks(limit: 10);
    if (!mounted) return;
    showDialog(context: context, builder: (_) => _FlashQuizDialog(chunks: chunks));
  }

  // ── Sejarah Hari Ini ─────────────────────────────────────────────────────
  void _showHistoryFact() async {
    final chunks = await _fetchGameChunks(subject: 'Sejarah', limit: 1);
    if (!mounted || chunks.isEmpty) return;
    showDialog(context: context, builder: (_) => _HistoryFactDialog(chunk: chunks.first));
  }

  Future<List<Map<String, dynamic>>> _fetchGameChunks({String? subject, int limit = 10}) async {
    try {
      final uri = Uri.parse('$kApiUrl/api/home/game-chunks').replace(queryParameters: {
        if (subject != null) 'subject': subject,
        'limit': '$limit',
      });
      final r = await http.get(uri, headers: {'Authorization': 'Bearer $_token'});
      if (r.statusCode == 200) return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
    } catch (_) {}
    return [];
  }

  // ─── Section 7: Quote of the Day ─────────────────────────────────────────
  Widget _buildQuoteOfDay() {
    final q = _dash?['daily_quote'] as Map<String, dynamic>?;
    if (q == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.format_quote_rounded, color: kPrimary, size: 16)),
          const SizedBox(width: 8),
          const Text('Kata-Kata Hari Ini', style: TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 14),
        Text(q['text'] as String? ?? '',
          style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w500, height: 1.65,
            fontStyle: FontStyle.italic)),
        const SizedBox(height: 10),
        Text('— ${q['author'] as String? ?? ''}',
          style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ─── Section 8: Weather ───────────────────────────────────────────────────
  Widget _buildWeatherCard() {
    if (_selectedCity == null) {
      return GestureDetector(
        onTap: _showCityPicker,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF06B6D4).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.wb_cloudy_rounded, color: Color(0xFF06B6D4), size: 20)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Cuaca Tempatan', style: TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('Ketik untuk pilih bandar anda', style: TextStyle(color: kMuted, fontSize: 11)),
            ]),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: kMuted, size: 20),
          ]),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        if (_weatherLoading)
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Color(0xFF06B6D4), strokeWidth: 2))
        else
          Icon(_weatherIcon, color: const Color(0xFF06B6D4), size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_weatherLoading ? 'Memuatkan...' : '${_temp?.round() ?? '--'}°C · ${_weatherDesc ?? ''}',
            style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w700)),
          Text(_selectedCity!, style: const TextStyle(color: kMuted, fontSize: 11)),
        ])),
        GestureDetector(
          onTap: _showCityPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
            child: const Text('Tukar', style: TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  // ─── Section 9: News Feed ─────────────────────────────────────────────────
  Widget _buildNewsSection() {
    final news = (_dash?['news'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (news.isEmpty) return const SizedBox.shrink();

    final typeIcon = {
      'news': Icons.newspaper_rounded,
      'scholarship': Icons.emoji_events_rounded,
      'tip': Icons.tips_and_updates_rounded,
      'quote': Icons.format_quote_rounded,
    };
    final typeColor = {
      'news': kPrimary,
      'scholarship': kYellow,
      'tip': kGreen,
      'quote': const Color(0xFF06B6D4),
    };
    final typeLabel = {
      'news': 'BERITA',
      'scholarship': 'BIASISWA',
      'tip': 'TIP BELAJAR',
      'quote': 'PETIKAN',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Terkini', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ...news.take(3).map((item) {
          final type = item['type'] as String? ?? 'news';
          final color = typeColor[type] ?? kPrimary;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(typeIcon[type] ?? Icons.info_rounded, color: color, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(typeLabel[type] ?? 'INFO',
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 6),
                  if ((item['source'] as String?)?.isNotEmpty == true)
                    Flexible(child: Text(item['source'] as String,
                      style: const TextStyle(color: kMuted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 6),
                Text(item['title'] as String? ?? '',
                  style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 4),
                Text(item['body'] as String? ?? '',
                  style: const TextStyle(color: kMuted, fontSize: 11, height: 1.5),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ])),
            ]),
          );
        }),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Mini-game: Nombor Cepat
// ══════════════════════════════════════════════════════════════════════════════
class _MathGameDialog extends StatefulWidget {
  const _MathGameDialog();
  @override State<_MathGameDialog> createState() => _MathGameDialogState();
}

class _MathGameDialogState extends State<_MathGameDialog> {
  final _rng = math.Random();
  int _q = 0, _score = 0, _total = 10;
  int _a = 0, _b = 0, _op = 0;
  late List<int> _choices;
  int? _selected;
  bool _done = false;

  @override
  void initState() { super.initState(); _next(); }

  void _next() {
    if (_q >= _total) { setState(() => _done = true); return; }
    _a = _rng.nextInt(19) + 1;
    _b = _rng.nextInt(19) + 1;
    _op = _rng.nextInt(3); // 0=+, 1=-, 2=×
    if (_op == 1 && _b > _a) { final t = _a; _a = _b; _b = t; }
    final ans = _op == 0 ? _a + _b : _op == 1 ? _a - _b : _a * _b;
    final wrong = List.generate(3, (_) {
      int w;
      do { w = ans + _rng.nextInt(11) - 5; } while (w == ans);
      return w;
    });
    _choices = [ans, ...wrong]..shuffle(_rng);
    setState(() { _selected = null; });
  }

  int get _answer => _op == 0 ? _a + _b : _op == 1 ? _a - _b : _a * _b;

  void _tap(int val) {
    if (_selected != null) return;
    setState(() { _selected = val; if (val == _answer) _score++; });
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) { setState(() => _q++); _next(); }
    });
  }

  @override
  Widget build(BuildContext context) {
    final opStr = ['+', '−', '×'][_op];
    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _done ? Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Tamat!', style: TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text('$_score / $_total betul', style: TextStyle(
            color: _score >= 7 ? kGreen : _score >= 4 ? kYellow : kRed,
            fontSize: 36, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Tutup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]) : Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('Soalan ${_q + 1}/$_total', style: const TextStyle(color: kMuted, fontSize: 12)),
            const Spacer(),
            Text('Markah: $_score', style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 24),
          Text('$_a $opStr $_b = ?',
            style: const TextStyle(color: kText, fontSize: 34, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          GridView.count(crossAxisCount: 2, shrinkWrap: true, childAspectRatio: 2.5,
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            children: _choices.map((v) {
              Color bg = kSurface2;
              Color border = kBorder;
              if (_selected != null) {
                if (v == _answer) { bg = kGreen.withOpacity(0.2); border = kGreen; }
                else if (v == _selected) { bg = kRed.withOpacity(0.2); border = kRed; }
              }
              return GestureDetector(
                onTap: () => _tap(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                  child: Center(child: Text('$v', style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800)))),
              );
            }).toList()),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Mini-game: Teka Istilah
// ══════════════════════════════════════════════════════════════════════════════
class _TermGameDialog extends StatefulWidget {
  final List<Map<String, dynamic>> chunks;
  final String token;
  const _TermGameDialog({required this.chunks, required this.token});
  @override State<_TermGameDialog> createState() => _TermGameDialogState();
}

class _TermGameDialogState extends State<_TermGameDialog> {
  final _rng = math.Random();
  int _idx = 0, _score = 0;
  int? _selected;
  late List<String> _choices;

  @override
  void initState() { super.initState(); _buildChoices(); }

  void _buildChoices() {
    if (widget.chunks.isEmpty) return;
    final correct = widget.chunks[_idx]['concept_title'] as String? ?? '';
    final others = widget.chunks
        .where((c) => c != widget.chunks[_idx] && (c['concept_title'] as String?)?. isNotEmpty == true)
        .map((c) => c['concept_title'] as String)
        .toList()..shuffle(_rng);
    _choices = [correct, ...others.take(3)]..shuffle(_rng);
    _selected = null;
  }

  void _tap(int i) {
    if (_selected != null || widget.chunks.isEmpty) return;
    final correct = widget.chunks[_idx]['concept_title'] as String? ?? '';
    setState(() { _selected = i; if (_choices[i] == correct) _score++; });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_idx + 1 >= widget.chunks.length || _idx >= 9) {
        Navigator.pop(context);
        return;
      }
      setState(() { _idx++; _buildChoices(); });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chunks.isEmpty) return Dialog(
      backgroundColor: kSurface,
      child: const Padding(padding: EdgeInsets.all(32), child: Text('Tiada data', style: TextStyle(color: kMuted))));

    final chunk = widget.chunks[_idx];
    final correct = chunk['concept_title'] as String? ?? '';
    final desc = chunk['concept_explanation'] as String? ?? '';
    final total = math.min(10, widget.chunks.length);

    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('Teka Istilah · ${_idx + 1}/$total', style: const TextStyle(color: kMuted, fontSize: 12)),
            const Spacer(),
            Text('$_score betul', style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: kMuted, size: 18)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(14)),
            child: Text(desc, style: const TextStyle(color: kText, fontSize: 12, height: 1.6),
              maxLines: 4, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 4),
          const Text('Apa istilah ini?', style: TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 14),
          ...List.generate(_choices.length, (i) {
            Color bg = kSurface2;
            Color border = kBorder;
            if (_selected != null) {
              if (_choices[i] == correct) { bg = kGreen.withOpacity(0.2); border = kGreen; }
              else if (i == _selected) { bg = kRed.withOpacity(0.2); border = kRed; }
            }
            return GestureDetector(
              onTap: () => _tap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                child: Text(_choices[i], style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            );
          }),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Mini-game: Kilat Kuiz (flip-card)
// ══════════════════════════════════════════════════════════════════════════════
class _FlashQuizDialog extends StatefulWidget {
  final List<Map<String, dynamic>> chunks;
  const _FlashQuizDialog({required this.chunks});
  @override State<_FlashQuizDialog> createState() => _FlashQuizDialogState();
}

class _FlashQuizDialogState extends State<_FlashQuizDialog> {
  int _idx = 0;
  bool _revealed = false;
  int _know = 0, _dontKnow = 0;

  void _answer(bool know) {
    if (know) _know++; else _dontKnow++;
    final next = _idx + 1;
    if (next >= widget.chunks.length || next >= 10) {
      Navigator.pop(context);
      return;
    }
    setState(() { _idx = next; _revealed = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chunks.isEmpty) return Dialog(
      backgroundColor: kSurface,
      child: const Padding(padding: EdgeInsets.all(32), child: Text('Tiada data', style: TextStyle(color: kMuted))));

    final chunk = widget.chunks[_idx];
    final q = chunk['check_in_question'] as String? ?? chunk['concept_title'] as String? ?? '';
    final a = chunk['concept_explanation'] as String? ?? '';
    final total = math.min(10, widget.chunks.length);

    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('Kilat Kuiz · ${_idx + 1}/$total', style: const TextStyle(color: kMuted, fontSize: 12)),
            const Spacer(),
            Text('✓ $_know  ✗ $_dontKnow', style: const TextStyle(color: kMuted, fontSize: 11)),
            const SizedBox(width: 8),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: kMuted, size: 18)),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _revealed ? kGreen.withOpacity(0.1) : kSurface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _revealed ? kGreen.withOpacity(0.4) : kBorder)),
              child: Column(children: [
                Text(_revealed ? a : q,
                  style: const TextStyle(color: kText, fontSize: 13, height: 1.6),
                  textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_revealed ? 'Jawapan (ketik untuk soal semula)' : 'Ketik untuk lihat jawapan',
                  style: const TextStyle(color: kMuted, fontSize: 10)),
              ]),
            ),
          ),
          if (_revealed) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => _answer(false),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kRed),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Tidak Tahu', style: TextStyle(color: kRed, fontWeight: FontWeight.w700)))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () => _answer(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Tahu!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Mini-game: Sejarah Hari Ini
// ══════════════════════════════════════════════════════════════════════════════
class _HistoryFactDialog extends StatelessWidget {
  final Map<String, dynamic> chunk;
  const _HistoryFactDialog({required this.chunk});

  @override
  Widget build(BuildContext context) {
    final title = chunk['concept_title'] as String? ?? '';
    final body = chunk['concept_explanation'] as String? ?? '';
    final keywords = (chunk['keywords'] as List?)?.cast<String>() ?? [];

    return Dialog(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFD97706).withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.history_edu_rounded, color: Color(0xFFD97706), size: 20)),
            const SizedBox(width: 10),
            const Text('Sejarah Hari Ini', style: TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: const Icon(Icons.close, color: kMuted, size: 18)),
          ]),
          const SizedBox(height: 18),
          Text(title, style: const TextStyle(color: const Color(0xFFD97706), fontSize: 16, fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(color: kText, fontSize: 13, height: 1.7)),
          if (keywords.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: keywords.map((k) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text(k, style: const TextStyle(color: Color(0xFFD97706), fontSize: 10, fontWeight: FontWeight.w700)),
            )).toList()),
          ],
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706), elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Faham!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))),
        ]),
      ),
    );
  }
}
