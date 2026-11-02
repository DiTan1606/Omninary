-- Số từ khác nhau người học đã luyện mỗi ngày (giờ Việt Nam), dùng cho lịch heatmap ở trang Home.
create or replace function public.get_daily_word_counts(p_from date, p_to date)
returns table(day date, words integer)
language sql
stable
security definer
set search_path = public
as $$
  select (a.answered_at at time zone 'Asia/Ho_Chi_Minh')::date as day,
         count(distinct v)::integer as words
  from learning_attempts a
  join learning_sessions s on s.session_id = a.session_id
  cross join lateral unnest(a.user_vocabulary_ids) as v
  where s.user_id = auth.uid()
    and (a.answered_at at time zone 'Asia/Ho_Chi_Minh')::date between p_from and p_to
  group by 1
  order by 1;
$$;

revoke all on function public.get_daily_word_counts(date, date) from public, anon;
grant execute on function public.get_daily_word_counts(date, date) to authenticated;
