// Isolated PostgreSQL tests. Never connects to Supabase.
// node supabase/tests/vocabulary_topic_memberships_test.mjs /tmp/omninary-streak-pg
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { workspaceChecks } from './vocabulary_workspace_checks.mjs';
import { independentItemChecks } from './vocabulary_independent_items_checks.mjs';
const require = createRequire(resolve(process.argv[2] ?? '/tmp/omninary-streak-pg', 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const migration = fs.readFileSync(resolve(root, 'vocabulary_topic_memberships.sql'), 'utf8');
const u = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
const admin = '00000000-0000-4000-8000-000000000003';
const a = '00000000-0000-4000-8000-000000000011';
const b = '00000000-0000-4000-8000-000000000012';
const foreignTopic = '00000000-0000-4000-8000-000000000013';
const meaning = '00000000-0000-4000-8000-000000000021';
const progress = '00000000-0000-4000-8000-000000000031';
let checks = 0;
const one = async (query) => (await db.query(query)).rows[0];
const verify = (value, label) => { assert.ok(value, label); checks++; };
const asUser = async (id) => db.exec(`RESET ROLE; SELECT set_config('request.jwt.claim.sub','${id}',false); SET ROLE authenticated;`);
const reset = async () => db.exec('RESET ROLE;');
await db.exec(`
  CREATE ROLE anon; CREATE ROLE authenticated; CREATE SCHEMA auth;
  CREATE TABLE auth.users(id uuid PRIMARY KEY);
  CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
  CREATE FUNCTION public.require_current_user() RETURNS uuid LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; RETURN auth.uid(); END $$;
  CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql AS $$ SELECT auth.uid()='${admin}'::uuid $$;
  GRANT USAGE ON SCHEMA public,auth TO authenticated;
  CREATE TABLE public.topics(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL UNIQUE,
    visibility text NOT NULL DEFAULT 'system',owner_id uuid REFERENCES auth.users ON DELETE SET NULL);
  CREATE TABLE public.vocab_catalog(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),topic_id uuid REFERENCES topics ON DELETE SET NULL,
    created_by uuid REFERENCES auth.users,visibility text NOT NULL,word text NOT NULL,
    cefr text,ipa text,word_form text,e_meaning text,ev_meaning text,v_meaning text,e_example text,v_example text,
    word_family text,synonymous text,antonym text,bonus text);
  CREATE TABLE public.user_vocabulary(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES auth.users,
    vocab_id uuid NOT NULL REFERENCES vocab_catalog ON DELETE CASCADE,learning_level integer NOT NULL DEFAULT 0,
    next_review timestamptz,pronunciation_score integer,saved_at timestamptz DEFAULT now(),
    CONSTRAINT user_vocabulary_learning_level_check CHECK(learning_level BETWEEN 0 AND 6),UNIQUE(user_id,vocab_id));
  ALTER TABLE topics ENABLE ROW LEVEL SECURITY;
  ALTER TABLE vocab_catalog ENABLE ROW LEVEL SECURITY;
  ALTER TABLE user_vocabulary ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "Users can view available topics" ON topics FOR SELECT TO authenticated USING(visibility='system' OR owner_id=auth.uid() OR is_admin());
  CREATE POLICY topics_select_authenticated ON topics FOR SELECT TO authenticated USING(true);
  CREATE POLICY own_topic_insert ON topics FOR INSERT TO authenticated WITH CHECK(owner_id=auth.uid() AND visibility='private');
  CREATE POLICY own_topic_delete ON topics FOR DELETE TO authenticated USING(owner_id=auth.uid() AND visibility='private');
  CREATE POLICY vocab_visible ON vocab_catalog FOR SELECT TO authenticated USING(visibility='system' OR created_by=auth.uid() OR is_admin());
  CREATE POLICY progress_visible ON user_vocabulary FOR SELECT TO authenticated USING(user_id=auth.uid() OR is_admin());
  GRANT SELECT,INSERT,DELETE ON topics TO authenticated;
  GRANT SELECT ON vocab_catalog,user_vocabulary TO authenticated;
  INSERT INTO auth.users VALUES('${u}'),('${other}'),('${admin}');
  INSERT INTO topics VALUES('${a}','Business','system',NULL),('${b}','IELTS','private','${u}'),('${foreignTopic}','Other private','private','${other}');
  INSERT INTO vocab_catalog(id,topic_id,created_by,visibility,word,word_form,v_meaning)
    VALUES('${meaning}','${a}','${admin}','system','Bank','noun','Ngân hàng');
  INSERT INTO user_vocabulary(id,user_id,vocab_id,learning_level,next_review,pronunciation_score)
    VALUES('${progress}','${u}','${meaning}',4,'2030-01-01',88);
`);
try {
  await db.exec(migration);
  const before = await one(`SELECT * FROM user_vocabulary WHERE id='${progress}'`);
  verify((await one('SELECT count(*)::int n FROM topic_vocab')).n === 1, 'backfills catalog membership');
  verify((await one('SELECT count(*)::int n FROM user_topic_vocab')).n === 1, 'backfills selected membership');
  verify((await one('SELECT count(*)::int n FROM vocabulary_words')).n === 1, 'backfills independent word identity');
  await asUser(u);
  await db.exec(`SELECT save_vocabulary_to_topic(ARRAY['${meaning}'::uuid],'${b}');`);
  await db.exec(`SELECT save_vocabulary_to_topic(ARRAY['${meaning}'::uuid,'${meaning}'::uuid],'${b}');`);
  assert.deepEqual(await one(`SELECT * FROM user_vocabulary WHERE id='${progress}'`), before); checks++;
  verify((await one('SELECT count(*)::int n FROM user_vocabulary')).n === 1, 'same meaning has exactly one progress record');
  verify((await one('SELECT count(*)::int n FROM user_topic_vocab')).n === 2, 'same learned meaning appears in two chosen topics');
  await assert.rejects(() => db.exec(`SELECT save_vocabulary_to_topic(ARRAY['${meaning}'::uuid],'${foreignTopic}');`)); checks++;
  verify((await one(`SELECT count(*)::int n FROM topics WHERE id='${foreignTopic}'`)).n === 0, 'private topics hidden from other learners');
  await assert.rejects(() => db.exec(`SELECT set_catalog_topics('${meaning}',ARRAY['${a}'::uuid]);`)); checks++;
  await assert.rejects(() => db.exec(`INSERT INTO topic_vocab VALUES('${b}','${meaning}',now());`)); checks++;
  await assert.rejects(() => db.exec(`INSERT INTO user_topic_vocab VALUES('${progress}','${foreignTopic}',now());`)); checks++;
  const newMeaning = (await one(`SELECT create_vocabulary_meaning('{"word":"bank","word_form":"noun","v_meaning":"Bờ sông"}'::jsonb,'${b}',false) AS id`)).id;
  verify((await one(`SELECT learning_level,next_review FROM user_vocabulary WHERE vocab_id='${newMeaning}'`)).learning_level === 0, 'new sense starts at zero');
  await reset();
  verify((await one('SELECT count(*)::int n FROM vocabulary_words')).n === 1, 'different senses share word identity');
  verify((await one('SELECT count(*)::int n FROM vocab_catalog')).n === 2, 'different meanings are not merged');
  await asUser(other);
  verify((await one(`SELECT count(*)::int n FROM vocab_catalog WHERE id='${newMeaning}'`)).n === 0, 'private meaning hidden');
  await assert.rejects(() => db.exec(`SELECT save_vocabulary_to_topic(ARRAY['${newMeaning}'::uuid],'${foreignTopic}');`)); checks++;
  await db.exec(`INSERT INTO topics(name,visibility,owner_id) VALUES('IELTS','private','${other}');`); checks++;
  await asUser(u);
  const countBefore = (await one('SELECT count(*)::int n FROM vocab_catalog')).n;
  await assert.rejects(() => db.exec(`SELECT create_vocabulary_meaning('{"word":"secret"}','${foreignTopic}',false);`)); checks++;
  verify((await one('SELECT count(*)::int n FROM vocab_catalog')).n === countBefore, 'failed create leaves no orphan sense');
  await assert.rejects(() => db.exec(`SELECT create_vocabulary_meaning('{"word":"secret"}',NULL,true);`)); checks++;
  await db.exec(`SELECT remove_vocabulary_from_topic(ARRAY['${meaning}'::uuid],'${b}');`);
  assert.deepEqual(await one(`SELECT * FROM user_vocabulary WHERE id='${progress}'`), before); checks++;
  verify((await one(`SELECT count(*)::int n FROM user_topic_vocab WHERE user_vocabulary_id='${progress}' AND topic_id='${b}'`)).n === 0, 'remove affects only chosen membership');
  await reset(); await db.exec(migration);
  verify((await one(`SELECT count(*)::int n FROM user_topic_vocab WHERE user_vocabulary_id='${progress}' AND topic_id='${b}'`)).n === 0, 're-running migration does not restore removed membership');
  await db.exec(`UPDATE user_vocabulary SET learning_level=7 WHERE id='${progress}';`);
  verify((await one(`SELECT learning_level FROM user_vocabulary WHERE id='${progress}'`)).learning_level === 7, 'level six can advance to seven');
  await asUser(admin);
  await db.exec(`SELECT set_catalog_topics('${meaning}',ARRAY['${a}'::uuid]);`);
  await db.exec(`SELECT attach_reviewed_topic_meanings('${a}',ARRAY['${meaning}'::uuid],'${u}');`);
  verify((await one(`SELECT learning_level FROM user_vocabulary WHERE id='${progress}'`)).learning_level === 7, 'reviewed-topic save preserves existing progress');
  await asUser(u);
  await db.exec(`DELETE FROM topics WHERE id='${b}';`);
  verify((await one(`SELECT count(*)::int n FROM user_vocabulary WHERE vocab_id='${newMeaning}'`)).n === 1, 'deleting collection retains saved meaning');
  verify((await one(`SELECT count(*)::int n FROM vocab_catalog WHERE id='${newMeaning}'`)).n === 1, 'deleting collection retains content');
  verify((await one(`SELECT learning_level FROM user_vocabulary WHERE id='${progress}'`)).learning_level === 7, 'deleting collection retains other progress');
  await assert.rejects(() => db.exec(`SELECT save_vocabulary_to_topic(ARRAY['${newMeaning}'::uuid],'${foreignTopic}');`)); checks++;
  await reset();
  verify((await one(`SELECT count(*)::int n FROM user_topic_vocab WHERE topic_id='${b}'`)).n === 0, 'deleted collection has no dangling membership');
  await db.exec(`INSERT INTO vocab_catalog(id,created_by,visibility,word,topic_id) VALUES(gen_random_uuid(),'${admin}','system','  credit   card  ','${a}');`);
  verify((await one(`SELECT normalized_word FROM vocabulary_words WHERE normalized_word='credit card'`)).normalized_word === 'credit card', 'normalizes word spacing');
  console.log(`PASS: ${checks} vocabulary structure checks`);
  await workspaceChecks({ db, migrationPath: resolve(root, 'vocabulary_workspace.sql'), user: u, other,
    meaning, secondMeaning: newMeaning, progress, systemTopic: a });
  await independentItemChecks({ db, migrationPath: resolve(root, 'vocabulary_independent_items.sql'), user: u, other });
  await reset();
  const rootBefore = await one(`SELECT root_topic_id FROM user_vocabulary_workspace WHERE user_id='${u}'`);
  const progressBeforeRename = (await db.query('SELECT * FROM user_vocabulary ORDER BY id')).rows;
  await db.exec(fs.readFileSync(resolve(root, 'vocabulary_root_collection_name.sql'), 'utf8'));
  verify((await one(`SELECT name FROM topics WHERE id='${rootBefore.root_topic_id}'`)).name === 'Bộ từ gốc', 'existing root renamed in place');
  assert.deepEqual((await db.query('SELECT * FROM user_vocabulary ORDER BY id')).rows, progressBeforeRename);
  await asUser(u);
  verify((await one('SELECT ensure_vocabulary_root() id')).id === rootBefore.root_topic_id, 'renamed root retains ID');
  await assert.rejects(() => db.exec(`DELETE FROM topics WHERE id='${rootBefore.root_topic_id}'`));
  await asUser(admin);
  const newRoot = await one('SELECT ensure_vocabulary_root() id');
  verify((await one(`SELECT name FROM topics WHERE id='${newRoot.id}'`)).name === 'Bộ từ gốc', 'new users receive new root name');
  await reset();
  await db.exec(fs.readFileSync(resolve(root, 'vocabulary_root_collection_name.sql'), 'utf8'));
  console.log('PASS: root rename, stable identity, progress preservation, protection and migration rerun');
} finally { await db.close(); }
