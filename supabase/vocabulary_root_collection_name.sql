-- Requires vocabulary_independent_items.sql. Keeps root IDs and all memberships.
BEGIN;
LOCK TABLE public.topics IN SHARE ROW EXCLUSIVE MODE;
CREATE OR REPLACE FUNCTION public.ensure_vocabulary_root()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u uuid := public.require_current_user(); root_id uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text,0));
  SELECT root_topic_id INTO root_id FROM public.user_vocabulary_workspace WHERE user_id=u;
  IF root_id IS NULL THEN
    SELECT id INTO root_id FROM public.topics WHERE owner_id=u AND visibility='private'
      AND lower(btrim(name))=lower('Bộ từ gốc') LIMIT 1;
    IF root_id IS NULL THEN
      INSERT INTO public.topics(name,visibility,owner_id) VALUES('Bộ từ gốc','private',u) RETURNING id INTO root_id;
    END IF;
    INSERT INTO public.user_vocabulary_workspace(user_id,root_topic_id) VALUES(u,root_id);
  END IF;
  -- Repair unfiled vocabulary items after deleting a folder or using older clients.
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
    IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Không thể xoá Bộ từ gốc'; END IF;
    IF NEW.name IS DISTINCT FROM OLD.name OR NEW.visibility IS DISTINCT FROM OLD.visibility THEN
      RAISE EXCEPTION 'Không thể đổi tên hoặc chia sẻ Bộ từ gốc';
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS protect_vocabulary_root_trigger ON public.topics;
UPDATE public.topics t SET name='Bộ từ gốc'
FROM public.user_vocabulary_workspace w WHERE t.id=w.root_topic_id AND t.name IS DISTINCT FROM 'Bộ từ gốc';
CREATE TRIGGER protect_vocabulary_root_trigger BEFORE DELETE OR UPDATE OF name,visibility
 ON public.topics FOR EACH ROW EXECUTE FUNCTION public.protect_vocabulary_root();
REVOKE ALL ON FUNCTION public.ensure_vocabulary_root(),public.protect_vocabulary_root() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ensure_vocabulary_root() TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
