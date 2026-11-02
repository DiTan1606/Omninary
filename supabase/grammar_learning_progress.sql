-- Tiến độ ngữ pháp theo tài khoản. Không lưu tiến độ vào bộ nhớ bền vững trên thiết bị.
begin;

create table if not exists public.user_grammar_progress (
    user_id uuid not null references auth.users(id) on delete cascade,
    topic_id text not null check (topic_id ~ '^(A[12]|B[12]|C[12])\.[1-9][0-9]?$'),
    snapshot jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id, topic_id),
    constraint grammar_snapshot_shape check (
        coalesce(jsonb_typeof(snapshot) = 'object'
            and snapshot #>> '{privateContent,gramV4,version}' = '4'
            and jsonb_typeof(snapshot #> '{privateContent,gramV4,progress}') = 'object', false)
        and octet_length(snapshot::text) <= 32768
    )
);

alter table public.user_grammar_progress enable row level security;
revoke all on public.user_grammar_progress from anon, authenticated;
grant select, insert, update on public.user_grammar_progress to authenticated;
grant all on public.user_grammar_progress to service_role;

drop policy if exists grammar_select_own on public.user_grammar_progress;
create policy grammar_select_own on public.user_grammar_progress for select to authenticated
    using ((select auth.uid()) = user_id);
drop policy if exists grammar_insert_own on public.user_grammar_progress;
create policy grammar_insert_own on public.user_grammar_progress for insert to authenticated
    with check ((select auth.uid()) = user_id);
drop policy if exists grammar_update_own on public.user_grammar_progress;
create policy grammar_update_own on public.user_grammar_progress for update to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Giữ các phần đã học, mức đã hoàn thành và điểm cao nhất khi hai thiết bị cùng lưu.
-- Câu đang làm, câu trả lời và hạn giờ lấy theo lần lưu mới nhất.
create or replace function public.grammar_preserve_achievements()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare
    prior jsonb := old.snapshot #> '{privateContent,gramV4,progress}';
    incoming jsonb := new.snapshot #> '{privateContent,gramV4,progress}';
    merged jsonb;
    read_parts jsonb;
    completed jsonb;
    best_scores jsonb;
begin
    select coalesce(jsonb_object_agg(k, true), '{}'::jsonb) into read_parts
    from (
        select key as k from jsonb_each(coalesce(prior->'read', '{}'::jsonb)) where value = 'true'::jsonb
        union
        select key as k from jsonb_each(coalesce(incoming->'read', '{}'::jsonb)) where value = 'true'::jsonb
    ) as parts;
    select jsonb_object_agg(level, coalesce(prior->'done'->level = 'true'::jsonb, false)
        or coalesce(incoming->'done'->level = 'true'::jsonb, false)) into completed
    from unnest(array['easy','medium','hard']) as levels(level);
    select jsonb_object_agg(level, greatest(
        case when jsonb_typeof(prior->'best'->level) = 'number' then (prior->'best'->>level)::numeric else 0 end,
        case when jsonb_typeof(incoming->'best'->level) = 'number' then (incoming->'best'->>level)::numeric else 0 end
    )) into best_scores from unnest(array['easy','medium','hard']) as levels(level);
    merged := incoming || jsonb_build_object('read', read_parts, 'done', completed, 'best', best_scores);
    new.snapshot := jsonb_set(new.snapshot, '{privateContent,gramV4,progress}', merged);
    new.created_at := old.created_at;
    new.updated_at := now();
    return new;
end;
$$;
revoke all on function public.grammar_preserve_achievements() from public, anon;
grant execute on function public.grammar_preserve_achievements() to authenticated, service_role;
drop trigger if exists grammar_preserve_achievements on public.user_grammar_progress;
create trigger grammar_preserve_achievements before update on public.user_grammar_progress
    for each row execute function public.grammar_preserve_achievements();

comment on table public.user_grammar_progress is 'Tiến độ, sao, câu trả lời và thời hạn từng câu của bài ngữ pháp; mỗi tài khoản chỉ đọc/ghi hàng của mình.';
commit;
