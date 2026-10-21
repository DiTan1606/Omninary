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
