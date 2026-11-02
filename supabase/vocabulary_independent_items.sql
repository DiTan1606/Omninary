-- Apply AFTER vocabulary_topic_memberships.sql and vocabulary_workspace.sql.
-- Each vocab_catalog.id is an independent vocabulary item. Spelling is content.
-- Removes only derived spelling identities and display grouping metadata.
BEGIN;
LOCK TABLE public.vocab_catalog, public.user_vocabulary, public.topic_vocab, public.user_topic_vocab IN SHARE ROW EXCLUSIVE MODE;
CREATE TEMP TABLE vocabulary_item_migration_guard ON COMMIT DROP AS
SELECT
 (SELECT md5(coalesce(string_agg((to_jsonb(v)-'word_id')::text,'' ORDER BY id),'')) FROM public.vocab_catalog v) AS catalog_hash,
 (SELECT md5(coalesce(string_agg(to_jsonb(u)::text,'' ORDER BY id),'')) FROM public.user_vocabulary u) AS progress_hash,
 (SELECT md5(coalesce(string_agg((to_jsonb(m)-'display_group_id')::text,'' ORDER BY user_vocabulary_id,topic_id),'')) FROM public.user_topic_vocab m) AS membership_hash,
 (SELECT md5(coalesce(string_agg(to_jsonb(t)::text,'' ORDER BY topic_id,vocab_id),'')) FROM public.topic_vocab t) AS catalog_membership_hash;

CREATE OR REPLACE FUNCTION public.vocabulary_location_snapshot(p_vocab_ids uuid[])
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object('vocab_ids',to_jsonb(p_vocab_ids),'memberships',coalesce(jsonb_agg(
    jsonb_build_object('vocab_id',uv.vocab_id,'topic_id',ut.topic_id)
  ) FILTER(WHERE ut.topic_id IS NOT NULL),'[]'::jsonb))
  FROM public.user_vocabulary uv LEFT JOIN public.user_topic_vocab ut ON ut.user_vocabulary_id=uv.id
  WHERE uv.user_id=auth.uid() AND uv.vocab_id=ANY(p_vocab_ids);
$$;

CREATE OR REPLACE FUNCTION public.change_vocabulary_location(
  p_vocab_ids uuid[],p_source_topic_id uuid,p_destination_topic_id uuid,p_action text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user(); ids uuid[]; destination uuid; snapshot jsonb;
BEGIN
  PERFORM public.ensure_vocabulary_root();
  SELECT array_agg(DISTINCT id) INTO ids FROM unnest(p_vocab_ids) id WHERE id IS NOT NULL;
  IF coalesce(cardinality(ids),0)=0 OR cardinality(ids)>1000 THEN RAISE EXCEPTION 'Invalid vocabulary selection'; END IF;
  IF (SELECT count(*) FROM public.user_vocabulary uv WHERE uv.user_id=u AND uv.vocab_id=ANY(ids))<>cardinality(ids) THEN
    RAISE EXCEPTION 'Vocabulary items must already belong to your library';
  END IF;
  -- Serialize moves/undo for this learner.
  PERFORM 1 FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(ids) ORDER BY id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM public.topics WHERE id=p_source_topic_id AND (visibility='system' OR owner_id=u)) THEN
    RAISE EXCEPTION 'Source folder is not accessible';
  END IF;
  IF (SELECT count(*) FROM public.user_topic_vocab ut JOIN public.user_vocabulary uv ON uv.id=ut.user_vocabulary_id
    WHERE uv.user_id=u AND uv.vocab_id=ANY(ids) AND ut.topic_id=p_source_topic_id)<>cardinality(ids) THEN
    RAISE EXCEPTION 'Selection is no longer in this folder';
  END IF;
  snapshot := public.vocabulary_location_snapshot(ids);
  IF p_action IN ('move','add','root') THEN
    destination := CASE WHEN p_action='root' THEN public.ensure_vocabulary_root() ELSE p_destination_topic_id END;
    IF NOT EXISTS(SELECT 1 FROM public.topics WHERE id=destination AND visibility='private' AND owner_id=u) THEN
      RAISE EXCEPTION 'Choose one of your personal folders';
    END IF;
    IF destination=p_source_topic_id THEN RETURN snapshot; END IF;
    PERFORM public.save_vocabulary_to_topic(ids,destination);
  ELSIF p_action<>'remove' THEN RAISE EXCEPTION 'Invalid folder operation';
  END IF;
  IF p_action IN ('move','root','remove') THEN
    PERFORM public.remove_vocabulary_from_topic(ids,p_source_topic_id);
    PERFORM public.ensure_vocabulary_root();
  END IF;
  RETURN snapshot;
END $$;

CREATE OR REPLACE FUNCTION public.restore_vocabulary_locations(p_snapshot jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user(); ids uuid[]; item jsonb; t uuid; v uuid;
BEGIN
  PERFORM public.ensure_vocabulary_root();
  SELECT array_agg(DISTINCT value::uuid) INTO ids FROM jsonb_array_elements_text(p_snapshot->'vocab_ids');
  IF coalesce(cardinality(ids),0)=0 OR cardinality(ids)>1000 THEN RAISE EXCEPTION 'Invalid undo selection'; END IF;
  PERFORM 1 FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(ids) ORDER BY id FOR UPDATE;
  IF (SELECT count(*) FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(ids))<>cardinality(ids) THEN
    RAISE EXCEPTION 'These vocabulary items are no longer in your library';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_snapshot->'memberships') LOOP
    v := (item->>'vocab_id')::uuid; t := (item->>'topic_id')::uuid;
    IF NOT(v=ANY(ids)) OR NOT EXISTS(SELECT 1 FROM public.topics WHERE id=t AND (visibility='system' OR owner_id=u)) THEN
      RAISE EXCEPTION 'Undo folder is not accessible';
    END IF;
  END LOOP;
  DELETE FROM public.topic_vocab tv USING public.user_topic_vocab ut,public.user_vocabulary uv,public.topics t
    WHERE tv.topic_id=ut.topic_id AND tv.vocab_id=uv.vocab_id AND ut.user_vocabulary_id=uv.id
      AND uv.user_id=u AND uv.vocab_id=ANY(ids) AND t.id=ut.topic_id AND t.visibility='private' AND t.owner_id=u;
  DELETE FROM public.user_topic_vocab ut USING public.user_vocabulary uv
    WHERE ut.user_vocabulary_id=uv.id AND uv.user_id=u AND uv.vocab_id=ANY(ids);
  FOR item IN SELECT value FROM jsonb_array_elements(p_snapshot->'memberships') LOOP
    v := (item->>'vocab_id')::uuid; t := (item->>'topic_id')::uuid;
    INSERT INTO public.user_topic_vocab(user_vocabulary_id,topic_id)
      SELECT id,t FROM public.user_vocabulary WHERE user_id=u AND vocab_id=v ON CONFLICT DO NOTHING;
    INSERT INTO public.topic_vocab(topic_id,vocab_id)
      SELECT t,v FROM public.topics WHERE id=t AND visibility='private' AND owner_id=u ON CONFLICT DO NOTHING;
  END LOOP;
  PERFORM public.ensure_vocabulary_root();
END $$;


CREATE OR REPLACE FUNCTION public.create_vocabulary_item(p_vocab jsonb,p_topic_id uuid DEFAULT NULL,p_as_system boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid := public.require_current_user(); new_id uuid := gen_random_uuid(); t public.topics%ROWTYPE;
BEGIN
  IF p_as_system AND NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF NULLIF(btrim(p_vocab->>'word'),'') IS NULL THEN RAISE EXCEPTION 'A word is required'; END IF;
  IF p_topic_id IS NOT NULL THEN
    SELECT * INTO t FROM public.topics WHERE id=p_topic_id;
    IF NOT FOUND OR NOT(t.visibility='system' OR (t.visibility='private' AND t.owner_id=u) OR public.is_admin()) THEN
      RAISE EXCEPTION 'Topic is not accessible';
    END IF;
  END IF;
  INSERT INTO public.vocab_catalog(id,topic_id,created_by,visibility,word,cefr,ipa,word_form,
    e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,bonus)
  VALUES(new_id,p_topic_id,u,CASE WHEN p_as_system THEN 'system' ELSE 'private' END,btrim(p_vocab->>'word'),
    NULLIF(btrim(p_vocab->>'cefr'),''),NULLIF(btrim(p_vocab->>'ipa'),''),NULLIF(btrim(p_vocab->>'word_form'),''),
    NULLIF(btrim(p_vocab->>'e_meaning'),''),NULLIF(btrim(p_vocab->>'ev_meaning'),''),NULLIF(btrim(p_vocab->>'v_meaning'),''),
    CASE WHEN btrim(p_vocab->>'e_example') IN ('...','…') THEN NULL ELSE NULLIF(btrim(p_vocab->>'e_example'),'') END,
    CASE WHEN btrim(p_vocab->>'v_example') IN ('...','…') THEN NULL ELSE NULLIF(btrim(p_vocab->>'v_example'),'') END,
    NULLIF(btrim(p_vocab->>'word_family'),''),NULLIF(btrim(p_vocab->>'synonymous'),''),NULLIF(btrim(p_vocab->>'antonym'),''),NULLIF(btrim(p_vocab->>'bonus'),''));
  IF NOT p_as_system THEN PERFORM public.save_vocabulary_to_topic(ARRAY[new_id],p_topic_id); END IF;
  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_vocabulary_item(jsonb,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_vocabulary_item(jsonb,uuid,boolean) TO authenticated;
CREATE OR REPLACE FUNCTION public.create_vocabulary_meaning(p_vocab jsonb,p_topic_id uuid DEFAULT NULL,p_as_system boolean DEFAULT false)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
 SELECT public.create_vocabulary_item(p_vocab,p_topic_id,p_as_system);
$$;
DROP FUNCTION IF EXISTS public.group_vocabulary_meanings(uuid[],uuid,boolean);
ALTER TABLE public.user_topic_vocab DROP COLUMN IF EXISTS display_group_id;
DROP TABLE IF EXISTS public.vocabulary_display_groups;
DROP TRIGGER IF EXISTS assign_vocabulary_word_trigger ON public.vocab_catalog;
DROP FUNCTION IF EXISTS public.assign_vocabulary_word();
DO $$ BEGIN
 IF to_regclass('public.vocabulary_words') IS NOT NULL THEN
   DROP POLICY IF EXISTS vocabulary_words_visible ON public.vocabulary_words;
 END IF;
END $$;
ALTER TABLE public.vocab_catalog DROP COLUMN IF EXISTS word_id;
DROP TABLE IF EXISTS public.vocabulary_words;

-- Keep the nonempty-word validation without creating a parent word record.
CREATE OR REPLACE FUNCTION public.validate_vocabulary_item_word()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
 IF NEW.word IS NULL OR btrim(NEW.word)='' THEN RAISE EXCEPTION 'A vocabulary item cannot have an empty word'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.validate_vocabulary_item_word() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS validate_vocabulary_item_word_trigger ON public.vocab_catalog;
CREATE TRIGGER validate_vocabulary_item_word_trigger BEFORE INSERT OR UPDATE OF word
ON public.vocab_catalog FOR EACH ROW EXECUTE FUNCTION public.validate_vocabulary_item_word();
COMMENT ON TABLE public.vocab_catalog IS 'Independent vocabulary items. Each ID is one learning unit; identical spelling never merges items.';
COMMENT ON TABLE public.topic_vocab IS 'Catalog membership: a vocabulary item may belong to multiple vocabulary collections.';
COMMENT ON TABLE public.user_topic_vocab IS 'Personal collection membership referencing the same user vocabulary progress record.';
COMMENT ON TABLE public.user_vocabulary IS 'One progress record per learner and vocabulary item (user_id, vocab_id).';
REVOKE ALL ON FUNCTION public.vocabulary_location_snapshot(uuid[]) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.change_vocabulary_location(uuid[],uuid,uuid,text),public.restore_vocabulary_locations(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.change_vocabulary_location(uuid[],uuid,uuid,text),public.restore_vocabulary_locations(jsonb) TO authenticated;
DO $$ DECLARE expected record; BEGIN
 SELECT * INTO expected FROM vocabulary_item_migration_guard;
 IF expected.catalog_hash IS DISTINCT FROM (SELECT md5(coalesce(string_agg((to_jsonb(v)-'word_id')::text,'' ORDER BY id),'')) FROM public.vocab_catalog v)
 OR expected.progress_hash IS DISTINCT FROM (SELECT md5(coalesce(string_agg(to_jsonb(u)::text,'' ORDER BY id),'')) FROM public.user_vocabulary u)
 OR expected.membership_hash IS DISTINCT FROM (SELECT md5(coalesce(string_agg((to_jsonb(m)-'display_group_id')::text,'' ORDER BY user_vocabulary_id,topic_id),'')) FROM public.user_topic_vocab m)
 OR expected.catalog_membership_hash IS DISTINCT FROM (SELECT md5(coalesce(string_agg(to_jsonb(t)::text,'' ORDER BY topic_id,vocab_id),'')) FROM public.topic_vocab t)
 THEN RAISE EXCEPTION 'Vocabulary data preservation check failed'; END IF;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;
