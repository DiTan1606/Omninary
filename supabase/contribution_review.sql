create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

create table if not exists public.vocab_submissions (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  catalog_id uuid not null references public.vocab_catalog(id) on delete cascade,
  topic_id uuid references public.topics(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  admin_note text
);

create unique index if not exists vocab_submissions_one_pending_per_catalog
on public.vocab_submissions (catalog_id)
where status = 'pending';

create table if not exists public.topic_submissions (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  admin_note text
);

create table if not exists public.topic_submission_words (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.topic_submissions(id) on delete cascade,
  word text not null,
  cefr text,
  ipa text,
  word_form text,
  e_meaning text,
  ev_meaning text,
  v_meaning text,
  e_example text,
  v_example text,
  word_family text,
  synonymous text,
  antonym text,
  bonus text,
  created_at timestamptz not null default now()
);

alter table public.vocab_submissions enable row level security;
alter table public.topic_submissions enable row level security;
alter table public.topic_submission_words enable row level security;

drop policy if exists "Users can create vocab submissions" on public.vocab_submissions;
create policy "Users can create vocab submissions"
on public.vocab_submissions
for insert
to authenticated
with check (requester_id = auth.uid());

drop policy if exists "Users can view own vocab submissions" on public.vocab_submissions;
create policy "Users can view own vocab submissions"
on public.vocab_submissions
for select
to authenticated
using (requester_id = auth.uid() or public.is_admin());

drop policy if exists "Admins can update vocab submissions" on public.vocab_submissions;
create policy "Admins can update vocab submissions"
on public.vocab_submissions
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Users can create topic submissions" on public.topic_submissions;
create policy "Users can create topic submissions"
on public.topic_submissions
for insert
to authenticated
with check (requester_id = auth.uid());

drop policy if exists "Users can view own topic submissions" on public.topic_submissions;
create policy "Users can view own topic submissions"
on public.topic_submissions
for select
to authenticated
using (requester_id = auth.uid() or public.is_admin());

drop policy if exists "Admins can update topic submissions" on public.topic_submissions;
create policy "Admins can update topic submissions"
on public.topic_submissions
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

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

drop policy if exists "Users can create words for own topic submissions" on public.topic_submission_words;
create policy "Users can create words for own topic submissions"
on public.topic_submission_words
for insert
to authenticated
with check (
  exists (
    select 1
    from public.topic_submissions ts
    where ts.id = submission_id
      and ts.requester_id = auth.uid()
  )
);

drop policy if exists "Users can view own topic submission words" on public.topic_submission_words;
create policy "Users can view own topic submission words"
on public.topic_submission_words
for select
to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.topic_submissions ts
    where ts.id = submission_id
      and ts.requester_id = auth.uid()
  )
);

drop policy if exists "Admins can update topic submission words" on public.topic_submission_words;
create policy "Admins can update topic submission words"
on public.topic_submission_words
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

grant select, insert, update on public.vocab_submissions to authenticated;
grant select, insert, update, delete on public.topic_submissions to authenticated;
grant select, insert, update on public.topic_submission_words to authenticated;

drop policy if exists "Admins can view user vocabulary" on public.user_vocabulary;
create policy "Admins can view user vocabulary"
on public.user_vocabulary
for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can insert user vocabulary" on public.user_vocabulary;
create policy "Admins can insert user vocabulary"
on public.user_vocabulary
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "Admins can create user notifications" on public.notifications;
create policy "Admins can create user notifications"
on public.notifications
for insert
to authenticated
with check (public.is_admin());

grant select, insert on public.user_vocabulary to authenticated;
grant insert on public.notifications to authenticated;
