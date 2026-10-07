import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import nodemailer from 'nodemailer';
import cron from 'node-cron';
import express from 'express';

// LNV-YYYYMMDD-XXXXXX
function generateTicketNumber() {
  const d = new Date();
  const dateStr = d.toISOString().slice(0, 10).replace(/-/g, '');
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let rand = '';
  for (let i = 0; i < 6; i++) rand += chars[Math.floor(Math.random() * chars.length)];
  return `LNV-${dateStr}-${rand}`;
}

const VALID_CATEGORIES = ['bug_report', 'need_help', 'content_error', 'suggestion', 'feature_request', 'general_feedback'];
const VALID_STATUSES   = ['open', 'in_progress', 'resolved', 'closed'];
const VALID_PRIORITIES = ['low', 'normal', 'high', 'critical'];

export function initFeedbackRoutes(app, supabase, JWT_SECRET, authStudent) {

  // Admin middleware: verifies JWT AND confirms admin_id exists in admins table
  const authAdmin = async (req, res, next) => {
    const token = req.headers.authorization?.replace('Bearer ', '');
    if (!token) return res.status(401).json({ error: 'No token' });
    let payload;
    try {
      payload = jwt.verify(token, JWT_SECRET);
    } catch {
      return res.status(401).json({ error: 'Invalid token' });
    }
    if (!payload.admin_id) return res.status(403).json({ error: 'Admin access only' });
    const { data } = await supabase
      .from('admins')
      .select('id')
      .eq('id', payload.admin_id)
      .maybeSingle();
    if (!data) return res.status(403).json({ error: 'Admin not found' });
    req.admin = { id: data.id };
    next();
  };

  // ── POST /api/admin/login ────────────────────────────────────────────────────
  app.post('/api/admin/login', async (req, res) => {
    try {
      const { email, password } = req.body;
      if (!email || !password) return res.status(400).json({ error: 'Email and password required' });
      const { data } = await supabase
        .from('admins')
        .select('id, email, full_name, role, password_hash')
        .eq('email', email)
        .maybeSingle();
      if (!data) {
        return res.status(401).json({ error: 'Invalid email or password' });
      }
      // Bcrypt hashes always start with $2b$ or $2a$.
      // Legacy rows store plaintext in password_hash — auto-upgrade on first successful login.
      const isBcryptHash = data.password_hash.startsWith('$2b$') || data.password_hash.startsWith('$2a$');
      let passwordValid;
      if (isBcryptHash) {
        passwordValid = await bcrypt.compare(password, data.password_hash);
      } else {
        passwordValid = data.password_hash === password;
        if (passwordValid) {
          // Upgrade silently — never log or expose plaintext or hash values.
          const upgraded = await bcrypt.hash(password, 12);
          await supabase.from('admins').update({ password_hash: upgraded }).eq('id', data.id);
        }
      }
      if (!passwordValid) {
        return res.status(401).json({ error: 'Invalid email or password' });
      }
      const token = jwt.sign({ admin_id: data.id }, JWT_SECRET, { expiresIn: '8h' });
      return res.json({
        token,
        admin: { id: data.id, email: data.email, full_name: data.full_name, role: data.role },
      });
    } catch (e) {
      console.error('[admin/login]', e.message);
      return res.status(500).json({ error: 'Login failed' });
    }
  });

  // ── POST /api/feedback/submit ────────────────────────────────────────────────
  // Rate-limited by feedbackLimiter registered in server_updated.mjs
  app.post('/api/feedback/submit', authStudent, async (req, res) => {
    try {
      const { category, description, page_url, subject_context, device_info } = req.body;
      if (!category || !description) return res.status(400).json({ error: 'category and description required' });
      if (!VALID_CATEGORIES.includes(category)) return res.status(400).json({ error: 'Invalid category' });
      if (typeof description !== 'string' || description.trim().length === 0) {
        return res.status(400).json({ error: 'Description must not be empty' });
      }

      // Identity derived exclusively from verified JWT — never from request body
      const studentUUID = req.user.student_id;

      let ticketNumber;
      for (let attempt = 0; attempt < 3; attempt++) {
        ticketNumber = generateTicketNumber();
        const { data: collision } = await supabase
          .from('feedback_tickets')
          .select('id')
          .eq('ticket_number', ticketNumber)
          .maybeSingle();
        if (!collision) break;
      }

      const { data, error } = await supabase
        .from('feedback_tickets')
        .insert([{
          ticket_number:   ticketNumber,
          user_id:         studentUUID,
          student_id:      studentUUID,
          role:            'student',
          category,
          description:     description.trim().slice(0, 5000),
          page_url:        page_url        ? String(page_url).slice(0, 500)        : null,
          subject_context: subject_context ? String(subject_context).slice(0, 200) : null,
          device_info:     (device_info && typeof device_info === 'object') ? device_info : null,
        }])
        .select('id, ticket_number, status, created_at')
        .single();

      if (error) {
        console.error('[feedback/submit]', error.message);
        return res.status(500).json({ error: 'Failed to submit feedback' });
      }
      return res.status(201).json({
        ticket_number: data.ticket_number,
        id:            data.id,
        status:        data.status,
        created_at:    data.created_at,
      });
    } catch (e) {
      console.error('[feedback/submit]', e.message);
      return res.status(500).json({ error: 'Server error' });
    }
  });

  // ── POST /api/feedback/screenshot/:ticketNumber ──────────────────────────────
  // Accepts raw image bytes (Content-Type: image/jpeg or image/png, max 5 MB).
  // Uploads to private bucket feedback-screenshots/{ticketNumber}/screen.{ext}.
  app.post(
    '/api/feedback/screenshot/:ticketNumber',
    authStudent,
    express.raw({ type: 'image/*', limit: '5mb' }),
    async (req, res) => {
      try {
        const { ticketNumber } = req.params;
        const studentUUID = req.user.student_id;
        const ct = req.headers['content-type'] || '';
        if (!ct.startsWith('image/')) return res.status(400).json({ error: 'Image content-type required' });
        if (!Buffer.isBuffer(req.body) || req.body.length < 100) {
          return res.status(400).json({ error: 'Empty or invalid image' });
        }

        const { data: ticket } = await supabase
          .from('feedback_tickets')
          .select('id')
          .eq('ticket_number', ticketNumber)
          .eq('user_id', studentUUID)
          .maybeSingle();
        if (!ticket) return res.status(404).json({ error: 'Ticket not found' });

        const ext = ct.includes('png') ? 'png' : 'jpg';
        const objectPath = `${ticketNumber}/screen.${ext}`;

        const { error: upErr } = await supabase.storage
          .from('feedback-screenshots')
          .upload(objectPath, req.body, { contentType: ct, upsert: true });
        if (upErr) {
          console.error('[feedback/screenshot] upload:', upErr.message);
          return res.status(500).json({ error: 'Upload failed' });
        }

        await supabase
          .from('feedback_tickets')
          .update({ screenshot_path: objectPath })
          .eq('id', ticket.id);

        return res.json({ screenshot_path: objectPath });
      } catch (e) {
        console.error('[feedback/screenshot]', e.message);
        return res.status(500).json({ error: 'Server error' });
      }
    }
  );

  // ── GET /api/admin/feedback ──────────────────────────────────────────────────
  app.get('/api/admin/feedback', authAdmin, async (req, res) => {
    try {
      const { status, priority, category, page = '1', limit: limitStr = '20' } = req.query;
      const pageNum  = Math.max(1, parseInt(page)     || 1);
      const limitNum = Math.min(100, Math.max(1, parseInt(limitStr) || 20));
      const offset   = (pageNum - 1) * limitNum;

      let query = supabase
        .from('feedback_tickets')
        .select(
          'id, ticket_number, user_id, student_id, role, category, description, page_url, ' +
          'subject_context, screenshot_path, status, priority, admin_notes, ' +
          'created_at, updated_at, resolved_at',
          { count: 'exact' }
        )
        .order('created_at', { ascending: false })
        .range(offset, offset + limitNum - 1);

      if (status)   query = query.eq('status', status);
      if (priority) query = query.eq('priority', priority);
      if (category) query = query.eq('category', category);

      const { data, error, count } = await query;
      if (error) {
        console.error('[admin/feedback]', error.message);
        return res.status(500).json({ error: 'Query failed' });
      }
      return res.json({ tickets: data, total: count, page: pageNum, limit: limitNum });
    } catch (e) {
      console.error('[admin/feedback]', e.message);
      return res.status(500).json({ error: 'Server error' });
    }
  });

  // ── PATCH /api/admin/feedback/:id ────────────────────────────────────────────
  app.patch('/api/admin/feedback/:id', authAdmin, async (req, res) => {
    try {
      const { id } = req.params;
      const { status, priority, admin_notes } = req.body;
      const updates = {};

      if (status !== undefined) {
        if (!VALID_STATUSES.includes(status)) return res.status(400).json({ error: 'Invalid status' });
        updates.status = status;
        if (status === 'resolved' || status === 'closed') {
          updates.resolved_at = new Date().toISOString();
        }
      }
      if (priority !== undefined) {
        if (!VALID_PRIORITIES.includes(priority)) return res.status(400).json({ error: 'Invalid priority' });
        updates.priority = priority;
      }
      if (admin_notes !== undefined) {
        updates.admin_notes = String(admin_notes).slice(0, 2000);
      }
      if (Object.keys(updates).length === 0) return res.status(400).json({ error: 'Nothing to update' });

      const { data, error } = await supabase
        .from('feedback_tickets')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
      if (error) {
        console.error('[admin/feedback PATCH]', error.message);
        return res.status(500).json({ error: 'Update failed' });
      }
      return res.json({ ticket: data });
    } catch (e) {
      console.error('[admin/feedback PATCH]', e.message);
      return res.status(500).json({ error: 'Server error' });
    }
  });

  // ── GET /api/admin/feedback/:id/screenshot ───────────────────────────────────
  // Returns a 1-hour signed URL. Never exposes a public URL.
  app.get('/api/admin/feedback/:id/screenshot', authAdmin, async (req, res) => {
    try {
      const { id } = req.params;
      const { data: ticket } = await supabase
        .from('feedback_tickets')
        .select('screenshot_path')
        .eq('id', id)
        .maybeSingle();
      if (!ticket)                  return res.status(404).json({ error: 'Ticket not found' });
      if (!ticket.screenshot_path) return res.status(404).json({ error: 'No screenshot attached' });

      const { data: signed, error: signErr } = await supabase.storage
        .from('feedback-screenshots')
        .createSignedUrl(ticket.screenshot_path, 3600);
      if (signErr) {
        console.error('[admin/screenshot]', signErr.message);
        return res.status(500).json({ error: 'Could not create signed URL' });
      }
      return res.json({ url: signed.signedUrl });
    } catch (e) {
      console.error('[admin/screenshot]', e.message);
      return res.status(500).json({ error: 'Server error' });
    }
  });

  console.log('[feedback] Routes registered: submit, screenshot, admin CRUD');
}

// ── Daily digest state machine ────────────────────────────────────────────────
// States:  processing → sent | failed | skipped
//
// Claiming protocol:
//   First run   — INSERT 'processing'. UNIQUE(digest_date) ensures exactly one
//                 instance wins even with simultaneous cron fires.
//   Active run  — row is 'processing' and age < STALE_MS → stand down.
//   Stale run   — row is 'processing' and age >= STALE_MS → conditional UPDATE
//                 bumps sent_at; PostgreSQL row-locking ensures only one stealer wins.
//   Failed run  — conditional UPDATE failed → processing allows retry; 'sent'/'skipped'
//                 block further attempts.
//
// WARNING: SMTP cannot guarantee exactly-once delivery. If the provider accepts the
// message but returns a transient error, a 'failed' retry will send a duplicate.
// There is no application-level deduplication for SMTP. This limitation is inherent
// to the protocol and cannot be resolved in this layer.

const DIGEST_STALE_MS = 15 * 60 * 1000; // processing claims older than 15 min are stealable

// Exported for unit testing — not part of the production public API.
export async function _runDigest(supabase, transporter, {
  digestDate = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kuala_Lumpur' }),
  staleMs    = DIGEST_STALE_MS,
} = {}) {
  // ── Step 1: Determine whether this instance may proceed ──────────────────────
  const { data: existing } = await supabase
    .from('digest_log')
    .select('id, delivery_status, sent_at')
    .eq('digest_date', digestDate)
    .maybeSingle();

  if (existing) {
    const { delivery_status, sent_at } = existing;

    // Terminal success states — never re-send
    if (delivery_status === 'sent' || delivery_status === 'skipped') {
      console.log('[digest]', digestDate, '— already completed (' + delivery_status + '), skipping');
      return;
    }

    if (delivery_status === 'processing') {
      const ageMs = Date.now() - new Date(sent_at).getTime();
      if (ageMs < staleMs) {
        console.log('[digest]', digestDate,
          '— active processing claim (age ' + Math.round(ageMs / 1000) + 's), skipping');
        return;
      }
      // Stale: try to steal by bumping sent_at while the status-and-age condition still holds.
      // PostgreSQL serialises concurrent UPDATEs on the same row; the second caller sees
      // the already-bumped sent_at and matches 0 rows.
      const staleThreshold = new Date(Date.now() - staleMs).toISOString();
      const { data: stolen } = await supabase
        .from('digest_log')
        .update({ sent_at: new Date().toISOString() })
        .eq('digest_date', digestDate)
        .eq('delivery_status', 'processing')
        .lt('sent_at', staleThreshold)
        .select('id');
      if (!stolen || stolen.length === 0) {
        console.log('[digest]', digestDate, '— stale steal lost, skipping');
        return;
      }
      console.log('[digest]', digestDate, '— claimed stale processing row');
      // Fall through to send
    } else if (delivery_status === 'failed') {
      // Retry: transition failed → processing. Conditional on delivery_status so that
      // two concurrent retries cannot both proceed.
      const { data: claimed } = await supabase
        .from('digest_log')
        .update({
          delivery_status: 'processing',
          sent_at:         new Date().toISOString(),
          error_message:   null,
        })
        .eq('digest_date', digestDate)
        .eq('delivery_status', 'failed')
        .select('id');
      if (!claimed || claimed.length === 0) {
        console.log('[digest]', digestDate, '— retry claim lost, skipping');
        return;
      }
      console.log('[digest]', digestDate, '— claimed failed row for retry');
      // Fall through to send
    }
  } else {
    // No row for this date. INSERT atomically — UNIQUE(digest_date) means only one
    // concurrent INSERT succeeds; the loser receives a unique-violation error.
    const { error: insertErr } = await supabase
      .from('digest_log')
      .insert([{ digest_date: digestDate, delivery_status: 'processing', tickets_count: 0 }]);
    if (insertErr) {
      console.log('[digest]', digestDate, '— lost INSERT race, skipping');
      return;
    }
    console.log('[digest]', digestDate, '— INSERT claim succeeded');
  }

  // ── Step 2: Fetch open tickets ──────────────────────────────────────────────
  const { data: tickets } = await supabase
    .from('feedback_tickets')
    .select('id, ticket_number, category, description, status, priority, created_at')
    .in('status', ['open', 'in_progress'])
    .order('priority', { ascending: false })
    .order('created_at', { ascending: true })
    .limit(50);

  const count = tickets ? tickets.length : 0;

  if (count === 0) {
    await supabase.from('digest_log')
      .update({ delivery_status: 'skipped', tickets_count: 0 })
      .eq('digest_date', digestDate);
    console.log('[digest]', digestDate, '— no open tickets, skipped');
    return;
  }

  // ── Step 3: Build HTML ──────────────────────────────────────────────────────
  const priorityIcon = { critical: '[CRITICAL]', high: '[HIGH]', normal: '[NORMAL]', low: '[LOW]' };
  const rows = tickets.map(t => {
    const icon = priorityIcon[t.priority] || '';
    const desc = t.description.length > 120 ? t.description.slice(0, 120) + '...' : t.description;
    const date = new Date(t.created_at).toLocaleString('en-MY', { timeZone: 'Asia/Kuala_Lumpur' });
    return `<tr>
      <td style="padding:6px;border:1px solid #ddd">${t.ticket_number}</td>
      <td style="padding:6px;border:1px solid #ddd">${icon} ${t.priority}</td>
      <td style="padding:6px;border:1px solid #ddd">${t.category.replace(/_/g, ' ')}</td>
      <td style="padding:6px;border:1px solid #ddd">${t.status}</td>
      <td style="padding:6px;border:1px solid #ddd">${desc}</td>
      <td style="padding:6px;border:1px solid #ddd;white-space:nowrap">${date}</td>
    </tr>`;
  }).join('');

  const html = `<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;color:#222">
<h2 style="color:#6366F1">Learnova Feedback Digest &mdash; ${digestDate}</h2>
<p><strong>${count}</strong> open/in-progress ticket${count !== 1 ? 's' : ''} as of midnight KL time.</p>
<table style="border-collapse:collapse;width:100%;font-size:14px">
<thead><tr style="background:#f3f4f6">
  <th style="padding:8px;border:1px solid #ddd;text-align:left">Ticket</th>
  <th style="padding:8px;border:1px solid #ddd;text-align:left">Priority</th>
  <th style="padding:8px;border:1px solid #ddd;text-align:left">Category</th>
  <th style="padding:8px;border:1px solid #ddd;text-align:left">Status</th>
  <th style="padding:8px;border:1px solid #ddd;text-align:left">Description</th>
  <th style="padding:8px;border:1px solid #ddd;text-align:left">Submitted (KL)</th>
</tr></thead>
<tbody>${rows}</tbody>
</table>
<p style="color:#999;font-size:12px;margin-top:24px">Sent automatically by Learnova backend. Do not reply.</p>
</body></html>`;

  // ── Step 4: Send and finalize ───────────────────────────────────────────────
  let finalStatus = 'sent';
  let finalError  = null;
  try {
    await transporter.sendMail({
      from:    process.env.EMAIL_FROM || process.env.EMAIL_USER,
      to:      process.env.ADMIN_DIGEST_EMAIL,
      subject: `Learnova Feedback Digest ${digestDate} — ${count} ticket${count !== 1 ? 's' : ''}`,
      html,
    });
    console.log('[digest]', digestDate, '— sent,', count, 'tickets');
  } catch (emailErr) {
    console.error('[digest] Email error:', emailErr.message);
    finalStatus = 'failed';
    finalError  = emailErr.message.slice(0, 500);
  }

  await supabase.from('digest_log')
    .update({
      delivery_status: finalStatus,
      tickets_count:   count,
      sent_at:         new Date().toISOString(),
      error_message:   finalError,
    })
    .eq('digest_date', digestDate);
}

export function startDailyDigest(supabase) {
  if (!process.env.EMAIL_HOST || !process.env.ADMIN_DIGEST_EMAIL) {
    console.warn('[digest] EMAIL_HOST or ADMIN_DIGEST_EMAIL not set — digest disabled');
    return;
  }

  const transporter = nodemailer.createTransport({
    host:   process.env.EMAIL_HOST,
    port:   parseInt(process.env.EMAIL_PORT || '587'),
    secure: process.env.EMAIL_PORT === '465',
    auth:   { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASS },
  });

  cron.schedule(
    '0 0 * * *',
    () => _runDigest(supabase, transporter).catch(e => console.error('[digest] Uncaught:', e.message)),
    { timezone: 'Asia/Kuala_Lumpur' }
  );
  console.log('[digest] Daily digest scheduled for 00:00 Asia/Kuala_Lumpur');
}
