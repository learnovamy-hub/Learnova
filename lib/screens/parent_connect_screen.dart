import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class ParentConnectScreen extends StatefulWidget {
  const ParentConnectScreen({super.key});
  @override
  State<ParentConnectScreen> createState() => _ParentConnectScreenState();
}

class _ParentConnectScreenState extends State<ParentConnectScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _successMsg;
  String _token = '';

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Sila masukkan kod pelajar.');
      return;
    }

    setState(() { _loading = true; _error = null; _successMsg = null; });

    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/parent/connect'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'student_code': code}),
      );
      final data = jsonDecode(r.body);
      if (r.statusCode == 200) {
        setState(() => _successMsg = data['message'] ?? 'Permintaan dihantar!');
        _codeCtrl.clear();
      } else {
        setState(() => _error = data['error'] ?? 'Ralat berlaku. Cuba lagi.');
      }
    } catch (_) {
      setState(() => _error = 'Gagal menyambung. Semak internet kamu.');
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Sambung dengan Pelajar', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: kText),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // How it works
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kPrimary.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline_rounded, color: kPrimary, size: 16),
                SizedBox(width: 8),
                Text('Cara sambung', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              const Text(
                '1. Minta anak kamu buka Learnova\n'
                '2. Pergi ke Profil → Student ID\n'
                '3. Dapatkan kod LRN-XXXX-XXXXX\n'
                '4. Masukkan kod tersebut di bawah',
                style: TextStyle(color: kMuted, fontSize: 12, height: 1.7),
              ),
            ]),
          ),
          const SizedBox(height: 28),
          const Text('Masukkan Kod Pelajar', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          // Code input
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 2),
            decoration: InputDecoration(
              hintText: 'LRN-2026-00001',
              hintStyle: TextStyle(color: kMuted.withOpacity(0.5), fontSize: 16, letterSpacing: 1),
              filled: true,
              fillColor: kSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
              prefixIcon: const Icon(Icons.badge_rounded, color: kMuted, size: 20),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Format: LRN-XXXX-XXXXX', style: TextStyle(color: kMuted, fontSize: 11)),
          const SizedBox(height: 20),
          // Error / Success
          if (_error != null) Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kRed.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: kRed.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: kRed, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!, style: const TextStyle(color: kRed, fontSize: 13))),
            ]),
          ),
          if (_successMsg != null) Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: kGreen.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded, color: kGreen, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_successMsg!, style: const TextStyle(color: kGreen, fontSize: 13))),
            ]),
          ),
          const SizedBox(height: 20),
          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _sendRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor: kPrimary.withOpacity(0.5),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Hantar Permintaan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 24),
          // Divider
          Row(children: [
            const Expanded(child: Divider(color: kBorder)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('Nota', style: TextStyle(color: kMuted.withOpacity(0.6), fontSize: 11)),
            ),
            const Expanded(child: Divider(color: kBorder)),
          ]),
          const SizedBox(height: 16),
          const Text(
            'Selepas menghantar permintaan, anak kamu akan menerima notifikasi dalam app dan perlu menerima permintaan tersebut terlebih dahulu.',
            style: TextStyle(color: kMuted, fontSize: 12, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
