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
