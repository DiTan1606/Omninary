-- Historical migration: on new databases apply vocabulary_independent_items.sql LAST.
-- Do not rerun this historical migration on an already migrated production database.
-- Requires vocabulary_topic_memberships.sql. Personal presentation only:
-- existing meaning IDs, progress and review history are never rewritten.
BEGIN;
CREATE TABLE IF NOT EXISTS public.user_vocabulary_workspace (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  root_topic_id uuid NOT NULL UNIQUE REFERENCES public.topics(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS public.vocabulary_display_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  topic_id uuid NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
  word_id uuid NOT NULL REFERENCES public.vocabulary_words(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.user_topic_vocab ADD COLUMN IF NOT EXISTS display_group_id uuid
  REFERENCES public.vocabulary_display_groups(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS vocabulary_display_groups_owner_topic ON public.vocabulary_display_groups(user_id,topic_id);
ALTER TABLE public.user_vocabulary_workspace ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vocabulary_display_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS own_workspace ON public.user_vocabulary_workspace;
CREATE POLICY own_workspace ON public.user_vocabulary_workspace FOR SELECT TO authenticated USING(user_id=auth.uid());
DROP POLICY IF EXISTS own_display_groups ON public.vocabulary_display_groups;
CREATE POLICY own_display_groups ON public.vocabulary_display_groups FOR SELECT TO authenticated USING(user_id=auth.uid());
REVOKE ALL ON public.user_vocabulary_workspace,public.vocabulary_display_groups FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.user_vocabulary_workspace,public.vocabulary_display_groups TO authenticated;

CREATE OR REPLACE FUNCTION public.ensure_vocabulary_root()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user(); root_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text,0));
  SELECT root_topic_id INTO root_id FROM public.user_vocabulary_workspace WHERE user_id=u;
  IF root_id IS NULL THEN
    SELECT id INTO root_id FROM public.topics WHERE owner_id=u AND visibility='private'
      AND lower(btrim(name))=lower('Chưa xác định') LIMIT 1;
    IF root_id IS NULL THEN
      INSERT INTO public.topics(name,visibility,owner_id) VALUES('Chưa xác định','private',u) RETURNING id INTO root_id;
    END IF;
    INSERT INTO public.user_vocabulary_workspace(user_id,root_topic_id) VALUES(u,root_id);
  END IF;
  -- Repair unfiled senses after deleting a folder or using older clients.
  INSERT INTO public.user_topic_vocab(user_vocabulary_id,topic_id)
    SELECT uv.id,root_id FROM public.user_vocabulary uv WHERE uv.user_id=u
      AND NOT EXISTS(SELECT 1 FROM public.user_topic_vocab ut WHERE ut.user_vocabulary_id=uv.id)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.topic_vocab(topic_id,vocab_id)
    SELECT root_id,uv.vocab_id FROM public.user_vocabulary uv JOIN public.user_topic_vocab ut ON ut.user_vocabulary_id=uv.id
    WHERE uv.user_id=u AND ut.topic_id=root_id ON CONFLICT DO NOTHING;
  RETURN root_id;
END $$;

CREATE OR REPLACE FUNCTION public.protect_vocabulary_root()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM public.user_vocabulary_workspace WHERE root_topic_id=OLD.id) THEN
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Không thể xoá thư mục gốc Chưa xác định'; END IF;
    IF NEW.name IS DISTINCT FROM OLD.name OR NEW.visibility IS DISTINCT FROM OLD.visibility THEN
      RAISE EXCEPTION 'Không thể đổi tên hoặc chia sẻ thư mục gốc Chưa xác định';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS protect_vocabulary_root_trigger ON public.topics;
CREATE TRIGGER protect_vocabulary_root_trigger BEFORE DELETE OR UPDATE OF name,visibility
  ON public.topics FOR EACH ROW EXECUTE FUNCTION public.protect_vocabulary_root();

CREATE OR REPLACE FUNCTION public.vocabulary_location_snapshot(p_vocab_ids uuid[])
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  SELECT jsonb_build_object('vocab_ids',to_jsonb(p_vocab_ids),'memberships',coalesce(jsonb_agg(
    jsonb_build_object('vocab_id',uv.vocab_id,'topic_id',ut.topic_id,'display_group_id',ut.display_group_id)
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
  IF coalesce(cardinality(ids),0)=0 OR cardinality(ids)>1000 THEN RAISE EXCEPTION 'Invalid meaning selection'; END IF;
  IF (SELECT count(*) FROM public.user_vocabulary uv WHERE uv.user_id=u AND uv.vocab_id=ANY(ids))<>cardinality(ids) THEN
    RAISE EXCEPTION 'Meanings must already belong to your library';
  END IF;
  -- Serialize moves/groups/undo for this learner.
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

CREATE OR REPLACE FUNCTION public.group_vocabulary_meanings(p_vocab_ids uuid[],p_topic_id uuid,p_ungroup boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user(); ids uuid[]; word uuid; group_id uuid; snapshot jsonb;
BEGIN
  PERFORM public.ensure_vocabulary_root();
  SELECT array_agg(DISTINCT id) INTO ids FROM unnest(p_vocab_ids) id WHERE id IS NOT NULL;
  IF coalesce(cardinality(ids),0)=0 OR cardinality(ids)>1000 THEN RAISE EXCEPTION 'Select meanings'; END IF;
  PERFORM 1 FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(ids) ORDER BY id FOR UPDATE;
  IF (SELECT count(*) FROM public.user_topic_vocab ut JOIN public.user_vocabulary uv ON uv.id=ut.user_vocabulary_id
    WHERE uv.user_id=u AND uv.vocab_id=ANY(ids) AND ut.topic_id=p_topic_id)<>cardinality(ids) THEN
    RAISE EXCEPTION 'Selection is no longer in this folder';
  END IF;
  snapshot := public.vocabulary_location_snapshot(ids);
  IF NOT p_ungroup THEN
    IF cardinality(ids)<2 OR (SELECT count(DISTINCT word_id) FROM public.vocab_catalog WHERE id=ANY(ids))<>1 THEN
      RAISE EXCEPTION 'Choose at least two meanings of the same English word';
    END IF;
    SELECT word_id INTO word FROM public.vocab_catalog WHERE id=ids[1];
    INSERT INTO public.vocabulary_display_groups(user_id,topic_id,word_id) VALUES(u,p_topic_id,word) RETURNING id INTO group_id;
  END IF;
  UPDATE public.user_topic_vocab ut SET display_group_id=group_id FROM public.user_vocabulary uv
    WHERE ut.user_vocabulary_id=uv.id AND uv.user_id=u AND uv.vocab_id=ANY(ids) AND ut.topic_id=p_topic_id;
  RETURN snapshot;
END $$;

CREATE OR REPLACE FUNCTION public.restore_vocabulary_locations(p_snapshot jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user(); ids uuid[]; item jsonb; t uuid; g uuid; v uuid;
BEGIN
  PERFORM public.ensure_vocabulary_root();
  SELECT array_agg(DISTINCT value::uuid) INTO ids FROM jsonb_array_elements_text(p_snapshot->'vocab_ids');
  IF coalesce(cardinality(ids),0)=0 OR cardinality(ids)>1000 THEN RAISE EXCEPTION 'Invalid undo selection'; END IF;
  PERFORM 1 FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(ids) ORDER BY id FOR UPDATE;
  IF (SELECT count(*) FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(ids))<>cardinality(ids) THEN
    RAISE EXCEPTION 'These meanings are no longer in your library';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_snapshot->'memberships') LOOP
    v := (item->>'vocab_id')::uuid; t := (item->>'topic_id')::uuid; g := (item->>'display_group_id')::uuid;
    IF NOT(v=ANY(ids)) OR NOT EXISTS(SELECT 1 FROM public.topics WHERE id=t AND (visibility='system' OR owner_id=u)) THEN
      RAISE EXCEPTION 'Undo folder is not accessible';
    END IF;
    IF g IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vocabulary_display_groups dg JOIN public.vocab_catalog vc ON vc.id=v
      WHERE dg.id=g AND dg.user_id=u AND dg.topic_id=t AND dg.word_id=vc.word_id) THEN
      RAISE EXCEPTION 'Undo group is not accessible';
    END IF;
  END LOOP;
  DELETE FROM public.topic_vocab tv USING public.user_topic_vocab ut,public.user_vocabulary uv,public.topics t
    WHERE tv.topic_id=ut.topic_id AND tv.vocab_id=uv.vocab_id AND ut.user_vocabulary_id=uv.id
      AND uv.user_id=u AND uv.vocab_id=ANY(ids) AND t.id=ut.topic_id AND t.visibility='private' AND t.owner_id=u;
  DELETE FROM public.user_topic_vocab ut USING public.user_vocabulary uv
    WHERE ut.user_vocabulary_id=uv.id AND uv.user_id=u AND uv.vocab_id=ANY(ids);
  FOR item IN SELECT value FROM jsonb_array_elements(p_snapshot->'memberships') LOOP
    v := (item->>'vocab_id')::uuid; t := (item->>'topic_id')::uuid; g := (item->>'display_group_id')::uuid;
    INSERT INTO public.user_topic_vocab(user_vocabulary_id,topic_id,display_group_id)
      SELECT id,t,g FROM public.user_vocabulary WHERE user_id=u AND vocab_id=v ON CONFLICT DO NOTHING;
    INSERT INTO public.topic_vocab(topic_id,vocab_id)
      SELECT t,v FROM public.topics WHERE id=t AND visibility='private' AND owner_id=u ON CONFLICT DO NOTHING;
  END LOOP;
  PERFORM public.ensure_vocabulary_root();
END $$;

CREATE OR REPLACE FUNCTION public.delete_vocabulary_from_workspace(p_vocab_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user();
BEGIN
  PERFORM public.ensure_vocabulary_root();
  -- Catalog definitions are reusable; only this user's progress is removed.
  DELETE FROM public.user_vocabulary WHERE user_id=u AND vocab_id=ANY(p_vocab_ids);
END $$;
REVOKE ALL ON FUNCTION public.protect_vocabulary_root(),public.vocabulary_location_snapshot(uuid[]),
  public.ensure_vocabulary_root(),public.change_vocabulary_location(uuid[],uuid,uuid,text),
  public.group_vocabulary_meanings(uuid[],uuid,boolean),public.restore_vocabulary_locations(jsonb),
  public.delete_vocabulary_from_workspace(uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ensure_vocabulary_root(),public.change_vocabulary_location(uuid[],uuid,uuid,text),
  public.group_vocabulary_meanings(uuid[],uuid,boolean),public.restore_vocabulary_locations(jsonb),
  public.delete_vocabulary_from_workspace(uuid[]) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
