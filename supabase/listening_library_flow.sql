-- Omninary listening library flow.
-- Run this once in Supabase SQL Editor after the base listening tables exist.

begin;

create table if not exists public.user_listening_lessons (
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_id uuid not null references public.listening_lessons(id) on delete cascade,
  is_in_learning boolean not null default false,
  downloaded_at timestamptz not null default timezone('utc', now()),
  learning_started_at timestamptz,
  completed_at timestamptz,
  primary key (user_id, lesson_id)
);

create index if not exists user_listening_lessons_user_downloaded_idx
  on public.user_listening_lessons(user_id, downloaded_at desc);

-- The original listening MVP stored progress per sentence. Keep that data model,
-- while making the (user_id, segment_id) conflict target explicit for upserts.
create table if not exists public.user_listening_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  segment_id uuid not null references public.listening_segments(id) on delete cascade,
  status text not null default 'completed',
  attempts integer not null default 0,
  best_score integer not null default 0,
  completed_at timestamptz,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, segment_id)
);

create unique index if not exists user_listening_progress_user_segment_key
  on public.user_listening_progress(user_id, segment_id);

alter table public.listening_lessons enable row level security;
alter table public.listening_segments enable row level security;
alter table public.user_listening_lessons enable row level security;
alter table public.user_listening_progress enable row level security;

drop policy if exists "Authenticated users read published listening lessons" on public.listening_lessons;
create policy "Authenticated users read published listening lessons"
on public.listening_lessons
for select to authenticated
using (is_published = true);

drop policy if exists "Authenticated users read segments of published listening lessons" on public.listening_segments;
create policy "Authenticated users read segments of published listening lessons"
on public.listening_segments
for select to authenticated
using (
  exists (
    select 1
    from public.listening_lessons lesson
    where lesson.id = lesson_id
      and lesson.is_published = true
  )
);

drop policy if exists "Users manage own listening library" on public.user_listening_lessons;
create policy "Users manage own listening library"
on public.user_listening_lessons
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users manage own listening progress" on public.user_listening_progress;
create policy "Users manage own listening progress"
on public.user_listening_progress
for all to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

grant select on public.listening_lessons, public.listening_segments to authenticated;
grant select, insert, update, delete on public.user_listening_lessons to authenticated;
grant select, insert, update, delete on public.user_listening_progress to authenticated;

commit;

-- Quick verification: after downloading a lesson in the app, this should show one row.
-- select * from public.user_listening_lessons order by downloaded_at desc;
