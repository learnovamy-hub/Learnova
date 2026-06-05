import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/constants.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _token;
  bool _loading = true;
  bool _paying = false;
  Map<String, dynamic>? _plans;
  List<dynamic> _mySubjects = [];
  bool _trialMode = false;

  String _selectedPlan = 'single';
  final Set<String> _selectedSubjects = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    await Future.wait([_loadPlans(), _loadMySubjects()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPlans() async {
    try {
      final r = await http.get(Uri.parse('$kApiUrl/api/payment/plans'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        _plans = jsonDecode(r.body);
      }
    } catch (_) {}
  }

  Future<void> _loadMySubjects() async {
    if (_token == null) return;
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/payment/my-subjects'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        _mySubjects = data['subjects'] ?? [];
        _trialMode = data['trial_mode'] == true;
      }
    } catch (_) {}
  }

  bool _hasAccess(String subject) {
    if (_trialMode) return true;
    return _mySubjects.any((s) => s['subject'] == subject && s['active'] == true);
  }

  Future<void> _checkout() async {
    if (_token == null) return;
    final subjects = _selectedPlan == 'bundleAll'
        ? (_plans?['subjects'] as List? ?? []).cast<String>()
        : _selectedSubjects.toList();

    if (_selectedPlan != 'bundleAll' && subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih sekurang-kurangnya satu subjek')),
      );
      return;
    }

    setState(() => _paying = true);
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/payment/create-checkout'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'plan': _selectedPlan, 'subjects': subjects}),
      ).timeout(const Duration(seconds: 15));

      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final url = data['checkout_url'] as String?;
        if (url != null) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ralat membuat bayaran. Cuba lagi.')),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tiada sambungan. Cuba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Tambah Subjek', style: TextStyle(fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_trialMode) _trialBanner(),
                  const SizedBox(height: 4),
                  const Text('Pilih Pelan', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  ..._planCards(),
                  const SizedBox(height: 24),
                  if (_selectedPlan != 'bundleAll') ...[
                    const Text('Pilih Subjek', style: TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      _selectedPlan == 'bundle3'
                          ? 'Pilih 3 subjek (sudah termasuk: Bahasa Malaysia percuma)'
                          : 'Pilih 1 subjek untuk akses 30 hari',
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    _subjectPicker(),
                  ],
                  const SizedBox(height: 80),
                ]),
              )),
              _bottomBar(),
            ]),
    );
  }

  Widget _trialBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGreen.withOpacity(0.3)),
      ),
      child: const Row(children: [
        Icon(Icons.star_rounded, color: kGreen, size: 16),
        SizedBox(width: 8),
        Expanded(child: Text(
          'God Mode aktif — semua subjek tersedia percuma sekarang',
          style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w600),
        )),
      ]),
    );
  }

  List<Widget> _planCards() {
    final planDefs = [
      {'id': 'single', 'name': '1 Subjek', 'price': 'RM15', 'desc': '1 subjek pilihan, 30 hari'},
      {'id': 'bundle3', 'name': '3 Subjek', 'price': 'RM35', 'desc': 'Mana-mana 3 subjek, 30 hari'},
      {'id': 'bundleAll', 'name': 'Semua Subjek', 'price': 'RM69', 'desc': '13 subjek SPM tanpa had'},
    ];
    return planDefs.map((p) {
      final selected = _selectedPlan == p['id'];
      return GestureDetector(
        onTap: () => setState(() {
          _selectedPlan = p['id']!;
          if (_selectedPlan == 'bundle3' && _selectedSubjects.length > 3) {
            final keep = _selectedSubjects.take(3).toList();
            _selectedSubjects.clear();
            _selectedSubjects.addAll(keep);
          }
          if (_selectedPlan == 'single' && _selectedSubjects.length > 1) {
            final first = _selectedSubjects.first;
            _selectedSubjects.clear();
            _selectedSubjects.add(first);
          }
        }),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? kPrimary.withOpacity(0.08) : kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? kPrimary : kBorder, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? kPrimary : Colors.transparent,
                border: Border.all(color: selected ? kPrimary : kBorder, width: 2),
              ),
              child: selected ? const Icon(Icons.check, color: Colors.white, size: 12) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name']!, style: TextStyle(color: selected ? kPrimary : kText, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(p['desc']!, style: const TextStyle(color: kMuted, fontSize: 12)),
            ])),
            Text(p['price']!, style: TextStyle(color: selected ? kPrimary : kText, fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
    }).toList();
  }

  Widget _subjectPicker() {
    final subjects = (_plans?['subjects'] as List? ?? []).cast<String>();
    final maxSelect = _selectedPlan == 'bundle3' ? 3 : 1;
    return Wrap(spacing: 8, runSpacing: 8,
      children: subjects.map((s) {
        final hasAccess = _hasAccess(s);
        final picked = _selectedSubjects.contains(s);
        return GestureDetector(
          onTap: () {
            if (hasAccess) return; // already has it
            setState(() {
              if (picked) {
                _selectedSubjects.remove(s);
              } else {
                if (_selectedSubjects.length >= maxSelect) {
                  _selectedSubjects.remove(_selectedSubjects.first);
                }
                _selectedSubjects.add(s);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: hasAccess
                  ? kGreen.withOpacity(0.08)
                  : picked
                      ? kPrimary.withOpacity(0.1)
                      : kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hasAccess ? kGreen.withOpacity(0.4) : picked ? kPrimary : kBorder,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (hasAccess) const Icon(Icons.check_circle_rounded, color: kGreen, size: 13)
              else if (picked) const Icon(Icons.check_circle_rounded, color: kPrimary, size: 13)
              else const Icon(Icons.lock_outline_rounded, color: kMuted, size: 13),
              const SizedBox(width: 5),
              Text(s, style: TextStyle(
                color: hasAccess ? kGreen : picked ? kPrimary : kText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _bottomBar() {
    String priceText = 'RM15';
    if (_selectedPlan == 'bundle3') priceText = 'RM35';
    if (_selectedPlan == 'bundleAll') priceText = 'RM69';

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: kBorder))),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Jumlah', style: TextStyle(color: kMuted, fontSize: 11)),
          Text(priceText, style: const TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(width: 16),
        Expanded(child: ElevatedButton(
          onPressed: _paying ? null : _checkout,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _paying
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Bayar Sekarang', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        )),
      ]),
    );
  }
}
