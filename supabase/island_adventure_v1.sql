-- Island and adventure v1: the home island (regions bought and buildings built with Omni)
-- and adventure progress. New tables and functions only; nothing existing is changed.

CREATE TABLE IF NOT EXISTS public.island_state (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  open_regions text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.island_buildings (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lot_key text NOT NULL CHECK (lot_key ~ '^[0-9]{1,3},[0-9]{1,3}$'),
  building text NOT NULL,
  built_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, lot_key)
);

CREATE TABLE IF NOT EXISTS public.adventure_progress (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  region text NOT NULL CHECK (region IN ('forest', 'lake', 'city', 'desert')),
  stages_done integer NOT NULL DEFAULT 0 CHECK (stages_done BETWEEN 0 AND 15),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, region)
);

-- One reward per finished learning session, so a stage cannot be paid twice.
CREATE TABLE IF NOT EXISTS public.adventure_stage_runs (
  session_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  region text NOT NULL,
  stage integer NOT NULL,
  quests integer NOT NULL,
  earned integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.island_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.island_buildings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adventure_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adventure_stage_runs ENABLE ROW LEVEL SECURITY;

-- Learners read their own rows; every write goes through the functions below.
CREATE POLICY island_state_own_read ON public.island_state FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY island_buildings_own_read ON public.island_buildings FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY adventure_progress_own_read ON public.adventure_progress FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY adventure_stage_runs_own_read ON public.adventure_stage_runs FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

-- Prices in Omni; must match IslandCatalog in the app.
CREATE OR REPLACE FUNCTION public.island_building_cost(p_building text)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE p_building
    WHEN 'home' THEN 200 WHEN 'fountain' THEN 200 WHEN 'windmill' THEN 150 WHEN 'bakery' THEN 300
    WHEN 'cafe' THEN 500 WHEN 'greenhouse' THEN 500 WHEN 'school' THEN 800 WHEN 'library' THEN 800
    WHEN 'pagoda' THEN 1500 WHEN 'statue' THEN 2000 ELSE NULL END;
$$;

CREATE OR REPLACE FUNCTION public.island_building_need(p_building text)
RETURNS integer LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE p_building WHEN 'pagoda' THEN 100 WHEN 'statue' THEN 200 ELSE 0 END;
$$;

-- Region id → (layer, parent, needs); layer 1 costs 800, layer 2 and joining regions 1500.
CREATE OR REPLACE FUNCTION public.island_region_rule(p_region text, OUT layer integer, OUT requires text[])
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT r.layer, r.requires FROM (VALUES
    ('A', 1, '{}'::text[]), ('B', 1, '{}'), ('C', 1, '{}'), ('D', 1, '{}'), ('E', 1, '{}'), ('F', 1, '{}'), ('G', 1, '{}'), ('H', 1, '{}'),
    ('A2', 2, '{A}'), ('B2', 2, '{B}'), ('C2', 2, '{C}'), ('D2', 2, '{D}'), ('E2', 2, '{E}'), ('F2', 2, '{F}'), ('G2', 2, '{G}'), ('H2', 2, '{H}'),
    ('J1', 2, '{A2,H2}'), ('J2', 2, '{A2,B2}'), ('J3', 2, '{F2,G2}'), ('J4', 2, '{G2,E2}'), ('J5', 2, '{C2,D2}'), ('J6', 2, '{D2,E2}')
  ) AS r(id, layer, requires) WHERE r.id = p_region;
$$;

-- Words the learner has learned at least once: one resident each.
CREATE OR REPLACE FUNCTION public.island_learned_words(p_user uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT count(*)::integer FROM public.user_vocabulary WHERE user_id = p_user AND COALESCE(learning_level, 0) >= 1;
$$;

CREATE OR REPLACE FUNCTION public.island_state_json(p_user uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'open_regions', COALESCE((SELECT to_jsonb(open_regions) FROM public.island_state WHERE user_id = p_user), '[]'::jsonb),
    'buildings', COALESCE((SELECT jsonb_object_agg(lot_key, building) FROM public.island_buildings WHERE user_id = p_user), '{}'::jsonb),
    'progress', COALESCE((SELECT jsonb_object_agg(region, stages_done) FROM public.adventure_progress WHERE user_id = p_user), '{}'::jsonb),
    'omni_points', (SELECT omni_points FROM public.profiles WHERE id = p_user),
    'learned_words', public.island_learned_words(p_user));
$$;

-- Reads the island; the first call sets up the free starter buildings.
CREATE OR REPLACE FUNCTION public.get_island_state()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid := public.require_current_user();
BEGIN
  INSERT INTO public.island_state(user_id) VALUES (u) ON CONFLICT (user_id) DO NOTHING;
  IF FOUND THEN
    INSERT INTO public.island_buildings(user_id, lot_key, building) VALUES
      (u, '38,37', 'myhouse'), (u, '43,37', 'lab'), (u, '56,36', 'shop'), (u, '42,48', 'clinic'), (u, '60,39', 'home'), (u, '46,49', 'home')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN public.island_state_json(u);
END;
$$;

CREATE OR REPLACE FUNCTION public.island_build(p_lot_key text, p_building text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid := public.require_current_user(); cost integer := public.island_building_cost(p_building);
  need integer := public.island_building_need(p_building); pts integer;
BEGIN
  IF cost IS NULL THEN RAISE EXCEPTION 'Công trình này không xây được.'; END IF;
  IF p_lot_key !~ '^[0-9]{1,3},[0-9]{1,3}$' THEN RAISE EXCEPTION 'Ô đất không hợp lệ.'; END IF;
  PERFORM public.get_island_state();
  IF EXISTS (SELECT 1 FROM public.island_buildings WHERE user_id = u AND lot_key = p_lot_key) THEN RAISE EXCEPTION 'Ô đất này đã có công trình.'; END IF;
  IF (SELECT count(*) FROM public.island_buildings WHERE user_id = u) >= 100 THEN RAISE EXCEPTION 'Đảo đã hết ô đất.'; END IF;
  IF need > 0 AND public.island_learned_words(u) < need THEN RAISE EXCEPTION 'Cần học % từ để xây công trình này.', need; END IF;
  SELECT omni_points INTO pts FROM public.profiles WHERE id = u FOR UPDATE;
  IF COALESCE(pts, 0) < cost THEN RAISE EXCEPTION 'Bạn chưa đủ điểm Omni để xây.'; END IF;
  UPDATE public.profiles SET omni_points = omni_points - cost WHERE id = u;
  INSERT INTO public.island_buildings(user_id, lot_key, building) VALUES (u, p_lot_key, p_building);
  RETURN public.island_state_json(u);
END;
$$;

CREATE OR REPLACE FUNCTION public.island_open_region(p_region text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid := public.require_current_user(); rule record; opened text[]; cost integer; pts integer;
BEGIN
  SELECT * INTO rule FROM public.island_region_rule(p_region);
  IF rule.layer IS NULL THEN RAISE EXCEPTION 'Vùng đất không hợp lệ.'; END IF;
  PERFORM public.get_island_state();
  SELECT open_regions INTO opened FROM public.island_state WHERE user_id = u FOR UPDATE;
  IF p_region = ANY(opened) THEN RAISE EXCEPTION 'Vùng đất này đã mở.'; END IF;
  IF NOT (rule.requires <@ opened) THEN RAISE EXCEPTION 'Cần mở vùng đất bên trong trước.'; END IF;
  cost := CASE WHEN rule.layer = 1 THEN 800 ELSE 1500 END;
  SELECT omni_points INTO pts FROM public.profiles WHERE id = u FOR UPDATE;
  IF COALESCE(pts, 0) < cost THEN RAISE EXCEPTION 'Bạn chưa đủ điểm Omni để mở vùng đất.'; END IF;
  UPDATE public.profiles SET omni_points = omni_points - cost WHERE id = u;
  UPDATE public.island_state SET open_regions = array_append(open_regions, p_region), updated_at = now() WHERE user_id = u;
  RETURN public.island_state_json(u);
END;
$$;

-- Pays a finished stage: 5 Omni per quest plus 50 for the stage, inside the shared 500/day cap.
-- The stage must be backed by a learning session this learner completed.
CREATE OR REPLACE FUNCTION public.adventure_complete_stage(p_session_id uuid, p_region text, p_stage integer, p_quests integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE u uuid := public.require_current_user(); need integer; done integer; p public.profiles%ROWTYPE;
  quests integer := LEAST(GREATEST(p_quests, 0), 40); earned integer;
BEGIN
  need := CASE p_region WHEN 'forest' THEN 0 WHEN 'lake' THEN 30 WHEN 'city' THEN 80 WHEN 'desert' THEN 150 ELSE NULL END;
  IF need IS NULL OR p_stage < 0 OR p_stage > 14 THEN RAISE EXCEPTION 'Màn chơi không hợp lệ.'; END IF;
  IF public.island_learned_words(u) < need THEN RAISE EXCEPTION 'Vùng này mở khi bạn học % từ.', need; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.learning_sessions WHERE session_id = p_session_id AND user_id = u AND completed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'Phiên học của màn này chưa được lưu.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.adventure_stage_runs WHERE session_id = p_session_id) THEN
    RETURN public.island_state_json(u) || jsonb_build_object('earned', 0, 'already_paid', true);
  END IF;
  INSERT INTO public.adventure_progress(user_id, region) VALUES (u, p_region) ON CONFLICT DO NOTHING;
  SELECT stages_done INTO done FROM public.adventure_progress WHERE user_id = u AND region = p_region FOR UPDATE;
  IF p_stage > done THEN RAISE EXCEPTION 'Hãy qua các màn trước đã.'; END IF;
  IF p_stage = done THEN UPDATE public.adventure_progress SET stages_done = LEAST(15, done + 1), updated_at = now() WHERE user_id = u AND region = p_region; END IF;
  SELECT * INTO p FROM public.profiles WHERE id = u FOR UPDATE;
  IF p.omni_points_earned_date IS DISTINCT FROM current_date THEN p.omni_points_earned_today := 0; END IF;
  earned := LEAST(quests * 5 + 50, GREATEST(0, 500 - COALESCE(p.omni_points_earned_today, 0)));
  UPDATE public.profiles SET omni_points = omni_points + earned, omni_points_earned_date = current_date,
    omni_points_earned_today = COALESCE(p.omni_points_earned_today, 0) + earned WHERE id = u;
  INSERT INTO public.adventure_stage_runs(session_id, user_id, region, stage, quests, earned) VALUES (p_session_id, u, p_region, p_stage, quests, earned);
  RETURN public.island_state_json(u) || jsonb_build_object('earned', earned, 'already_paid', false);
END;
$$;

REVOKE ALL ON FUNCTION public.island_state_json(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.island_learned_words(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_island_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.island_build(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.island_open_region(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.adventure_complete_stage(uuid, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_island_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.island_build(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.island_open_region(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adventure_complete_stage(uuid, text, integer, integer) TO authenticated;
