-- English and Vietnamese examples are optional. Rows without a usable English
-- example remain learnable, but iOS skips their sentence-scramble and
-- pronunciation exercises.

begin;

alter table public.vocab_catalog
  drop constraint if exists vocab_catalog_e_example_required;

alter table public.topic_submission_words
  drop constraint if exists topic_submission_words_e_example_required;

update public.vocab_catalog
set
  e_example = case when btrim(coalesce(e_example, '')) in ('...', '…') then null else e_example end,
  v_example = case when btrim(coalesce(v_example, '')) in ('...', '…') then null else v_example end
where btrim(coalesce(e_example, '')) in ('...', '…')
   or btrim(coalesce(v_example, '')) in ('...', '…');

update public.topic_submission_words
set
  e_example = case when btrim(coalesce(e_example, '')) in ('...', '…') then null else e_example end,
  v_example = case when btrim(coalesce(v_example, '')) in ('...', '…') then null else v_example end
where btrim(coalesce(e_example, '')) in ('...', '…')
   or btrim(coalesce(v_example, '')) in ('...', '…');

commit;
