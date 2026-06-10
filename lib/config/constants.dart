import 'package:flutter/material.dart';
const String kApiUrl = 'https://learnova-backend-production-bd3a.up.railway.app';
const List<Map<String, dynamic>> kSubjects = [
  {'name': 'Bahasa Malaysia', 'color': 0xFF4A7AFA, 'description': 'Bahasa, sastera & tatabahasa'},
  {'name': 'English',         'color': 0xFF22C55E, 'description': 'Grammar, writing & comprehension'},
  {'name': 'Matematik',       'color': 0xFF6366F1, 'description': 'Algebra, geometri & kalkulus'},
  {'name': 'Add Maths',       'color': 0xFF6B7EFF, 'description': 'Matematik tambahan SPM'},
  {'name': 'Fizik',           'color': 0xFFF59E0B, 'description': 'Mekanik, elektrik & moden'},
  {'name': 'Kimia',           'color': 0xFF22C55E, 'description': 'Sebatian, tindak balas & lebih'},
  {'name': 'Biologi',         'color': 0xFF10B981, 'description': 'Sel, genetik & ekosistem'},
  {'name': 'Sejarah',         'color': 0xFFEF4444, 'description': 'Sejarah Malaysia & dunia'},
];
const List<Map<String, dynamic>> kZHSubjects = [
  {'name': '数学',  'apiKey': 'ZH-Mathematics', 'color': 0xFF4A7AFA, 'description': 'SPM 数学 · 中文教学'},
  {'name': '附加数学', 'apiKey': 'ZH-AddMaths',   'color': 0xFF6B7EFF, 'description': 'SPM 附加数学 · 中文教学'},
  {'name': '物理',  'apiKey': 'ZH-Physics',    'color': 0xFFF59E0B, 'description': 'SPM 物理 · 中文教学'},
  {'name': '化学',  'apiKey': 'ZH-Chemistry',  'color': 0xFF22C55E, 'description': 'SPM 化学 · 中文教学'},
  {'name': '生物',  'apiKey': 'ZH-Biology',    'color': 0xFF10B981, 'description': 'SPM 生物 · 中文教学'},
  {'name': '历史',  'apiKey': 'ZH-Sejarah',    'color': 0xFFEF4444, 'description': 'SPM 历史 · 中文教学'},
  {'name': '英文',  'apiKey': 'ZH-English',    'color': 0xFF8B5CF6, 'description': 'SPM 英文 · 中文讲解'},
  {'name': '马来文', 'apiKey': 'ZH-BahasaMalaysia', 'color': 0xFFEC4899, 'description': 'SPM 马来文 · 中文讲解'},
];

const Color kPrimary  = Color(0xFF6366F1);
const Color kPrimary2 = Color(0xFF8B5CF6);
const Color kGreen    = Color(0xFF10B981);
const Color kYellow   = Color(0xFFF59E0B);
const Color kRed      = Color(0xFFEF4444);
const Color kBg       = Color(0xFF0F1117);
const Color kSurface  = Color(0xFF1A1D27);
const Color kSurface2 = Color(0xFF242736);
const Color kBorder   = Color(0xFF2E3347);
const Color kText     = Color(0xFFE2E8F0);
const Color kMuted    = Color(0xFF94A3B8);
String gStudentRole = 'student';

