import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
const dir=await mkdtemp(path.join(tmpdir(),'omninary-vocab-import-'));
try {
  const output=path.join(dir,'excel.mjs');
  await build({entryPoints:[fileURLToPath(new URL('../src/lib/excel.ts',import.meta.url))],outfile:output,bundle:true,platform:'node',format:'esm',logLevel:'silent'});
  const {parseVocabularyRows}=await import(pathToFileURL(output).href);
  const headers=['STT MỚI','STT CŨ','word','cefr','ipa','word_form','e_meaning','ev_meaning','v_meaning','e_example','v_example','word_family','synonymous','antonym','collocation','formula','note','bonus'];
  const cells=[0,12,'happy','B1','/ˈhæpi/','adjective','feeling pleased','cảm thấy hài lòng','vui','I am happy.','Tôi vui.','happiness','glad','sad','happy occasion','happy to do something','usage note','extra bonus'];
  const [row]=parseVocabularyRows([headers,cells],null);
  for(const field of headers.slice(2)) assert.equal(row[field],cells[headers.indexOf(field)]);
  assert.equal(row.error,undefined);
  for(const field of ['STT MỚI','STT CŨ','id','idioms']) assert.equal(field in row,false);
  assert.notEqual(row.note,row.bonus);
  const legacyHeaders=[...headers.slice(2,11),'bonus','idioms'];
  const [legacy]=parseVocabularyRows([legacyHeaders,[...cells.slice(2,11),'old bonus','on cloud nine']],null);
  assert.equal(legacy.error,undefined); assert.equal(legacy.bonus,'old bonus');
  assert.equal(legacy.note,''); assert.equal(legacy.collocation,''); assert.equal('idioms' in legacy,false);
  const [incomplete]=parseVocabularyRows([['word','bonus'],['legacy','old bonus']],null);
  assert.ok(incomplete.error); assert.equal(incomplete.bonus,'old bonus');
  for(const field of headers.slice(2,11)) {
    const bad=[...cells]; bad[headers.indexOf(field)]='  ';
    assert.ok(parseVocabularyRows([headers,bad],null)[0].error,field);
  }
  for(const field of headers.slice(11)) {
    const multi=[...cells]; multi[headers.indexOf(field)]=' one, with explanation ; ; two ; ';
    assert.equal(parseVocabularyRows([headers,multi],null)[0][field],'one, with explanation; two');
    const annotated=[...cells]; annotated[headers.indexOf(field)]='old value\n(Nhận xét ưu tiên 2: Cần sửa)';
    assert.match(parseVocabularyRows([headers,annotated],null)[0].error,/nhận xét/);
  }
  const idiom=[...cells]; idiom[2]='go Dutch'; idiom[5]='idioms';
  assert.equal(parseVocabularyRows([headers,idiom],null)[0].word_form,'idioms');
  if(process.argv[2]) {
    const source=JSON.parse(await readFile(process.argv[2],'utf8'));
    const rows=parseVocabularyRows(source.sheets[0].values,null);
    assert.equal(rows.length,196);
    assert.equal(rows[0].formula,'stay up late doing sth; stay up late to do sth');
    assert.equal(rows[0].bonus,''); assert.ok(rows[0].note.includes('burn the midnight oil'));
    assert.equal(rows.filter(r=>r.error).length,6);
  }
  console.log('PASS: 16 attributes, ignored STT and obsolete idioms column, required content, semicolon values and review annotation protection');
} finally {await rm(dir,{recursive:true,force:true});}
