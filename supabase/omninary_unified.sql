-- GIỮ CHUỖI, VẬT PHẨM VÀ GHI NHẬN PHIÊN HỌC THỐNG NHẤT
-- Chạy nguyên tệp trong trình SQL của Supabase. Có thể chạy lại.
-- Yêu cầu các bảng nền hiện có: profiles, user_stats, activity_logs, user_vocabulary.
-- Không xóa tài khoản, điểm, chuỗi hoặc lịch sử học. Ghi đè các hàm liên quan.
-- Không thay đổi các hàm trang bị biểu tượng hoặc các tính năng khác của ứng dụng.
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS omni_points integer NOT NULL DEFAULT 1250,
  ADD COLUMN IF NOT EXISTS equipped_omni_icon text NOT NULL DEFAULT 'ditandnary_classic',
  ADD COLUMN IF NOT EXISTS unlocked_omni_icons text[] NOT NULL DEFAULT ARRAY['ditandnary_classic', 'extraordinary_aurora']::text[],
  ADD COLUMN IF NOT EXISTS double_points_until timestamptz,
  -- Single expiry for trial, monthly, and annual Extraordinary access.
  ADD COLUMN IF NOT EXISTS extraordinary_trial_until timestamptz,
  ADD COLUMN IF NOT EXISTS learning_hearts_remaining integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS learning_hearts_reset_date date,
  ADD COLUMN IF NOT EXISTS omni_points_earned_date date,
  ADD COLUMN IF NOT EXISTS omni_points_earned_today integer NOT NULL DEFAULT 0;


-- Remove the broad prototype policy. The client may edit display_name only;
-- all economy columns are writable solely through the functions below.
DROP POLICY IF EXISTS "Users can update own profile omni data" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own display name" ON public.profiles;
CREATE POLICY "Users can update own display name"
ON public.profiles FOR UPDATE TO authenticated
USING (id = auth.uid() OR public.is_admin())
WITH CHECK (id = auth.uid() OR public.is_admin());
REVOKE UPDATE ON TABLE public.profiles FROM authenticated;
GRANT UPDATE (display_name) ON TABLE public.profiles TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.user_stats, public.activity_logs FROM authenticated;

-- Remove the unsafe prototype RPC signatures before installing the constrained API.
DROP FUNCTION IF EXISTS public.add_omni_points(uuid, integer);
DROP FUNCTION IF EXISTS public.redeem_omni_icon(uuid, text, integer);


CREATE OR REPLACE FUNCTION public.require_current_user()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE current_user_id uuid := auth.uid();
BEGIN
  IF current_user_id IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  RETURN current_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.require_current_user() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.require_current_user() TO authenticated;
CREATE UNIQUE INDEX IF NOT EXISTS activity_logs_user_date_unique ON public.activity_logs(user_id, date);
REVOKE INSERT, UPDATE, DELETE ON public.user_stats, public.activity_logs FROM authenticated;


-- SOURCE: omni_item_catalog.sql
-- =============================================================================
-- Omni item single-source catalog
-- Run before the current omni_points_and_icons.sql. Safe to re-run.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.omni_item_catalog (
  id text PRIMARY KEY,
  name text NOT NULL,
  subtitle text NOT NULL,
  icon_name text NOT NULL,
  color_start text NOT NULL,
  color_end text NOT NULL,
  points_cost integer NOT NULL CHECK (points_cost >= 0),
  is_extra_only boolean NOT NULL DEFAULT false,
  disabled_in_extra boolean NOT NULL DEFAULT false,
  extra_disabled_text text NOT NULL DEFAULT '',
  sort_order integer NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.omni_item_catalog
  (id, name, subtitle, icon_name, color_start, color_end, points_cost, is_extra_only, disabled_in_extra, extra_disabled_text, sort_order)
VALUES
  ('extra_heart', 'Trái tim bên lề', 'Dùng 50 điểm để cộng ngay 1 lượt học.', 'heart.fill', 'EC4899', 'EF4444', 50, false, true, 'Đã vô hạn lượt học', 10),
  ('double_points', 'Gấp đôi Canxi', 'Dùng 150 điểm để nhân đôi điểm đến hết ngày.', 'bolt.fill', 'F59E0B', 'FDE047', 150, false, false, '', 20),
  ('streak_freeze', 'Mùa đông không lạnh', 'Dùng 300 điểm để bảo vệ chuỗi hôm nay.', 'snowflake', '06B6D4', '3B82F6', 300, false, false, '', 30),
  ('restore_streak', 'Người giữ lửa', 'Dùng 1000 điểm để khôi phục chuỗi đã mất.', 'flame.fill', 'EF4444', 'F97316', 1000, true, false, '', 40),
  ('extraordinary_trial', 'Trải nghiệm phi thường', 'Dùng 1000 điểm để kích hoạt Extraordinary trong 3 ngày.', 'infinity', '3B82F6', '8B5CF6', 1000, false, true, 'Đang có Extraordinary', 50)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, subtitle = EXCLUDED.subtitle, icon_name = EXCLUDED.icon_name,
  color_start = EXCLUDED.color_start, color_end = EXCLUDED.color_end,
  points_cost = EXCLUDED.points_cost, is_extra_only = EXCLUDED.is_extra_only,
  disabled_in_extra = EXCLUDED.disabled_in_extra, extra_disabled_text = EXCLUDED.extra_disabled_text,
  sort_order = EXCLUDED.sort_order, is_active = true, updated_at = now();

ALTER TABLE public.omni_item_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can read active Omni item catalog" ON public.omni_item_catalog;
CREATE POLICY "Authenticated users can read active Omni item catalog"
ON public.omni_item_catalog FOR SELECT TO authenticated
USING (is_active = true);
REVOKE ALL ON TABLE public.omni_item_catalog FROM anon, authenticated;
GRANT SELECT ON TABLE public.omni_item_catalog TO authenticated;

-- use_omni_item is defined in streak_workflow.sql.

-- Install streak_workflow.sql for item mutations.


-- SOURCE: streak_workflow.sql
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


-- SOURCE: ditandnary_review_schedule_v2.sql
-- Run after the vocabulary tables exist, before the v2 learning functions.
-- Deploy ditandnary_review_schedule_deploy.sql to run this migration and
-- replace the learning functions in one transaction on an existing project.
-- Re-running this file does not shift levels twice.

CREATE TABLE IF NOT EXISTS public.ditandnary_schedule_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON public.ditandnary_schedule_migrations FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  LOCK TABLE public.ditandnary_schedule_migrations IN EXCLUSIVE MODE;
  IF NOT EXISTS (
    SELECT 1 FROM public.ditandnary_schedule_migrations
    WHERE name = 'new_zero_master_super_v2'
  ) THEN
    -- Old 0 was unscheduled; old 1 was due immediately. Preserve every
    -- scheduled review date while shifting the internal level down by one.
    ALTER TABLE public.user_vocabulary ALTER COLUMN learning_level DROP NOT NULL;
    ALTER TABLE public.user_vocabulary ALTER COLUMN learning_level DROP DEFAULT;
    ALTER TABLE public.user_vocabulary DROP CONSTRAINT IF EXISTS user_vocabulary_learning_level_check;

    UPDATE public.user_vocabulary
    SET learning_level = CASE
          WHEN learning_level IS NULL OR learning_level = 0 THEN NULL
          WHEN learning_level >= 11 THEN 10
          ELSE learning_level - 1
        END,
        next_review = CASE
          WHEN learning_level IS NULL OR learning_level = 0 OR learning_level >= 11 THEN NULL
          ELSE next_review
        END;

    ALTER TABLE public.user_vocabulary
      ADD CONSTRAINT user_vocabulary_learning_level_check
      CHECK (learning_level BETWEEN 0 AND 10);
    INSERT INTO public.ditandnary_schedule_migrations(name)
    VALUES ('new_zero_master_super_v2');
  END IF;
END;
$$;


-- SOURCE: vocabulary_learning_atomic_flow.sql
-- =============================================================================
-- Atomic vocabulary-learning settlement for Ditan / Extraordinary.
-- Run ditandnary_review_schedule_v2.sql first on an existing database.
-- Vietnam time is authoritative for daily heart, reward, activity, and streak dates.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.vocabulary_learning_settlements (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_vocabulary_ids text[] NOT NULL,
  correct_answers integer NOT NULL,
  response jsonb NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vocabulary_learning_settlements_user_completed_idx
  ON public.vocabulary_learning_settlements (user_id, completed_at DESC);

ALTER TABLE public.vocabulary_learning_settlements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.vocabulary_learning_settlements FROM anon, authenticated;

-- Direct clients may still save a better pronunciation score. Learning level and
-- next-review mutations are exclusively owned by the RPCs in this migration.
REVOKE UPDATE ON TABLE public.user_vocabulary FROM authenticated;
GRANT UPDATE (pronunciation_score) ON TABLE public.user_vocabulary TO authenticated;

CREATE OR REPLACE FUNCTION public.protect_new_user_vocabulary_progress()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF auth.role() = 'authenticated' AND NOT public.is_admin() THEN
    NEW.learning_level := NULL;
    NEW.next_review := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_new_user_vocabulary_progress_trigger
  ON public.user_vocabulary;
CREATE TRIGGER protect_new_user_vocabulary_progress_trigger
BEFORE INSERT ON public.user_vocabulary
FOR EACH ROW EXECUTE FUNCTION public.protect_new_user_vocabulary_progress();

CREATE OR REPLACE FUNCTION public.get_learning_access_state()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.require_current_user();
  v_profile public.profiles%ROWTYPE;
  v_today date := timezone('Asia/Ho_Chi_Minh', now())::date;
  v_reset_at timestamptz := ((timezone('Asia/Ho_Chi_Minh', now())::date + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh');
  v_is_extra boolean;
BEGIN
  SELECT * INTO v_profile
  FROM public.profiles
  WHERE id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  v_is_extra := COALESCE(v_profile.extraordinary_trial_until > now(), false);

  IF NOT v_is_extra AND v_profile.learning_hearts_reset_date IS DISTINCT FROM v_today THEN
    UPDATE public.profiles
    SET learning_hearts_remaining = 5,
        learning_hearts_reset_date = v_today
    WHERE id = v_user_id
    RETURNING * INTO v_profile;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'is_extra', v_is_extra,
    'remaining_hearts', v_profile.learning_hearts_remaining,
    'reset_date', v_profile.learning_hearts_reset_date,
    'reset_at', v_reset_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.start_vocabulary_learning(p_user_vocabulary_ids text[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.require_current_user();
  v_ids text[];
  v_requested_count integer;
  v_owned_count integer;
  v_started_count integer;
BEGIN
  SELECT COALESCE(array_agg(DISTINCT value ORDER BY value), ARRAY[]::text[])
  INTO v_ids
  FROM unnest(COALESCE(p_user_vocabulary_ids, ARRAY[]::text[])) AS requested(value)
  WHERE NULLIF(btrim(value), '') IS NOT NULL;

  v_requested_count := cardinality(v_ids);
  IF v_requested_count = 0 OR v_requested_count > 50 THEN
    RAISE EXCEPTION 'Invalid vocabulary selection';
  END IF;

  SELECT count(*) INTO v_owned_count
  FROM public.user_vocabulary
  WHERE user_id = v_user_id
    AND id::text = ANY(v_ids);

  IF v_owned_count <> v_requested_count THEN
    RAISE EXCEPTION 'Vocabulary selection is invalid or is not owned by the current user';
  END IF;

  UPDATE public.user_vocabulary
  SET learning_level = 0,
      next_review = now()
  WHERE user_id = v_user_id
    AND id::text = ANY(v_ids)
    AND learning_level IS NULL;

  GET DIAGNOSTICS v_started_count = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'started_count', v_started_count
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_vocabulary_learning_session(
  p_session_id uuid,
  p_user_vocabulary_ids text[],
  p_correct_answers integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.require_current_user();
  v_profile public.profiles%ROWTYPE;
  v_stats public.user_stats%ROWTYPE;
  v_existing public.vocabulary_learning_settlements%ROWTYPE;
  v_ids text[];
  v_requested_count integer;
  v_owned_due_count integer;
  v_updated_count integer;
  v_today date := timezone('Asia/Ho_Chi_Minh', now())::date;
  v_reset_at timestamptz := ((timezone('Asia/Ho_Chi_Minh', now())::date + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh');
  v_is_extra boolean;
  v_is_first_learning_today boolean;
  v_earned integer;
  v_cap_remaining integer;
  v_response jsonb;
BEGIN
  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'Missing learning session id';
  END IF;
  IF p_correct_answers < 0 OR p_correct_answers > 500 THEN
    RAISE EXCEPTION 'Invalid answer count';
  END IF;

  -- Serializes duplicate requests even when the first request is still in flight.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_session_id::text, 0));

  SELECT * INTO v_existing
  FROM public.vocabulary_learning_settlements
  WHERE session_id = p_session_id;

  IF FOUND THEN
    IF v_existing.user_id <> v_user_id THEN
      RAISE EXCEPTION 'Learning session belongs to another user';
    END IF;
    -- Keep session rewards idempotent but return the account's current streak state.
    v_response := public.refresh_streak_state_for(v_user_id, now());
    SELECT * INTO v_profile FROM public.profiles WHERE id = v_user_id;
    RETURN v_existing.response || v_response || jsonb_build_object('already_completed', true,
      'new_points', v_profile.omni_points,
      'is_first_learning_today', COALESCE((v_existing.response->>'is_first_learning_today')::boolean, false)
        AND v_existing.response->>'last_learning_date' = v_today::text);
  END IF;

  SELECT COALESCE(array_agg(DISTINCT value ORDER BY value), ARRAY[]::text[])
  INTO v_ids
  FROM unnest(COALESCE(p_user_vocabulary_ids, ARRAY[]::text[])) AS requested(value)
  WHERE NULLIF(btrim(value), '') IS NOT NULL;

  v_requested_count := cardinality(v_ids);
  IF v_requested_count = 0 OR v_requested_count > 50 THEN
    RAISE EXCEPTION 'Invalid vocabulary selection';
  END IF;

  SELECT * INTO v_profile
  FROM public.profiles
  WHERE id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  v_is_extra := COALESCE(v_profile.extraordinary_trial_until > now(), false);

  -- Ditan gets exactly five sessions per Vietnam calendar day.
  IF NOT v_is_extra AND v_profile.learning_hearts_reset_date IS DISTINCT FROM v_today THEN
    UPDATE public.profiles
    SET learning_hearts_remaining = 5,
        learning_hearts_reset_date = v_today
    WHERE id = v_user_id
    RETURNING * INTO v_profile;
  END IF;

  IF NOT v_is_extra AND v_profile.learning_hearts_remaining <= 0 THEN
    RAISE EXCEPTION 'No learning hearts remaining';
  END IF;

  SELECT count(*) INTO v_owned_due_count
  FROM public.user_vocabulary
  WHERE user_id = v_user_id
    AND id::text = ANY(v_ids)
    AND learning_level BETWEEN 0 AND 9
    AND (next_review IS NULL OR next_review::timestamptz <= now());

  IF v_owned_due_count <> v_requested_count THEN
    RAISE EXCEPTION 'Vocabulary selection is invalid, not due, or is not owned by the current user';
  END IF;

  UPDATE public.user_vocabulary
  SET learning_level = learning_level + 1,
      next_review = CASE learning_level + 1
        WHEN 1 THEN now() + interval '1 day'
        WHEN 2 THEN now() + interval '3 days'
        WHEN 3 THEN now() + interval '7 days'
        WHEN 4 THEN now() + interval '15 days'
        WHEN 5 THEN now() + interval '30 days'
        WHEN 6 THEN now() + interval '60 days'
        WHEN 7 THEN now() + interval '120 days'
        WHEN 8 THEN now() + interval '240 days'
        WHEN 9 THEN now() + interval '365 days'
        ELSE NULL -- Level 10 is Super and has no automatic review.
      END
  WHERE user_id = v_user_id
    AND id::text = ANY(v_ids);

  GET DIAGNOSTICS v_updated_count = ROW_COUNT;
  IF v_updated_count <> v_requested_count THEN
    RAISE EXCEPTION 'Vocabulary progress update was incomplete';
  END IF;

  -- The same streak transaction is used by every learning mode.
  v_response := public.record_daily_activity();
  v_is_first_learning_today := (v_response->>'is_first_learning_today')::boolean;
  SELECT * INTO v_stats FROM public.user_stats WHERE user_id = v_user_id;

  IF v_profile.omni_points_earned_date IS DISTINCT FROM v_today THEN
    v_profile.omni_points_earned_today := 0;
  END IF;

  v_earned := p_correct_answers;
  IF v_is_extra THEN
    v_earned := floor(v_earned * 1.2);
  END IF;
  IF v_profile.double_points_until > now() THEN
    v_earned := v_earned * 2;
  END IF;
  v_cap_remaining := GREATEST(0, 500 - v_profile.omni_points_earned_today);
  v_earned := LEAST(v_earned, v_cap_remaining);

  UPDATE public.profiles
  SET omni_points = omni_points + v_earned,
      omni_points_earned_date = v_today,
      omni_points_earned_today = v_profile.omni_points_earned_today + v_earned,
      learning_hearts_remaining = CASE
        WHEN v_is_extra THEN learning_hearts_remaining
        ELSE learning_hearts_remaining - 1
      END
  WHERE id = v_user_id
  RETURNING * INTO v_profile;

  v_response := jsonb_build_object(
    'success', true,
    'already_completed', false,
    'earned_points', v_earned,
    'new_points', v_profile.omni_points,
    'remaining_hearts', v_profile.learning_hearts_remaining,
    'reset_date', v_profile.learning_hearts_reset_date,
    'reset_at', v_reset_at,
    'is_extra', v_is_extra,
    'streak_count', v_stats.streak_count,
    'saved_streak_count', v_stats.saved_streak_count,
    'streak_freeze_date', v_stats.streak_freeze_date,
    'streak_restore_expires_at', v_stats.streak_restore_expires_at,
    'is_first_learning_today', v_is_first_learning_today,
    'previous_streak_count', (v_response->>'previous_streak_count')::integer,
    'was_frozen_today', (v_response->>'was_frozen_today')::boolean,
    'last_learning_date', v_stats.last_learning_date,
    'streak_protected_through', v_stats.streak_protected_through,
    'streak_freeze_used_at', v_stats.streak_freeze_used_at,
    'streak_freeze_requires_learning', v_stats.streak_freeze_requires_learning,
    'streak_restored_on', v_stats.streak_restored_on
  );

  INSERT INTO public.vocabulary_learning_settlements (
    session_id,
    user_id,
    user_vocabulary_ids,
    correct_answers,
    response
  ) VALUES (
    p_session_id,
    v_user_id,
    v_ids,
    p_correct_answers,
    v_response
  );

  RETURN v_response;
END;
$$;

REVOKE ALL ON FUNCTION public.get_learning_access_state() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_vocabulary_learning(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_vocabulary_learning_session(uuid, text[], integer) FROM PUBLIC;
-- Superseded by complete_vocabulary_learning_session; leaving it executable would
-- allow a client to settle points and hearts without settling vocabulary progress.
DO $$ BEGIN
  IF to_regprocedure('public.settle_learning_reward(integer)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.settle_learning_reward(integer) FROM PUBLIC, authenticated;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.get_learning_access_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_vocabulary_learning(text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_vocabulary_learning_session(uuid, text[], integer) TO authenticated;


-- SOURCE: extra_v1_learning_telemetry.sql
-- Extra v1 beta: immutable per-session, per-word, and per-attempt learning data.
-- Run this AFTER vocabulary_learning_atomic_flow.sql.
-- It keeps Ditan's current fixed schedule while collecting the evidence Extra
-- will use for personalised scheduling.

CREATE TABLE IF NOT EXISTS public.learning_sessions (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now(),
  is_extra boolean NOT NULL DEFAULT false,
  task_count integer NOT NULL DEFAULT 0 CHECK (task_count >= 0),
  correct_answers integer NOT NULL DEFAULT 0 CHECK (correct_answers >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.learning_attempts (
  attempt_id uuid PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES public.learning_sessions(session_id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL,
  user_vocabulary_ids text[] NOT NULL CHECK (cardinality(user_vocabulary_ids) > 0),
  task_type text NOT NULL CHECK (task_type IN (
    'listen_and_type', 'meaning_and_type', 'multiple_choice',
    'sentence_scramble', 'pronunciation_example'
  )),
  attempt_number integer NOT NULL CHECK (attempt_number BETWEEN 1 AND 20),
  is_correct boolean NOT NULL,
  answer_text text,
  response_duration_ms integer NOT NULL CHECK (response_duration_ms BETWEEN 0 AND 600000),
  pronunciation_score integer CHECK (pronunciation_score BETWEEN 0 AND 100),
  answered_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS learning_attempts_session_id_idx
  ON public.learning_attempts (session_id);

CREATE TABLE IF NOT EXISTS public.learning_word_results (
  session_id uuid NOT NULL REFERENCES public.learning_sessions(session_id) ON DELETE CASCADE,
  user_vocabulary_id text NOT NULL,
  attempt_count integer NOT NULL DEFAULT 0,
  correct_attempt_count integer NOT NULL DEFAULT 0,
  first_attempt_count integer NOT NULL DEFAULT 0,
  first_attempt_correct_count integer NOT NULL DEFAULT 0,
  first_attempt_accuracy numeric(5,2) NOT NULL DEFAULT 0,
  average_response_duration_ms integer,
  best_pronunciation_score integer,
  outcome jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (session_id, user_vocabulary_id)
);

CREATE INDEX IF NOT EXISTS learning_word_results_user_vocabulary_idx
  ON public.learning_word_results (user_vocabulary_id);

ALTER TABLE public.learning_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_word_results ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own learning sessions" ON public.learning_sessions;
CREATE POLICY "Users can read own learning sessions"
  ON public.learning_sessions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Users can read own learning attempts" ON public.learning_attempts;
CREATE POLICY "Users can read own learning attempts"
  ON public.learning_attempts FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.learning_sessions s
    WHERE s.session_id = learning_attempts.session_id
      AND (s.user_id = auth.uid() OR public.is_admin())
  ));

DROP POLICY IF EXISTS "Users can read own learning word results" ON public.learning_word_results;
CREATE POLICY "Users can read own learning word results"
  ON public.learning_word_results FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.learning_sessions s
    WHERE s.session_id = learning_word_results.session_id
      AND (s.user_id = auth.uid() OR public.is_admin())
  ));

-- Attempts are evidence, not client-owned progress. Only the function below
-- may create them; clients may only read their own history.
REVOKE ALL ON TABLE public.learning_sessions FROM PUBLIC, authenticated;
REVOKE ALL ON TABLE public.learning_attempts FROM PUBLIC, authenticated;
REVOKE ALL ON TABLE public.learning_word_results FROM PUBLIC, authenticated;
GRANT SELECT ON TABLE public.learning_sessions TO authenticated;
GRANT SELECT ON TABLE public.learning_attempts TO authenticated;
GRANT SELECT ON TABLE public.learning_word_results TO authenticated;

CREATE OR REPLACE FUNCTION public.complete_vocabulary_learning_session_extra_v1(
  p_session_id uuid,
  p_user_vocabulary_ids text[],
  p_correct_answers integer,
  p_attempts jsonb DEFAULT '[]'::jsonb,
  p_started_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := public.require_current_user();
  v_result jsonb;
  v_ids text[];
  v_attempt_count integer;
  v_valid_attempt_count integer;
  v_distinct_attempt_count integer;
  v_started_at timestamptz;
BEGIN
  IF jsonb_typeof(COALESCE(p_attempts, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Learning attempts must be an array';
  END IF;
  IF jsonb_array_length(COALESCE(p_attempts, '[]'::jsonb)) > 500 THEN
    RAISE EXCEPTION 'Too many learning attempts';
  END IF;

  -- The existing function owns all Ditan-safe progress and reward changes.
  -- If this wrapper later fails, PostgreSQL rolls that whole transaction back.
  v_result := public.complete_vocabulary_learning_session(
    p_session_id,
    p_user_vocabulary_ids,
    p_correct_answers
  );

  -- A retry gets the exact previous settlement and must never duplicate evidence.
  IF COALESCE((v_result ->> 'already_completed')::boolean, false) THEN
    RETURN v_result || jsonb_build_object('telemetry_recorded', true);
  END IF;

  SELECT COALESCE(array_agg(DISTINCT value ORDER BY value), ARRAY[]::text[])
  INTO v_ids
  FROM unnest(COALESCE(p_user_vocabulary_ids, ARRAY[]::text[])) AS requested(value)
  WHERE NULLIF(btrim(value), '') IS NOT NULL;

  v_started_at := GREATEST(
    now() - interval '24 hours',
    LEAST(COALESCE(p_started_at, now()), now() + interval '5 minutes')
  );

  WITH raw AS (
    SELECT
      (item ->> 'attempt_id')::uuid AS attempt_id,
      (item ->> 'exercise_id')::uuid AS exercise_id,
      ARRAY(SELECT jsonb_array_elements_text(COALESCE(item -> 'user_vocabulary_ids', '[]'::jsonb))) AS user_vocabulary_ids,
      item ->> 'task_type' AS task_type,
      (item ->> 'attempt_number')::integer AS attempt_number,
      (item ->> 'is_correct')::boolean AS is_correct,
      NULLIF(item ->> 'answer_text', '') AS answer_text,
      (item ->> 'response_duration_ms')::integer AS response_duration_ms,
      NULLIF(item ->> 'pronunciation_score', '')::integer AS pronunciation_score,
      (item ->> 'answered_at')::timestamptz AS answered_at
    FROM jsonb_array_elements(COALESCE(p_attempts, '[]'::jsonb)) AS item
  )
  SELECT
    count(*),
    count(*) FILTER (WHERE
      cardinality(user_vocabulary_ids) > 0
      AND NOT EXISTS (
        SELECT 1 FROM unnest(user_vocabulary_ids) AS attempted_id
        WHERE attempted_id <> ALL(v_ids)
      )
      AND task_type IN ('listen_and_type', 'meaning_and_type', 'multiple_choice', 'sentence_scramble', 'pronunciation_example')
      AND attempt_number BETWEEN 1 AND 20
      AND is_correct IS NOT NULL
      AND response_duration_ms BETWEEN 0 AND 600000
      AND (pronunciation_score IS NULL OR pronunciation_score BETWEEN 0 AND 100)
      AND char_length(COALESCE(answer_text, '')) <= 1000
      AND answered_at BETWEEN v_started_at - interval '5 minutes' AND now() + interval '5 minutes'
    ),
    count(DISTINCT attempt_id)
  INTO v_attempt_count, v_valid_attempt_count, v_distinct_attempt_count
  FROM raw;

  IF v_attempt_count <> v_valid_attempt_count OR v_attempt_count <> v_distinct_attempt_count THEN
    RAISE EXCEPTION 'Learning attempt data is invalid';
  END IF;

  INSERT INTO public.learning_sessions (
    session_id, user_id, started_at, is_extra, task_count, correct_answers
  ) VALUES (
    p_session_id,
    v_user_id,
    v_started_at,
    COALESCE((v_result ->> 'is_extra')::boolean, false),
    v_attempt_count,
    p_correct_answers
  );

  WITH raw AS (
    SELECT
      (item ->> 'attempt_id')::uuid AS attempt_id,
      (item ->> 'exercise_id')::uuid AS exercise_id,
      ARRAY(SELECT jsonb_array_elements_text(item -> 'user_vocabulary_ids')) AS user_vocabulary_ids,
      item ->> 'task_type' AS task_type,
      (item ->> 'attempt_number')::integer AS attempt_number,
      (item ->> 'is_correct')::boolean AS is_correct,
      NULLIF(item ->> 'answer_text', '') AS answer_text,
      (item ->> 'response_duration_ms')::integer AS response_duration_ms,
      NULLIF(item ->> 'pronunciation_score', '')::integer AS pronunciation_score,
      (item ->> 'answered_at')::timestamptz AS answered_at
    FROM jsonb_array_elements(COALESCE(p_attempts, '[]'::jsonb)) AS item
  )
  INSERT INTO public.learning_attempts (
    attempt_id, session_id, exercise_id, user_vocabulary_ids, task_type,
    attempt_number, is_correct, answer_text, response_duration_ms,
    pronunciation_score, answered_at
  )
  SELECT
    attempt_id, p_session_id, exercise_id, user_vocabulary_ids, task_type,
    attempt_number, is_correct, answer_text, response_duration_ms,
    pronunciation_score, answered_at
  FROM raw;

  INSERT INTO public.learning_word_results (
    session_id, user_vocabulary_id, attempt_count, correct_attempt_count,
    first_attempt_count, first_attempt_correct_count, first_attempt_accuracy,
    average_response_duration_ms, best_pronunciation_score, outcome
  )
  SELECT
    p_session_id,
    selected_id,
    count(a.attempt_id),
    count(a.attempt_id) FILTER (WHERE a.is_correct),
    count(a.attempt_id) FILTER (WHERE a.attempt_number = 1),
    count(a.attempt_id) FILTER (WHERE a.attempt_number = 1 AND a.is_correct),
    COALESCE(
      round(
        100.0 * count(a.attempt_id) FILTER (WHERE a.attempt_number = 1 AND a.is_correct)
        / NULLIF(count(a.attempt_id) FILTER (WHERE a.attempt_number = 1), 0),
        2
      ),
      0
    ),
    round(avg(a.response_duration_ms))::integer,
    max(a.pronunciation_score),
    jsonb_build_object(
      'progress_rule', 'ditan_fixed_v1',
      'eligible_to_advance', true,
      'source', 'extra_v1_beta'
    )
  FROM unnest(v_ids) AS selected(selected_id)
  LEFT JOIN public.learning_attempts a
    ON a.session_id = p_session_id
    AND selected_id = ANY(a.user_vocabulary_ids)
  GROUP BY selected_id;

  RETURN v_result || jsonb_build_object('telemetry_recorded', true);
END;
$$;

REVOKE ALL ON FUNCTION public.complete_vocabulary_learning_session_extra_v1(uuid, text[], integer, jsonb, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_vocabulary_learning_session_extra_v1(uuid, text[], integer, jsonb, timestamptz) TO authenticated;

-- New app versions call the Extra v1 wrapper. Keep the legacy function available
-- only until every active client has updated, then revoke its authenticated grant.

COMMIT;
