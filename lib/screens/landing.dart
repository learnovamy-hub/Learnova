import 'package:flutter/material.dart';
import '../config/constants.dart';
import 'auth.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
                  borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 36)),
              const SizedBox(height: 24),
              const Text('Learnova', style: TextStyle(color: kText, fontSize: 36, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('AI-Powered Tutoring for SPM Students', style: TextStyle(color: kMuted, fontSize: 16)),
              const Spacer(),
              _roleButton(context, 'Student', 'Learn with AI tutor', Icons.person_rounded, kPrimary, 'student'),
              const SizedBox(height: 12),
              _roleButton(context, 'Parent', 'Monitor your child', Icons.family_restroom_rounded, kYellow, 'parent'),
              const SizedBox(height: 12),
              _roleButton(context, 'Teacher', 'Teach and earn equity', Icons.school_rounded, kGreen, 'teacher'),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleButton(BuildContext context, String title, String subtitle, IconData icon, Color color, String role) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AuthScreen(role: role))),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3))),
        child: Row(children: [
          Container(width: 46, height: 46,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
            Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 12)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: color.withOpacity(0.7), size: 14),
        ]),
      ),
    );
  }
}
