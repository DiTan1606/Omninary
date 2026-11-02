-- =============================================================================
-- OMNINARY economy migration
-- Run after omni_icon_catalog.sql and omni_item_catalog.sql in Supabase SQL Editor as a database owner.
-- The app may read profile data, but economy state is mutated only by RPCs below.
-- =============================================================================

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

ALTER TABLE public.user_stats
  ADD COLUMN IF NOT EXISTS streak_freeze_date text,
  ADD COLUMN IF NOT EXISTS saved_streak_count integer NOT NULL DEFAULT 0,
  -- Exact deadline for spending a saved streak with "Người giữ lửa".
  ADD COLUMN IF NOT EXISTS streak_restore_expires_at timestamptz;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_omni_points_nonnegative,
  DROP CONSTRAINT IF EXISTS profiles_omni_hearts_nonnegative,
  DROP CONSTRAINT IF EXISTS profiles_omni_daily_points_nonnegative,
  ADD CONSTRAINT profiles_omni_points_nonnegative CHECK (omni_points >= 0),
  ADD CONSTRAINT profiles_omni_hearts_nonnegative CHECK (learning_hearts_remaining >= 0),
  ADD CONSTRAINT profiles_omni_daily_points_nonnegative CHECK (omni_points_earned_today >= 0);

CREATE UNIQUE INDEX IF NOT EXISTS activity_logs_user_date_unique
  ON public.activity_logs (user_id, date);

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

-- Run omni_icon_catalog.sql before this migration so the server and app share one catalog.
CREATE OR REPLACE FUNCTION public.omni_icon_cost(p_icon_id text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT points_required
  FROM public.omni_icon_catalog
  WHERE id = p_icon_id AND is_active = true AND points_required IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION public.redeem_omni_icon(icon_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid := public.require_current_user(); v_cost integer := public.omni_icon_cost(icon_id);
  v_points integer; v_icons text[];
BEGIN
  IF v_cost IS NULL THEN RAISE EXCEPTION 'Unknown or non-purchasable icon'; END IF;
  SELECT omni_points, unlocked_omni_icons INTO v_points, v_icons FROM public.profiles WHERE id = v_user_id FOR UPDATE;
  IF icon_id = ANY(v_icons) THEN RAISE EXCEPTION 'Icon is already unlocked'; END IF;
  IF v_points < v_cost THEN RAISE EXCEPTION 'Insufficient Omni points'; END IF;
  UPDATE public.profiles SET omni_points = omni_points - v_cost,
    unlocked_omni_icons = array_append(unlocked_omni_icons, icon_id)
  WHERE id = v_user_id RETURNING omni_points, unlocked_omni_icons INTO v_points, v_icons;
  RETURN jsonb_build_object('success', true, 'new_points', v_points, 'unlocked_omni_icons', v_icons);
END;
$$;

CREATE OR REPLACE FUNCTION public.equip_omni_icon(icon_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.require_current_user(); v_icons text[];
BEGIN
  SELECT unlocked_omni_icons INTO v_icons FROM public.profiles WHERE id = v_user_id FOR UPDATE;
  IF icon_id <> 'ditandnary_classic' AND NOT icon_id = ANY(v_icons) THEN RAISE EXCEPTION 'Icon is not unlocked'; END IF;
  UPDATE public.profiles SET equipped_omni_icon = icon_id WHERE id = v_user_id;
  RETURN jsonb_build_object('success', true, 'equipped_omni_icon', icon_id);
END;
$$;

-- Temporary development/top-up credit. It cannot target another account, cannot
-- subtract funds, and accepts only packages currently shown by the app.
CREATE OR REPLACE FUNCTION public.grant_development_omni_points(points integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.require_current_user(); v_balance integer;
BEGIN
  IF points NOT IN (1000, 2400, 5400, 12000) THEN RAISE EXCEPTION 'Unsupported development package'; END IF;
  UPDATE public.profiles SET omni_points = omni_points + points WHERE id = v_user_id
  RETURNING omni_points INTO v_balance;
  RETURN jsonb_build_object('success', true, 'new_points', v_balance);
END;
$$;

CREATE OR REPLACE FUNCTION public.unlock_streak_omni_icons()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.require_current_user(); v_streak integer; v_icons text[];
BEGIN
  SELECT streak_count INTO v_streak FROM public.user_stats WHERE user_id = v_user_id;
  SELECT unlocked_omni_icons INTO v_icons FROM public.profiles WHERE id = v_user_id FOR UPDATE;
  IF COALESCE(v_streak, 0) >= 30 AND NOT 'omni_streak_30' = ANY(v_icons) THEN v_icons := array_append(v_icons, 'omni_streak_30'); END IF;
  IF COALESCE(v_streak, 0) >= 100 AND NOT 'omni_streak_100' = ANY(v_icons) THEN v_icons := array_append(v_icons, 'omni_streak_100'); END IF;
  IF COALESCE(v_streak, 0) >= 200 AND NOT 'omni_streak_200' = ANY(v_icons) THEN v_icons := array_append(v_icons, 'omni_streak_200'); END IF;
  IF COALESCE(v_streak, 0) >= 300 AND NOT 'omni_streak_300' = ANY(v_icons) THEN v_icons := array_append(v_icons, 'omni_streak_300'); END IF;
  UPDATE public.profiles SET unlocked_omni_icons = v_icons WHERE id = v_user_id;
  RETURN jsonb_build_object('success', true, 'unlocked_omni_icons', v_icons);
END;
$$;

-- use_omni_item is defined in streak_workflow.sql.

-- Temporary development entitlement. Replace with verified StoreKit transactions before release.
CREATE OR REPLACE FUNCTION public.activate_extraordinary_access(days integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := public.require_current_user(); v_until timestamptz;
BEGIN
  IF days NOT IN (3, 30, 365) THEN RAISE EXCEPTION 'Unsupported access duration'; END IF;
  v_until := now() + make_interval(days => days);
  UPDATE public.profiles SET extraordinary_trial_until = GREATEST(COALESCE(extraordinary_trial_until, now()), v_until)
  WHERE id = v_user_id RETURNING extraordinary_trial_until INTO v_until;
  RETURN jsonb_build_object('success', true, 'extraordinary_trial_until', v_until);
END;
$$;

CREATE OR REPLACE FUNCTION public.settle_learning_reward(correct_answers integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id uuid := public.require_current_user(); v_profile public.profiles%ROWTYPE;
  v_earned integer; v_cap_remaining integer; v_is_extra boolean;
  v_today date := timezone('Asia/Ho_Chi_Minh', now())::date;
BEGIN
  IF correct_answers < 0 OR correct_answers > 500 THEN RAISE EXCEPTION 'Invalid answer count'; END IF;
  SELECT * INTO v_profile FROM public.profiles WHERE id = v_user_id FOR UPDATE;
  v_is_extra := v_profile.extraordinary_trial_until > now();
  IF NOT v_is_extra THEN
    IF v_profile.learning_hearts_reset_date IS DISTINCT FROM v_today THEN
      v_profile.learning_hearts_remaining := 5;
      UPDATE public.profiles SET learning_hearts_remaining = 5, learning_hearts_reset_date = v_today WHERE id = v_user_id;
    END IF;
    IF v_profile.learning_hearts_remaining <= 0 THEN RAISE EXCEPTION 'No learning hearts remaining'; END IF;
  END IF;
  IF v_profile.omni_points_earned_date IS DISTINCT FROM v_today THEN
    v_profile.omni_points_earned_today := 0;
    UPDATE public.profiles SET omni_points_earned_date = v_today, omni_points_earned_today = 0 WHERE id = v_user_id;
  END IF;
  v_earned := correct_answers;
  IF v_is_extra THEN v_earned := floor(v_earned * 1.2); END IF;
  IF v_profile.double_points_until > now() THEN v_earned := v_earned * 2; END IF;
  v_cap_remaining := GREATEST(0, 500 - v_profile.omni_points_earned_today); v_earned := LEAST(v_earned, v_cap_remaining);
  UPDATE public.profiles SET omni_points = omni_points + v_earned,
    omni_points_earned_today = omni_points_earned_today + v_earned,
    learning_hearts_remaining = CASE WHEN v_is_extra THEN learning_hearts_remaining ELSE learning_hearts_remaining - 1 END
  WHERE id = v_user_id RETURNING * INTO v_profile;
  RETURN jsonb_build_object('success', true, 'earned_points', v_earned, 'new_points', v_profile.omni_points,
    'remaining_hearts', v_profile.learning_hearts_remaining);
END;
$$;

-- record_daily_activity is defined in streak_workflow.sql.

-- refresh_streak_state is defined in streak_workflow.sql.

REVOKE ALL ON FUNCTION public.require_current_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.require_current_user() TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_omni_icon(text), public.equip_omni_icon(text),
  public.activate_extraordinary_access(integer),
  public.settle_learning_reward(integer),
  public.grant_development_omni_points(integer), public.unlock_streak_omni_icons() TO authenticated;
