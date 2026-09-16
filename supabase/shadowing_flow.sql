-- Omninary Shadowing flow.
-- Run this after listening_library_flow.sql and listening_secure_decimal_scoring.sql.
-- The Edge Function owns score writes after Azure verifies the recording.

begin;

alter table public.user_listening_lessons
  add column if not exists is_in_shadowing boolean not null default false,
  add column if not exists shadowing_started_at timestamptz,
  add column if not exists shadowing_completed_at timestamptz,
  add column if not exists shadowing_latest_score numeric(5,1) not null default 0,
  add column if not exists shadowing_best_score numeric(5,1) not null default 0;

create table if not exists public.user_shadowing_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  segment_id uuid not null references public.listening_segments(id) on delete cascade,
  status text not null default 'practicing' check (status in ('practicing', 'passed')),
  attempts integer not null default 0 check (attempts >= 0),
  latest_score numeric(5,1) not null default 0,
  best_score numeric(5,1) not null default 0,
  accuracy_score numeric(5,1) not null default 0,
  fluency_score numeric(5,1) not null default 0,
  completeness_score numeric(5,1) not null default 0,
  passed_at timestamptz,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, segment_id)
);

create index if not exists user_shadowing_progress_user_updated_idx
  on public.user_shadowing_progress(user_id, updated_at desc);

-- `user_listening_lessons` is intentionally still user-writable for download and
-- start actions. The assessment scores and completion timestamp, however, can
-- only be written by the service-role Edge Function after Azure replies.
create or replace function public.protect_shadowing_lesson_scores()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if auth.role() = 'authenticated' then
    if tg_op = 'INSERT' and (
      new.shadowing_completed_at is not null
      or coalesce(new.shadowing_latest_score, 0) <> 0
      or coalesce(new.shadowing_best_score, 0) <> 0
    ) then
      raise exception 'Shadowing scores are server-managed';
    end if;

    if tg_op = 'UPDATE' and (
      new.shadowing_completed_at is distinct from old.shadowing_completed_at
      or new.shadowing_latest_score is distinct from old.shadowing_latest_score
      or new.shadowing_best_score is distinct from old.shadowing_best_score
    ) then
      raise exception 'Shadowing scores are server-managed';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists protect_shadowing_lesson_scores on public.user_listening_lessons;
create trigger protect_shadowing_lesson_scores
before insert or update on public.user_listening_lessons
for each row execute function public.protect_shadowing_lesson_scores();

alter table public.user_shadowing_progress enable row level security;

drop policy if exists "Users read own shadowing progress" on public.user_shadowing_progress;
create policy "Users read own shadowing progress"
on public.user_shadowing_progress
for select to authenticated
using (auth.uid() = user_id);

-- Scores originate only from the authenticated Edge Function after Azure returns
-- its assessment. Clients may read their data but cannot create or alter scores.
revoke insert, update, delete on table public.user_shadowing_progress from anon, authenticated;
grant select on table public.user_shadowing_progress to authenticated;

commit;

-- Quick verification after completing one shadowing sentence:
-- select * from public.user_shadowing_progress order by updated_at desc;
