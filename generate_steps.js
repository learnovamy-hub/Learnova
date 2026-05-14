const https = require('https');
require('dotenv').config();
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://nxvbpanozswheackgwni.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_KEY;
const ANTHROPIC_KEY = process.env.ANTHROPIC_API_KEY;
if (!SUPABASE_KEY || !ANTHROPIC_KEY) { console.error('Missing keys in .env'); process.exit(1); }
function request(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => { try { resolve({ status: res.statusCode, body: JSON.parse(data) }); } catch { resolve({ status: res.statusCode, body: data }); } });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}
async function fetchLessons(limit) {
  const url = new URL(SUPABASE_URL + '/rest/v1/lessons');
  url.searchParams.set('select', 'id,title,topic,subject,form_level,introduction,learning_objectives,content,worked_examples,common_mistakes,summary');
  url.searchParams.set('steps', 'is.null');
  url.searchParams.set('status', 'eq.published');
  url.searchParams.set('limit', String(limit));
  const res = await request({ hostname: url.hostname, path: url.pathname + url.search, method: 'GET',
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': 'Bearer ' + SUPABASE_KEY } });
  return Array.isArray(res.body) ? res.body : [];
}
async function saveSteps(id, steps) {
  const url = new URL(SUPABASE_URL + '/rest/v1/lessons');
  url.searchParams.set('id', 'eq.' + id);
  const res = await request({ hostname: url.hostname, path: url.pathname + url.search, method: 'PATCH',
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': 'Bearer ' + SUPABASE_KEY,
      'Content-Type': 'application/json', 'Prefer': 'return=minimal' } }, { steps });
  return res.status === 204 || res.status === 200;
}
const SYSTEM = `You are an expert SPM tutor using AAMT evidence-based pedagogy (2025).
Output ONLY valid JSON with this shape:
{"steps":[{"id":1,"type":"objectives|prior_knowledge|concept|formula|example|working|mistake|connection|summary","title":"4-6 word title","text":"Screen text max 200 words no markdown","voice_script":"Friendly tutor narration max 120 words conversational"}],"check_ins":[{"after_step_id":3,"question":"SPM question","options":["A","B","C","D"],"correct_index":0,"explanation":"Why correct max 60 words"}]}
SEQUENCE: objectives -> prior_knowledge -> concept -> formula -> example -> working -> mistake -> connection -> summary
Put check_ins after concept or formula steps only. Total steps 7-10. Check_ins 1-3.`;
async function generateSteps(lesson) {
  const prompt = 'Generate AAMT-sequenced steps for:\nLESSON: ' + lesson.title + '\nSUBJECT: ' + lesson.subject + ' Form ' + lesson.form_level + '\nTOPIC: ' + lesson.topic + '\nCONTENT:\n' + (lesson.content||'').substring(0,2500) + '\nEXAMPLES:\n' + (lesson.worked_examples||'').substring(0,800) + '\nMISTAKES:\n' + (lesson.common_mistakes||'').substring(0,400) + '\nSUMMARY:\n' + (lesson.summary||'').substring(0,400);
  const res = await request({ hostname: 'api.anthropic.com', path: '/v1/messages', method: 'POST',
    headers: { 'x-api-key': ANTHROPIC_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' } },
    { model: 'claude-haiku-4-5-20251001', max_tokens: 4096, system: SYSTEM, messages: [{ role: 'user', content: prompt }] });
  if (res.status !== 200) throw new Error('Claude ' + res.status);
  const text = (res.body.content?.[0]?.text||'').replace(/```json\s*/g,'').replace(/```\s*/g,'').trim();
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error('No JSON');
  const parsed = JSON.parse(match[0]);
  if (!Array.isArray(parsed.steps)||!parsed.steps.length) throw new Error('Empty steps');
  if (!Array.isArray(parsed.check_ins)) parsed.check_ins = [];
  return parsed;
}
async function main() {
  const batchSize = parseInt(process.argv[2]||'10',10);
  console.log('Learnova Step Generator');
  const lessons = await fetchLessons(batchSize);
  if (!lessons.length) { console.log('All lessons have steps.'); return; }
  console.log('Processing ' + lessons.length + ' lessons');
  let ok=0,fail=0;
  for (let i=0;i<lessons.length;i++) {
    const l=lessons[i];
    process.stdout.write('  ['+(i+1)+'/'+lessons.length+'] '+l.subject+' - '+l.topic+'... ');
    try {
      const data = await generateSteps(l);
      const saved = await saveSteps(l.id, data);
      if (saved) { ok++; console.log('OK  '+data.steps.length+' steps, '+data.check_ins.length+' check-ins'); }
      else { fail++; console.log('SAVE FAILED'); }
    } catch(e) { fail++; console.log('ERROR: '+e.message.substring(0,80)); }
    if (i<lessons.length-1) await new Promise(r=>setTimeout(r,1300));
  }
  console.log('Done: '+ok+' OK, '+fail+' failed');
}
main().catch(console.error);