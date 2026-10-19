import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/constants.dart';
import 'screens/landing.dart';
import 'screens/teacher_portal.dart';
import 'screens/parent_portal.dart';
import 'screens/welcome_home.dart';
import 'screens/parent_screen.dart';

void main() { runApp(const LearnovaApp()); }

class LearnovaApp extends StatelessWidget {
  const LearnovaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learnova',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        fontFamily: 'Roboto',
      ),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() { super.initState(); _checkAuth(); }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      final path = Uri.base.path;
      if (path == '/parent' || path.startsWith('/parent/')) {
        if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const ParentScreen()));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (mounted) {
        Widget dest = const LandingScreen();
        if (token != null && token.isNotEmpty) {
          final role = prefs.getString('role') ?? 'student';
          if (role == 'teacher') dest = const TeacherPortal();
          else if (role == 'parent') dest = const ParentPortal();
          else dest = WelcomeHome(
            studentName: prefs.getString('student_name') ?? prefs.getString('name') ?? 'there',
            studentId: prefs.getString('userId') ?? prefs.getString('student_id') ?? '');
        }
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => dest));
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LandingScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPrimary, kPrimary2]), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.school_rounded, color: Colors.white, size: 44)),
        const SizedBox(height: 20),
        Text('Learnova', style: TextStyle(color: cs.onSurface, fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('AI-Powered Tutoring', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
        const SizedBox(height: 40),
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ])),
    );
  }
}
