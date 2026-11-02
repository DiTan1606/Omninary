-- All writes are rolled back; existing learner achievements are not modified.
begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id::text from auth.users order by id limit 1),'role','authenticated')::text,true) is not null as test_identity_ready;
set local role authenticated;
do $$
declare
  t record; answers jsonb; attempt jsonb; snapshot jsonb; packet jsonb; again jsonb;
  topic text; idx integer := 0;
begin
  if auth.uid() is null then raise exception 'Test identity required'; end if;
  for t in select * from (values ('easy',0,16,false),('easy',12,16,false),('easy',13,16,true),('medium',12,16,false),('medium',13,16,true),('hard',15,16,false),('hard',16,16,true),('easy',8,10,false),('easy',9,10,true),('medium',16,20,false),('medium',17,20,true),('easy',20,25,false),('easy',21,25,true),('hard',19,20,false),('hard',20,20,true)) as cases(level,score,total,passed) loop
    idx:=idx+1; topic:='C2.'||(69+idx)::text;
    if exists(select 1 from public.user_grammar_progress where user_id=auth.uid() and topic_id=topic) then raise exception 'Reserved test topic already contains data'; end if;
    if t.level<>'easy' then
      insert into public.user_grammar_progress(user_id,topic_id,snapshot) values(auth.uid(),topic,
        jsonb_set('{"privateContent":{"gramV4":{"version":4,"progress":{"read":{},"done":{"easy":true,"medium":false,"hard":false},"best":{}}}}}',
          '{privateContent,gramV4,progress,done,medium}',to_jsonb(t.level='hard')));
    end if;
    select jsonb_agg(jsonb_build_object('questionID','test-'||i,'prompt','Choose.','stem','I ___ happy.','answer','am','correctAnswer','am','correct',i<=t.score,'timedOut',false) order by i) into answers from generate_series(1,t.total) i;
    attempt:=jsonb_build_object('id',gen_random_uuid(),'level',t.level,'duration',60,'results',answers);
    -- Deliberately lie about done and best to confirm the server derives both from answers.
    snapshot:='{"privateContent":{"gramV4":{"version":4,"progress":{"read":{},"done":{"easy":true,"medium":true,"hard":true},"best":{"easy":16,"medium":16,"hard":16}}}}}';
    packet:=public.complete_grammar_attempt(auth.uid(),topic,attempt,snapshot);
    if (packet#>>array['snapshot','privateContent','gramV4','progress','done',t.level])::boolean is distinct from t.passed then raise exception 'Wrong pass result: % %',t.level,t.score; end if;
    if (packet#>>array['snapshot','privateContent','gramV4','progress','best',t.level])::integer<>t.score then raise exception 'Best score did not come from answers'; end if;
    if (packet#>>'{attempt,score}')::integer<>t.score then raise exception 'Failed attempt not stored'; end if;
    if t.level='easy' and ((packet#>>'{snapshot,privateContent,gramV4,progress,done,medium}')::boolean or (packet#>>'{snapshot,privateContent,gramV4,progress,done,hard}')::boolean) then raise exception 'Client awarded unrelated levels'; end if;
    again:=public.complete_grammar_attempt(auth.uid(),topic,attempt,snapshot);
    if packet#>>'{attempt,completed_at}' is distinct from again#>>'{attempt,completed_at}' then raise exception 'Duplicate retry'; end if;
    -- A worse retry must preserve an already earned star.
    if t.passed then
      attempt:=jsonb_set(attempt,'{id}',to_jsonb(gen_random_uuid()::text));
      select jsonb_agg(jsonb_set(item,'{correct}','false'::jsonb)) into answers from jsonb_array_elements(answers) item;
      attempt:=jsonb_set(attempt,'{results}',answers);
      packet:=public.complete_grammar_attempt(auth.uid(),topic,attempt,snapshot);
      if packet#>>array['snapshot','privateContent','gramV4','progress','done',t.level]<>'true' then raise exception 'Earned star lost'; end if;
    end if;
  end loop;
end $$;
reset role;
rollback;
