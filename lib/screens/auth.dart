import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';
import 'landing.dart';
import 'teacher_portal.dart';
import 'parent_portal.dart';
import 'welcome_home.dart';

class AuthScreen extends StatefulWidget {
  final String role;
  const AuthScreen({super.key, required this.role});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  bool _showPassword = false;
  bool _isLogin = true;
  bool _isLoading = false;

  Color get _roleColor => widget.role == 'teacher' ? kGreen : widget.role == 'parent' ? kYellow : kPrimary;
  String get _roleLabel => widget.role == 'teacher' ? 'Teacher' : widget.role == 'parent' ? 'Parent' : 'Student';
  IconData get _roleIcon => widget.role == 'teacher' ? Icons.school_rounded : widget.role == 'parent' ? Icons.family_restroom_rounded : Icons.person_rounded;

  Future<void> _submit() async {
    if (_emailCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) { _showSnack('Please fill in all fields'); return; }
    setState(() => _isLoading = true);
    try {
      final rolePrefix = widget.role == 'teacher' ? 'teacher' : widget.role == 'parent' ? 'parent' : 'student';
      final endpoint = _isLogin ? '/api/$rolePrefix/login' : '/api/$rolePrefix/signup';
      final name = _nameCtrl.text.trim().isEmpty ? _emailCtrl.text.trim().split('@').first : _nameCtrl.text.trim();
      final Map<String, dynamic> body = _isLogin
          ? {'email': _emailCtrl.text.trim(), 'password': _passwordCtrl.text}
          : {'email': _emailCtrl.text.trim(), 'password': _passwordCtrl.text, 'name': name, if (_parentEmailCtrl.text.trim().isNotEmpty) 'parent_email': _parentEmailCtrl.text.trim()};
      final response = await http.post(Uri.parse('$kApiUrl$endpoint'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        // Server returns { token, student_id/teacher_id/parent_id, name }
        final studentId = (data['student_id'] ?? data['teacher_id'] ?? data['parent_id'])?.toString() ?? '';
        final rawName = data['name']?.toString() ?? '';
        final studentName = (rawName.isEmpty || rawName.toLowerCase() == 'student')
            ? _emailCtrl.text.trim().split('@').first
            : rawName;
        final token = data['token'] ?? '';
        await prefs.setString('token', token);
        await prefs.setString('role', widget.role);
        await prefs.setString('userId', studentId);
        await prefs.setString('student_id', studentId);
        await prefs.setString('student_name', studentName);
        await prefs.setString('name', studentName);
        // Fetch and cache form_level immediately so WelcomeHome never needs to ask
        if (widget.role == 'student' && studentId.isNotEmpty && token.isNotEmpty) {
          try {
            final pr = await http.get(Uri.parse('$kApiUrl/api/student/profile'),
              headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 5));
            if (pr.statusCode == 200) {
              final form = jsonDecode(pr.body)?['student']?['form_level'];
              if (form != null) {
                final fs = 'Form $form';
                await prefs.setString('student_form_$studentId', fs);
                await prefs.setString('student_form', fs);
              }
            }
          } catch (_) {}
        }
        if (!mounted) return;
        if (widget.role == 'teacher') {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const TeacherPortal()), (_) => false);
        } else if (widget.role == 'parent') {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ParentPortal()), (_) => false);
        } else {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => WelcomeHome(studentName: studentName, studentId: studentId)), (_) => false);
        }
      } else { _showSnack(data['error'] ?? 'Incorrect email or password.', isError: true); }
    } catch (e) { _showSnack('Connection error. Please try again.', isError: true);
    } finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.red[700] : kSurface2));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: kText), onPressed: () => Navigator.pop(context))),
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.2, colors: [Color(0xFF1E1B4B), kBg])),
        child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          Row(children: [Container(width: 44, height: 44, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.school_rounded, color: Colors.white, size: 24)), const SizedBox(width: 12), const Text('Learnova', style: TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 32),
          Row(children: [Icon(_roleIcon, size: 28, color: _roleColor), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_isLogin ? 'Welcome back!' : 'Join Learnova', style: const TextStyle(color: kText, fontSize: 22, fontWeight: FontWeight.w800)), Text('$_roleLabel login', style: TextStyle(color: _roleColor, fontSize: 13, fontWeight: FontWeight.w600))])]),
          const SizedBox(height: 32),
          if (!_isLogin && widget.role != 'parent') ...[ _field(_nameCtrl, 'Full Name', Icons.person_outline), const SizedBox(height: 14)],
          if (!_isLogin && widget.role == 'student') ...[ _field(_parentEmailCtrl, 'Parent Email (optional)', Icons.family_restroom), const SizedBox(height: 14)],
          _field(_emailCtrl, 'Email Address', Icons.email_outlined, type: TextInputType.emailAddress),
          const SizedBox(height: 14),
          _field(_passwordCtrl, 'Password', Icons.lock_outline, obscure: !_showPassword, isPassword: true),
          const SizedBox(height: 28),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isLoading ? null : _submit, style: ElevatedButton.styleFrom(backgroundColor: _roleColor), child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_isLogin ? 'Sign In as $_roleLabel' : 'Create Account'))),
          if (widget.role != 'parent') ...[ const SizedBox(height: 20), Center(child: TextButton(onPressed: () => setState(() => _isLogin = !_isLogin), child: Text(_isLogin ? "Don't have an account? Sign Up" : 'Already have an account? Sign In', style: TextStyle(color: _roleColor, fontWeight: FontWeight.w600))))],
        ]))),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool obscure = false, bool isPassword = false, TextInputType type = TextInputType.text}) {
    return TextField(controller: ctrl, obscureText: obscure, keyboardType: type, style: const TextStyle(color: kText), decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: kMuted, size: 20), suffixIcon: isPassword ? IconButton(icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off, color: kMuted, size: 20), onPressed: () => setState(() => _showPassword = !_showPassword)) : null));
  }

  @override
  void dispose() { _emailCtrl.dispose(); _passwordCtrl.dispose(); _nameCtrl.dispose(); _parentEmailCtrl.dispose(); super.dispose(); }
}
