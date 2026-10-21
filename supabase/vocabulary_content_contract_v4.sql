-- Run after vocabulary_content_fields_v3.sql; safe to rerun.
-- 9 required text fields + 7 optional semicolon-separated text fields.
-- Idioms are independent catalog records with word_form = 'idioms'.
BEGIN;

-- Never discard a populated legacy idioms field silently.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.vocab_catalog v WHERE nullif(btrim(to_jsonb(v)->>'idioms'),'') IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.topic_submission_words s WHERE nullif(btrim(to_jsonb(s)->>'idioms'),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'Convert populated idioms fields into independent vocabulary items before applying v4';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.normalize_vocabulary_content()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  content jsonb := to_jsonb(NEW);
  changes jsonb := '{}'::jsonb;
  field_name text;
  value text;
BEGIN
  FOREACH field_name IN ARRAY ARRAY['word','cefr','ipa','word_form','e_meaning','ev_meaning','v_meaning','e_example','v_example'] LOOP
    value := btrim(content->>field_name, E' \t\r\n');
    IF value IS NULL OR value = '' OR (field_name IN ('e_example','v_example') AND value IN ('...','…')) THEN
      RAISE EXCEPTION 'Thiếu thông tin bắt buộc: %', field_name USING ERRCODE = '23514';
    END IF;
    IF value ~ E'[\n\r]\\(Nhận xét ưu tiên [123]:' THEN
      RAISE EXCEPTION 'Hãy xử lý và xoá nhận xét trong ô % trước khi nhập', field_name USING ERRCODE = '23514';
    END IF;
    changes := changes || jsonb_build_object(field_name,value);
  END LOOP;
  FOREACH field_name IN ARRAY ARRAY['word_family','synonymous','antonym','collocation','formula','note','bonus'] LOOP
    value := content->>field_name;
    IF value ~ E'[\n\r]\\(Nhận xét ưu tiên [123]:' THEN
      RAISE EXCEPTION 'Hãy xử lý và xoá nhận xét trong ô % trước khi nhập', field_name USING ERRCODE = '23514';
    END IF;
    SELECT string_agg(btrim(part, E' \t\r\n'), '; ' ORDER BY position)
      INTO value
      FROM unnest(string_to_array(value,';')) WITH ORDINALITY AS parts(part,position)
      WHERE btrim(part, E' \t\r\n') <> '';
    changes := changes || jsonb_build_object(field_name,value);
  END LOOP;
  NEW := jsonb_populate_record(NEW,changes);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.normalize_vocabulary_content() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_vocabulary_item(
  p_vocab jsonb, p_topic_id uuid DEFAULT NULL, p_as_system boolean DEFAULT false
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u uuid := public.require_current_user();
  new_id uuid := gen_random_uuid();
  t public.topics%ROWTYPE;
  field_name text;
BEGIN
  IF p_as_system AND NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  FOREACH field_name IN ARRAY ARRAY['word','cefr','ipa','word_form','e_meaning','ev_meaning','v_meaning','e_example','v_example'] LOOP
    IF jsonb_typeof(p_vocab->field_name) IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'Thuộc tính % phải là một giá trị văn bản', field_name USING ERRCODE = '23514';
    END IF;
  END LOOP;
  FOREACH field_name IN ARRAY ARRAY['word_family','synonymous','antonym','collocation','formula','note','bonus'] LOOP
    IF p_vocab ? field_name AND jsonb_typeof(p_vocab->field_name) NOT IN ('string','null') THEN
      RAISE EXCEPTION 'Thuộc tính % phải là văn bản, ngăn cách các giá trị bằng dấu ;', field_name USING ERRCODE = '23514';
    END IF;
  END LOOP;
  IF p_topic_id IS NOT NULL THEN
    SELECT * INTO t FROM public.topics WHERE id=p_topic_id;
    IF NOT FOUND OR NOT(t.visibility='system' OR (t.visibility='private' AND t.owner_id=u) OR public.is_admin()) THEN
      RAISE EXCEPTION 'Topic is not accessible';
    END IF;
  END IF;
  INSERT INTO public.vocab_catalog(
    id,topic_id,created_by,visibility,word,cefr,ipa,word_form,
    e_meaning,ev_meaning,v_meaning,e_example,v_example,
    word_family,synonymous,antonym,collocation,formula,note,bonus
  ) VALUES (
    new_id,p_topic_id,u,CASE WHEN p_as_system THEN 'system' ELSE 'private' END,
    p_vocab->>'word',p_vocab->>'cefr',p_vocab->>'ipa',p_vocab->>'word_form',
    p_vocab->>'e_meaning',p_vocab->>'ev_meaning',p_vocab->>'v_meaning',
    p_vocab->>'e_example',p_vocab->>'v_example',p_vocab->>'word_family',
    p_vocab->>'synonymous',p_vocab->>'antonym',p_vocab->>'collocation',
    p_vocab->>'formula',p_vocab->>'note',p_vocab->>'bonus'
  );
  IF NOT p_as_system THEN PERFORM public.save_vocabulary_to_topic(ARRAY[new_id],p_topic_id); END IF;
  RETURN new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.create_vocabulary_item(jsonb,uuid,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_vocabulary_item(jsonb,uuid,boolean) TO authenticated;

ALTER TABLE public.vocab_catalog DROP COLUMN IF EXISTS idioms RESTRICT;
ALTER TABLE public.topic_submission_words DROP COLUMN IF EXISTS idioms RESTRICT;

DROP TRIGGER IF EXISTS vocabulary_content_contract ON public.vocab_catalog;
CREATE TRIGGER vocabulary_content_contract BEFORE INSERT OR UPDATE ON public.vocab_catalog
  FOR EACH ROW EXECUTE FUNCTION public.normalize_vocabulary_content();
DROP TRIGGER IF EXISTS vocabulary_content_contract ON public.topic_submission_words;
CREATE TRIGGER vocabulary_content_contract BEFORE INSERT OR UPDATE ON public.topic_submission_words
  FOR EACH ROW EXECUTE FUNCTION public.normalize_vocabulary_content();

-- Existing incomplete content remains intact for review. New writes must comply.
DO $$
DECLARE
  table_name text;
  field_name text;
  required_check text := '';
BEGIN
  FOREACH field_name IN ARRAY ARRAY['word','cefr','ipa','word_form','e_meaning','ev_meaning','v_meaning','e_example','v_example'] LOOP
    required_check := required_check || CASE WHEN required_check='' THEN '' ELSE ' AND ' END
      || format('(%1$I IS NOT NULL AND length(btrim(%1$I,E'' \t\r\n''))>0)',field_name);
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY['vocab_catalog','topic_submission_words'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid=format('public.%I',table_name)::regclass AND conname='vocabulary_core_content_required') THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT vocabulary_core_content_required CHECK (%s) NOT VALID',table_name,required_check);
    END IF;
  END LOOP;
END;
$$;
COMMENT ON COLUMN public.vocab_catalog.word_form IS 'Từ loại hoặc dạng mục học; thành ngữ là bản ghi riêng với giá trị idioms.';
COMMENT ON COLUMN public.vocab_catalog.word_family IS 'Văn bản bổ sung; mỗi giá trị ngăn cách bằng dấu ;. Không phải tập đáp án tự động.';
COMMENT ON COLUMN public.vocab_catalog.synonymous IS 'Đồng nghĩa đúng cách dùng; các giá trị ngăn cách bằng dấu ;.';
COMMENT ON COLUMN public.vocab_catalog.antonym IS 'Trái nghĩa đúng cách dùng; các giá trị ngăn cách bằng dấu ;.';
COMMENT ON COLUMN public.vocab_catalog.collocation IS 'Cụm từ thường đi cùng; các giá trị ngăn cách bằng dấu ;.';
COMMENT ON COLUMN public.vocab_catalog.formula IS 'Mẫu cấu trúc; các giá trị ngăn cách bằng dấu ;.';
COMMENT ON COLUMN public.vocab_catalog.note IS 'Ghi chú cách dùng; các giá trị ngăn cách bằng dấu ;. Không nhập nhận xét rà bảng.';
COMMENT ON COLUMN public.vocab_catalog.bonus IS 'Thông tin mở rộng; các giá trị ngăn cách bằng dấu ;.';
NOTIFY pgrst, 'reload schema';
COMMIT;
