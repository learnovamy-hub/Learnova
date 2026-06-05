// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/disclaimers.dart';
import 'welcome_home.dart';

class OnboardingScreen extends StatefulWidget {
  final String studentId;
  final String token;
  final String studentName;
  const OnboardingScreen({Key? key, required this.studentId, required this.token, required this.studentName}) : super(key: key);
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int selectedForm = 0;
  String selectedLang = 'en';
  List<String> selectedSubjects = [];
  bool _agreedToTerms = false;

  final subjects = ['Mathematics','Add Maths','Physics','Chemistry','Biology','Bahasa Melayu','English','Sejarah','Geography','Pendidikan Islam'];
  final subjectColors = [Colors.blue,Colors.purple,Colors.teal,Colors.green,Colors.lightGreen,Colors.orange,Colors.blueGrey,Colors.brown,Colors.indigo,Colors.cyan];
  final langs = [{'code':'en','label':'English'},{'code':'ms','label':'BM'},{'code':'zh','label':'Mandarin'},{'code':'ta','label':'Tamil'}];

  void _showFullDisclaimer() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notis Platform Learnova', style: TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(child: Text(LearnovaDisclaimers.fullNotice, style: const TextStyle(fontSize: 13, height: 1.6))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Faham'))],
      ),
    );
  }

  void _proceed() {
    if (selectedForm == 0 || selectedSubjects.isEmpty || !_agreedToTerms) return;
    try {
      html.window.localStorage['student_form'] = selectedForm.toString();
      html.window.localStorage['student_lang'] = selectedLang;
      html.window.localStorage['student_subjects'] = selectedSubjects.join(',');
      html.window.localStorage['onboarding_complete'] = 'true';
    } catch (_) {}
    try {
      final xhr = html.HttpRequest();
      xhr.open('POST', '$kApiUrl/api/student/profile/onboard', async: true);
      xhr.setRequestHeader('Content-Type', 'application/json');
      xhr.send(jsonEncode({
        'student_id': widget.studentId,
        'token': widget.token,
        'form_level': selectedForm,
        'subjects': selectedSubjects,
        'preferred_language': selectedLang,
        'onboarding_complete': true,
      }));
    } catch (_) {}
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => WelcomeHome(
        studentName: widget.studentName,
        studentId: widget.studentId,
      )),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canProceed = selectedForm > 0 && selectedSubjects.isNotEmpty && _agreedToTerms;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: SafeArea(child: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 68, 20, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Learnova', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('Set up your profile', style: TextStyle(color: Colors.white60, fontSize: 15)),
            const SizedBox(height: 32),
            Row(children: [
              const Text('FORM LEVEL', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(6)),
                child: const Text('PILIH SATU SAHAJA', style: TextStyle(color: Colors.white24, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Pilihan ini kekal hingga hujung tahun persekolahan', style: TextStyle(color: Colors.white24, fontSize: 11)),
            const SizedBox(height: 10),
            Row(children: List.generate(5, (i) {
              final f = i+1; final sel = selectedForm == f;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => selectedForm = f),
                child: Container(
                  margin: EdgeInsets.only(right: i<4?8:0),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: sel?Colors.blue:Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: sel?Colors.blue:Colors.white24, width: sel?2:1)),
                  child: Column(children: [
                    Text('$f', style: TextStyle(color: sel?Colors.white:Colors.white54, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(f>=4?'SPM':'PT3', style: TextStyle(color: sel?Colors.white60:Colors.white24, fontSize: 9)),
                  ]))));
            })),
            const SizedBox(height: 28),
            const Text('LANGUAGE', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 10),
            Row(children: langs.asMap().entries.map((e) {
              final code = e.value['code'] as String; final sel = selectedLang == code;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => selectedLang = code),
                child: Container(
                  margin: EdgeInsets.only(right: e.key<langs.length-1?8:0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel?Colors.blue.withOpacity(0.3):Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel?Colors.blue:Colors.white.withOpacity(0.15), width: sel?2:1)),
                  child: Text(e.value['label'] as String, textAlign: TextAlign.center,
                    style: TextStyle(color: sel?Colors.white:Colors.white54, fontSize: 11, fontWeight: sel?FontWeight.w700:FontWeight.w400)))));
            }).toList()),
            const SizedBox(height: 28),
            const Text('SUBJECTS', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 3.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: subjects.asMap().entries.map((e) {
                final name = e.value; final color = subjectColors[e.key]; final sel = selectedSubjects.contains(name);
                return GestureDetector(
                  onTap: () => setState(() { if(sel) selectedSubjects.remove(name); else selectedSubjects.add(name); }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel?color.withOpacity(0.2):Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel?color:Colors.white.withOpacity(0.1), width: sel?2:1)),
                    child: Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(name, style: TextStyle(color: sel?Colors.white:Colors.white60, fontSize: 12, fontWeight: sel?FontWeight.w700:FontWeight.w400), overflow: TextOverflow.ellipsis)),
                      if(sel) Icon(Icons.check_circle, color: color, size: 14),
                    ])));
              }).toList()),
            const SizedBox(height: 20),
            // Terms agreement
            GestureDetector(
              onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _agreedToTerms ? Colors.blue.withOpacity(0.1) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _agreedToTerms ? Colors.blue : Colors.white24),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(_agreedToTerms ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                    color: _agreedToTerms ? Colors.blue : Colors.white38, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text(
                      'Saya faham bahawa Learnova adalah platform AI pembelajaran dan mungkin tidak sentiasa tepat.',
                      style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _showFullDisclaimer,
                      child: const Text('Baca notis penuh',
                        style: TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline, decorationColor: Colors.blue)),
                    ),
                  ])),
                ]),
              ),
            ),
          ]),
        ),
        Positioned(
          top: 4, left: 4,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        Positioned(
          left: 20, right: 20, bottom: 24,
          child: GestureDetector(
            onTap: canProceed ? _proceed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: canProceed ? Colors.blue : Colors.white12,
                borderRadius: BorderRadius.circular(14),
                boxShadow: canProceed ? [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))] : []),
              child: Center(child: Text(
                canProceed ? "Let's go!  Form $selectedForm  ${selectedSubjects.length} subjects"
                  : selectedForm == 0 ? "Select your form level first"
                  : selectedSubjects.isEmpty ? "Select at least one subject"
                  : "Agree to terms above to continue",
                style: TextStyle(color: canProceed?Colors.white:Colors.white38, fontSize: 15, fontWeight: FontWeight.w700))))),
        ),
      ])),
    );
  }
}