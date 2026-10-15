// Converts the API's integer form_level to the text label used in
// structured_lessons.form ('Form 4', 'Form 5', 'A-Level').
//
// Accepts both the raw integer (4/5/6) or its .toString() ("4"/"5"/"6")
// and the already-correct label from onboarding ("Form 4"/"Form 5"/"A-Level").
// Returns null for any value that cannot be mapped.
String? labelFromFormLevel(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s == 'Form 4' || s == '4') return 'Form 4';
  if (s == 'Form 5' || s == '5') return 'Form 5';
  if (s == 'A-Level' || s == '6') return 'A-Level';
  return null;
}

// Validates that [raw] is a label the /api/lessons/path query accepts.
// structured_lessons only has 'Form 4' and 'Form 5' rows.
// A-Level content is not yet in structured_lessons, so returns null for it.
// Returns null for missing, empty, or unrecognised values — callers must
// handle null explicitly rather than silently falling back to Form 5.
String? normalizeFormLabel(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final label = labelFromFormLevel(raw);
  if (label == 'Form 4' || label == 'Form 5') return label;
  return null;
}
