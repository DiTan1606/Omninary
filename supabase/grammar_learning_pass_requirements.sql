-- Percentage-only update. Existing data and grants are preserved.
-- The size constraint is replaced atomically, retaining score/answer consistency.
create or replace function public.grammar_attempt_answers_valid(value jsonb)
returns boolean language sql immutable security invoker set search_path = '' as $$
  select case when pg_catalog.jsonb_typeof(value) = 'array' then
    pg_catalog.jsonb_array_length(value) between 1 and 500
    and pg_catalog.octet_length(value::text) <= 65536
    and not exists (
      select 1 from pg_catalog.jsonb_array_elements(value) item
      where pg_catalog.jsonb_typeof(item) is distinct from 'object'
        or pg_catalog.jsonb_typeof(item->'correct') is distinct from 'boolean'
        or pg_catalog.jsonb_typeof(item->'timedOut') is distinct from 'boolean'
        or (item->'correct' = 'true'::jsonb and item->'timedOut' = 'true'::jsonb)
        or exists (
          select 1 from (values ('questionID'),('prompt'),('stem'),('answer'),('correctAnswer')) required(key)
          where pg_catalog.jsonb_typeof(item->required.key) is distinct from 'string'
            or pg_catalog.length(item->>required.key) > 2000
        )
    ) else false end
$$;


alter table public.user_grammar_attempts drop constraint user_grammar_attempts_check;
alter table public.user_grammar_attempts add constraint user_grammar_attempts_check
 check(score between 0 and jsonb_array_length(answers) and score=public.grammar_attempt_score(answers));
create or replace function public.complete_grammar_attempt(
  p_user_id uuid, p_topic_id text, p_attempt jsonb, p_snapshot jsonb
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  result public.user_grammar_attempts%rowtype;
  progress jsonb;
  prior jsonb;
  earned boolean;
  attempt_id uuid;
  attempt_level text;
  attempt_release uuid;
  attempt_duration integer;
  expected_questions integer;
begin
  if current_user_id is null or current_user_id is distinct from p_user_id then
    raise exception 'Sign in to your own account.' using errcode = '42501';
  end if;
  attempt_id := (p_attempt->>'id')::uuid;
  attempt_level := p_attempt->>'level';
  attempt_duration := (p_attempt->>'duration')::integer;
  if attempt_id is null or attempt_level is null or attempt_duration is null
    or not public.grammar_attempt_answers_valid(p_attempt->'results')
    or p_snapshot #>> '{privateContent,gramV4,version}' is distinct from '4'
    or attempt_level not in ('easy','medium','hard')
    or jsonb_typeof(p_snapshot #> array['privateContent','gramV4','progress','done',attempt_level]) is distinct from 'boolean' then
    raise exception 'Invalid completed grammar attempt.' using errcode = '22023';
  end if;
  attempt_release := nullif(p_attempt->>'lessonVersion','')::uuid;
  if attempt_release is not null and not exists(select 1 from public.grammar_lesson_versions
    where id=attempt_release and topic_id=p_topic_id and published_at is not null) then
    raise exception 'Invalid lesson version.' using errcode='22023';
  end if;
  select jsonb_array_length(v.manifest#>array['course','exercises',attempt_level]) into expected_questions
    from public.grammar_lesson_versions v where v.id=coalesce(attempt_release,
      (select published_version from public.grammar_courses where topic_id=p_topic_id));
  if expected_questions is not null and jsonb_array_length(p_attempt->'results')<>expected_questions then
    raise exception 'The answer count must match the published question bank.' using errcode='22023';
  end if;
  insert into public.user_grammar_attempts (user_id,id,topic_id,level,duration_seconds,answers,score,lesson_version_id)
  values (current_user_id,attempt_id,p_topic_id,attempt_level,attempt_duration,p_attempt->'results',public.grammar_attempt_score(p_attempt->'results'),attempt_release)
  on conflict (user_id,id) do nothing;
  select * into strict result from public.user_grammar_attempts
    where user_id = current_user_id and id = attempt_id;
  if result.topic_id is distinct from p_topic_id or result.level is distinct from attempt_level
    or (attempt_release is not null and result.lesson_version_id is distinct from attempt_release)
    or result.answers is distinct from p_attempt->'results' or result.duration_seconds is distinct from attempt_duration then
    raise exception 'An attempt cannot be changed after completion.' using errcode = '22023';
  end if;
  select snapshot #> '{privateContent,gramV4,progress}' into prior
    from public.user_grammar_progress where user_id=current_user_id and topic_id=p_topic_id;
  prior:=coalesce(prior,'{}'::jsonb);
  earned:=(case when attempt_level='hard' then result.score=jsonb_array_length(result.answers) else result.score::bigint*100>jsonb_array_length(result.answers)::bigint*80 end) and
    case attempt_level when 'easy' then true
      when 'medium' then coalesce(prior#>'{done,easy}'='true'::jsonb,false)
      when 'hard' then coalesce(prior#>'{done,easy}'='true'::jsonb and prior#>'{done,medium}'='true'::jsonb,false)
      else false end;
  -- Only this attempt can earn a new level; other achievement flags come from storage.
  -- The existing update trigger merges concurrent saves and preserves earned stars.
  p_snapshot := jsonb_set(p_snapshot, '{privateContent,gramV4,progress}',
    (p_snapshot #> '{privateContent,gramV4,progress}') || jsonb_build_object(
      'done', coalesce(prior->'done', '{"easy":false,"medium":false,"hard":false}'::jsonb)
        || jsonb_build_object(attempt_level, earned),
      'best', coalesce(prior->'best', '{}'::jsonb)
        || jsonb_build_object(attempt_level, result.score)));
  insert into public.user_grammar_progress (user_id,topic_id,snapshot)
    values (current_user_id,p_topic_id,p_snapshot)
    on conflict (user_id,topic_id) do update set snapshot = excluded.snapshot
    returning snapshot into progress;
  return pg_catalog.jsonb_build_object('attempt',pg_catalog.to_jsonb(result),'snapshot',progress);
end
$$;
