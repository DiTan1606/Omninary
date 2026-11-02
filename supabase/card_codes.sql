-- Codes printed on physical word cards. Typing a code in the app's Explore page
-- reveals that card and lets the learner add the word to their collection.
--
-- One row per printed code. The development print has one code per word
-- (edition 'dev'); a retail print can give every copy its own code
-- (same table, another edition, copy_no 1..n), so codes never need a new schema.
-- The code list itself is not stored in this repository.

create table if not exists public.card_codes (
  code text primary key,
  catalog_id uuid not null references public.vocab_catalog (id) on delete cascade,
  edition text not null default 'dev',
  copy_no integer,
  created_at timestamptz not null default now(),
  -- 4-6 characters, no look-alikes (0/O, 1/I/L)
  constraint card_codes_format check (code ~ '^[2-9A-HJKMNP-Z]{4,6}$'),
  constraint card_codes_copy unique (edition, catalog_id, copy_no)
);

create index if not exists card_codes_catalog_idx on public.card_codes (catalog_id);
-- an edition without copy numbers has exactly one code per word
create unique index if not exists card_codes_one_per_word
  on public.card_codes (edition, catalog_id) where copy_no is null;

-- Nobody lists codes from the client: RLS on, no policies.
alter table public.card_codes enable row level security;

-- Look a typed code up; normalizes case and spaces. Returns no row for an unknown code.
create or replace function public.redeem_card_code(p_code text)
returns table (catalog_id uuid, card_no integer, edition text)
language sql
stable
security definer
set search_path = public
as $$
  select c.catalog_id, v.card_no, c.edition
  from public.card_codes c
  join public.vocab_catalog v on v.id = c.catalog_id
  where c.code = upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));
$$;

revoke all on function public.redeem_card_code(text) from public;
grant execute on function public.redeem_card_code(text) to anon, authenticated;
