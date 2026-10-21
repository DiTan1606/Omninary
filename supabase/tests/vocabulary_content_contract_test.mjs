import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(resolve(process.argv[2] ?? '/private/tmp/omninary-vocab-dbtest-20261010', 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const db = new PGlite();
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const migration = fs.readFileSync(resolve(root, 'vocabulary_content_contract_v4.sql'), 'utf8');
const user='00000000-0000-4000-8000-000000000001';
const payload={word:' go Dutch ',cefr:'B2',ipa:'/ɡəʊ dʌtʃ/',word_form:'idioms',e_meaning:'To share the cost of something.',ev_meaning:'Cùng chia chi phí.',v_meaning:'chia đều tiền',e_example:'We decided to go Dutch for dinner.',v_example:'Chúng tôi quyết định chia đều tiền bữa tối.',word_family:' ; ;',synonymous:' split the bill ; share the cost; ; ',note:'Ghi chú riêng; Ví dụ khác',bonus:'Thông tin mở rộng'};
try {
  await db.exec(`
    CREATE ROLE anon; CREATE ROLE authenticated;
    CREATE FUNCTION require_current_user() RETURNS uuid LANGUAGE sql AS $$ SELECT '${user}'::uuid $$;
    CREATE FUNCTION is_admin() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
    CREATE TABLE topics(id uuid PRIMARY KEY, visibility text, owner_id uuid);
    CREATE TABLE vocab_catalog(id uuid PRIMARY KEY,topic_id uuid,created_by uuid,visibility text,word text,
      cefr text,ipa text,word_form text,e_meaning text,ev_meaning text,v_meaning text,e_example text,v_example text,
      word_family text,synonymous text,antonym text,collocation text,idioms text,formula text,note text,bonus text);
    CREATE TABLE topic_submission_words(LIKE vocab_catalog);
    CREATE TABLE user_vocabulary(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,vocab_id uuid,learning_level integer);
    CREATE FUNCTION save_vocabulary_to_topic(ids uuid[],topic uuid) RETURNS void LANGUAGE sql AS $$
      INSERT INTO user_vocabulary(user_id,vocab_id,learning_level) SELECT '${user}'::uuid,unnest(ids),NULL
    $$;
    INSERT INTO vocab_catalog(id,word) VALUES(gen_random_uuid(),'legacy incomplete');
    INSERT INTO user_vocabulary(user_id,vocab_id,learning_level) SELECT '${user}',id,4 FROM vocab_catalog;
    GRANT USAGE ON SCHEMA public TO authenticated,anon;
    GRANT SELECT, INSERT, UPDATE ON vocab_catalog TO authenticated;
  `);
  const legacy=(await db.query('SELECT to_jsonb(v)-\'idioms\' data FROM vocab_catalog v')).rows;
  const progress=(await db.query('SELECT * FROM user_vocabulary')).rows;
  await db.exec(migration);
  assert.deepEqual((await db.query('SELECT to_jsonb(v) data FROM vocab_catalog v')).rows,legacy);
  assert.deepEqual((await db.query('SELECT * FROM user_vocabulary')).rows,progress);
  assert.equal((await db.query("SELECT count(*) n FROM information_schema.columns WHERE table_name IN ('vocab_catalog','topic_submission_words') AND column_name='idioms'")).rows[0].n,0);
  await db.exec('SET ROLE authenticated');
  const id=(await db.query('SELECT create_vocabulary_item($1,NULL,false) id',[JSON.stringify(payload)])).rows[0].id;
  const saved=(await db.query('SELECT * FROM vocab_catalog WHERE id=$1',[id])).rows[0];
  assert.equal(saved.word,'go Dutch'); assert.equal(saved.word_form,'idioms');
  assert.equal(saved.synonymous,'split the bill; share the cost'); assert.equal(saved.word_family,null);
  assert.equal(saved.note,payload.note); assert.equal(saved.bonus,payload.bonus);
  // The trigger must work on authenticated direct writes despite revoked manual execution.
  await db.query("UPDATE vocab_catalog SET synonymous=' first ; ; second;' WHERE id=$1",[id]);
  assert.equal((await db.query('SELECT synonymous FROM vocab_catalog WHERE id=$1',[id])).rows[0].synonymous,'first; second');
  await assert.rejects(()=>db.query("UPDATE vocab_catalog SET cefr=' ' WHERE id=$1",[id]));
  await assert.rejects(()=>db.query("INSERT INTO vocab_catalog(id,word) VALUES(gen_random_uuid(),'missing content')"));
  for(const field of ['word','cefr','ipa','word_form','e_meaning','ev_meaning','v_meaning','e_example','v_example']) {
    for(const bad of ['',null,[],{}]) await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,false)',[JSON.stringify({...payload,[field]:bad})]));
  }
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,false)',[JSON.stringify({...payload,note:['a','b']})]));
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,false)',[JSON.stringify({...payload,e_example:'…'})]));
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,false)',[JSON.stringify({...payload,note:'A; B\n(Nhận xét ưu tiên 1: Cần sửa)'})]));
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,true)',[JSON.stringify(payload)]));
  await db.exec('RESET ROLE; SET ROLE anon');
  await assert.rejects(()=>db.query('SELECT create_vocabulary_item($1,NULL,false)',[JSON.stringify(payload)]));
  await db.exec('RESET ROLE');
  await assert.rejects(()=>db.query("UPDATE vocab_catalog SET cefr=' ' WHERE id=$1",[id]));
  await db.query("UPDATE vocab_catalog SET synonymous='a ; ; b;' WHERE id=$1",[id]);
  assert.equal((await db.query('SELECT synonymous FROM vocab_catalog WHERE id=$1',[id])).rows[0].synonymous,'a; b');
  await assert.rejects(()=>db.query("INSERT INTO topic_submission_words(id,word) VALUES(gen_random_uuid(),'invalid draft')"));
  await db.query('INSERT INTO topic_submission_words SELECT * FROM vocab_catalog WHERE id=$1',[id]);
  const catalog=(await db.query('SELECT * FROM vocab_catalog ORDER BY id')).rows;
  await db.exec(migration);
  assert.deepEqual((await db.query('SELECT * FROM vocab_catalog ORDER BY id')).rows,catalog);
  console.log('PASS: 16-field contract, independent idioms, required content, semicolon values, review annotations, permissions, legacy progress and rerun');
} finally { await db.close(); }
