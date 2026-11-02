-- Preserve the exact words where a learner used a hint in listening dictation.
-- Run this after listening_scoring_flow.sql.

begin;

alter table public.user_listening_progress
  add column if not exists hinted_word_indexes integer[] not null default '{}';

-- Existing progress stored only a count, so use a stable fallback for old attempts.
-- New attempts will store the real word indexes selected by the learner.
update public.user_listening_progress
set hinted_word_indexes = case
  when hinted_word_count <= 0 then '{}'
  else array(select generate_series(0, hinted_word_count - 1))
end
where cardinality(hinted_word_indexes) = 0
  and hinted_word_count > 0;

drop function if exists public.record_listening_segment_completion(uuid, integer, integer, integer);

create function public.record_listening_segment_completion(
  p_segment_id uuid,
  p_score integer,
  p_hinted_word_count integer,
  p_word_count integer,
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
  normalized_hint_indexes integer[] := coalesce(p_hinted_word_indexes, '{}');
  hint_count integer;
  distinct_hint_count integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select count(*), count(distinct hint_index)
  into hint_count, distinct_hint_count
  from unnest(normalized_hint_indexes) as hints(hint_index);

  if p_score not between 0 and 100
    or p_word_count <= 0
    or p_hinted_word_count < 0
    or p_hinted_word_count > p_word_count
    or hint_count <> distinct_hint_count
    or hint_count <> p_hinted_word_count
    or exists (
      select 1
      from unnest(normalized_hint_indexes) as hints(hint_index)
      where hint_index < 0 or hint_index >= p_word_count
    ) then
    raise exception 'Invalid listening score data';
  end if;

  insert into public.user_listening_progress (
    user_id, segment_id, status, attempts, latest_score, best_score,
    hinted_word_count, hinted_word_indexes, word_count, completed_at, updated_at
  ) values (
    current_user_id, p_segment_id, 'completed', 1, p_score, p_score,
    p_hinted_word_count, normalized_hint_indexes, p_word_count, now_utc, now_utc
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

grant execute on function public.record_listening_segment_completion(uuid, integer, integer, integer, integer[]) to authenticated;
grant execute on function public.restart_listening_lesson(uuid) to authenticated;

commit;
