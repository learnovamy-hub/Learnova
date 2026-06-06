import 'package:flutter/material.dart';
import 'auth.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Animation<double>> _anims = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    final delays = [0.0, 0.15, 0.22, 0.30, 0.37, 0.45, 0.52];
    for (final d in delays) {
      _anims.add(CurvedAnimation(
        parent: _controller,
        curve: Interval(d, d + 0.5, curve: Curves.easeOut),
      ));
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _fade(int i, Widget child) => FadeTransition(
    opacity: _anims[i],
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(_anims[i]),
      child: child,
    ),
  );

  void _go(String role) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => AuthScreen(role: role)));

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF07080C);
    const accent = Color(0xFF5B6EF5);
    const textColor = Color(0xFFE8ECF8);
    const muted = Color(0xFF4A5070);
    const surface = Color(0xFF0F1117);
    const border = Color(0xFF1C1F2B);
    const dim = Color(0xFF22263A);

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.2),
            radius: 1.2,
            colors: [Color(0x14273580), bg],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 32, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    // 1. Logo mark
                    _fade(0, Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF7B8EFF), accent],
                        ),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white, size: 22),
                    )),

                    const SizedBox(height: 16),

                    // 2. Wordmark
                    _fade(1, const Text('Learnova',
                      style: TextStyle(
                        fontSize: 28,
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    )),

                    const SizedBox(height: 6),

                    // 3. Tagline
                    _fade(2, const Text(
                      "Malaysia's AI Tutor for SPM",
                      style: TextStyle(
                        fontSize: 13,
                        color: muted,
                        fontWeight: FontWeight.w400,
                      ),
                    )),

                    const SizedBox(height: 40),

                    // 4. Divider
                    _fade(3, Container(
                      height: 0.5,
                      color: border,
                      width: double.infinity,
                    )),

                    const SizedBox(height: 28),

                    // 5. Primary CTA — Student
                    _fade(4, SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _go('student'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Mula Belajar',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  )),
                                Text('Chat dengan Nova sekarang',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.65),
                                    fontWeight: FontWeight.w400,
                                  )),
                              ],
                            ),
                            Text('→',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white.withOpacity(0.8),
                              )),
                          ],
                        ),
                      ),
                    )),

                    const SizedBox(height: 10),

                    // 6. Secondary buttons row
                    _fade(5, Row(
                      children: [
                        Expanded(child: _secondaryBtn(
                          emoji: '👨‍👩‍👧',
                          label: 'Ibu Bapa',
                          sub: 'Pantau kemajuan anak',
                          role: 'parent',
                          surface: surface,
                          border: border,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _secondaryBtn(
                          emoji: '👩‍🏫',
                          label: 'Guru',
                          sub: 'Sumbang kandungan',
                          role: 'teacher',
                          surface: surface,
                          border: border,
                        )),
                      ],
                    )),

                    const SizedBox(height: 24),

                    // 7. Sign in link
                    _fade(6, GestureDetector(
                      onTap: () => _go('student'),
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(fontSize: 12),
                          children: [
                            TextSpan(
                              text: 'Sudah ada akaun? ',
                              style: TextStyle(color: muted)),
                            TextSpan(
                              text: 'Log Masuk',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.w500,
                              )),
                          ],
                        ),
                      ),
                    )),

                    const SizedBox(height: 40),

                    // 8. Footer
                    Text('DIKUASAI OLEH NOVA AI',
                      style: TextStyle(
                        fontSize: 10,
                        color: dim,
                        letterSpacing: 1.5,
                      )),

                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondaryBtn({
    required String emoji,
    required String label,
    required String sub,
    required String role,
    required Color surface,
    required Color border,
  }) {
    return GestureDetector(
      onTap: () => _go(role),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$emoji $label',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6A7090),
              )),
            const SizedBox(height: 3),
            Text(sub,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF4A5070),
              )),
          ],
        ),
      ),
    );
  }
}
