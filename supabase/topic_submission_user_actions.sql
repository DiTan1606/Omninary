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
