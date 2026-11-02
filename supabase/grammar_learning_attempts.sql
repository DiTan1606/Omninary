-- Completed grammar attempts are immutable and belong to the signed-in learner.
-- Apply after grammar_learning_progress.sql. The existing v4 progress shape stays compatible.
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

create or replace function public.grammar_attempt_score(value jsonb)
returns smallint language sql immutable security invoker set search_path = '' as $$
  select case when pg_catalog.jsonb_typeof(value) = 'array' then
    (select pg_catalog.count(*)::smallint from pg_catalog.jsonb_array_elements(value) item
     where item->'correct' = 'true'::jsonb and item->'timedOut' = 'false'::jsonb)
    else null end
$$;

create table public.user_grammar_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  id uuid not null,
  topic_id text not null check (topic_id ~ '^(A1|A2|B1|B2|C1|C2)\.[1-9][0-9]?$'),
  level text not null check (level in ('easy','medium','hard')),
  content_version integer not null default 1 check (content_version > 0),
  completed_at timestamptz not null default pg_catalog.now(),
  duration_seconds integer not null check (duration_seconds between 0 and 604800),
  answers jsonb not null check (public.grammar_attempt_answers_valid(answers)),
  score smallint not null check (score between 0 and pg_catalog.jsonb_array_length(answers) and score = public.grammar_attempt_score(answers)),
  primary key (user_id, id)
);
create index user_grammar_attempts_topic_date_idx
  on public.user_grammar_attempts (user_id, topic_id, completed_at desc, id desc);
alter table public.user_grammar_attempts enable row level security;
revoke all on public.user_grammar_attempts from public, anon, authenticated;
grant select, insert on public.user_grammar_attempts to authenticated;
grant all on public.user_grammar_attempts to service_role;
create policy grammar_attempts_select_own on public.user_grammar_attempts
  for select to authenticated using ((select auth.uid()) = user_id);
create policy grammar_attempts_insert_own on public.user_grammar_attempts
  for insert to authenticated with check ((select auth.uid()) = user_id);

-- The result and the newly earned star commit together. Retrying the same UUID is idempotent.
create or replace function public.complete_grammar_attempt(
  p_user_id uuid, p_topic_id text, p_attempt jsonb, p_snapshot jsonb
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  result public.user_grammar_attempts%rowtype;
  progress jsonb;
  attempt_id uuid;
  attempt_level text;
  attempt_duration integer;
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
    or p_snapshot #> array['privateContent','gramV4','progress','done',attempt_level] is distinct from 'true'::jsonb then
    raise exception 'Invalid completed grammar attempt.' using errcode = '22023';
  end if;
  insert into public.user_grammar_attempts (user_id,id,topic_id,level,duration_seconds,answers,score)
  values (current_user_id,attempt_id,p_topic_id,attempt_level,attempt_duration,p_attempt->'results',public.grammar_attempt_score(p_attempt->'results'))
  on conflict (user_id,id) do nothing;
  select * into strict result from public.user_grammar_attempts
    where user_id = current_user_id and id = attempt_id;
  if result.topic_id is distinct from p_topic_id or result.level is distinct from attempt_level
    or result.answers is distinct from p_attempt->'results' or result.duration_seconds is distinct from attempt_duration then
    raise exception 'An attempt cannot be changed after completion.' using errcode = '22023';
  end if;
  insert into public.user_grammar_progress (user_id,topic_id,snapshot)
    values (current_user_id,p_topic_id,p_snapshot)
    on conflict (user_id,topic_id) do update set snapshot = excluded.snapshot
    returning snapshot into progress;
  return pg_catalog.jsonb_build_object('attempt',pg_catalog.to_jsonb(result),'snapshot',progress);
end
$$;

revoke all on function public.grammar_attempt_answers_valid(jsonb) from public, anon;
revoke all on function public.grammar_attempt_score(jsonb) from public, anon;
revoke all on function public.complete_grammar_attempt(uuid,text,jsonb,jsonb) from public, anon;
grant execute on function public.grammar_attempt_answers_valid(jsonb) to authenticated, service_role;
grant execute on function public.grammar_attempt_score(jsonb) to authenticated, service_role;
grant execute on function public.complete_grammar_attempt(uuid,text,jsonb,jsonb) to authenticated, service_role;
comment on table public.user_grammar_attempts is 'Immutable completed grammar exercises. Answers keep the original question and correction for historical review.';
