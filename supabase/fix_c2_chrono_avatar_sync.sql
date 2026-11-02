-- =============================================================================
-- Migration: Sửa triệt để lỗi đồng bộ Avatar & RPC equip_omni_icon cho Cỗ Máy Thời Gian
-- Hướng dẫn: Mở Supabase Dashboard -> SQL Editor -> Dán toàn bộ nội dung này và nhấn RUN.
-- =============================================================================

-- 1. Cập nhật hàm equip_omni_icon trên Supabase:
--    - Cho phép trang bị 'omni_mythic_imperial_chrono' và bất kỳ icon nào khi có quyền Extraordinary
--    - Tự động bổ sung icon vào danh sách unlocked_omni_icons nếu chưa có để đảm bảo tính toàn vẹn
CREATE OR REPLACE FUNCTION public.equip_omni_icon(icon_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE 
  v_user_id uuid := public.require_current_user(); 
  v_icons text[];
  v_is_extra boolean := false;
BEGIN
  SELECT unlocked_omni_icons, (COALESCE(extraordinary_trial_until, '-infinity'::timestamptz) > now())
  INTO v_icons, v_is_extra 
  FROM public.profiles 
  WHERE id = v_user_id FOR UPDATE;

  -- Kiểm tra quyền: Cho phép nếu là ditandnary_classic, cỗ máy thời gian, đã mở khóa, hoặc user Extraordinary
  IF icon_id <> 'ditandnary_classic' 
     AND icon_id <> 'omni_mythic_imperial_chrono'
     AND NOT icon_id = ANY(v_icons) 
     AND NOT v_is_extra THEN 
    RAISE EXCEPTION 'Icon is not unlocked'; 
  END IF;

  -- Đảm bảo icon đã trang bị cũng có mặt trong danh sách unlocked_omni_icons
  IF NOT (icon_id = ANY(v_icons)) THEN
    v_icons := array_append(v_icons, icon_id);
    UPDATE public.profiles 
    SET equipped_omni_icon = icon_id, 
        unlocked_omni_icons = v_icons 
    WHERE id = v_user_id;
  ELSE
    UPDATE public.profiles 
    SET equipped_omni_icon = icon_id 
    WHERE id = v_user_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'equipped_omni_icon', icon_id, 'unlocked_omni_icons', v_icons);
END;
$$;

-- Cấp quyền gọi RPC cho người dùng đã đăng nhập (authenticated)
GRANT EXECUTE ON FUNCTION public.equip_omni_icon(text) TO authenticated;

-- 2. Thêm 'omni_mythic_imperial_chrono' vào danh sách đã mở khóa của người dùng
UPDATE public.profiles
SET unlocked_omni_icons = array_append(unlocked_omni_icons, 'omni_mythic_imperial_chrono')
WHERE NOT ('omni_mythic_imperial_chrono' = ANY(unlocked_omni_icons));

-- 3. Cập nhật icon đang trang bị trên database thành 'omni_mythic_imperial_chrono'
--    (áp dụng cho tài khoản Extraordinary hoặc tài khoản hiện tại)
UPDATE public.profiles
SET equipped_omni_icon = 'omni_mythic_imperial_chrono'
WHERE extraordinary_trial_until > now() OR id = auth.uid() OR email = 'tranleduytan166@gmail.com';

-- 4. Xác nhận kết quả
SELECT id, display_name, email, equipped_omni_icon, unlocked_omni_icons
FROM public.profiles
WHERE equipped_omni_icon = 'omni_mythic_imperial_chrono';
