-- =============================================================================
-- Omnicon single-source catalog, grouped by CEFR level:
-- A1 = Tiêu chuẩn, A2 = Hiếm, B1 = Sử thi, B2 = Huyền thoại,
-- C1 = Thần thoại, C2 = cấp tối thượng dành cho Omnicon tương lai.
-- Run after omni_points_and_icons.sql. This script is safe to re-run.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.omni_icon_catalog (
  id text PRIMARY KEY,
  name text NOT NULL,
  tier text NOT NULL CHECK (tier IN ('signature', 'streak', 'points')),
  asset_name text NOT NULL,
  alternate_icon_name text,
  subtitle text NOT NULL DEFAULT '',
  is_extra_exclusive boolean NOT NULL DEFAULT false,
  points_required integer CHECK (points_required IS NULL OR points_required >= 0),
  streak_days_required integer CHECK (streak_days_required IS NULL OR streak_days_required >= 0),
  rarity text NOT NULL,
  category text NOT NULL,
  category_sort_order integer NOT NULL DEFAULT 0,
  sort_order integer NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((points_required IS NULL) OR tier = 'points'),
  CHECK ((streak_days_required IS NULL) OR tier = 'streak')
);

INSERT INTO public.omni_icon_catalog
  (id, name, tier, asset_name, alternate_icon_name, subtitle, is_extra_exclusive, points_required, streak_days_required, rarity, category, category_sort_order, sort_order)
VALUES
  ('ditandnary_classic', 'Ditandnary Classic', 'signature', 'OmniIconDitandnary', NULL, 'Kính mờ xanh băng nguyên bản của Ditandnary.', false, NULL, NULL, 'A1', 'A1', 10, 10),
  ('extraordinary_aurora', 'Extraordinary Aurora', 'signature', 'OmniIconExtraordinary', 'OmniExtraordinaryAppIcon', 'Cực quang tím neon huyền ảo của Extraordinary.', true, NULL, NULL, 'A1', 'A1', 10, 20),
  ('omni_streak_30', 'Streak 30 days', 'streak', 'OmniStreak30', 'OmniStreak30AppIcon', 'Ngọn lửa vinh danh chuỗi 30 ngày học liên tục.', false, NULL, 30, 'A2', 'A2', 20, 30),
  ('omni_streak_100', 'Streak 100 days', 'streak', 'OmniStreak100', 'OmniStreak100AppIcon', 'Lửa xanh điện tử vinh danh chuỗi 100 ngày bền bỉ.', false, NULL, 100, 'A2', 'A2', 20, 40),
  ('omni_streak_200', 'Streak 200 days', 'streak', 'OmniStreak200', 'OmniStreak200AppIcon', 'Sắc tím thiên hà vinh danh chuỗi 200 ngày xuất sắc.', false, NULL, 200, 'A2', 'A2', 20, 50),
  ('omni_streak_300', 'Streak 300 days', 'streak', 'OmniStreak300', 'OmniStreak300AppIcon', 'Hoàng kim thái dương vinh danh chuỗi 300+ ngày.', false, NULL, 300, 'A2', 'A2', 20, 60),
  ('omni_aisc_26', 'AISC''26', 'points', 'OmniAISC26', 'OmniAISC26AppIcon', 'Biểu trưng sắc đỏ kỷ niệm cuộc thi học thuật năm 2026.', false, 0, NULL, 'A2', 'A2', 20, 61),
  ('omni_season_spring', 'Sakura Bloom', 'points', 'OmniSeasonSpring', 'OmniSeasonSpringAppIcon', 'Hoa đào mùa xuân.', false, 5000, NULL, 'B1', 'B1', 30, 70),
  ('omni_season_summer', 'Summer Sea', 'points', 'OmniSeasonSummer', 'OmniSeasonSummerAppIcon', 'Biển xanh mùa hạ.', false, 5000, NULL, 'B1', 'B1', 30, 80),
  ('omni_season_autumn', 'Maple Leaf', 'points', 'OmniSeasonAutumn', 'OmniSeasonAutumnAppIcon', 'Lá phong mùa thu.', false, 5000, NULL, 'B1', 'B1', 30, 90),
  ('omni_season_winter', 'Snow Frost', 'points', 'OmniSeasonWinter', 'OmniSeasonWinterAppIcon', 'Băng tuyết mùa đông.', false, 5000, NULL, 'B1', 'B1', 30, 100),
  ('omni_legendary_celestial_oracle', 'Celestial Oracle', 'points', 'OmniLegendaryCelestialOracle', 'OmniLegendaryCelestialOracleAppIcon', 'Ngọc thiên thể khắc chòm sao, bao bọc một quỹ đạo ánh sáng.', false, 8000, NULL, 'B2', 'B2', 40, 110),
  ('omni_legendary_imperial_koi', 'Imperial Koi', 'points', 'OmniLegendaryImperialKoi', 'OmniLegendaryImperialKoiAppIcon', 'Cặp cá koi hoàng gia bơi giữa sóng mực và sơn mài vàng son.', false, 8000, NULL, 'B2', 'B2', 40, 120),
  ('omni_mythic_jade_dragon', 'Jade Dragon', 'points', 'OmniMythicJadeDragon', 'OmniMythicJadeDragonAppIcon', 'Thanh long thời Lý ngự trên bầu trời sao và ngọc cẩm thạch.', false, 10000, NULL, 'Thần thoại', 'Thần thoại', 50, 130),
  ('omni_mythic_imperial_chrono', 'Chrono-Omni', 'points', 'OmniMythicImperialChrono', 'OmniMythicImperialChronoAppIcon', 'Cỗ máy thời gian hoàng kim vĩnh cửu với bộ 3 kim đồng hồ và cơ khí lộ máy.', false, 15000, NULL, 'C2', 'C2', 60, 140)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  tier = EXCLUDED.tier,
  asset_name = EXCLUDED.asset_name,
  alternate_icon_name = EXCLUDED.alternate_icon_name,
  subtitle = EXCLUDED.subtitle,
  is_extra_exclusive = EXCLUDED.is_extra_exclusive,
  points_required = EXCLUDED.points_required,
  streak_days_required = EXCLUDED.streak_days_required,
  rarity = EXCLUDED.rarity,
  category = EXCLUDED.category,
  category_sort_order = EXCLUDED.category_sort_order,
  sort_order = EXCLUDED.sort_order,
  is_active = true,
  updated_at = now();

-- Migrate any catalog rows that were created before the CEFR naming scheme.
UPDATE public.omni_icon_catalog
SET
  rarity = CASE rarity
    WHEN 'Tiêu chuẩn' THEN 'A1'
    WHEN 'Hiếm' THEN 'A2'
    WHEN 'Sử thi' THEN 'B1'
    WHEN 'Huyền thoại' THEN 'B2'
    WHEN 'Thần thoại' THEN 'C1'
    ELSE rarity
  END,
  category = CASE category
    WHEN 'Tiêu chuẩn' THEN 'A1'
    WHEN 'Hiếm' THEN 'A2'
    WHEN 'Sử thi' THEN 'B1'
    WHEN 'Huyền thoại' THEN 'B2'
    WHEN 'Thần thoại' THEN 'C1'
    ELSE category
  END,
  category_sort_order = CASE category
    WHEN 'Tiêu chuẩn' THEN 10
    WHEN 'A1' THEN 10
    WHEN 'Hiếm' THEN 20
    WHEN 'A2' THEN 20
    WHEN 'Sử thi' THEN 30
    WHEN 'B1' THEN 30
    WHEN 'Huyền thoại' THEN 40
    WHEN 'B2' THEN 40
    WHEN 'Thần thoại' THEN 50
    WHEN 'C1' THEN 50
    WHEN 'C2' THEN 60
    ELSE category_sort_order
  END;

ALTER TABLE public.omni_icon_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated users can read active Omnicon catalog" ON public.omni_icon_catalog;
CREATE POLICY "Authenticated users can read active Omnicon catalog"
ON public.omni_icon_catalog FOR SELECT TO authenticated
USING (is_active = true);
REVOKE ALL ON TABLE public.omni_icon_catalog FROM anon, authenticated;
GRANT SELECT ON TABLE public.omni_icon_catalog TO authenticated;

-- Price validation and deduction share this exact catalog with the app UI.
CREATE OR REPLACE FUNCTION public.omni_icon_cost(p_icon_id text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT points_required
  FROM public.omni_icon_catalog
  WHERE id = p_icon_id AND is_active = true AND points_required IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.omni_icon_cost(text) FROM PUBLIC;
