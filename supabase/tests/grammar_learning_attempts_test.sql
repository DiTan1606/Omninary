-- Transactional checks: nothing from this script remains in the learner's account.
begin;
do $$ begin
  perform set_config('grammar.test_user',(select id::text from auth.users order by id limit 1),true);
  perform set_config('grammar.test_attempt',gen_random_uuid()::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('grammar.test_user'),'role','authenticated')::text,true);
end $$;
set local role authenticated;
do $$
declare
  answers jsonb;
  attempt jsonb;
  snapshot jsonb := '{"privateContent":{"gramV4":{"version":4,"progress":{"read":{},"done":{"easy":true},"best":{"easy":13}}}}}';
  first_save jsonb;
  second_save jsonb;
  rolled_back_id uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'A signed-in test identity is required.'; end if;
  select jsonb_agg(jsonb_build_object('questionID','test-'||i,'prompt','Choose the form.','stem','I ___ a student.',
    'answer',case when i<=13 then 'am' else 'is' end,'correctAnswer','am','correct',i<=13,'timedOut',i=16) order by i)
    into answers from generate_series(1,16) i;
  attempt := jsonb_build_object('id',current_setting('grammar.test_attempt'),'level','easy','duration',120,'results',answers);
  first_save := public.complete_grammar_attempt(auth.uid(),'C2.99',attempt,snapshot);
  if first_save #>> '{attempt,score}' <> '13' or first_save #>> '{snapshot,privateContent,gramV4,progress,done,easy}' <> 'true'
    then raise exception 'The completed result and its star were not committed together.'; end if;
  second_save := public.complete_grammar_attempt(auth.uid(),'C2.99',attempt,snapshot);
  if first_save #>> '{attempt,completed_at}' <> second_save #>> '{attempt,completed_at}'
    or (select count(*) from public.user_grammar_attempts where id=current_setting('grammar.test_attempt')::uuid) <> 1
    then raise exception 'A retry created a duplicate attempt.'; end if;
  begin
    perform public.complete_grammar_attempt(auth.uid(),'C2.99',jsonb_set(attempt,'{results,0,stem}','"Changed"'),snapshot);
    raise exception 'A completed attempt was changed.';
  exception when invalid_parameter_value then null; end;
  begin
    update public.user_grammar_attempts set score=0 where id=current_setting('grammar.test_attempt')::uuid;
    raise exception 'Completed attempts were writable.';
  exception when insufficient_privilege then null; end;
  begin
    perform public.complete_grammar_attempt(auth.uid(),'C2.99',jsonb_set(attempt,'{id}',to_jsonb(rolled_back_id::text)),
      snapshot || jsonb_build_object('padding',repeat('x',40000)));
    raise exception 'An invalid progress record was accepted.';
  exception when check_violation then null; end;
  if exists(select 1 from public.user_grammar_attempts where id=rolled_back_id) then
    raise exception 'A failed transaction left an orphaned attempt.';
  end if;
  begin
    perform public.complete_grammar_attempt(auth.uid(),'C2.99',jsonb_set(attempt,'{results}','[]'::jsonb),snapshot);
    raise exception 'Incomplete answers were accepted.';
  exception when invalid_parameter_value then null; end;
  if has_table_privilege('authenticated','public.user_grammar_attempts','UPDATE')
    or has_table_privilege('anon','public.user_grammar_attempts','SELECT') then
    raise exception 'Unexpected table privileges.';
  end if;
end $$;
do $$ begin
  perform set_config('request.jwt.claims','{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}',true);
end $$;
do $$ begin
  if exists(select 1 from public.user_grammar_attempts where id=current_setting('grammar.test_attempt')::uuid) then
    raise exception 'Another account could read the result.';
  end if;
  begin
    perform public.complete_grammar_attempt(current_setting('grammar.test_user')::uuid,'C2.99','{}','{}');
    raise exception 'An RPC could write into another account.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform 1 from public.user_grammar_attempts limit 1;
    raise exception 'An anonymous visitor could read attempts.';
  exception when insufficient_privilege then null; end;
  begin
    perform public.complete_grammar_attempt(null,'C2.99','{}','{}');
    raise exception 'An anonymous visitor could invoke the completion function.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
