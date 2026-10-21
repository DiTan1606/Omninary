// Isolated database; never connects to Supabase or changes experiment data.
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(resolve(process.argv[2] ?? '/private/tmp/omninary-streak-pg', 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const migration = fs.readFileSync(resolve(root, 'vocabulary_content_fields_v3.sql'), 'utf8');
const user='00000000-0000-4000-8000-000000000001';
const admin='00000000-0000-4000-8000-000000000002';
const fields=['collocation','idioms','formula','note'];
try {
  await db.exec(`
    CREATE ROLE anon; CREATE ROLE authenticated; CREATE SCHEMA auth;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    CREATE FUNCTION require_current_user() RETURNS uuid LANGUAGE plpgsql AS $$ BEGIN IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; RETURN auth.uid(); END $$;
    CREATE FUNCTION is_admin() RETURNS boolean LANGUAGE sql AS $$ SELECT auth.uid()='${admin}'::uuid $$;
    CREATE TABLE topics(id uuid PRIMARY KEY, visibility text, owner_id uuid);
    CREATE TABLE vocab_catalog(id uuid PRIMARY KEY,topic_id uuid,created_by uuid,visibility text,word text,
      cefr text,ipa text,word_form text,e_meaning text,ev_meaning text,v_meaning text,e_example text,v_example text,
      word_family text,synonymous text,antonym text,bonus text);
    CREATE TABLE topic_submission_words(id uuid PRIMARY KEY,word text,bonus text);
    CREATE TABLE user_vocabulary(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,vocab_id uuid,learning_level integer,next_review timestamptz);
    CREATE FUNCTION save_vocabulary_to_topic(ids uuid[],topic uuid) RETURNS void LANGUAGE sql AS $$
      INSERT INTO user_vocabulary(user_id,vocab_id,learning_level) SELECT auth.uid(),unnest(ids),NULL
    $$;
    CREATE FUNCTION create_vocabulary_meaning(p_vocab jsonb,p_topic_id uuid DEFAULT NULL,p_as_system boolean DEFAULT false)
      RETURNS uuid LANGUAGE plpgsql AS $$ BEGIN RETURN create_vocabulary_item(p_vocab,p_topic_id,p_as_system); END $$;
    GRANT USAGE ON SCHEMA public,auth TO authenticated,anon;
    GRANT SELECT ON vocab_catalog TO authenticated;
    INSERT INTO vocab_catalog(id,word,bonus) VALUES(gen_random_uuid(),'existing','old bonus');
    INSERT INTO user_vocabulary(user_id,vocab_id,learning_level,next_review) SELECT '${user}',id,4,'2030-01-01' FROM vocab_catalog;
  `);
  const before=(await db.query('SELECT * FROM user_vocabulary')).rows;
  await db.exec(migration);
  assert.deepEqual((await db.query('SELECT * FROM user_vocabulary')).rows,before);
  assert.equal((await db.query("SELECT bonus,note FROM vocab_catalog WHERE word='existing'")).rows[0].note,null);
  assert.equal((await db.query("SELECT bonus FROM vocab_catalog WHERE word='existing'")).rows[0].bonus,'old bonus');
  await db.exec(`SELECT set_config('request.jwt.claim.sub','${user}',false); SET ROLE authenticated;`);
  const payload={word:' happy ',collocation:' happy occasion ',idioms:'on cloud nine',formula:'be happy to do something',note:'Ghi chú riêng',bonus:'Mở rộng riêng'};
  const id=(await db.query('SELECT create_vocabulary_item($1,NULL,false) id',[JSON.stringify(payload)])).rows[0].id;
  const row=(await db.query('SELECT * FROM vocab_catalog WHERE id=$1',[id])).rows[0];
  for (const field of fields) assert.equal(row[field],payload[field].trim());
  assert.equal(row.word,'happy'); assert.equal(row.bonus,payload.bonus);
  const legacy=(await db.query('SELECT create_vocabulary_meaning($1,NULL,false) id',[JSON.stringify({word:'legacy'})])).rows[0].id;
  assert.equal((await db.query('SELECT note FROM vocab_catalog WHERE id=$1',[legacy])).rows[0].note,null);
  const blank=(await db.query('SELECT create_vocabulary_item($1,NULL,false) id',[JSON.stringify({word:'blank',note:'   '})])).rows[0].id;
  assert.equal((await db.query('SELECT note FROM vocab_catalog WHERE id=$1',[blank])).rows[0].note,null);
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,true)',[JSON.stringify({word:'unauthorized'})]));
  await db.exec('RESET ROLE; SET ROLE anon');
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,false)',[JSON.stringify({word:'unauthenticated'})]));
  await db.exec('RESET ROLE');
  const catalog=(await db.query('SELECT * FROM vocab_catalog ORDER BY id')).rows;
  await db.exec(migration);
  assert.deepEqual((await db.query('SELECT * FROM vocab_catalog ORDER BY id')).rows,catalog);
  await db.query('INSERT INTO topic_submission_words(id,word,collocation,idioms,formula,note,bonus) VALUES(gen_random_uuid(),$1,$2,$3,$4,$5,$6)',['draft',...fields.map(f=>payload[f]),payload.bonus]);
  const draft=(await db.query("SELECT * FROM topic_submission_words WHERE word='draft'")).rows[0];
  for(const field of fields) assert.equal(draft[field],payload[field]);
  console.log('PASS: new fields, legacy clients, blank handling, note/bonus separation, access control, rerun and progress preservation');
} finally {await db.close();}
