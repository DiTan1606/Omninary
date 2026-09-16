-- User-web support policies for OmninaryWeb.
-- Run this after the private topic/contribution migrations.

with ranked_duplicates as (
  select
    id,
    row_number() over (
      partition by user_id, vocab_id
      order by
        coalesce(learning_level, 0) desc,
        coalesce(pronunciation_score, 0) desc,
        saved_at asc nulls last,
        id
    ) as duplicate_rank
  from public.user_vocabulary
  where user_id is not null
    and vocab_id is not null
)
delete from public.user_vocabulary uv
using ranked_duplicates rd
where uv.id = rd.id
  and rd.duplicate_rank > 1;

create unique index if not exists user_vocabulary_one_row_per_user_vocab
on public.user_vocabulary(user_id, vocab_id);

drop policy if exists "Users can view available vocab catalog rows" on public.vocab_catalog;
create policy "Users can view available vocab catalog rows"
on public.vocab_catalog
for select
to authenticated
using (
  visibility = 'system'
  or created_by = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can view own user vocabulary" on public.user_vocabulary;
create policy "Users can view own user vocabulary"
on public.user_vocabulary
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can insert own user vocabulary" on public.user_vocabulary;
create policy "Users can insert own user vocabulary"
on public.user_vocabulary
for insert
to authenticated
with check (
  user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can update own user vocabulary" on public.user_vocabulary;
create policy "Users can update own user vocabulary"
on public.user_vocabulary
for update
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
)
with check (
  user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can delete own user vocabulary" on public.user_vocabulary;
create policy "Users can delete own user vocabulary"
on public.user_vocabulary
for delete
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can view own notifications" on public.notifications;
create policy "Users can view own notifications"
on public.notifications
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can update own notifications" on public.notifications;
create policy "Users can update own notifications"
on public.notifications
for update
to authenticated
using (
  user_id = auth.uid()
  or public.is_admin()
)
with check (
  user_id = auth.uid()
  or public.is_admin()
);

grant select, insert, update, delete on public.user_vocabulary to authenticated;
grant select, update on public.notifications to authenticated;
grant select on public.vocab_catalog to authenticated;

drop policy if exists "Users can resubmit rejected topic submissions" on public.topic_submissions;
create policy "Users can resubmit rejected topic submissions"
on public.topic_submissions
for update
to authenticated
using (requester_id = auth.uid() and status = 'rejected')
with check (requester_id = auth.uid() and status = 'pending');

drop policy if exists "Users can delete rejected topic submissions" on public.topic_submissions;
create policy "Users can delete rejected topic submissions"
on public.topic_submissions
for delete
to authenticated
using (requester_id = auth.uid() and status = 'rejected');

grant update, delete on public.topic_submissions to authenticated;

create table if not exists public.user_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  streak_count integer not null default 0,
  last_learning_date text
);

create table if not exists public.activity_logs (
  user_id uuid not null references auth.users(id) on delete cascade,
  date text not null,
  completed boolean not null default true,
  primary key (user_id, date)
);

alter table public.user_stats enable row level security;
alter table public.activity_logs enable row level security;

drop policy if exists "Users can view own stats" on public.user_stats;
create policy "Users can view own stats"
on public.user_stats
for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "Users can upsert own stats" on public.user_stats;
create policy "Users can upsert own stats"
on public.user_stats
for insert
to authenticated
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "Users can update own stats" on public.user_stats;
create policy "Users can update own stats"
on public.user_stats
for update
to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "Users can view own activity logs" on public.activity_logs;
create policy "Users can view own activity logs"
on public.activity_logs
for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

drop policy if exists "Users can insert own activity logs" on public.activity_logs;
create policy "Users can insert own activity logs"
on public.activity_logs
for insert
to authenticated
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "Users can update own activity logs" on public.activity_logs;
create policy "Users can update own activity logs"
on public.activity_logs
for update
to authenticated
using (user_id = auth.uid() or public.is_admin())
with check (user_id = auth.uid() or public.is_admin());

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using (id = auth.uid() or public.is_admin())
with check (id = auth.uid() or public.is_admin());

grant select, insert, update on public.user_stats to authenticated;
grant select, insert, update on public.activity_logs to authenticated;
grant update on public.profiles to authenticated;
