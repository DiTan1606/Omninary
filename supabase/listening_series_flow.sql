-- Omninary listening series flow.
-- Run this once in Supabase SQL Editor after listening_library_flow.sql.
-- Existing user downloads stay intact because the library continues to reference lesson IDs.

begin;

create table if not exists public.listening_series (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  vi_title text,
  description text,
  is_published boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.listening_lessons
  add column if not exists series_id uuid references public.listening_series(id) on delete restrict;

create index if not exists listening_lessons_series_created_idx
  on public.listening_lessons(series_id, created_at desc);

alter table public.listening_series enable row level security;

drop policy if exists "Authenticated users read published listening series" on public.listening_series;
create policy "Authenticated users read published listening series"
on public.listening_series
for select to authenticated
using (is_published = true);

grant select on public.listening_series to authenticated;

-- Backfill the first imported lesson into its first listening series.
insert into public.listening_series (slug, title, vi_title, is_published)
values ('im-mary', 'I''m Mary', 'Tôi là Mary', true)
on conflict (slug) do update
set
  title = excluded.title,
  vi_title = excluded.vi_title,
  is_published = excluded.is_published;

update public.listening_lessons as lesson
set series_id = series.id
from public.listening_series as series
where lesson.slug = 'are_you_a_workaholic'
  and series.slug = 'im-mary';

-- Deleting a downloaded lesson also clears its sentence progress. If that lesson is
-- downloaded again later, it correctly starts as a fresh lesson.
create or replace function public.remove_listening_lesson_from_library(p_lesson_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from user_listening_progress as progress
  using listening_segments as segment
  where progress.user_id = auth.uid()
    and progress.segment_id = segment.id
    and segment.lesson_id = p_lesson_id;

  delete from user_listening_lessons
  where user_id = auth.uid()
    and lesson_id = p_lesson_id;
end;
$$;

grant execute on function public.remove_listening_lesson_from_library(uuid) to authenticated;

commit;

-- Quick verification:
-- select series.title, lesson.title
-- from public.listening_series series
-- join public.listening_lessons lesson on lesson.series_id = series.id
-- order by series.title, lesson.created_at desc;
