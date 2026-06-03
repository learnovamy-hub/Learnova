/**
 * LEARNOVA PRE-GENERATED CONTENT LOOKUP
 * Serves questions, FAQs, and explanations from Supabase cache.
 * Zero Claude API calls for known content.
 */

const FAQ_TRIGGERS = [
  'apa itu', 'apa yang dimaksud', 'kenapa', 'mengapa',
  'bagaimana cara', 'apa bedanya', 'cara mengingat',
  'rumusnya', 'contohnya', 'apa itu',
  'what is', 'how to', 'why', 'what does', 'explain',
  'what are', 'define', 'difference between',
  'tak faham', 'tak mengerti', 'maksud', 'ertinya',
];

const EXPLANATION_TRIGGERS = {
  fear_reduction: ['takut', 'susah', 'sulit', 'nervous', 'risau', 'scared', 'hard', 'difficult', 'give up', 'cannot'],
  beginner:       ['mula', 'start', 'awal', 'basic', 'first time', 'dont know', 'zero'],
  analogy:        ['analogi', 'contoh kehidupan', 'daily life', 'real life', 'macam apa', 'like what'],
  exam_focused:   ['exam', 'ujian', 'peperiksaan', 'tips', 'trick', 'ingat', 'remember', 'formula'],
};

export class PregenLookup {
  constructor(supabase) {
    this.sb = supabase;
    this._cache = new Map();
  }

  _cacheGet(key) { return this._cache.get(key) ?? null; }

  _cacheSet(key, value, ttlMs = 300_000) {
    this._cache.set(key, value);
    setTimeout(() => this._cache.delete(key), ttlMs);
  }

  // Get questions for a topic — no API call
  async getQuestions(country, subject, topic, { difficulty = null, count = 5, type = null, excludeIds = [] } = {}) {
    const cacheKey = `q:${country}:${subject}:${topic}:${difficulty}:${count}:${type}`;
    const cached = this._cacheGet(cacheKey);
    if (cached) return cached;

    let query = this.sb
      .from('question_bank')
      .select('*')
      .eq('country', country)
      .eq('subject', subject)
      .ilike('topic', `%${topic}%`);

    if (difficulty) query = query.eq('difficulty', difficulty);
    if (type)       query = query.eq('question_type', type);
    if (excludeIds.length) query = query.not('id', 'in', `(${excludeIds.join(',')})`);

    const { data } = await query
      .order('times_attempted', { ascending: true })
      .limit(count * 3);

    if (!data?.length) return [];

    const shuffled = data.sort(() => Math.random() - 0.5).slice(0, count);
    this._cacheSet(cacheKey, shuffled);
    return shuffled;
  }

  // Get closest FAQ answer — no API call
  async getFAQ(country, subject, topic, studentQuestion) {
    const words = studentQuestion.toLowerCase().split(/\s+/).slice(0, 6).join(' | ');
    const { data } = await this.sb
      .from('faq_bank')
      .select('id, question, answer, category, learnova_method')
      .eq('country', country)
      .eq('subject', subject)
      .ilike('topic', `%${topic}%`)
      .textSearch('question', words, { type: 'websearch' })
      .limit(3);

    if (data?.length) {
      // Fire-and-forget usage increment
      this.sb.rpc('increment_faq_use', { faq_id: data[0].id }).catch(() => {});
      return data[0];
    }
    return null;
  }

  // Get pre-built explanation — no API call
  async getExplanation(country, subject, topic, type = 'standard') {
    const cacheKey = `exp:${country}:${subject}:${topic}:${type}`;
    const cached = this._cacheGet(cacheKey);
    if (cached) return cached;

    const { data } = await this.sb
      .from('concept_explanations')
      .select('explanation, explanation_type')
      .eq('country', country)
      .eq('subject', subject)
      .ilike('topic', `%${topic}%`)
      .eq('explanation_type', type)
      .maybeSingle();

    if (data?.explanation) {
      this._cacheSet(cacheKey, data.explanation);
      return data.explanation;
    }
    return null;
  }

  // Detect if a message is FAQ-type and serve pre-generated answer
  async detectAndServeFAQ(country, subject, topic, userMessage) {
    const lower = userMessage.toLowerCase();
    const isFAQType = FAQ_TRIGGERS.some(t => lower.includes(t));
    if (!isFAQType) return null;
    return this.getFAQ(country, subject, topic, userMessage);
  }

  // Detect explanation type from message
  detectExplanationType(userMessage) {
    const lower = userMessage.toLowerCase();
    for (const [type, triggers] of Object.entries(EXPLANATION_TRIGGERS)) {
      if (triggers.some(t => lower.includes(t))) return type;
    }
    return null;
  }
}

export default PregenLookup;
