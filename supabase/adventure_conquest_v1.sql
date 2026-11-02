-- Adventure conquest v1: 60 maps (4 regions × 15) conquered in order, 6 levels each.
-- `words` counts 5 per finished level (30 = the map's 6 levels); a full map is collected and
-- the next one opens. An adventure with fewer than 5 due words still clears one level. Additive: adventure_complete_stage and adventure_progress stay for older apps.

CREATE TABLE IF NOT EXISTS public.adventure_conquest (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Maps collected so far, which is also the index of the map being conquered (60 = all).
  map_index integer NOT NULL DEFAULT 0 CHECK (map_index BETWEEN 0 AND 60),
  words integer NOT NULL DEFAULT 0 CHECK (words BETWEEN 0 AND 30),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.adventure_conquest ENABLE ROW LEVEL SECURITY;
CREATE POLICY adventure_conquest_own_read ON public.adventure_conquest FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

-- Learners who cleared stages before conquest keep them: one cleared stage, one collected map.
CREATE OR REPLACE FUNCTION public.adventure_conquest_start(p_user uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT LEAST(60, COALESCE(sum(stages_done), 0))::integer FROM public.adventure_progress WHERE user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION public.island_state_json(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'open_regions', COALESCE((SELECT to_jsonb(open_regions) FROM public.island_state WHERE user_id = p_user), '[]'::jsonb),
    'buildings', COALESCE((SELECT jsonb_object_agg(lot_key, building) FROM public.island_buildings WHERE user_id = p_user), '{}'::jsonb),
    'progress', COALESCE((SELECT jsonb_object_agg(region, stages_done) FROM public.adventure_progress WHERE user_id = p_user), '{}'::jsonb),
    'conquest', COALESCE((SELECT jsonb_build_object('map', map_index, 'words', words) FROM public.adventure_conquest WHERE user_id = p_user),
                         jsonb_build_object('map', public.adventure_conquest_start(p_user), 'words', 0)),
    'omni_points', (SELECT omni_points FROM public.profiles WHERE id = p_user),
    'learned_words', public.island_learned_words(p_user));
$$;

-- Pays a finished adventure and adds its words to the map being conquered.
-- Omni as before: 5 per question plus 50, inside the shared 500/day cap. One payment per session.
CREATE OR REPLACE FUNCTION public.adventure_complete(p_session_id uuid, p_words integer, p_quests integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid := public.require_current_user(); p public.profiles%ROWTYPE; c public.adventure_conquest%ROWTYPE;
  -- One finished adventure is one level (màn) of the map, however many words were due: 5 of its 30.
  gained integer := CASE WHEN p_words > 0 THEN 5 ELSE 0 END; quests integer := LEAST(GREATEST(p_quests, 0), 40);
  earned integer; map_before integer; words_before integer; collected integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.learning_sessions WHERE session_id = p_session_id AND user_id = u AND completed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Phiên học của lần phiêu lưu này chưa được lưu.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.adventure_stage_runs WHERE session_id = p_session_id) THEN
    RETURN public.island_state_json(u) || jsonb_build_object('earned', 0, 'already_paid', true);
  END IF;
  INSERT INTO public.adventure_conquest(user_id, map_index) VALUES (u, public.adventure_conquest_start(u)) ON CONFLICT DO NOTHING;
  SELECT * INTO c FROM public.adventure_conquest WHERE user_id = u FOR UPDATE;
  map_before := c.map_index; words_before := c.words;
  IF c.map_index < 60 THEN
    IF c.words + gained >= 30 THEN
      collected := c.map_index;
      UPDATE public.adventure_conquest SET map_index = c.map_index + 1, words = 0, updated_at = now() WHERE user_id = u;
    ELSE
      UPDATE public.adventure_conquest SET words = c.words + gained, updated_at = now() WHERE user_id = u;
    END IF;
  END IF;
  SELECT * INTO p FROM public.profiles WHERE id = u FOR UPDATE;
  IF p.omni_points_earned_date IS DISTINCT FROM current_date THEN p.omni_points_earned_today := 0; END IF;
  earned := LEAST(quests * 5 + 50, GREATEST(0, 500 - COALESCE(p.omni_points_earned_today, 0)));
  UPDATE public.profiles SET omni_points = omni_points + earned, omni_points_earned_date = current_date,
    omni_points_earned_today = COALESCE(p.omni_points_earned_today, 0) + earned WHERE id = u;
  INSERT INTO public.adventure_stage_runs(session_id, user_id, region, stage, quests, earned) VALUES (p_session_id, u, 'map', map_before, quests, earned);
  RETURN public.island_state_json(u) || jsonb_build_object('earned', earned, 'already_paid', false,
    'map_before', map_before, 'words_before', words_before, 'gained', gained, 'collected', collected);
END;
$$;

REVOKE ALL ON FUNCTION public.adventure_conquest_start(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.island_state_json(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.adventure_complete(uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.adventure_complete(uuid, integer, integer) TO authenticated;
