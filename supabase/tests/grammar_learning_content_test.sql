-- Read-only published-content checks, plus rejected writes inside a rolled-back transaction.
begin;
do $$ begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',(select id::text from auth.users order by id limit 1),'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$
declare packet jsonb; document jsonb; release uuid; audio_count integer;
begin
  packet:=public.get_grammar_lesson('A1.1');
  if packet is null then raise exception 'The published lesson is not readable.'; end if;
  document:=(packet->>'manifest_text')::jsonb;release:=(packet->>'version_id')::uuid;
  if packet->>'manifest_sha256' is distinct from encode(extensions.digest(convert_to(packet->>'manifest_text','UTF8'),'sha256'),'hex')
    or document->>'versionID' is distinct from release::text then raise exception 'Manifest integrity failed.'; end if;
  if jsonb_array_length(document#>'{course,parts}')<>27
    or jsonb_array_length(document#>'{course,contractionDemos}')<>10
    or jsonb_array_length(document->'audioAssets')<>37
    or jsonb_array_length(document#>'{course,teachingRules,pronouns}')<>7
    or jsonb_array_length(document#>'{course,teachingRules,contractions}')<>10
    then raise exception 'Published learning content is incomplete.'; end if;
  if exists(select 1 from (values ('easy',20),('medium',30),('hard',28)) levels(key,expected)
    where jsonb_array_length(document->'course'->'exercises'->levels.key)<>levels.expected) then raise exception 'The exercise banks are incomplete.'; end if;
  select count(*) into audio_count from storage.objects where bucket_id='grammar-audio' and name like 'A1.1/'||release::text||'/%';
  if audio_count<>37 then raise exception 'A signed-in learner cannot read all published audio.'; end if;
  if exists(select 1 from jsonb_array_elements(document->'audioAssets') asset
    where not exists(select 1 from public.grammar_lesson_audio a join storage.objects o on o.name=a.path and o.bucket_id='grammar-audio'
      where a.version_id=release and a.path=asset->>'path' and a.sha256=asset->>'sha256'
      and a.byte_count=(asset->>'byteCount')::integer and (o.metadata->>'size')::integer=a.byte_count))
    then raise exception 'The published audio metadata does not match its objects.'; end if;
  begin
    update public.grammar_courses set title='Unauthorized change' where topic_id='A1.1';
    raise exception 'A learner could change lesson content.';
  exception when insufficient_privilege then null; end;
  begin
    perform public.publish_grammar_lesson(document);
    raise exception 'A learner could publish content.';
  exception when insufficient_privilege then null; end;
  if (select public from storage.buckets where id='grammar-audio') then raise exception 'The audio bucket is public.'; end if;
end $$;
reset role;
set local role service_role;
do $$ begin
  begin
    update public.grammar_lesson_versions set manifest=jsonb_set(manifest,'{course,title}','"Changed"')
      where id=(select published_version from public.grammar_courses where topic_id='A1.1');
    raise exception 'A published version could be overwritten.';
  exception when object_not_in_prerequisite_state then null; end;
  begin
    update public.grammar_lesson_audio set sha256=repeat('0',64)
      where version_id=(select published_version from public.grammar_courses where topic_id='A1.1');
    raise exception 'Published audio metadata could be overwritten.';
  exception when object_not_in_prerequisite_state then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform public.get_grammar_lesson('A1.1');
    raise exception 'An anonymous visitor could fetch lesson content.';
  exception when insufficient_privilege then null; end;
  begin
    perform 1 from public.grammar_courses;
    raise exception 'An anonymous visitor could read the catalog.';
  exception when insufficient_privilege then null; end;
  if exists(select 1 from storage.objects where bucket_id='grammar-audio') then raise exception 'Anonymous access to audio objects is allowed.'; end if;
end $$;
reset role;
rollback;
