-- If you already ran an older script (IronLog or Repsheet), remove those empty tables first (uncomment these lines):
-- drop table if exists public.ironlog_entries, public.ironlog_custom_exercises, public.ironlog_profiles;
-- drop table if exists public.repsheet_entries, public.repsheet_custom_exercises, public.repsheet_profiles;

-- Record Breaker: run once in Supabase → SQL Editor → New query → Run.
-- Creates only tables prefixed "recordbreaker_". Your other app's tables are not touched.
-- Safe to run again.

-- 1. Profile per user (name, phone, dashboard preference)
create table if not exists public.recordbreaker_profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  phone      text not null,
  name       text not null default 'Athlete',
  prefs      jsonb not null default '{"view":"week"}',
  created_at timestamptz not null default now()
);

-- 2. Every exercise logged (one row = one exercise on one date, with its sets)
create table if not exists public.recordbreaker_entries (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  date       date not null,
  muscle     text not null,
  exercise   text not null,
  sets       jsonb not null default '[]' check (jsonb_typeof(sets) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists recordbreaker_entries_user_date on public.recordbreaker_entries (user_id, date);
create index if not exists recordbreaker_entries_user_ex   on public.recordbreaker_entries (user_id, lower(exercise));

-- 3. Exercises people type themselves ("not in the list")
create table if not exists public.recordbreaker_custom_exercises (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  muscle     text not null,
  name       text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists recordbreaker_custom_unique
  on public.recordbreaker_custom_exercises (user_id, muscle, lower(name));

-- 4. Security: each person can only see and change their own rows
alter table public.recordbreaker_profiles         enable row level security;
alter table public.recordbreaker_entries          enable row level security;
alter table public.recordbreaker_custom_exercises enable row level security;

drop policy if exists recordbreaker_profiles_own on public.recordbreaker_profiles;
create policy recordbreaker_profiles_own on public.recordbreaker_profiles
  for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists recordbreaker_entries_own on public.recordbreaker_entries;
create policy recordbreaker_entries_own on public.recordbreaker_entries
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists recordbreaker_custom_own on public.recordbreaker_custom_exercises;
create policy recordbreaker_custom_own on public.recordbreaker_custom_exercises
  for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- 5. Let logged-in users reach these tables through the app
--    (needed if "Automatically expose new tables" was turned off; harmless otherwise)
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.recordbreaker_profiles         to authenticated;
grant select, insert, update, delete on public.recordbreaker_entries          to authenticated;
grant select, insert, update, delete on public.recordbreaker_custom_exercises to authenticated;

-- 6. (added later) How a custom exercise is tracked: w = weight×reps, bw = reps, time = minutes, hold = seconds
alter table public.recordbreaker_custom_exercises add column if not exists kind text not null default 'w';
