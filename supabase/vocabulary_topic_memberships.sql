-- Historical migration: on new databases apply vocabulary_independent_items.sql LAST.
-- Do not rerun this historical migration on an already migrated production database.
-- Run once after the existing vocabulary/private-topic workflows, before shipping
-- the new clients. Additive: catalog IDs, user progress and attempt IDs are retained.
BEGIN;

CREATE TABLE IF NOT EXISTS public.vocabulary_words (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  normalized_word text NOT NULL UNIQUE,
  display_word text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.vocab_catalog ADD COLUMN IF NOT EXISTS word_id uuid
  REFERENCES public.vocabulary_words(id);

CREATE OR REPLACE FUNCTION public.assign_vocabulary_word()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE k text; resolved_id uuid;
BEGIN
  k := lower(regexp_replace(btrim(NEW.word), '\s+', ' ', 'g'));
  IF k = '' THEN RAISE EXCEPTION 'A vocabulary word cannot be empty'; END IF;
  INSERT INTO public.vocabulary_words(normalized_word, display_word)
  VALUES(k, btrim(NEW.word)) ON CONFLICT(normalized_word) DO NOTHING;
  SELECT id INTO resolved_id FROM public.vocabulary_words WHERE normalized_word = k;
  NEW.word_id := resolved_id;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.assign_vocabulary_word() FROM PUBLIC;
DROP TRIGGER IF EXISTS assign_vocabulary_word_trigger ON public.vocab_catalog;
CREATE TRIGGER assign_vocabulary_word_trigger BEFORE INSERT OR UPDATE OF word, word_id
ON public.vocab_catalog FOR EACH ROW EXECUTE FUNCTION public.assign_vocabulary_word();
UPDATE public.vocab_catalog SET word = word WHERE word_id IS NULL;
ALTER TABLE public.vocab_catalog ALTER COLUMN word_id SET NOT NULL;

CREATE TABLE IF NOT EXISTS public.topic_vocab (
  topic_id uuid NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
  vocab_id uuid NOT NULL REFERENCES public.vocab_catalog(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(topic_id, vocab_id)
);
CREATE INDEX IF NOT EXISTS topic_vocab_vocab_idx ON public.topic_vocab(vocab_id);
CREATE TABLE IF NOT EXISTS public.user_topic_vocab (
  user_vocabulary_id uuid NOT NULL REFERENCES public.user_vocabulary(id) ON DELETE CASCADE,
  topic_id uuid NOT NULL REFERENCES public.topics(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_vocabulary_id, topic_id)
);
CREATE INDEX IF NOT EXISTS user_topic_vocab_topic_idx ON public.user_topic_vocab(topic_id);

-- Do not re-populate removed memberships when this file is run again.
CREATE TABLE IF NOT EXISTS public.vocabulary_structure_migrations (
  name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON public.vocabulary_structure_migrations FROM PUBLIC, anon, authenticated;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.vocabulary_structure_migrations WHERE name='topic_memberships_v1') THEN
    INSERT INTO public.topic_vocab(topic_id,vocab_id)
    SELECT topic_id,id FROM public.vocab_catalog WHERE topic_id IS NOT NULL
    ON CONFLICT DO NOTHING;
    INSERT INTO public.user_topic_vocab(user_vocabulary_id,topic_id)
    SELECT uv.id,vc.topic_id FROM public.user_vocabulary uv
    JOIN public.vocab_catalog vc ON vc.id=uv.vocab_id WHERE vc.topic_id IS NOT NULL
    ON CONFLICT DO NOTHING;
    INSERT INTO public.vocabulary_structure_migrations(name) VALUES('topic_memberships_v1');
  END IF;
END $$;

-- Retain topic_id for older clients and contribution drafts only. It is no longer
-- the authoritative membership list. Legacy inserts add a membership, never move it.
CREATE OR REPLACE FUNCTION public.seed_legacy_vocabulary_topic()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.topic_id IS NOT NULL AND (TG_OP='INSERT' OR NEW.topic_id IS DISTINCT FROM OLD.topic_id) THEN
    INSERT INTO public.topic_vocab(topic_id,vocab_id) VALUES(NEW.topic_id,NEW.id) ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.seed_legacy_vocabulary_topic() FROM PUBLIC;
DROP TRIGGER IF EXISTS seed_legacy_vocabulary_topic_trigger ON public.vocab_catalog;
CREATE TRIGGER seed_legacy_vocabulary_topic_trigger AFTER INSERT OR UPDATE OF topic_id
ON public.vocab_catalog FOR EACH ROW EXECUTE FUNCTION public.seed_legacy_vocabulary_topic();

ALTER TABLE public.vocabulary_words ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.topic_vocab ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_topic_vocab ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS vocabulary_words_visible ON public.vocabulary_words;
CREATE POLICY vocabulary_words_visible ON public.vocabulary_words FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.vocab_catalog v WHERE v.word_id=vocabulary_words.id
    AND (v.visibility='system' OR v.created_by=auth.uid() OR public.is_admin()))
);
DROP POLICY IF EXISTS topic_vocab_visible ON public.topic_vocab;
CREATE POLICY topic_vocab_visible ON public.topic_vocab FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.topics t JOIN public.vocab_catalog v ON v.id=topic_vocab.vocab_id
    WHERE t.id=topic_vocab.topic_id
      AND (t.visibility='system' OR t.owner_id=auth.uid() OR public.is_admin())
      AND (v.visibility='system' OR v.created_by=auth.uid() OR public.is_admin()))
);
DROP POLICY IF EXISTS user_topic_vocab_visible ON public.user_topic_vocab;
CREATE POLICY user_topic_vocab_visible ON public.user_topic_vocab FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM public.user_vocabulary uv WHERE uv.id=user_topic_vocab.user_vocabulary_id
    AND (uv.user_id=auth.uid() OR public.is_admin()))
);
REVOKE ALL ON public.vocabulary_words, public.topic_vocab, public.user_topic_vocab FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.vocabulary_words, public.topic_vocab, public.user_topic_vocab TO authenticated;
-- Remove a prototype policy that made every private topic visible to every user.
DROP POLICY IF EXISTS topics_select_authenticated ON public.topics;

-- Topic names are unique within a user's collection, not across all users.
ALTER TABLE public.topics DROP CONSTRAINT IF EXISTS topics_name_key;
CREATE UNIQUE INDEX IF NOT EXISTS private_topic_owner_name_unique
ON public.topics(owner_id,lower(btrim(name))) WHERE visibility='private';
CREATE UNIQUE INDEX IF NOT EXISTS system_topic_name_unique
ON public.topics(lower(btrim(name))) WHERE visibility='system';

-- A repeated save is safe under concurrency and NEVER replaces progress.
CREATE OR REPLACE FUNCTION public.save_vocabulary_to_topic(p_vocab_ids uuid[], p_topic_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid := public.require_current_user(); ids uuid[]; t public.topics%ROWTYPE; added integer;
BEGIN
  SELECT array_agg(DISTINCT id) INTO ids FROM unnest(p_vocab_ids) id WHERE id IS NOT NULL;
  IF COALESCE(cardinality(ids),0)=0 OR cardinality(ids)>1000 THEN RAISE EXCEPTION 'Invalid meaning selection'; END IF;
  IF (SELECT count(*) FROM public.vocab_catalog v WHERE v.id=ANY(ids)
      AND (v.visibility='system' OR v.created_by=u OR public.is_admin())) <> cardinality(ids) THEN
    RAISE EXCEPTION 'One or more meanings are not accessible';
  END IF;
  IF p_topic_id IS NOT NULL THEN
    SELECT * INTO t FROM public.topics WHERE id=p_topic_id;
    IF NOT FOUND OR NOT (t.visibility='system' OR (t.visibility='private' AND t.owner_id=u) OR public.is_admin()) THEN
      RAISE EXCEPTION 'Topic is not accessible';
    END IF;
    -- Users may curate their own private topics. Public topic content is admin-owned.
    IF t.visibility='system' AND NOT public.is_admin() AND EXISTS (
      SELECT 1 FROM unnest(ids) id WHERE NOT EXISTS (
        SELECT 1 FROM public.topic_vocab tv WHERE tv.topic_id=p_topic_id AND tv.vocab_id=id
      ) AND NOT EXISTS (
        SELECT 1 FROM public.vocab_catalog v WHERE v.id=id AND v.visibility='private' AND v.created_by=u
      )
    ) THEN RAISE EXCEPTION 'Meaning does not belong to this system topic'; END IF;
    IF t.visibility='private' OR public.is_admin() THEN
      INSERT INTO public.topic_vocab(topic_id,vocab_id) SELECT p_topic_id,id FROM unnest(ids) id ON CONFLICT DO NOTHING;
    END IF;
  END IF;
  INSERT INTO public.user_vocabulary(user_id,vocab_id)
  SELECT u,id FROM unnest(ids) id ON CONFLICT(user_id,vocab_id) DO NOTHING;
  GET DIAGNOSTICS added = ROW_COUNT;
  IF p_topic_id IS NOT NULL THEN
    INSERT INTO public.user_topic_vocab(user_vocabulary_id,topic_id)
    SELECT uv.id,p_topic_id FROM public.user_vocabulary uv WHERE uv.user_id=u AND uv.vocab_id=ANY(ids)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN jsonb_build_object('success',true,'added_meanings',added);
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_vocabulary_from_topic(p_vocab_ids uuid[],p_topic_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid := public.require_current_user(); t public.topics%ROWTYPE;
BEGIN
  SELECT * INTO t FROM public.topics WHERE id=p_topic_id;
  IF NOT FOUND OR NOT(t.visibility='system' OR (t.visibility='private' AND t.owner_id=u) OR public.is_admin()) THEN
    RAISE EXCEPTION 'Topic is not accessible';
  END IF;
  DELETE FROM public.user_topic_vocab ut USING public.user_vocabulary uv
  WHERE ut.user_vocabulary_id=uv.id AND uv.user_id=u AND ut.topic_id=p_topic_id AND uv.vocab_id=ANY(p_vocab_ids);
  IF t.visibility='private' AND t.owner_id=u THEN
    DELETE FROM public.topic_vocab WHERE topic_id=p_topic_id AND vocab_id=ANY(p_vocab_ids);
  END IF;
  RETURN jsonb_build_object('success',true);
END;
$$;

-- Create and save a genuinely new meaning in one transaction. Reuse of existing
-- meanings is an explicit save_vocabulary_to_topic operation, never a text merge.
CREATE OR REPLACE FUNCTION public.create_vocabulary_meaning(p_vocab jsonb,p_topic_id uuid DEFAULT NULL,p_as_system boolean DEFAULT false)
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

CREATE OR REPLACE FUNCTION public.set_catalog_topics(p_vocab_id uuid,p_topic_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE u uuid := public.require_current_user(); ids uuid[];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  PERFORM 1 FROM public.vocab_catalog WHERE id=p_vocab_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Meaning not found'; END IF;
  SELECT COALESCE(array_agg(DISTINCT id),ARRAY[]::uuid[]) INTO ids FROM unnest(p_topic_ids) id WHERE id IS NOT NULL;
  IF (SELECT count(*) FROM public.topics WHERE id=ANY(ids) AND visibility='system') <> cardinality(ids) THEN RAISE EXCEPTION 'Invalid system topics'; END IF;
  DELETE FROM public.topic_vocab tv USING public.topics t
    WHERE tv.topic_id=t.id AND t.visibility='system' AND tv.vocab_id=p_vocab_id AND tv.topic_id<>ALL(ids);
  INSERT INTO public.topic_vocab(topic_id,vocab_id) SELECT id,p_vocab_id FROM unnest(ids) id ON CONFLICT DO NOTHING;
  -- Membership changes never rewrite any learner's progress or selected collections.
END;
$$;

-- Admin approval of a draft can attach existing sense IDs and save them for the
-- submitter without resetting progress, even if the meaning was already learned.
CREATE OR REPLACE FUNCTION public.attach_reviewed_topic_meanings(p_topic_id uuid,p_vocab_ids uuid[],p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.require_current_user();
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin access required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.topics WHERE id=p_topic_id AND visibility='system') THEN
    RAISE EXCEPTION 'System topic required';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_vocab_ids) id WHERE NOT EXISTS(
    SELECT 1 FROM public.vocab_catalog WHERE vocab_catalog.id=id AND visibility='system'
  )) THEN RAISE EXCEPTION 'Only approved meanings may be published'; END IF;
  INSERT INTO public.topic_vocab(topic_id,vocab_id) SELECT p_topic_id,id FROM unnest(p_vocab_ids) id ON CONFLICT DO NOTHING;
  INSERT INTO public.user_vocabulary(user_id,vocab_id)
    SELECT p_user_id,id FROM unnest(p_vocab_ids) id ON CONFLICT(user_id,vocab_id) DO NOTHING;
  INSERT INTO public.user_topic_vocab(user_vocabulary_id,topic_id)
    SELECT id,p_topic_id FROM public.user_vocabulary WHERE user_id=p_user_id AND vocab_id=ANY(p_vocab_ids)
    ON CONFLICT DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.save_vocabulary_to_topic(uuid[],uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.remove_vocabulary_from_topic(uuid[],uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_catalog_topics(uuid,uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_vocabulary_meaning(jsonb,uuid,boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.attach_reviewed_topic_meanings(uuid,uuid[],uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_vocabulary_to_topic(uuid[],uuid),
  public.remove_vocabulary_from_topic(uuid[],uuid), public.set_catalog_topics(uuid,uuid[]),
  public.create_vocabulary_meaning(jsonb,uuid,boolean), public.attach_reviewed_topic_meanings(uuid,uuid[],uuid) TO authenticated;

-- Allow the internal Master steps through level 9 and terminal Super at level 10.
ALTER TABLE public.user_vocabulary DROP CONSTRAINT IF EXISTS user_vocabulary_learning_level_check;
ALTER TABLE public.user_vocabulary ADD CONSTRAINT user_vocabulary_learning_level_check CHECK(learning_level BETWEEN 0 AND 10);
NOTIFY pgrst, 'reload schema';
COMMIT;
