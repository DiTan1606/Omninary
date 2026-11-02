-- Versioned lesson content. Apply after grammar_learning_progress.sql and grammar_learning_attempts.sql.
create table public.grammar_lesson_versions (
  id uuid primary key,
  topic_id text not null check (topic_id ~ '^(A1|A2|B1|B2|C1|C2)\.[1-9][0-9]?$'),
  renderer_version integer not null check (renderer_version = 1),
  manifest jsonb not null check (jsonb_typeof(manifest)='object' and octet_length(manifest::text)<=2097152),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  unique (topic_id,id)
);
create table public.grammar_lesson_audio (
  path text primary key,
  version_id uuid not null references public.grammar_lesson_versions(id),
  key text not null check (key ~ '^[a-zA-Z0-9_-]+\.mp3$'),
  sha256 text not null check (sha256 ~ '^[a-f0-9]{64}$'),
  byte_count integer not null check (byte_count between 1 and 10485760),
  unique (version_id,key)
);
create table public.grammar_courses (
  topic_id text primary key,
  title text not null check (length(title) between 1 and 200),
  title_vi text not null check (length(title_vi) between 1 and 300),
  part_ids text[] not null check (cardinality(part_ids) between 1 and 180),
  published_version uuid not null,
  renderer_version integer not null check (renderer_version=1),
  updated_at timestamptz not null default now(),
  foreign key (topic_id,published_version) references public.grammar_lesson_versions(topic_id,id)
);
create index grammar_courses_version_idx on public.grammar_courses(published_version);
alter table public.grammar_lesson_versions enable row level security;
alter table public.grammar_lesson_audio enable row level security;
alter table public.grammar_courses enable row level security;
revoke all on public.grammar_lesson_versions,public.grammar_lesson_audio,public.grammar_courses from public,anon,authenticated;
grant select on public.grammar_lesson_versions,public.grammar_lesson_audio,public.grammar_courses to authenticated;
grant all on public.grammar_lesson_versions,public.grammar_lesson_audio,public.grammar_courses to service_role;
create policy grammar_versions_read_published on public.grammar_lesson_versions for select to authenticated using (published_at is not null);
create policy grammar_audio_read_published on public.grammar_lesson_audio for select to authenticated using (
  exists(select 1 from public.grammar_lesson_versions v where v.id=version_id and v.published_at is not null)
);
create policy grammar_courses_read on public.grammar_courses for select to authenticated using (true);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('grammar-audio','grammar-audio',false,10485760,array['audio/mpeg']);
create policy grammar_audio_download_published on storage.objects for select to authenticated using (
  bucket_id='grammar-audio' and exists(select 1 from public.grammar_lesson_audio a where a.path=name)
);

create or replace function public.grammar_protect_published_content()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if tg_table_name='grammar_lesson_versions' then
    if old.published_at is not null then raise exception 'Published grammar versions are immutable.' using errcode='55000'; end if;
  elsif exists(select 1 from public.grammar_lesson_versions where id=old.version_id and published_at is not null) then
    raise exception 'Published grammar audio metadata is immutable.' using errcode='55000';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
create trigger grammar_versions_immutable before update or delete on public.grammar_lesson_versions
for each row execute function public.grammar_protect_published_content();
create trigger grammar_audio_immutable before update or delete on public.grammar_lesson_audio
for each row execute function public.grammar_protect_published_content();

create or replace function public.get_grammar_lesson(p_topic_id text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select pg_catalog.jsonb_build_object('version_id',v.id,'manifest_text',v.manifest::text,
    'manifest_sha256',pg_catalog.encode(extensions.digest(pg_catalog.convert_to(v.manifest::text,'UTF8'),'sha256'),'hex'))
  from public.grammar_courses c join public.grammar_lesson_versions v on v.id=c.published_version
  where c.topic_id=p_topic_id and v.published_at is not null
$$;

-- Only the publishing service may call this. Audio objects must already exist at their immutable paths.
create or replace function public.publish_grammar_lesson(p_manifest jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
  release_id uuid := (p_manifest->>'versionID')::uuid;
  topic text := p_manifest->>'topicID';
  course jsonb := p_manifest->'course';
  asset jsonb;
  part_ids text[];
  previous_ids text[];
  stored_manifest jsonb;
  expected_count integer;
begin
  if p_manifest->>'schemaVersion' is distinct from '1' or p_manifest->>'rendererVersion' is distinct from '1'
    or release_id is null or topic is null or jsonb_typeof(course) is distinct from 'object'
    or jsonb_typeof(course->'parts') is distinct from 'array'
    or jsonb_typeof(course->'contractionDemos') is distinct from 'array'
    or jsonb_typeof(p_manifest->'audioAssets') is distinct from 'array'
    or length(course->>'title') not between 1 and 200 or length(course->>'titleVi') not between 1 and 300 then
    raise exception 'Invalid grammar release.' using errcode='22023';
  end if;
  if exists(select 1 from (values ('easy'),('medium'),('hard')) levels(key)
    where jsonb_typeof(course->'exercises'->levels.key) is distinct from 'array'
    or jsonb_array_length(course->'exercises'->levels.key) not between 1 and 500) then
    raise exception 'Each difficulty needs between 1 and 500 questions.' using errcode='22023';
  end if;
  select array_agg(item->>'id' order by ordinal) into part_ids
    from jsonb_array_elements(course->'parts') with ordinality parts(item,ordinal);
  if cardinality(part_ids) not between 1 and 180
    or (select count(distinct id) from unnest(part_ids) id)<>cardinality(part_ids)
    or exists(select 1 from unnest(part_ids) id where id is null or id !~ '^[a-zA-Z0-9_-]{1,64}$') then
    raise exception 'Invalid or duplicate theory identifiers.' using errcode='22023';
  end if;
  -- Stable identifiers preserve previously earned progress across editorial updates.
  select c.part_ids into previous_ids from public.grammar_courses c where c.topic_id=topic for update;
  if previous_ids is not null and not (previous_ids @> part_ids and previous_ids <@ part_ids) then
    raise exception 'Keep published theory identifiers stable.' using errcode='22023';
  end if;
  expected_count:=jsonb_array_length(course->'parts')+jsonb_array_length(course->'contractionDemos');
  if jsonb_array_length(p_manifest->'audioAssets')<>expected_count
    or (select count(distinct a->>'key') from jsonb_array_elements(p_manifest->'audioAssets') a)<>expected_count
    or exists(select 1 from jsonb_array_elements((course->'parts')||(course->'contractionDemos')) track
      where not exists(select 1 from jsonb_array_elements(p_manifest->'audioAssets') a where a->>'key'=track#>>'{audioInfo,audioFile}')) then
    raise exception 'Audio and lesson tracks do not match.' using errcode='22023';
  end if;
  select manifest into stored_manifest from public.grammar_lesson_versions where id=release_id;
  if found then
    if stored_manifest is distinct from p_manifest then raise exception 'A release identifier cannot be reused.' using errcode='22023'; end if;
  else
    insert into public.grammar_lesson_versions(id,topic_id,renderer_version,manifest) values(release_id,topic,1,p_manifest);
    for asset in select value from jsonb_array_elements(p_manifest->'audioAssets') loop
      if asset->>'path' is distinct from topic||'/'||release_id::text||'/'||(asset->>'key')
        or asset->>'mimeType' is distinct from 'audio/mpeg'
        or not exists(select 1 from storage.objects o where o.bucket_id='grammar-audio' and o.name=asset->>'path'
          and (o.metadata->>'size')::bigint=(asset->>'byteCount')::bigint) then
        raise exception 'An audio file is missing or has the wrong size.' using errcode='22023';
      end if;
      insert into public.grammar_lesson_audio(path,version_id,key,sha256,byte_count)
        values(asset->>'path',release_id,asset->>'key',asset->>'sha256',(asset->>'byteCount')::integer);
    end loop;
    update public.grammar_lesson_versions set published_at=now() where id=release_id;
  end if;
  insert into public.grammar_courses(topic_id,title,title_vi,part_ids,published_version,renderer_version)
    values(topic,course->>'title',course->>'titleVi',part_ids,release_id,1)
    on conflict(topic_id) do update set title=excluded.title,title_vi=excluded.title_vi,
      part_ids=excluded.part_ids,published_version=excluded.published_version,renderer_version=excluded.renderer_version,updated_at=now();
  return jsonb_build_object('topic_id',topic,'version_id',release_id,'audio_count',expected_count,'published',true);
end $$;
revoke all on function public.get_grammar_lesson(text) from public,anon;
grant execute on function public.get_grammar_lesson(text) to authenticated,service_role;
revoke all on function public.publish_grammar_lesson(jsonb) from public,anon,authenticated;
grant execute on function public.publish_grammar_lesson(jsonb) to service_role;
revoke all on function public.grammar_protect_published_content() from public,anon,authenticated;
grant execute on function public.grammar_protect_published_content() to service_role;

alter table public.user_grammar_attempts add column lesson_version_id uuid references public.grammar_lesson_versions(id);
create index user_grammar_attempts_lesson_version_idx on public.user_grammar_attempts(lesson_version_id) where lesson_version_id is not null;

-- Keep older installed clients compatible; new attempts also record the pinned lesson version.
create or replace function public.complete_grammar_attempt(
  p_user_id uuid, p_topic_id text, p_attempt jsonb, p_snapshot jsonb
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  result public.user_grammar_attempts%rowtype;
  progress jsonb;
  attempt_id uuid;
  attempt_level text;
  attempt_release uuid;
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
  attempt_release := nullif(p_attempt->>'lessonVersion','')::uuid;
  if attempt_release is not null and not exists(select 1 from public.grammar_lesson_versions
    where id=attempt_release and topic_id=p_topic_id and published_at is not null) then
    raise exception 'Invalid lesson version.' using errcode='22023';
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
  insert into public.user_grammar_progress (user_id,topic_id,snapshot)
    values (current_user_id,p_topic_id,p_snapshot)
    on conflict (user_id,topic_id) do update set snapshot = excluded.snapshot
    returning snapshot into progress;
  return pg_catalog.jsonb_build_object('attempt',pg_catalog.to_jsonb(result),'snapshot',progress);
end
$$;

