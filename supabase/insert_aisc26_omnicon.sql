-- Quà tặng sự kiện AISC'26, bậc A2. Có thể chạy lại.
-- Dùng luồng nhận biểu trưng hiện có với chi phí 0 điểm.
INSERT INTO public.omni_icon_catalog (
  id, name, tier, asset_name, alternate_icon_name, subtitle,
  is_extra_exclusive, points_required, streak_days_required,
  rarity, category, category_sort_order, sort_order, is_active, updated_at
) VALUES (
  'omni_aisc_26', 'AISC''26', 'points', 'OmniAISC26', 'OmniAISC26AppIcon',
  'Biểu trưng sắc đỏ kỷ niệm cuộc thi học thuật năm 2026.',
  false, 0, NULL, 'A2', 'A2', 20, 61, true, now()
)
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
  is_active = EXCLUDED.is_active,
  updated_at = EXCLUDED.updated_at
RETURNING id, name, category, points_required, asset_name, alternate_icon_name, is_active;
