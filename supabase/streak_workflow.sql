-- Canonical streak workflow. Run omninary_unified.sql for the complete installation.
ALTER TABLE public.user_stats
  ADD COLUMN IF NOT EXISTS streak_protected_through date,
  ADD COLUMN IF NOT EXISTS streak_freeze_used_at timestamptz,
  ADD COLUMN IF NOT EXISTS streak_freeze_requires_learning boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS streak_restored_on date,
  ADD COLUMN IF NOT EXISTS streak_freeze_date text,
  ADD COLUMN IF NOT EXISTS saved_streak_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS streak_restore_expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS user_stats_user_id_unique ON public.user_stats(user_id);

CREATE TABLE IF NOT EXISTS public.streak_freeze_history (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date date NOT NULL,
  used_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);
ALTER TABLE public.streak_freeze_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read own frozen days" ON public.streak_freeze_history;
CREATE POLICY "Read own frozen days" ON public.streak_freeze_history FOR SELECT TO authenticated
  USING (user_id = auth.uid());
REVOKE ALL ON public.streak_freeze_history FROM anon, authenticated;
GRANT SELECT ON public.streak_freeze_history TO authenticated;

-- Calendar evidence records the missed day, never the day the rescue was purchased.
CREATE TABLE IF NOT EXISTS public.streak_restore_history (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date date NOT NULL,
  restored_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, date)
);
ALTER TABLE public.streak_restore_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read own rescued days" ON public.streak_restore_history;
CREATE POLICY "Read own rescued days" ON public.streak_restore_history FOR SELECT TO authenticated
  USING (user_id = auth.uid());
REVOKE ALL ON public.streak_restore_history FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.streak_restore_history TO authenticated;

-- Preserve the mandatory study day for legacy restorations (saved value was cleared).
UPDATE public.user_stats SET streak_restored_on = last_learning_date::date + 1
WHERE streak_protected_through IS NULL AND streak_count > 0 AND saved_streak_count = 0
  AND last_learning_date IS NOT NULL;
-- Backfill once. A completed lesson wins over ice for that calendar day.
UPDATE public.user_stats SET streak_protected_through = GREATEST(last_learning_date::date, streak_freeze_date::date)
WHERE streak_protected_through IS NULL AND streak_count > 0;
INSERT INTO public.streak_freeze_history(user_id, date, used_at)
SELECT user_id, streak_freeze_date::date, streak_freeze_date::date::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'
FROM public.user_stats
WHERE streak_freeze_date IS NOT NULL AND last_learning_date::date IS DISTINCT FROM streak_freeze_date::date
ON CONFLICT DO NOTHING;
UPDATE public.user_stats SET streak_freeze_used_at = streak_freeze_date::date::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh',
  streak_freeze_requires_learning = COALESCE(last_learning_date::date < streak_freeze_date::date, true)
WHERE streak_freeze_used_at IS NULL AND streak_freeze_date IS NOT NULL;

-- Lock order is always profile -> stats. All public mutations use this helper.
-- p_now exists for deterministic integration tests; callers cannot execute this helper.
CREATE OR REPLACE FUNCTION public.refresh_streak_state_for(p_user_id uuid, p_now timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  s public.user_stats%ROWTYPE;
  v_extra boolean;
  v_today date := timezone('Asia/Ho_Chi_Minh', p_now)::date;
  v_deadline timestamptz;
BEGIN
  SELECT COALESCE(extraordinary_trial_until > p_now, false) INTO v_extra
  FROM public.profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;
  INSERT INTO public.user_stats(user_id, streak_count, saved_streak_count)
  VALUES(p_user_id, 0, 0) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO s FROM public.user_stats WHERE user_id = p_user_id FOR UPDATE;
  IF s.streak_count > 0 AND s.streak_protected_through IS NULL THEN
    s.streak_protected_through := GREATEST(s.last_learning_date::date, s.streak_freeze_date::date);
  END IF;
  IF s.streak_count > 0 AND (s.streak_protected_through IS NULL OR v_today > s.streak_protected_through + 1) THEN
    v_deadline := (s.streak_protected_through + 3)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh';
    IF v_extra AND s.saved_streak_count > 0 AND s.streak_restored_on IS NULL AND v_deadline > p_now THEN
      s.saved_streak_count := s.streak_count;
      s.streak_restore_expires_at := v_deadline;
    ELSE
      s.saved_streak_count := 0;
      s.streak_restore_expires_at := NULL;
    END IF;
    s.streak_count := 0;
    s.streak_restored_on := NULL;
  END IF;
  IF s.streak_count = 0 AND (NOT v_extra OR s.streak_restore_expires_at IS NULL OR s.streak_restore_expires_at <= p_now) THEN
    s.saved_streak_count := 0;
    s.streak_restore_expires_at := NULL;
  END IF;
  UPDATE public.user_stats SET streak_count = s.streak_count, saved_streak_count = s.saved_streak_count,
    streak_restore_expires_at = s.streak_restore_expires_at, streak_restored_on = s.streak_restored_on,
    streak_protected_through = s.streak_protected_through
  WHERE user_id = p_user_id;
  RETURN jsonb_build_object('streak_count', s.streak_count, 'saved_streak_count', s.saved_streak_count,
    'last_learning_date', s.last_learning_date, 'streak_freeze_date', s.streak_freeze_date,
    'streak_restore_expires_at', s.streak_restore_expires_at, 'streak_protected_through', s.streak_protected_through,
    'streak_freeze_used_at', s.streak_freeze_used_at, 'streak_freeze_requires_learning', s.streak_freeze_requires_learning,
    'streak_restored_on', s.streak_restored_on, 'is_extra', v_extra,
    'freeze_available_at', s.streak_freeze_used_at + interval '7 days');
END;
$$;
CREATE OR REPLACE FUNCTION public.refresh_streak_state()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.refresh_streak_state_for(public.require_current_user(), now());
$$;

CREATE OR REPLACE FUNCTION public.record_daily_activity()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u uuid := public.require_current_user();
  s public.user_stats%ROWTYPE;
  t date := timezone('Asia/Ho_Chi_Minh', now())::date;
  v_first boolean;
  v_previous integer;
  v_was_frozen boolean;
  result jsonb;
BEGIN
  PERFORM public.refresh_streak_state_for(u, now());
  SELECT * INTO s FROM public.user_stats WHERE user_id = u FOR UPDATE;
  v_first := s.last_learning_date::date IS DISTINCT FROM t;
  v_previous := s.streak_count;
  v_was_frozen := s.streak_freeze_date::date = t;
  IF v_first THEN
    UPDATE public.user_stats SET streak_count = s.streak_count + 1, saved_streak_count = s.streak_count + 1,
      last_learning_date = t, streak_protected_through = t, streak_freeze_date = NULL,
      streak_restore_expires_at = NULL, streak_restored_on = NULL, streak_freeze_requires_learning = false
    WHERE user_id = u;
    DELETE FROM public.streak_freeze_history WHERE user_id = u AND date = t;
  END IF;
  INSERT INTO public.activity_logs(user_id, date, completed) VALUES(u, t, true)
  ON CONFLICT(user_id, date) DO UPDATE SET completed = true;
  result := public.refresh_streak_state_for(u, now());
  RETURN result || jsonb_build_object('is_first_learning_today', v_first,
    'previous_streak_count', v_previous, 'was_frozen_today', COALESCE(v_was_frozen, false));
END;
$$;

CREATE OR REPLACE FUNCTION public.use_omni_item(item_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u uuid := public.require_current_user(); p public.profiles%ROWTYPE; s public.user_stats%ROWTYPE;
  cost integer; until_at timestamptz; t date := timezone('Asia/Ho_Chi_Minh', now())::date;
  result jsonb;
  rescued_day date;
BEGIN
  result := public.refresh_streak_state_for(u, now());
  SELECT * INTO p FROM public.profiles WHERE id = u FOR UPDATE;
  SELECT * INTO s FROM public.user_stats WHERE user_id = u FOR UPDATE;
  SELECT points_cost INTO cost FROM public.omni_item_catalog WHERE id = item_id AND is_active;
  IF cost IS NULL THEN RAISE EXCEPTION 'Unknown or inactive item'; END IF;
  IF p.omni_points < cost THEN RAISE EXCEPTION 'Bạn chưa đủ điểm Omni để dùng vật phẩm.'; END IF;
  IF item_id = 'extra_heart' THEN
    IF COALESCE(p.extraordinary_trial_until > now(), false) THEN RAISE EXCEPTION 'Extraordinary already has unlimited hearts'; END IF;
    UPDATE public.profiles SET learning_hearts_remaining = learning_hearts_remaining + 1 WHERE id = u;
  ELSIF item_id = 'double_points' THEN
    IF p.double_points_until > now() THEN RAISE EXCEPTION 'Double points is already active'; END IF;
    until_at := (t + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh';
    UPDATE public.profiles SET double_points_until = until_at WHERE id = u;
  ELSIF item_id = 'streak_freeze' THEN
    IF s.streak_count <= 0 THEN RAISE EXCEPTION 'Cần có chuỗi lớn hơn 0 để đóng băng.'; END IF;
    IF s.last_learning_date::date = t OR s.streak_freeze_date::date = t THEN RAISE EXCEPTION 'Hôm nay đã được bảo vệ.'; END IF;
    IF s.streak_restored_on IS NOT NULL THEN RAISE EXCEPTION 'Sau khi cứu chuỗi, bạn phải học hôm nay; không thể đóng băng.'; END IF;
    IF s.streak_freeze_requires_learning THEN RAISE EXCEPTION 'Bạn phải học sau lần đóng băng trước.'; END IF;
    IF s.streak_freeze_used_at + interval '7 days' > now() THEN RAISE EXCEPTION 'Mùa đông không lạnh chỉ dùng một lần trong mỗi 7 ngày.'; END IF;
    UPDATE public.user_stats SET streak_freeze_date = t, streak_protected_through = t,
      streak_freeze_used_at = now(), streak_freeze_requires_learning = true WHERE user_id = u;
    INSERT INTO public.streak_freeze_history(user_id, date) VALUES(u, t);
  ELSIF item_id = 'restore_streak' THEN
    IF NOT COALESCE(p.extraordinary_trial_until > now(), false) OR s.streak_count <> 0 OR s.saved_streak_count <= 0
      OR s.streak_restore_expires_at IS NULL OR s.streak_restore_expires_at <= now() THEN
      RAISE EXCEPTION 'Quyền khôi phục chuỗi không còn hiệu lực.';
    END IF;
    rescued_day := s.streak_protected_through + 1;
    INSERT INTO public.streak_restore_history(user_id, date) VALUES(u, rescued_day)
    ON CONFLICT (user_id, date) DO NOTHING;
    UPDATE public.user_stats SET streak_count = s.saved_streak_count, saved_streak_count = 0,
      streak_restore_expires_at = NULL, streak_restored_on = t, streak_protected_through = t - 1,
      streak_freeze_date = NULL WHERE user_id = u;
  ELSIF item_id = 'extraordinary_trial' THEN
    IF p.extraordinary_trial_until > now() THEN RAISE EXCEPTION 'Extraordinary is already active'; END IF;
    UPDATE public.profiles SET extraordinary_trial_until = now() + interval '3 days' WHERE id = u;
  ELSE RAISE EXCEPTION 'Unsupported item behavior'; END IF;
  UPDATE public.profiles SET omni_points = omni_points - cost WHERE id = u RETURNING * INTO p;
  result := public.refresh_streak_state_for(u, now());
  RETURN result || jsonb_build_object('success', true, 'new_points', p.omni_points,
    'remaining_hearts', p.learning_hearts_remaining, 'double_points_until', p.double_points_until,
    'extraordinary_trial_until', p.extraordinary_trial_until, 'streak_rescued_date', rescued_day);
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_streak_state_for(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.refresh_streak_state(), public.record_daily_activity(), public.use_omni_item(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.refresh_streak_state(), public.record_daily_activity(), public.use_omni_item(text) TO authenticated;

-- A retried listening/shadowing completion must keep its original first-session result.
CREATE TABLE IF NOT EXISTS public.streak_activity_sessions (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  response jsonb NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.streak_activity_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.streak_activity_sessions FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.record_daily_activity(p_session_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u uuid := public.require_current_user();
  cached public.streak_activity_sessions%ROWTYPE;
  result jsonb;
  t text := timezone('Asia/Ho_Chi_Minh', now())::date::text;
BEGIN
  IF p_session_id IS NULL THEN RAISE EXCEPTION 'Thiếu mã phiên học.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));
  SELECT * INTO cached FROM public.streak_activity_sessions WHERE session_id = p_session_id;
  IF FOUND THEN
    IF cached.user_id <> u THEN RAISE EXCEPTION 'Phiên học không thuộc tài khoản của bạn.'; END IF;
    RETURN cached.response || public.refresh_streak_state_for(u, now()) || jsonb_build_object(
      'is_first_learning_today', COALESCE((cached.response->>'is_first_learning_today')::boolean, false)
        AND cached.response->>'last_learning_date' = t, 'already_recorded', true);
  END IF;
  result := public.record_daily_activity();
  INSERT INTO public.streak_activity_sessions(session_id, user_id, response) VALUES(p_session_id,u,result);
  RETURN result || jsonb_build_object('already_recorded', false);
END;
$$;
REVOKE ALL ON FUNCTION public.record_daily_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_daily_activity(uuid) TO authenticated;
