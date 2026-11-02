-- Omninary listening dictation scoring.
-- Run this once after listening_library_flow.sql and listening_series_flow.sql.

begin;

alter table public.user_listening_progress
  add column if not exists latest_score integer not null default 0,
  add column if not exists hinted_word_count integer not null default 0,
  add column if not exists word_count integer not null default 0;

alter table public.user_listening_lessons
  add column if not exists latest_score integer not null default 0,
  add column if not exists best_score integer not null default 0;

-- Progress created by the first MVP represented a fully correct sentence.
update public.user_listening_progress as progress
set
  latest_score = progress.best_score,
  hinted_word_count = 0,
  word_count = greatest(coalesce(segment.word_count, 0), 1)
from public.listening_segments as segment
where segment.id = progress.segment_id
  and progress.word_count = 0;

with lesson_scores as (
  select
    progress.user_id,
    segment.lesson_id,
    round(
      avg(
        (greatest(progress.word_count - progress.hinted_word_count, 0)::numeric
          / greatest(progress.word_count, 1)::numeric) * 100
      )
    )::integer as score
  from public.user_listening_progress as progress
  join public.listening_segments as segment on segment.id = progress.segment_id
  where progress.status = 'completed'
  group by progress.user_id, segment.lesson_id
)
update public.user_listening_lessons as user_lesson
set
  latest_score = lesson_scores.score,
  best_score = greatest(user_lesson.best_score, lesson_scores.score)
from lesson_scores
where user_lesson.user_id = lesson_scores.user_id
  and user_lesson.lesson_id = lesson_scores.lesson_id
  and user_lesson.completed_at is not null;

update public.user_listening_lessons
set is_in_learning = false
where completed_at is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'user_listening_progress_score_range'
      and conrelid = 'public.user_listening_progress'::regclass
  ) then
    alter table public.user_listening_progress
      add constraint user_listening_progress_score_range
      check (latest_score between 0 and 100 and best_score between 0 and 100);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'user_listening_progress_word_counts_valid'
      and conrelid = 'public.user_listening_progress'::regclass
  ) then
    alter table public.user_listening_progress
      add constraint user_listening_progress_word_counts_valid
      check (
        word_count >= 0
        and hinted_word_count >= 0
        and hinted_word_count <= word_count
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'user_listening_lessons_score_range'
      and conrelid = 'public.user_listening_lessons'::regclass
  ) then
    alter table public.user_listening_lessons
      add constraint user_listening_lessons_score_range
      check (latest_score between 0 and 100 and best_score between 0 and 100);
  end if;
end;
$$;

create or replace function public.record_listening_segment_completion(
  p_segment_id uuid,
  p_score integer,
  p_hinted_word_count integer,
  p_word_count integer
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  now_utc timestamptz := timezone('utc', now());
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_score not between 0 and 100
    or p_word_count <= 0
    or p_hinted_word_count < 0
    or p_hinted_word_count > p_word_count then
    raise exception 'Invalid listening score data';
  end if;

  insert into public.user_listening_progress (
    user_id,
    segment_id,
    status,
    attempts,
    latest_score,
    best_score,
    hinted_word_count,
    word_count,
    completed_at,
    updated_at
  ) values (
    current_user_id,
    p_segment_id,
    'completed',
    1,
    p_score,
    p_score,
    p_hinted_word_count,
    p_word_count,
    now_utc,
    now_utc
  )
  on conflict (user_id, segment_id) do update
  set
    status = 'completed',
    attempts = user_listening_progress.attempts + 1,
    latest_score = excluded.latest_score,
    best_score = greatest(user_listening_progress.best_score, excluded.latest_score),
    hinted_word_count = excluded.hinted_word_count,
    word_count = excluded.word_count,
    completed_at = now_utc,
    updated_at = now_utc;
end;
$$;

create or replace function public.complete_listening_lesson(p_lesson_id uuid)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  total_segments integer;
  completed_segments integer;
  calculated_score integer;
  now_utc timestamptz := timezone('utc', now());
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.user_listening_lessons
    where user_id = current_user_id and lesson_id = p_lesson_id
  ) then
    raise exception 'Listening lesson is not in the user library';
  end if;

  select
    count(*),
    count(*) filter (where progress.status = 'completed')
  into total_segments, completed_segments
  from public.listening_segments as segment
  left join public.user_listening_progress as progress
    on progress.segment_id = segment.id
   and progress.user_id = current_user_id
  where segment.lesson_id = p_lesson_id;

  if total_segments = 0 or completed_segments <> total_segments then
    raise exception 'All listening sentences must be completed first';
  end if;

  select round(
    avg(
      (greatest(progress.word_count - progress.hinted_word_count, 0)::numeric
        / greatest(progress.word_count, 1)::numeric) * 100
    )
  )::integer
  into calculated_score
  from public.user_listening_progress as progress
  join public.listening_segments as segment on segment.id = progress.segment_id
  where progress.user_id = current_user_id
    and segment.lesson_id = p_lesson_id
    and progress.status = 'completed';

  update public.user_listening_lessons
  set
    completed_at = case
      when calculated_score >= 90 then coalesce(completed_at, now_utc)
      else completed_at
    end,
    is_in_learning = case
      when completed_at is not null or calculated_score >= 90 then false
      else true
    end,
    latest_score = calculated_score,
    best_score = greatest(best_score, calculated_score)
  where user_id = current_user_id
    and lesson_id = p_lesson_id;

  return calculated_score;
end;
$$;

create or replace function public.restart_listening_lesson(p_lesson_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  update public.user_listening_progress as progress
  set
    status = 'pending',
    latest_score = 0,
    hinted_word_count = 0,
    completed_at = null,
    updated_at = timezone('utc', now())
  from public.listening_segments as segment
  where progress.user_id = current_user_id
    and progress.segment_id = segment.id
    and segment.lesson_id = p_lesson_id;

  update public.user_listening_lessons
  set
    is_in_learning = completed_at is null
  where user_id = current_user_id
    and lesson_id = p_lesson_id;
end;
$$;

grant execute on function public.record_listening_segment_completion(uuid, integer, integer, integer) to authenticated;
grant execute on function public.complete_listening_lesson(uuid) to authenticated;
grant execute on function public.restart_listening_lesson(uuid) to authenticated;

commit;
