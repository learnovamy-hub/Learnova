create table if not exists login_events (
  id uuid primary key default gen_random_uuid(),
  user_role text not null check (user_role in ('student', 'parent', 'teacher')),
  user_id uuid not null,
  email text,
  success boolean not null default true,
  login_time timestamptz not null default now(),
  browser text,
  user_agent text,
  ip_address text,
  created_at timestamptz not null default now()
);

create index if not exists idx_login_events_role_user_time
on login_events(user_role, user_id, login_time desc);

create table if not exists user_resume_state (
  id uuid primary key default gen_random_uuid(),
  user_role text not null check (user_role in ('student', 'parent', 'teacher')),
  user_id uuid not null,
  last_screen text,
  subject text,
  topic text,
  subtopic text,
  lesson_id uuid,
  quiz_id uuid,
  progress_percent integer default 0,
  updated_at timestamptz not null default now(),
  unique(user_role, user_id)
);

create index if not exists idx_user_resume_state_role_user
on user_resume_state(user_role, user_id);

create table if not exists user_activity_summary (
  id uuid primary key default gen_random_uuid(),
  user_role text not null check (user_role in ('student', 'parent', 'teacher')),
  user_id uuid not null,
  email text,
  first_login_at timestamptz,
  last_login_at timestamptz,
  login_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_role, user_id)
);

create index if not exists idx_user_activity_summary_role_user
on user_activity_summary(user_role, user_id);
