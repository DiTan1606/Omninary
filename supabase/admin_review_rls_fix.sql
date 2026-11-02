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
