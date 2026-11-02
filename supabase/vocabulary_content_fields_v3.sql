-- Vocabulary content v3: 17 content attributes, one independent catalog item.
-- Run after vocabulary_independent_items.sql. Safe to rerun.
-- Adds content fields only; does not import, rewrite or reset vocabulary/progress.
BEGIN;

ALTER TABLE public.vocab_catalog
  ADD COLUMN IF NOT EXISTS collocation text,
  ADD COLUMN IF NOT EXISTS idioms text,
  ADD COLUMN IF NOT EXISTS formula text,
  ADD COLUMN IF NOT EXISTS note text;

ALTER TABLE public.topic_submission_words
  ADD COLUMN IF NOT EXISTS collocation text,
  ADD COLUMN IF NOT EXISTS idioms text,
  ADD COLUMN IF NOT EXISTS formula text,
  ADD COLUMN IF NOT EXISTS note text;

COMMENT ON COLUMN public.vocab_catalog.collocation IS 'Cụm từ thường đi cùng bản ghi từ vựng này. Văn bản biên soạn, chưa phải danh sách đáp án tự động.';
COMMENT ON COLUMN public.vocab_catalog.idioms IS 'Thành ngữ liên quan; lưu nguyên diễn giải và ngữ cảnh nếu có.';
COMMENT ON COLUMN public.vocab_catalog.formula IS 'Mẫu cấu trúc ngữ pháp/cách kết hợp. Không phải công thức cần thực thi.';
COMMENT ON COLUMN public.vocab_catalog.note IS 'Ghi chú cách dùng, phân biệt từ, sắc thái và lỗi thường gặp.';
COMMENT ON COLUMN public.vocab_catalog.bonus IS 'Thông tin mở rộng bổ sung; tách biệt với ghi chú cách dùng trong note.';
COMMENT ON COLUMN public.topic_submission_words.collocation IS 'Bản chụp cụm từ thường đi cùng tại thời điểm gửi duyệt.';
COMMENT ON COLUMN public.topic_submission_words.idioms IS 'Bản chụp thành ngữ tại thời điểm gửi duyệt.';
COMMENT ON COLUMN public.topic_submission_words.formula IS 'Bản chụp mẫu cấu trúc tại thời điểm gửi duyệt.';
COMMENT ON COLUMN public.topic_submission_words.note IS 'Bản chụp ghi chú cách dùng tại thời điểm gửi duyệt.';

CREATE OR REPLACE FUNCTION public.create_vocabulary_item(
  p_vocab jsonb, p_topic_id uuid DEFAULT NULL, p_as_system boolean DEFAULT false
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u uuid := public.require_current_user();
  new_id uuid := gen_random_uuid();
  t public.topics%ROWTYPE;
BEGIN
  IF p_as_system AND NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF NULLIF(btrim(p_vocab->>'word'),'') IS NULL THEN RAISE EXCEPTION 'A word is required'; END IF;
  IF p_topic_id IS NOT NULL THEN
    SELECT * INTO t FROM public.topics WHERE id=p_topic_id;
    IF NOT FOUND OR NOT(t.visibility='system' OR (t.visibility='private' AND t.owner_id=u) OR public.is_admin()) THEN
      RAISE EXCEPTION 'Topic is not accessible';
    END IF;
  END IF;
  INSERT INTO public.vocab_catalog(
    id,topic_id,created_by,visibility,word,cefr,ipa,word_form,
    e_meaning,ev_meaning,v_meaning,e_example,v_example,
    word_family,synonymous,antonym,collocation,idioms,formula,note,bonus
  ) VALUES (
    new_id,p_topic_id,u,CASE WHEN p_as_system THEN 'system' ELSE 'private' END,btrim(p_vocab->>'word'),
    NULLIF(btrim(p_vocab->>'cefr'),''),NULLIF(btrim(p_vocab->>'ipa'),''),NULLIF(btrim(p_vocab->>'word_form'),''),
    NULLIF(btrim(p_vocab->>'e_meaning'),''),NULLIF(btrim(p_vocab->>'ev_meaning'),''),NULLIF(btrim(p_vocab->>'v_meaning'),''),
    CASE WHEN btrim(p_vocab->>'e_example') IN ('...','…') THEN NULL ELSE NULLIF(btrim(p_vocab->>'e_example'),'') END,
    CASE WHEN btrim(p_vocab->>'v_example') IN ('...','…') THEN NULL ELSE NULLIF(btrim(p_vocab->>'v_example'),'') END,
    NULLIF(btrim(p_vocab->>'word_family'),''),NULLIF(btrim(p_vocab->>'synonymous'),''),NULLIF(btrim(p_vocab->>'antonym'),''),
    NULLIF(btrim(p_vocab->>'collocation'),''),NULLIF(btrim(p_vocab->>'idioms'),''),
    NULLIF(btrim(p_vocab->>'formula'),''),NULLIF(btrim(p_vocab->>'note'),''),NULLIF(btrim(p_vocab->>'bonus'),'')
  );
  IF NOT p_as_system THEN PERFORM public.save_vocabulary_to_topic(ARRAY[new_id],p_topic_id); END IF;
  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_vocabulary_item(jsonb,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_vocabulary_item(jsonb,uuid,boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
