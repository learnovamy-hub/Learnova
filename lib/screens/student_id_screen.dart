import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert' show jsonDecode;
import '../config/constants.dart';

class StudentIdScreen extends StatefulWidget {
  const StudentIdScreen({super.key});
  @override
  State<StudentIdScreen> createState() => _StudentIdScreenState();
}

class _StudentIdScreenState extends State<StudentIdScreen>
    with TickerProviderStateMixin {
  String? _studentCode;
  String _name = '';
  String _form = '';
  bool _loading = true;
  bool _showQr = false;

  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  late AnimationController _shimmerCtrl;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic));
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _shimmerAnim = Tween<double>(begin: -1, end: 2).animate(_shimmerCtrl);
    _load();
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/student/my-id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() {
          _studentCode = d['student_code'] as String?;
          _name        = d['name']         as String? ?? '';
          _form        = d['form'] != null ? 'Form ${d['form']}' : '';
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _toggleQr() {
    setState(() => _showQr = !_showQr);
    if (_showQr) {
      _flipCtrl.forward();
    } else {
      _flipCtrl.reverse();
    }
  }

  void _copyCode() {
    if (_studentCode == null) return;
    Clipboard.setData(ClipboardData(text: _studentCode!));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('ID disalin: $_studentCode'),
      backgroundColor: kGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _share() {
    if (_studentCode == null) return;
    Clipboard.setData(ClipboardData(
      text: 'ID Learnova saya: $_studentCode\n'
            'Ibu bapa boleh scan QR atau masukkan kod ini dalam app Learnova untuk memantau pembelajaran saya.',
    ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Mesej disalin — tampal dalam WhatsApp'),
      backgroundColor: const Color(0xFF25D366),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  String get _initials {
    if (_name.isEmpty) return 'S';
    final parts = _name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return _name[0].toUpperCase();
  }

  Widget _buildQrImage() {
    if (_studentCode == null) {
      return Container(
        width: 180, height: 180,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(10),
      child: QrImageView(
        data: _studentCode!,
        version: QrVersions.auto,
        size: 160,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1a1a2e)),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1a1a2e)),
        backgroundColor: Colors.white,
      ),
    );
  }

  // Front of card — name, code, form
  Widget _buildCardFront() {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, child) => Container(
        width: double.infinity,
        height: 240,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E1B4B), Color(0xFF3730A3), Color(0xFF1E1B4B)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kPrimary.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(color: kPrimary.withOpacity(0.25), blurRadius: 32, offset: const Offset(0, 12)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(children: [
            // Shimmer sweep
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(_shimmerAnim.value * 400, 0),
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0),
                        Colors.white.withOpacity(0.04),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Decorative circles
            Positioned(top: -30, right: -30,
              child: Container(width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: kPrimary.withOpacity(0.08)))),
            Positioned(bottom: -20, left: -20,
              child: Container(width: 80, height: 80,
                decoration: BoxDecoration(shape: BoxShape.circle, color: kPrimary2.withOpacity(0.08)))),
            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: child!,
            ),
          ]),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: kPrimary.withOpacity(0.5)),
            ),
            child: const Row(children: [
              Icon(Icons.school_rounded, color: kPrimary, size: 11),
              SizedBox(width: 5),
              Text('LEARNOVA', style: TextStyle(color: kPrimary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ]),
          ),
          const Spacer(),
          if (_form.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_form, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
        const Spacer(),
        // Avatar + name
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPrimary, kPrimary2]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.4), blurRadius: 12)],
            ),
            child: Center(child: Text(_initials,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name.isEmpty ? 'Pelajar' : _name,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('Pelajar SPM', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ])),
        ]),
        const SizedBox(height: 20),
        // Student code
        if (_studentCode != null)
          Row(children: [
            Text(_studentCode!,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3,
                fontFeatures: [FontFeature.tabularFigures()])),
            const Spacer(),
            GestureDetector(
              onTap: _copyCode,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.copy_rounded, color: Colors.white54, size: 16),
              ),
            ),
          ]),
      ]),
    );
  }

  // Back of card — QR code
  Widget _buildCardBack() {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF3730A3), Color(0xFF1E1B4B)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kPrimary.withOpacity(0.5), width: 1.5),
        boxShadow: [BoxShadow(color: kPrimary.withOpacity(0.25), blurRadius: 32, offset: const Offset(0, 12))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _buildQrImage(),
          const SizedBox(height: 12),
          Text('Scan untuk sambung dengan ibu bapa',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _buildFlipCard() {
    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (_, __) {
        final angle = _flipAnim.value * math.pi;
        final showFront = angle <= math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: showFront
              ? _buildCardFront()
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _buildCardBack(),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text('Kad Pelajar', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: kText),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: Column(children: [
                // Flip card
                _buildFlipCard(),
                const SizedBox(height: 20),

                // Tap to flip hint
                GestureDetector(
                  onTap: _toggleQr,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_showQr ? Icons.credit_card_rounded : Icons.qr_code_rounded,
                        color: kPrimary, size: 16),
                      const SizedBox(width: 8),
                      Text(_showQr ? 'Tunjuk Kad' : 'Tunjuk QR Code',
                        style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),

                const SizedBox(height: 32),

                // Info box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.info_outline_rounded, color: kPrimary, size: 16),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: Text(
                      'Tunjukkan QR code atau nombor ID ini kepada ibu bapa. Mereka boleh scan atau masukkan kod ini dalam app Learnova untuk memantau pembelajaran kamu.',
                      style: TextStyle(color: kMuted, fontSize: 12, height: 1.6),
                    )),
                  ]),
                ),

                const SizedBox(height: 20),

                // Action buttons
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Salin ID'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share_rounded, size: 16),
                    label: const Text('Kongsi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )),
                ]),
              ]),
            ),
    );
  }
}
