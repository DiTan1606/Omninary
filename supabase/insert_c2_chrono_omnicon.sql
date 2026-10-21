-- =============================================================================
-- Migration: Insert Omnicon C2 "Cỗ Máy Thời Gian" (Chrono-Omni)
-- Chạy script này trực tiếp trong Supabase SQL Editor.
-- Script hỗ trợ UPSERT (ON CONFLICT DO UPDATE) an toàn, có thể chạy lại nhiều lần.
-- =============================================================================

INSERT INTO public.omni_icon_catalog (
  id,
  name,
  tier,
  asset_name,
  alternate_icon_name,
  subtitle,
  is_extra_exclusive,
  points_required,
  streak_days_required,
  rarity,
  category,
  category_sort_order,
  sort_order,
  is_active,
  updated_at
) VALUES (
  'omni_mythic_imperial_chrono',
  'Cỗ Máy Thời Gian',
  'points',
  'OmniMythicImperialChrono',
  'OmniMythicImperialChronoAppIcon',
  'Cỗ máy thời gian hoàng kim vĩnh cửu với bộ 3 kim đồng hồ và cơ khí lộ máy.',
  false,
  15000,
  NULL,
  'C2',
  'C2',
  60,
  140,
  true,
  now()
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
  is_active = true,
  updated_at = now();

-- Kiểm tra lại bản ghi vừa thêm
SELECT 
  id, 
  name, 
  category, 
  rarity, 
  points_required, 
  asset_name, 
  alternate_icon_name, 
  is_active
FROM public.omni_icon_catalog
WHERE id = 'omni_mythic_imperial_chrono';
