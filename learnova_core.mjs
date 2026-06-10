// learnova_core.mjs — shared utilities for Learnova backend
// Import: import { formatNovaResponse } from './learnova_core.mjs';

/**
 * Parse and clean a Nova/Claude response string.
 * Handles:
 *   - Double-encoded JSON: Claude wraps its text inside {"reply":"..."}
 *   - Literal \n sequences from JSON encoding
 *   - Non-string values (objects, null)
 *
 * Returns a clean plain-text string suitable for display and TTS.
 */
export function formatNovaResponse(raw) {
  if (!raw) return '';
  let text = typeof raw === 'string' ? raw : String(raw);
  const trimmed = text.trim();

  // If the response is a JSON object, extract the reply/answer field
  if (trimmed.startsWith('{')) {
    // Happy path: valid JSON
    try {
      const parsed = JSON.parse(trimmed);
      const extracted = parsed.reply || parsed.answer || parsed.content || parsed.text || parsed.message;
      if (extracted && typeof extracted === 'string') {
        text = extracted;
      }
    } catch {
      // Regex fallback for truncated / malformed JSON
      const m = trimmed.match(/"(?:reply|answer)"\s*:\s*"((?:[^"\\]|\\.)*)"/);
      if (m) {
        try { text = JSON.parse('"' + m[1] + '"'); } catch { text = m[1]; }
      } else {
        // Cannot extract anything useful
        return '';
      }
    }
  }

  // Convert literal escape sequences that sometimes appear in Claude responses
  text = text.replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\"/g, '"');

  return text;
}

// Muslim/Malay/Arab name indicators for smart greeting
export const MUSLIM_NAME_INDICATORS = [
  'muhammad', 'muhamad', 'mohd', 'mohamad', 'mohammad', 'ahmad', 'ahmed',
  'nur', 'nurul', 'siti', 'wan', 'nik', 'tengku',
  'sharifah', 'syed', 'said', 'abd', 'abdul', 'abu',
  'ali', 'umar', 'omar', 'osman', 'hassan', 'husain', 'hussain',
  'ibrahim', 'ismail', 'idris', 'izzat', 'izzah',
  'fatimah', 'khadijah', 'zainab', 'aisyah', 'aisha', 'aishah',
  'yusof', 'yusuf', 'yahya', 'zakaria', 'hafiz', 'hakim',
  'azman', 'azwan', 'azrul', 'azri', 'farid', 'farhan', 'faiz',
  'halim', 'irfan', 'luqman', 'razif', 'razak', 'zulkifli',
  'nazir', 'nazri', 'nazrin', 'nazrul', 'nazirul', 'nazhan', 'nazar',
  'aziz', 'azhar', 'azlan',
  'haziq', 'hazim', 'hazwan',
  'faris', 'farish',
  'anis', 'anas', 'aniq',
  'arif', 'ariff', 'aqil', 'aqeel',
  'rauf', 'rafi', 'rafiq',
  'wafi', 'wafiq', 'walid',
  'taqi', 'taqiy', 'taufiq',
  'zafir', 'zahir', 'zahran',
  // Additional male names
  'akmal', 'adli', 'ayaan', 'ammar', 'aadam', 'ayyash', 'aadil', 'ahsan', 'asraf',
  'badrul', 'basyir', 'bima', 'bahrin', 'bashir', 'basri', 'barzin', 'bariq', 'burhan',
  'daud', 'daniel', 'darma', 'dzulqarnain', 'dzakwan', 'dzulfiqar', 'daffa', 'damar',
  'ehsan', 'elias', 'eiman', 'ezzat', 'eman',
  'faiq', 'fikri', 'firdaus', 'fadhil', 'faz',
  'ghazali', 'gibran', 'ghani', 'ghaffar', 'ghazwan', 'ghaisan',
  'hilmi', 'hasan', 'hamzah', 'hafizh',
  'ikhwan', 'iskandar', 'izzuddin', 'ihsan',
  'jamal', 'jibril',
  'kamil', 'karim', 'khayr', 'khairul', 'kasyaf', 'khalis', 'khidir',
  'luthfi', 'lazim', 'lail', 'lami', 'lazhar', 'luth',
  'marwan', 'miqdad', 'muaz', 'muammar',
  'nashr', 'naim', 'najib', 'nashit', 'nashwan', 'nawfal', 'nizam',
  'othman',
  'pasha',
  'qadir', 'qasim', 'qays', 'qamar', 'qawi', 'qudamah', 'qudus', 'qudrat', 'qamaruddin',
  'rahman', 'rashid', 'razi', 'rizqi', 'ruslan',
  'salim', 'sami', 'sani', 'saqib', 'sharif', 'siddiq', 'syakir', 'syazwan',
  'tariq', 'tahir', 'tamim', 'tarmizi',
  'uwais', 'ulwan', 'usamah', 'umair', 'ubay', 'ulfat',
  'wazir', 'wahab', 'wahid', 'wali', 'wajdi', 'wathiq', 'wajih',
  'yasir', 'yamin', 'yaqin', 'yazid', 'yunus', 'yumna',
  'zaid', 'zuhair', 'zamir', 'zuhdi', 'zainulabidin', 'zulqarnain',
  // Additional female names
  'balqis', 'baiduri',
  'damia', 'dana', 'durrah',
  'fatin', 'fiona',
  'ghayda',
  'haura', 'haya', 'humaira',
  'inara', 'imani', 'isya',
  'jauza', 'jihan', 'jannah',
  'kamilia', 'khalishah',
  'lafifah', 'latifah', 'leena', 'liyana', 'lubna',
  'maisarah', 'malika', 'marwa', 'mawar',
  'nadhirah', 'nayla', 'naimah', 'nathifa', 'nisrina', 'nabihah', 'nadeera', 'najla',
  'qaila', 'qairina',
  'rafidah', 'raidah', 'raihanah', 'rania',
  'safa', 'saidah', 'sakeena', 'salsabila', 'sameeha', 'sameera', 'samiyah', 'suhayla', 'syafia',
  'thahirah', 'talia',
  'ubaidah', 'ufairah', 'ulya', 'umaimah', 'uzma',
  'wafa', 'wardani',
  'yasmeen', 'yusrina',
  'zaaimah', 'zafirah', 'zahidah', 'zahiya', 'zahra', 'zara', 'zuhailin', 'zuhaira', 'zuyyin',
];

export function getSmartGreeting(name) {
  if (name) {
    const parts = name.toLowerCase().split(/\s+/);
    const isMuslim = parts.some(p =>
      MUSLIM_NAME_INDICATORS.some(ind => p.startsWith(ind) || (ind.startsWith(p) && p.length >= 3))
    );
    if (isMuslim) return 'Assalamualaikum';
  }
  const h = new Date().getHours();
  return h < 12 ? 'Selamat pagi' : h < 17 ? 'Selamat petang' : 'Selamat malam';
}

/**
 * Strip markdown formatting and emoji for TTS use.
 * Keeps sentence structure intact.
 */
export function stripMarkdownForTts(text) {
  if (!text) return '';
  return text
    .replace(/\*\*(.+?)\*\*/g, '$1')   // bold
    .replace(/\*(.+?)\*/g, '$1')        // italic
    .replace(/`{1,3}[^`]*`{1,3}/g, '') // code
    .replace(/#{1,6}\s+/g, '')          // headings
    .replace(/!\[.*?\]\(.*?\)/g, '')    // images
    .replace(/\[(.+?)\]\(.*?\)/g, '$1') // links
    .replace(/[\u{1F000}-\u{1FFFF}]/gu, '') // emoji (supplementary)
    .replace(/[\u{2600}-\u{27BF}]/gu, '')   // emoji (misc symbols)
    .trim();
}

/**
 * Full TTS text cleaning — strips markdown + replaces math symbols with
 * spoken BM words so OpenAI TTS doesn't produce gibberish.
 * Apply to ALL text before calling the TTS API.
 */
export function cleanTextForTTS(text) {
  if (!text) return '';
  return text
    // Remove markdown
    .replace(/\*\*(.*?)\*\*/g, '$1')
    .replace(/\*(.*?)\*/g, '$1')
    .replace(/#{1,6}\s/g, '')
    .replace(/`(.*?)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')

    // Replace math symbols with BM spoken words (BEFORE stripping non-ASCII)
    .replace(/÷/g, ' bahagi ')
    .replace(/×/g, ' darab ')
    .replace(/²/g, ' kuasa dua ')
    .replace(/³/g, ' kuasa tiga ')
    .replace(/√/g, ' punca kuasa dua ')
    .replace(/°/g, ' darjah ')
    .replace(/½/g, ' satu perdua ')
    .replace(/¼/g, ' satu perempat ')
    .replace(/¾/g, ' tiga perempat ')
    .replace(/π/g, ' pi ')
    .replace(/≈/g, ' lebih kurang ')
    .replace(/≠/g, ' tidak sama dengan ')
    .replace(/≤/g, ' kurang atau sama dengan ')
    .replace(/≥/g, ' lebih atau sama dengan ')
    .replace(/→/g, ' ')
    .replace(/←/g, ' ')
    .replace(/±/g, ' tambah tolak ')
    .replace(/∞/g, ' infiniti ')
    .replace(/∑/g, ' hasil tambah ')
    .replace(/∆/g, ' delta ')
    .replace(/α/g, ' alfa ')
    .replace(/β/g, ' beta ')
    .replace(/θ/g, ' teta ')
    .replace(/μ/g, ' mu ')
    .replace(/σ/g, ' sigma ')
    .replace(/λ/g, ' lambda ')
    .replace(/ω/g, ' omega ')

    // Remove remaining special / non-printable characters
    .replace(/[^\w\s.,?!;:()\-]/g, ' ')

    // Collapse multiple spaces and newlines
    .replace(/\s+/g, ' ')
    .trim();
}

// ── Teaching language config (replaces subject-prefix TTS routing) ────────────

export const TEACHING_LANGUAGES = {
  'bm': { name: 'Bahasa Malaysia', nativeName: 'Bahasa Malaysia', novaPromptKey: 'bm', ttsEngine: 'openai', ttsVoice: 'nova' },
  'en': { name: 'English',         nativeName: 'English',         novaPromptKey: 'en', ttsEngine: 'kokoro', ttsVoice: 'af_sarah' },
  'zh': { name: 'Mandarin',        nativeName: '中文',             novaPromptKey: 'zh', ttsEngine: 'kokoro', ttsVoice: 'zf_xiaobei' },
  'ta': { name: 'Tamil',           nativeName: 'தமிழ்',           novaPromptKey: 'ta', ttsEngine: 'kokoro', ttsVoice: 'af_sarah' },
  'id': { name: 'Bahasa Indonesia', nativeName: 'Bahasa Indonesia', novaPromptKey: 'id', ttsEngine: 'openai', ttsVoice: 'nova' },
};

// audio_url column per teaching language
export const AUDIO_COLUMN = {
  'bm': 'audio_url',
  'en': 'audio_url_en',
  'zh': 'audio_url_zh',
  'ta': 'audio_url_ta',
  'id': 'audio_url',
};

// ── Nova system prompts per teaching language ─────────────────────────────────

export const NOVA_ZH_PROMPT = `你是 Nova，Learnova 的 AI 导师。你帮助马来西亚华裔中学生备考 SPM。重要规则：1. 永远不要直接给出答案 2. 用苏格拉底式提问引导学生 3. 联系马来西亚生活实际举例 4. 每次回复必须以开放式问题结尾 5. 用简单易懂的中文 6. 鼓励学生，保持积极 7. 专注 SPM 考试技巧。回复必须以开放式问题结尾。`;

export const NOVA_TA_PROMPT = `நீங்கள் Nova, Learnova இன் AI ஆசிரியர். மலேசிய தமிழ் மாணவர்களுக்கு SPM தேர்வுக்கு உதவுகிறீர்கள். விதிகள்: 1. நேரடியாக விடை சொல்லாதீர்கள் 2. கேள்விகள் கேட்டு வழிகாட்டுங்கள் 3. எப்போதும் திறந்த கேள்வியுடன் முடியுங்கள்.`;
