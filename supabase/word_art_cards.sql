-- Word cards: a printed card number and a pixel picture for each catalog row.
-- card_no is the STT of the word in its source list (#1, #100...); it is also the key
-- of the picture in the word-art bucket and of the card's QR link.

alter table public.vocab_catalog
  add column if not exists card_no integer,
  add column if not exists art_path text;

create unique index if not exists vocab_catalog_card_no_key
  on public.vocab_catalog (card_no) where card_no is not null;

alter table public.vocab_catalog
  add constraint vocab_catalog_card_no_positive check (card_no is null or card_no > 0);

-- 24x24 PNGs, readable by everyone; only the service role writes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('word-art', 'word-art', true, 65536, array['image/png'])
on conflict (id) do update set public = true, file_size_limit = 65536, allowed_mime_types = array['image/png'];
