-- Kiểm chứng trên dự án đang kết nối; mọi dữ liệu thử đều được hoàn tác.
begin;
select set_config('grammar.test_user', (select id::text from auth.users order by id limit 1), true);
select set_config('request.jwt.claims', jsonb_build_object('sub', current_setting('grammar.test_user'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare saved jsonb;
begin
    if auth.uid() is null then raise exception 'Cần một tài khoản đã tồn tại để kiểm chứng'; end if;
    insert into public.user_grammar_progress(user_id, topic_id, snapshot) values (
        auth.uid(), 'C2.99', '{"privateContent":{"gramV4":{"version":4,"question":1,"progress":{"read":{"0-0":true},"done":{"easy":true},"best":{"easy":12}}}}}'
    );
    select snapshot into strict saved from public.user_grammar_progress where user_id=auth.uid() and topic_id='C2.99';
    if saved #>> '{privateContent,gramV4,question}' <> '1' then raise exception 'Không đọc được tiến độ vừa lưu'; end if;
    insert into public.user_grammar_progress(user_id, topic_id, snapshot) values (
        auth.uid(), 'C2.99', '{"privateContent":{"gramV4":{"version":4,"question":3,"deadline":1800000000000,"progress":{"read":{"1-0":true},"done":{"easy":false},"best":{"easy":9}}}}}'
    ) on conflict(user_id,topic_id) do update set snapshot=excluded.snapshot;
    select snapshot into strict saved from public.user_grammar_progress where user_id=auth.uid() and topic_id='C2.99';
    if saved #>> '{privateContent,gramV4,progress,read,0-0}' <> 'true'
        or saved #>> '{privateContent,gramV4,progress,read,1-0}' <> 'true'
        or saved #>> '{privateContent,gramV4,progress,done,easy}' <> 'true'
        or saved #>> '{privateContent,gramV4,progress,best,easy}' <> '12'
        or saved #>> '{privateContent,gramV4,question}' <> '3'
        or saved #>> '{privateContent,gramV4,deadline}' <> '1800000000000'
    then raise exception 'Lần lưu sau làm mất thành tích hoặc câu đang làm'; end if;
    begin
        update public.user_grammar_progress set user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' where topic_id='C2.99';
        raise exception 'Đã cho phép đổi chủ sở hữu';
    exception when insufficient_privilege then null; end;
    begin
        insert into public.user_grammar_progress(user_id, topic_id, snapshot) values (auth.uid(),'C2.98','{}');
        raise exception 'Đã chấp nhận dữ liệu sai định dạng';
    exception when check_violation then null; end;
end $$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
do $$
begin
    if exists(select 1 from public.user_grammar_progress where topic_id='C2.99') then raise exception 'Đọc được tiến độ của tài khoản khác'; end if;
    update public.user_grammar_progress set updated_at=now() where topic_id='C2.99';
    if found then raise exception 'Sửa được tiến độ của tài khoản khác'; end if;
    begin
        insert into public.user_grammar_progress(user_id,topic_id,snapshot) values (
            current_setting('grammar.test_user')::uuid,'C2.97','{"privateContent":{"gramV4":{"version":4,"progress":{}}}}'
        );
        raise exception 'Ghi được tiến độ cho tài khoản khác';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
    begin
        perform 1 from public.user_grammar_progress limit 1;
        raise exception 'Khách chưa đăng nhập đọc được dữ liệu';
    exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
