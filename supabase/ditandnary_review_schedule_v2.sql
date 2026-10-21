-- Run after the vocabulary tables exist, before the v2 learning functions.
-- Deploy ditandnary_review_schedule_deploy.sql to run this migration and
-- replace the learning functions in one transaction on an existing project.
-- Re-running this file does not shift levels twice.
BEGIN;

CREATE TABLE IF NOT EXISTS public.ditandnary_schedule_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON public.ditandnary_schedule_migrations FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  LOCK TABLE public.ditandnary_schedule_migrations IN EXCLUSIVE MODE;
  IF NOT EXISTS (
    SELECT 1 FROM public.ditandnary_schedule_migrations
    WHERE name = 'new_zero_master_super_v2'
  ) THEN
    -- Old 0 was unscheduled; old 1 was due immediately. Preserve every
    -- scheduled review date while shifting the internal level down by one.
    ALTER TABLE public.user_vocabulary ALTER COLUMN learning_level DROP NOT NULL;
    ALTER TABLE public.user_vocabulary ALTER COLUMN learning_level DROP DEFAULT;
    ALTER TABLE public.user_vocabulary DROP CONSTRAINT IF EXISTS user_vocabulary_learning_level_check;

    UPDATE public.user_vocabulary
    SET learning_level = CASE
          WHEN learning_level IS NULL OR learning_level = 0 THEN NULL
          WHEN learning_level >= 11 THEN 10
          ELSE learning_level - 1
        END,
        next_review = CASE
          WHEN learning_level IS NULL OR learning_level = 0 OR learning_level >= 11 THEN NULL
          ELSE next_review
        END;

    ALTER TABLE public.user_vocabulary
      ADD CONSTRAINT user_vocabulary_learning_level_check
      CHECK (learning_level BETWEEN 0 AND 10);
    INSERT INTO public.ditandnary_schedule_migrations(name)
    VALUES ('new_zero_master_super_v2');
  END IF;
END;
$$;

COMMIT;
