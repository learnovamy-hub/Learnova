import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';

class GodModeScreen extends StatefulWidget {
  const GodModeScreen({super.key});

  @override
  State<GodModeScreen> createState() => _GodModeScreenState();
}

class _GodModeScreenState extends State<GodModeScreen> {
  // Auth state
  String? _adminToken;
  Map<String, dynamic>? _admin;

  // Login form
  final _emailCtrl = TextEditingController(text: 'principal@test.com');
  final _passCtrl = TextEditingController();
  bool _loginLoading = false;
  String? _loginError;
  bool _obscure = true;

  // Dashboard data
  bool _dashLoading = false;
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _settings;

  // Student search
  final _searchCtrl = TextEditingController();
  List<dynamic> _students = [];
  bool _studentsLoading = false;
  int _studentsPage = 1;
  int _studentsTotal = 0;

  // Grant access form
  String? _grantStudentId;
  String _grantSubject = 'Mathematics';
  String _grantType = 'admin_grant';
  int _grantDays = 30;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loginLoading = true; _loginError = null; });
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': _emailCtrl.text.trim(), 'password': _passCtrl.text}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(r.body);
      if (r.statusCode == 200) {
        setState(() { _adminToken = data['token']; _admin = data['admin']; });
        await _loadDashboard();
        await _loadStudents();
      } else {
        setState(() => _loginError = data['error'] ?? 'Login gagal');
      }
    } catch (_) {
      setState(() => _loginError = 'Tiada sambungan');
    } finally {
      if (mounted) setState(() => _loginLoading = false);
    }
  }

  Future<void> _loadDashboard() async {
    setState(() => _dashLoading = true);
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/admin/dashboard'),
        headers: {'Authorization': 'Bearer $_adminToken'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        setState(() { _dashboard = d; _settings = Map<String, dynamic>.from(d['settings'] ?? {}); });
      }
    } catch (_) {}
    if (mounted) setState(() => _dashLoading = false);
  }

  Future<void> _loadStudents({String search = ''}) async {
    setState(() => _studentsLoading = true);
    try {
      final url = '$kApiUrl/api/admin/students?page=$_studentsPage&limit=20${search.isNotEmpty ? '&search=${Uri.encodeComponent(search)}' : ''}';
      final r = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $_adminToken'})
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        setState(() { _students = d['students'] ?? []; _studentsTotal = d['total'] ?? 0; });
      }
    } catch (_) {}
    if (mounted) setState(() => _studentsLoading = false);
  }

  Future<void> _toggleTrialMode(bool value) async {
    try {
      await http.patch(
        Uri.parse('$kApiUrl/api/admin/settings'),
        headers: {'Authorization': 'Bearer $_adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'key': 'trial_mode_active', 'value': value ? 'true' : 'false'}),
      ).timeout(const Duration(seconds: 8));
      setState(() => _settings?['trial_mode_active'] = value ? 'true' : 'false');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? 'God Mode aktif — semua akses dibuka' : 'God Mode ditutup — gating aktif')),
      );
    } catch (_) {}
  }

  Future<void> _grantAccess() async {
    if (_grantStudentId == null || _grantStudentId!.isEmpty) return;
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/admin/grant-access'),
        headers: {'Authorization': 'Bearer $_adminToken', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': _grantStudentId,
          'subject': _grantSubject,
          'access_type': _grantType,
          'days': _grantDays,
        }),
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Akses $_grantSubject diberikan kepada student')),
        );
        await _loadStudents();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_adminToken == null) return _buildLoginScreen();
    return _buildDashboard();
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('God Mode', style: TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 32),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: Text('⚡', style: TextStyle(fontSize: 36))),
          ),
          const SizedBox(height: 16),
          const Text('Admin God Mode', style: TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800)),
          const Text('Panel kawalan dalaman Learnova', style: TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 32),
          _field(_emailCtrl, 'Email Admin', Icons.email_rounded),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            style: const TextStyle(color: kText, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: const TextStyle(color: kMuted),
              prefixIcon: const Icon(Icons.lock_rounded, color: kMuted, size: 18),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: kMuted, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              filled: true, fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onSubmitted: (_) => _login(),
          ),
          if (_loginError != null) ...[
            const SizedBox(height: 8),
            Text(_loginError!, style: const TextStyle(color: kRed, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _loginLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _loginLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Log Masuk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          )),
        ]),
      ),
    );
  }

  Widget _buildDashboard() {
    final trialActive = _settings?['trial_mode_active'] == 'true';
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text('God Mode — ${_admin?['full_name'] ?? 'Admin'}', style: const TextStyle(fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () async { await _loadDashboard(); await _loadStudents(); },
          ),
          TextButton(
            onPressed: () => setState(() { _adminToken = null; _admin = null; }),
            child: const Text('Log Keluar', style: TextStyle(color: kRed, fontSize: 12)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Stats row
          if (_dashboard != null) ...[
            Row(children: [
              _statCard('Pelajar', '${_dashboard!['students'] ?? 0}', Icons.people_rounded, kPrimary),
              const SizedBox(width: 10),
              _statCard('Sesi', '${_dashboard!['sessions'] ?? 0}', Icons.school_rounded, kGreen),
              const SizedBox(width: 10),
              _statCard('Hasil', 'RM${((_dashboard!['revenue_cents'] ?? 0) / 100).toStringAsFixed(0)}', Icons.payments_rounded, kYellow),
            ]),
            const SizedBox(height: 20),
          ],

          // God Mode toggle
          _sectionHeader('God Mode', Icons.bolt_rounded),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: trialActive ? const Color(0xFF6C5CE7).withOpacity(0.08) : kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: trialActive ? const Color(0xFF6C5CE7).withOpacity(0.4) : kBorder),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trialActive ? 'AKTIF — Semua akses dibuka' : 'TIDAK AKTIF — Gating berjalan',
                    style: TextStyle(color: trialActive ? const Color(0xFF6C5CE7) : kMuted, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                const Text('Semasa aktif, semua pelajar boleh akses semua subjek percuma',
                    style: TextStyle(color: kMuted, fontSize: 11)),
              ])),
              Switch(
                value: trialActive,
                onChanged: _toggleTrialMode,
                activeColor: const Color(0xFF6C5CE7),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Grant access
          _sectionHeader('Beri Akses Manual', Icons.admin_panel_settings_rounded),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _field2(
                label: 'Student ID (UUID)',
                hint: 'Paste UUID pelajar di sini',
                onChanged: (v) => _grantStudentId = v,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _grantSubject,
                decoration: _dropDecor('Subjek'),
                dropdownColor: kSurface,
                style: const TextStyle(color: kText, fontSize: 13),
                items: kSubjects.map((s) => DropdownMenuItem(
                  value: s['name'] as String,
                  child: Text(s['name'] as String),
                )).toList(),
                onChanged: (v) => setState(() => _grantSubject = v!),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: _grantType,
                  decoration: _dropDecor('Jenis'),
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 'admin_grant', child: Text('Admin Grant')),
                    DropdownMenuItem(value: 'trial', child: Text('Trial')),
                    DropdownMenuItem(value: 'paid', child: Text('Berbayar')),
                    DropdownMenuItem(value: 'free', child: Text('Percuma')),
                  ],
                  onChanged: (v) => setState(() => _grantType = v!),
                )),
                const SizedBox(width: 10),
                Expanded(child: DropdownButtonFormField<int>(
                  value: _grantDays,
                  decoration: _dropDecor('Tempoh'),
                  dropdownColor: kSurface,
                  style: const TextStyle(color: kText, fontSize: 13),
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 hari')),
                    DropdownMenuItem(value: 30, child: Text('30 hari')),
                    DropdownMenuItem(value: 90, child: Text('90 hari')),
                    DropdownMenuItem(value: 365, child: Text('1 tahun')),
                    DropdownMenuItem(value: 9999, child: Text('Selamanya')),
                  ],
                  onChanged: (v) => setState(() => _grantDays = v!),
                )),
              ]),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _grantAccess,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Beri Akses', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              )),
            ]),
          ),
          const SizedBox(height: 24),

          // Students list
          _sectionHeader('Senarai Pelajar ($_studentsTotal)', Icons.people_rounded),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: kText, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cari nama pelajar...',
              hintStyle: const TextStyle(color: kMuted),
              prefixIcon: const Icon(Icons.search_rounded, color: kMuted, size: 18),
              filled: true, fillColor: kSurface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onSubmitted: (v) => _loadStudents(search: v),
          ),
          const SizedBox(height: 10),
          if (_studentsLoading)
            const Center(child: CircularProgressIndicator())
          else
            ..._students.map((s) => _studentTile(s)).toList(),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _studentTile(Map s) {
    final access = (s['access'] as List? ?? []);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s['name'] ?? 'Pelajar', style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w700))),
          GestureDetector(
            onTap: () => setState(() => _grantStudentId = s['id']),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: const Text('Pilih', style: TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        Text(s['email'] ?? '', style: const TextStyle(color: kMuted, fontSize: 11)),
        const SizedBox(height: 6),
        if (access.isEmpty)
          const Text('Tiada akses subjek', style: TextStyle(color: kMuted, fontSize: 11))
        else
          Wrap(spacing: 4, runSpacing: 4, children: access.map<Widget>((a) {
            final expired = a['expires_at'] != null && DateTime.tryParse(a['expires_at'])?.isBefore(DateTime.now()) == true;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: expired ? kRed.withOpacity(0.08) : kGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: expired ? kRed.withOpacity(0.3) : kGreen.withOpacity(0.3)),
              ),
              child: Text(
                '${a['subject']} (${a['access_type']}${expired ? ' TAMAT' : ''})',
                style: TextStyle(color: expired ? kRed : kGreen, fontSize: 10),
              ),
            );
          }).toList()),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    ));
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: kPrimary, size: 17),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: kText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kMuted),
        prefixIcon: Icon(icon, color: kMuted, size: 18),
        filled: true, fillColor: kSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _field2({required String label, required String hint, required ValueChanged<String> onChanged}) {
    return TextField(
      style: const TextStyle(color: kText, fontSize: 13),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kMuted, fontSize: 12),
        hintText: hint,
        hintStyle: const TextStyle(color: kMuted, fontSize: 12),
        filled: true, fillColor: kBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  InputDecoration _dropDecor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: kMuted, fontSize: 12),
    filled: true, fillColor: kBg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}
