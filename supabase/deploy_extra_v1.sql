-- DEPLOY EXTRA V1 (22/10/2026). Run once; safe to re-run. One transaction.
-- 1) Ditan: 10 sessions/day; larger word selections for Extra.
-- 2) Extra v1 adaptive tables, rules and complete_vocabulary_learning_session_v2.
BEGIN;

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
    SET learning_hearts_remaining = 10,
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
  IF p_correct_answers < 0 OR p_correct_answers > 5000 THEN
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
  -- Extra lets the learner pick any number of due words for one session.
  IF v_requested_count = 0 OR v_requested_count > 300 THEN
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

  -- Ditan gets exactly ten sessions per Vietnam calendar day (experiment schedule).
  IF NOT v_is_extra AND v_profile.learning_hearts_reset_date IS DISTINCT FROM v_today THEN
    UPDATE public.profiles
    SET learning_hearts_remaining = 10,
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


-- 1. Richer attempt evidence ---------------------------------------------------
ALTER TABLE public.learning_attempts
  ADD COLUMN IF NOT EXISTS attempt_score integer CHECK (attempt_score BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS skill_costs jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS signals jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS is_reinforcement boolean NOT NULL DEFAULT false;

ALTER TABLE public.learning_sessions
  ADD COLUMN IF NOT EXISTS algorithm_version text;

-- 2. One row per word per review: what was observed and what was decided -------
CREATE TABLE IF NOT EXISTS public.learning_word_mastery (
  session_id uuid NOT NULL REFERENCES public.learning_sessions(session_id) ON DELETE CASCADE,
  user_vocabulary_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  mode text NOT NULL CHECK (mode IN ('ditandnary', 'extraordinary')),
  level_before integer,
  reached_level integer,
  stored_level integer,
  level_attempt integer NOT NULL DEFAULT 1,
  exercise_scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  skill_scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  mastery integer CHECK (mastery BETWEEN 0 AND 100),
  previous_mastery integer,
  decision text NOT NULL CHECK (decision IN ('jump', 'advance', 'hold')),
  next_review timestamptz,
  attempt_count integer NOT NULL DEFAULT 0,
  reinforcement_count integer NOT NULL DEFAULT 0,
  algorithm_version text NOT NULL DEFAULT 'extra_v1',
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, user_vocabulary_id)
);

CREATE INDEX IF NOT EXISTS learning_word_mastery_user_word_idx
  ON public.learning_word_mastery (user_id, user_vocabulary_id, created_at DESC);

-- 3. Current skill profile per learner × word (drives reinforcement) ------------
CREATE TABLE IF NOT EXISTS public.learner_word_skill_profiles (
  user_vocabulary_id text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  skill_ewma jsonb NOT NULL DEFAULT '{}'::jsonb,
  exercise_ewma jsonb NOT NULL DEFAULT '{}'::jsonb,
  spelling_cost_by_type jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_first_asked jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_mastery integer,
  is_holding boolean NOT NULL DEFAULT false,
  hold_attempt integer NOT NULL DEFAULT 0,
  observations integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS learner_word_skill_profiles_user_idx
  ON public.learner_word_skill_profiles (user_id);

ALTER TABLE public.learning_word_mastery ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learner_word_skill_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own word mastery" ON public.learning_word_mastery;
CREATE POLICY "Users can read own word mastery"
  ON public.learning_word_mastery FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS "Users can read own skill profiles" ON public.learner_word_skill_profiles;
CREATE POLICY "Users can read own skill profiles"
  ON public.learner_word_skill_profiles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

-- Evidence and decisions are written only by the function below.
REVOKE ALL ON TABLE public.learning_word_mastery FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.learner_word_skill_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.learning_word_mastery TO authenticated;
GRANT SELECT ON TABLE public.learner_word_skill_profiles TO authenticated;

-- 4. Pure rules ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.extra_v1_review_days(p_level integer)
RETURNS integer
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_level IS NULL OR p_level < 1 THEN 0
    WHEN p_level = 1 THEN 1 WHEN p_level = 2 THEN 3 WHEN p_level = 3 THEN 7
    WHEN p_level = 4 THEN 15 WHEN p_level = 5 THEN 30 WHEN p_level = 6 THEN 60
    WHEN p_level = 7 THEN 120 WHEN p_level = 8 THEN 240 WHEN p_level = 9 THEN 365
    ELSE NULL
  END
$$;

-- Mirrors ExtraScheduler.decide in the app (LearningEngine.swift).
CREATE OR REPLACE FUNCTION public.extra_v1_decide(
  p_level_before integer,
  p_is_holding boolean,
  p_mastery integer,
  p_previous_mastery integer
)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_level integer := GREATEST(COALESCE(p_level_before, 0), 0);
  v_reached integer;
  v_drop integer;
  v_ratio numeric;
  v_days integer;
BEGIN
  v_reached := LEAST(CASE WHEN p_is_holding THEN GREATEST(v_level, 1) ELSE v_level + 1 END, 10);
  v_drop := GREATEST(0, COALESCE(p_previous_mastery, p_mastery) - p_mastery);

  IF p_mastery >= 85 AND v_drop <= 5 THEN
    RETURN jsonb_build_object('kind', 'jump', 'reached', v_reached,
      'stored', LEAST(v_reached + 1, 10), 'days', public.extra_v1_review_days(LEAST(v_reached + 1, 10)));
  END IF;

  IF p_mastery < 60 OR v_drop >= 20 THEN
    v_ratio := LEAST(0.80, GREATEST(0.15, p_mastery / 100.0 - v_drop / 200.0));
    v_days := GREATEST(1, round(public.extra_v1_review_days(v_reached - 1) * v_ratio)::integer);
    RETURN jsonb_build_object('kind', 'hold', 'reached', v_reached, 'stored', v_reached,
      'days', CASE WHEN v_reached >= 10 THEN NULL ELSE v_days END);
  END IF;

  RETURN jsonb_build_object('kind', 'advance', 'reached', v_reached, 'stored', v_reached,
    'days', public.extra_v1_review_days(v_reached));
END;
$$;

CREATE OR REPLACE FUNCTION public.extra_v1_type_weight(p_task_type text)
RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE p_task_type
    WHEN 'listen_and_type' THEN 0.20
    WHEN 'meaning_and_type' THEN 0.25
    WHEN 'multiple_choice' THEN 0.15
    WHEN 'sentence_scramble' THEN 0.20
    WHEN 'pronunciation_example' THEN 0.20
    ELSE 0
  END
$$;

-- EWMA merge of two {key: number} objects (α = 0.5); missing old values take the new one.
CREATE OR REPLACE FUNCTION public.extra_v1_ewma(p_old jsonb, p_new jsonb)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT COALESCE(p_old, '{}'::jsonb) || COALESCE((
    SELECT jsonb_object_agg(n.key, round(
      CASE WHEN p_old ? n.key THEN 0.5 * (p_old ->> n.key)::numeric + 0.5 * n.value::text::numeric
           ELSE n.value::text::numeric END, 1))
    FROM jsonb_each(COALESCE(p_new, '{}'::jsonb)) n
  ), '{}'::jsonb)
$$;

-- 5. Session completion v2 ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_vocabulary_learning_session_v2(
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
  v_is_extra boolean;
  v_started_at timestamptz;
  v_bad integer;
  v_word text;
  v_level_before integer;
  v_profile public.learner_word_skill_profiles%ROWTYPE;
  v_has_profile boolean;
  v_exercise jsonb;
  v_skills jsonb;
  v_spelling jsonb;
  v_first_type text;
  v_mastery integer;
  v_attempt_count integer;
  v_reinforcements integer;
  v_decision jsonb;
  v_kind text;
  v_stored integer;
  v_next timestamptz;
  v_level_attempt integer;
  v_words jsonb := '[]'::jsonb;
BEGIN
  IF jsonb_typeof(COALESCE(p_attempts, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'Learning attempts must be an array';
  END IF;
  IF jsonb_array_length(COALESCE(p_attempts, '[]'::jsonb)) > 5000 THEN
    RAISE EXCEPTION 'Too many learning attempts';
  END IF;

  -- Owns idempotency, hearts, streak, points and the Ditan +1 level step.
  v_result := public.complete_vocabulary_learning_session(p_session_id, p_user_vocabulary_ids, p_correct_answers);

  IF COALESCE((v_result ->> 'already_completed')::boolean, false) THEN
    SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY m.user_vocabulary_id), '[]'::jsonb) INTO v_words
    FROM public.learning_word_mastery m
    WHERE m.session_id = p_session_id AND m.user_id = v_user_id;
    RETURN v_result || jsonb_build_object('telemetry_recorded', true, 'word_results', v_words);
  END IF;

  v_is_extra := COALESCE((v_result ->> 'is_extra')::boolean, false);

  SELECT COALESCE(array_agg(DISTINCT value ORDER BY value), ARRAY[]::text[]) INTO v_ids
  FROM unnest(COALESCE(p_user_vocabulary_ids, ARRAY[]::text[])) AS requested(value)
  WHERE NULLIF(btrim(value), '') IS NOT NULL;

  v_started_at := GREATEST(now() - interval '24 hours',
    LEAST(COALESCE(p_started_at, now()), now() + interval '5 minutes'));

  CREATE TEMP TABLE IF NOT EXISTS pg_temp.extra_attempts (
    attempt_id uuid, exercise_id uuid, user_vocabulary_ids text[], task_type text,
    attempt_number integer, is_correct boolean, answer_text text, response_duration_ms integer,
    pronunciation_score integer, answered_at timestamptz, attempt_score integer,
    skill_costs jsonb, signals jsonb, is_reinforcement boolean
  ) ON COMMIT DROP;
  TRUNCATE pg_temp.extra_attempts;

  INSERT INTO pg_temp.extra_attempts
  SELECT
    (item ->> 'attempt_id')::uuid,
    (item ->> 'exercise_id')::uuid,
    ARRAY(SELECT jsonb_array_elements_text(COALESCE(item -> 'user_vocabulary_ids', '[]'::jsonb))),
    item ->> 'task_type',
    (item ->> 'attempt_number')::integer,
    (item ->> 'is_correct')::boolean,
    left(NULLIF(item ->> 'answer_text', ''), 1000),
    (item ->> 'response_duration_ms')::integer,
    NULLIF(item ->> 'pronunciation_score', '')::integer,
    (item ->> 'answered_at')::timestamptz,
    (item ->> 'attempt_score')::integer,
    COALESCE(item -> 'skill_costs', '{}'::jsonb),
    COALESCE(item -> 'signals', '{}'::jsonb),
    COALESCE((item ->> 'is_reinforcement')::boolean, false)
  FROM jsonb_array_elements(COALESCE(p_attempts, '[]'::jsonb)) AS item;

  SELECT count(*) INTO v_bad FROM pg_temp.extra_attempts a
  WHERE a.attempt_id IS NULL OR a.exercise_id IS NULL
     OR cardinality(a.user_vocabulary_ids) = 0
     OR EXISTS (SELECT 1 FROM unnest(a.user_vocabulary_ids) x WHERE x <> ALL(v_ids))
     OR a.task_type NOT IN ('listen_and_type', 'meaning_and_type', 'multiple_choice', 'sentence_scramble', 'pronunciation_example')
     OR a.attempt_number NOT BETWEEN 1 AND 50
     OR a.is_correct IS NULL
     OR a.response_duration_ms NOT BETWEEN 0 AND 600000
     OR (a.pronunciation_score IS NOT NULL AND a.pronunciation_score NOT BETWEEN 0 AND 100)
     OR a.attempt_score IS NULL OR a.attempt_score NOT BETWEEN 0 AND 100
     OR jsonb_typeof(a.skill_costs) <> 'object'
     OR EXISTS (SELECT 1 FROM jsonb_each(a.skill_costs) c
                WHERE c.key NOT IN ('meaning', 'recall', 'spelling', 'sound', 'context')
                   OR jsonb_typeof(c.value) <> 'number'
                   OR (c.value::text)::numeric NOT BETWEEN 0 AND 5000)
     OR a.answered_at NOT BETWEEN v_started_at - interval '5 minutes' AND now() + interval '5 minutes';
  IF v_bad > 0 OR (SELECT count(*) <> count(DISTINCT attempt_id) FROM pg_temp.extra_attempts) THEN
    RAISE EXCEPTION 'Learning attempt data is invalid';
  END IF;

  INSERT INTO public.learning_sessions (session_id, user_id, started_at, is_extra, task_count, correct_answers, algorithm_version)
  VALUES (p_session_id, v_user_id, v_started_at, v_is_extra,
          (SELECT count(*) FROM pg_temp.extra_attempts), p_correct_answers, 'extra_v1');

  INSERT INTO public.learning_attempts (
    attempt_id, session_id, exercise_id, user_vocabulary_ids, task_type, attempt_number,
    is_correct, answer_text, response_duration_ms, pronunciation_score, answered_at,
    attempt_score, skill_costs, signals, is_reinforcement)
  SELECT attempt_id, p_session_id, exercise_id, user_vocabulary_ids, task_type, attempt_number,
         is_correct, answer_text, response_duration_ms, pronunciation_score, answered_at,
         attempt_score, skill_costs, signals, is_reinforcement
  FROM pg_temp.extra_attempts;

  FOREACH v_word IN ARRAY v_ids LOOP
    -- The base function moved every due word up one level; recover the level before.
    SELECT learning_level - 1 INTO v_level_before
    FROM public.user_vocabulary WHERE user_id = v_user_id AND id::text = v_word;

    SELECT * INTO v_profile FROM public.learner_word_skill_profiles
    WHERE user_vocabulary_id = v_word AND user_id = v_user_id FOR UPDATE;
    v_has_profile := FOUND;

    -- Exercise score per type over the whole process: 100 / (1 + Σ lost / 100).
    SELECT COALESCE(jsonb_object_agg(task_type, round(100.0 / (1 + lost / 100.0), 1)), '{}'::jsonb)
    INTO v_exercise
    FROM (SELECT task_type, sum(100 - attempt_score)::numeric AS lost
          FROM pg_temp.extra_attempts WHERE v_word = ANY(user_vocabulary_ids) GROUP BY task_type) t;

    -- Skill scores from the per-skill costs of every attempt of this word.
    SELECT COALESCE(jsonb_object_agg(key, round(100.0 / (1 + cost / 100.0), 1)), '{}'::jsonb)
    INTO v_skills
    FROM (SELECT c.key, sum((c.value::text)::numeric) AS cost
          FROM pg_temp.extra_attempts a, jsonb_each(a.skill_costs) c
          WHERE v_word = ANY(a.user_vocabulary_ids) GROUP BY c.key) s;

    SELECT COALESCE(jsonb_object_agg(task_type, cost), '{}'::jsonb) INTO v_spelling
    FROM (SELECT a.task_type, sum((a.skill_costs ->> 'spelling')::numeric) AS cost
          FROM pg_temp.extra_attempts a
          WHERE v_word = ANY(a.user_vocabulary_ids) AND a.skill_costs ? 'spelling'
          GROUP BY a.task_type) s;

    SELECT task_type INTO v_first_type FROM pg_temp.extra_attempts
    WHERE v_word = ANY(user_vocabulary_ids) ORDER BY answered_at, attempt_number LIMIT 1;

    SELECT round(sum(public.extra_v1_type_weight(e.key) * (e.value::text)::numeric)
                 / NULLIF(sum(public.extra_v1_type_weight(e.key)), 0))::integer
    INTO v_mastery FROM jsonb_each(v_exercise) e;

    SELECT count(*), count(*) FILTER (WHERE is_reinforcement AND attempt_number = 1)
    INTO v_attempt_count, v_reinforcements
    FROM pg_temp.extra_attempts WHERE v_word = ANY(user_vocabulary_ids);

    IF v_is_extra AND v_mastery IS NOT NULL THEN
      v_decision := public.extra_v1_decide(v_level_before, COALESCE(v_profile.is_holding, false),
                                           v_mastery, v_profile.last_mastery);
    ELSE
      -- Ditan (or a session without evidence) keeps the fixed +1 step already applied.
      v_decision := jsonb_build_object('kind', 'advance', 'reached', v_level_before + 1,
        'stored', v_level_before + 1, 'days', public.extra_v1_review_days(v_level_before + 1));
    END IF;

    v_kind := v_decision ->> 'kind';
    v_stored := (v_decision ->> 'stored')::integer;
    v_next := CASE WHEN v_decision ->> 'days' IS NULL THEN NULL
                   ELSE now() + make_interval(days => (v_decision ->> 'days')::integer) END;
    v_level_attempt := CASE WHEN v_kind = 'hold' AND COALESCE(v_profile.is_holding, false)
                            THEN COALESCE(v_profile.hold_attempt, 1) + 1
                            ELSE 1 END;

    IF v_is_extra THEN
      UPDATE public.user_vocabulary
      SET learning_level = v_stored, next_review = v_next
      WHERE user_id = v_user_id AND id::text = v_word;
    END IF;

    INSERT INTO public.learner_word_skill_profiles AS p (
      user_vocabulary_id, user_id, skill_ewma, exercise_ewma, spelling_cost_by_type,
      last_first_asked, last_mastery, is_holding, hold_attempt, observations, updated_at)
    VALUES (
      v_word, v_user_id, v_skills, v_exercise, v_spelling,
      CASE WHEN v_first_type IS NULL THEN '{}'::jsonb ELSE jsonb_build_object(v_first_type, now()) END,
      COALESCE(v_mastery, v_profile.last_mastery),
      v_is_extra AND v_kind = 'hold', CASE WHEN v_kind = 'hold' THEN v_level_attempt ELSE 0 END,
      1, now())
    ON CONFLICT (user_vocabulary_id) DO UPDATE SET
      skill_ewma = public.extra_v1_ewma(p.skill_ewma, EXCLUDED.skill_ewma),
      exercise_ewma = public.extra_v1_ewma(p.exercise_ewma, EXCLUDED.exercise_ewma),
      spelling_cost_by_type = EXCLUDED.spelling_cost_by_type,
      last_first_asked = p.last_first_asked || EXCLUDED.last_first_asked,
      last_mastery = EXCLUDED.last_mastery,
      is_holding = EXCLUDED.is_holding,
      hold_attempt = EXCLUDED.hold_attempt,
      observations = p.observations + 1,
      updated_at = now()
    WHERE p.user_id = v_user_id;

    INSERT INTO public.learning_word_mastery (
      session_id, user_vocabulary_id, user_id, mode, level_before, reached_level, stored_level,
      level_attempt, exercise_scores, skill_scores, mastery, previous_mastery, decision,
      next_review, attempt_count, reinforcement_count)
    VALUES (
      p_session_id, v_word, v_user_id, CASE WHEN v_is_extra THEN 'extraordinary' ELSE 'ditandnary' END,
      v_level_before, (v_decision ->> 'reached')::integer, v_stored, v_level_attempt,
      v_exercise, v_skills, v_mastery, v_profile.last_mastery, v_kind,
      CASE WHEN v_is_extra THEN v_next ELSE
        (SELECT next_review::timestamptz FROM public.user_vocabulary WHERE user_id = v_user_id AND id::text = v_word) END,
      v_attempt_count, v_reinforcements);
  END LOOP;

  SELECT COALESCE(jsonb_agg(to_jsonb(m) ORDER BY m.user_vocabulary_id), '[]'::jsonb) INTO v_words
  FROM public.learning_word_mastery m WHERE m.session_id = p_session_id;

  RETURN v_result || jsonb_build_object('telemetry_recorded', true, 'algorithm_version', 'extra_v1',
                                        'word_results', v_words);
END;
$$;

-- Pure helpers never depend on the caller's search_path.
ALTER FUNCTION public.extra_v1_review_days(integer) SET search_path = '';
ALTER FUNCTION public.extra_v1_decide(integer, boolean, integer, integer) SET search_path = '';
ALTER FUNCTION public.extra_v1_type_weight(text) SET search_path = '';
ALTER FUNCTION public.extra_v1_ewma(jsonb, jsonb) SET search_path = '';
REVOKE EXECUTE ON FUNCTION public.extra_v1_decide(integer, boolean, integer, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.extra_v1_ewma(jsonb, jsonb) FROM anon;

REVOKE ALL ON FUNCTION public.complete_vocabulary_learning_session_v2(uuid, text[], integer, jsonb, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_vocabulary_learning_session_v2(uuid, text[], integer, jsonb, timestamptz) TO authenticated;

COMMIT;
