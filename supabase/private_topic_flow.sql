-- Private-first topic flow for Omninary.
-- Run this after the existing contribution_review.sql migrations.

alter table public.topics
add column if not exists description text,
add column if not exists visibility text not null default 'system'
  check (visibility in ('system', 'private', 'archived')),
add column if not exists owner_id uuid references auth.users(id) on delete set null,
add column if not exists created_at timestamptz not null default now();

update public.topics
set visibility = 'system'
where visibility is null;

alter table public.topic_submissions
add column if not exists topic_id uuid references public.topics(id) on delete set null;

alter table public.topic_submission_words
add column if not exists catalog_id uuid references public.vocab_catalog(id) on delete set null;

create unique index if not exists topic_submissions_one_pending_per_topic
on public.topic_submissions(topic_id)
where status = 'pending' and topic_id is not null;

alter table public.topics enable row level security;

drop policy if exists "Users can view available topics" on public.topics;
create policy "Users can view available topics"
on public.topics
for select
to authenticated
using (
  visibility = 'system'
  or owner_id = auth.uid()
  or public.is_admin()
);

drop policy if exists "Users can create private topics" on public.topics;
create policy "Users can create private topics"
on public.topics
for insert
to authenticated
with check (
  (
    owner_id = auth.uid()
    and visibility = 'private'
  )
  or public.is_admin()
);

drop policy if exists "Users can update own private topics" on public.topics;
create policy "Users can update own private topics"
on public.topics
for update
to authenticated
using (
  public.is_admin()
  or (owner_id = auth.uid() and visibility = 'private')
)
with check (
  public.is_admin()
  or (owner_id = auth.uid() and visibility = 'private')
);

drop policy if exists "Users can delete own private topics" on public.topics;
create policy "Users can delete own private topics"
on public.topics
for delete
to authenticated
using (
  public.is_admin()
  or (owner_id = auth.uid() and visibility = 'private')
);

grant select, insert, update, delete on public.topics to authenticated;

drop policy if exists "Users can create topic submissions" on public.topic_submissions;
create policy "Users can create topic submissions"
on public.topic_submissions
for insert
to authenticated
with check (
  requester_id = auth.uid()
  and (
    topic_id is null
    or exists (
      select 1
      from public.topics t
      where t.id = topic_id
        and t.owner_id = auth.uid()
        and t.visibility = 'private'
    )
  )
);

drop policy if exists "Users can create private vocab catalog rows" on public.vocab_catalog;
create policy "Users can create private vocab catalog rows"
on public.vocab_catalog
for insert
to authenticated
with check (
  created_by = auth.uid()
  and visibility = 'private'
  and (
    topic_id is null
    or exists (
      select 1
      from public.topics t
      where t.id = topic_id
        and (
          t.visibility = 'system'
          or t.owner_id = auth.uid()
          or public.is_admin()
        )
    )
  )
);

drop policy if exists "Users can update own private vocab catalog rows" on public.vocab_catalog;
create policy "Users can update own private vocab catalog rows"
on public.vocab_catalog
for update
to authenticated
using (
  public.is_admin()
  or (created_by = auth.uid() and visibility = 'private')
)
with check (
  public.is_admin()
  or (created_by = auth.uid() and visibility = 'private')
);

grant select, insert, update, delete on public.vocab_catalog to authenticated;
