# Omninary Web

Web workspace for Omninary learners and admins.

## Run locally

```bash
cd admin-web
npm install
npm run dev
```

Default local URLs:

- User web: `http://localhost:5174/app`
- Admin web: `http://localhost:5174/admin`

The admin route uses Supabase Auth and only allows accounts with `profiles.role = admin`.

## Environment

Copy `.env.example` if you want to override the default local Supabase config:

```bash
cp .env.example .env.local
```

Do not put a Supabase service role key in this frontend app.

## Supabase

Run `supabase/user_web_support.sql` after the existing contribution/private-topic migrations. It adds the user-web RLS policies and a unique guard so one user cannot download the same catalog row twice.

## Excel columns

Import supports these headers:

```text
word, cefr, ipa, word_form, e_meaning, ev_meaning, v_meaning,
e_example, v_example, word_family, synonymous, antonym, bonus
```

Vietnamese aliases such as `từ vựng`, `nghĩa việt`, `phiên âm`, and `loại từ` are also accepted.

## Current modules

- User dashboard
- Explore and download system topics
- My Vocabulary
- Learning review queue
- Private topic and private vocabulary creation
- User Excel import/export
- User contribution tracking and notifications
- Dashboard overview
- Topic management
- System vocabulary management
- Excel import/export
- Contribution review
- User role management
