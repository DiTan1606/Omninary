-- Decimal listening scores, 80-point pass threshold, and server-verified word counts.
-- Run this after listening_scoring_flow.sql and listening_hint_indexes.sql.

begin;

alter table public.user_listening_progress
  add column if not exists hinted_word_indexes integer[] not null default '{}';

alter table public.user_listening_progress
  alter column latest_score type numeric(5,1) using round(latest_score::numeric, 1),
  alter column best_score type numeric(5,1) using round(best_score::numeric, 1);

alter table public.user_listening_lessons
  alter column latest_score type numeric(5,1) using round(latest_score::numeric, 1),
  alter column best_score type numeric(5,1) using round(best_score::numeric, 1);

-- Legacy attempts only stored a hint count. Preserve an equivalent stable fallback.
update public.user_listening_progress
set hinted_word_indexes = case
  when hinted_word_count <= 0 then '{}'
  else array(select generate_series(0, hinted_word_count - 1))
end
where cardinality(hinted_word_indexes) = 0
  and hinted_word_count > 0;

-- The segment's admin-controlled word_count becomes the source of truth.
with trusted_progress as (
  select
    progress.user_id,
    progress.segment_id,
    greatest(coalesce(segment.word_count, 0), 1) as trusted_word_count,
    coalesce(progress.hinted_word_indexes, '{}') as stored_hint_indexes
  from public.user_listening_progress as progress
  join public.listening_segments as segment on segment.id = progress.segment_id
), normalized_progress as (
  select
    user_id,
    segment_id,
    trusted_word_count,
    coalesce(array(
      select distinct hint_index
      from unnest(stored_hint_indexes) as hints(hint_index)
      where hint_index >= 0 and hint_index < trusted_word_count
      order by hint_index
    ), '{}') as trusted_hint_indexes
  from trusted_progress
)
update public.user_listening_progress as progress
set
  word_count = normalized.trusted_word_count,
  hinted_word_indexes = normalized.trusted_hint_indexes,
  hinted_word_count = cardinality(normalized.trusted_hint_indexes),
  latest_score = round(
    ((normalized.trusted_word_count - cardinality(normalized.trusted_hint_indexes))::numeric
      / normalized.trusted_word_count) * 100,
    1
  )
from normalized_progress as normalized
where progress.user_id = normalized.user_id
  and progress.segment_id = normalized.segment_id;

with lesson_scores as (
  select
    progress.user_id,
    segment.lesson_id,
    round(
      avg(
        (greatest(progress.word_count - progress.hinted_word_count, 0)::numeric
          / greatest(progress.word_count, 1)::numeric) * 100
      ),
      1
    )::numeric(5,1) as score
  from public.user_listening_progress as progress
  join public.listening_segments as segment on segment.id = progress.segment_id
  where progress.status = 'completed'
  group by progress.user_id, segment.lesson_id
)
update public.user_listening_lessons as user_lesson
set
  completed_at = case
    when lesson_scores.score >= 80.0 then coalesce(user_lesson.completed_at, timezone('utc', now()))
    else user_lesson.completed_at
  end,
  is_in_learning = case
    when user_lesson.completed_at is not null or lesson_scores.score >= 80.0 then false
    else user_lesson.is_in_learning
  end,
  latest_score = lesson_scores.score,
  best_score = greatest(user_lesson.best_score, lesson_scores.score)
from lesson_scores
where user_lesson.user_id = lesson_scores.user_id
  and user_lesson.lesson_id = lesson_scores.lesson_id;

drop function if exists public.record_listening_segment_completion(uuid, integer, integer, integer);
drop function if exists public.record_listening_segment_completion(uuid, integer, integer, integer, integer[]);
drop function if exists public.complete_listening_lesson(uuid);

create function public.record_listening_segment_completion(
  p_segment_id uuid,
  p_hinted_word_indexes integer[]
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  now_utc timestamptz := timezone('utc', now());
  trusted_word_count integer;
  normalized_hint_indexes integer[] := coalesce(p_hinted_word_indexes, '{}');
  hint_count integer;
  distinct_hint_count integer;
  calculated_score numeric(5,1);
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select greatest(coalesce(segment.word_count, 0), 0)
  into trusted_word_count
  from public.listening_segments as segment
  where segment.id = p_segment_id;

  if not found then
    raise exception 'Listening segment not found';
  end if;

  if trusted_word_count <= 0 then
    raise exception 'Listening segment has no valid word count';
  end if;

  if not exists (
    select 1
    from public.user_listening_lessons as user_lesson
    join public.listening_segments as segment on segment.lesson_id = user_lesson.lesson_id
    where user_lesson.user_id = current_user_id
      and segment.id = p_segment_id
  ) then
    raise exception 'Listening lesson is not in the user library';
  end if;

  select count(*), count(distinct hint_index)
  into hint_count, distinct_hint_count
  from unnest(normalized_hint_indexes) as hints(hint_index);

  if hint_count <> distinct_hint_count
    or exists (
      select 1
      from unnest(normalized_hint_indexes) as hints(hint_index)
      where hint_index < 0 or hint_index >= trusted_word_count
    ) then
    raise exception 'Invalid listening hint data';
  end if;

  calculated_score := round(
    ((trusted_word_count - hint_count)::numeric / trusted_word_count) * 100,
    1
  );

  insert into public.user_listening_progress (
    user_id, segment_id, status, attempts, latest_score, best_score,
    hinted_word_count, hinted_word_indexes, word_count, completed_at, updated_at
  ) values (
    current_user_id, p_segment_id, 'completed', 1, calculated_score, calculated_score,
    hint_count, normalized_hint_indexes, trusted_word_count, now_utc, now_utc
  )
  on conflict (user_id, segment_id) do update
  set
    status = 'completed',
    attempts = user_listening_progress.attempts + 1,
    latest_score = excluded.latest_score,
    best_score = greatest(user_listening_progress.best_score, excluded.latest_score),
    hinted_word_count = excluded.hinted_word_count,
    hinted_word_indexes = excluded.hinted_word_indexes,
    word_count = excluded.word_count,
    completed_at = now_utc,
    updated_at = now_utc;
end;
$$;

create function public.complete_listening_lesson(p_lesson_id uuid)
returns numeric(5,1)
language plpgsql
security invoker
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  total_segments integer;
  completed_segments integer;
  calculated_score numeric(5,1);
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
    ),
    1
  )::numeric(5,1)
  into calculated_score
  from public.user_listening_progress as progress
  join public.listening_segments as segment on segment.id = progress.segment_id
  where progress.user_id = current_user_id
    and segment.lesson_id = p_lesson_id
    and progress.status = 'completed';

  update public.user_listening_lessons
  set
    completed_at = case
      when calculated_score >= 80.0 then coalesce(completed_at, now_utc)
      else completed_at
    end,
    is_in_learning = case
      when completed_at is not null or calculated_score >= 80.0 then false
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
    latest_score = 0.0,
    hinted_word_count = 0,
    hinted_word_indexes = '{}',
    completed_at = null,
    updated_at = timezone('utc', now())
  from public.listening_segments as segment
  where progress.user_id = current_user_id
    and progress.segment_id = segment.id
    and segment.lesson_id = p_lesson_id;

  update public.user_listening_lessons
  set is_in_learning = completed_at is null
  where user_id = current_user_id
    and lesson_id = p_lesson_id;
end;
$$;

grant execute on function public.record_listening_segment_completion(uuid, integer[]) to authenticated;
grant execute on function public.complete_listening_lesson(uuid) to authenticated;
grant execute on function public.restart_listening_lesson(uuid) to authenticated;

commit;
