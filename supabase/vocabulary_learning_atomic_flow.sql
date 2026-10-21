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
