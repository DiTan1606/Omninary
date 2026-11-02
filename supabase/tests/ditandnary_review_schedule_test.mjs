// Run with a PGlite installation path as the first argument.
// Uses an isolated database and never connects to a real account.
import { createRequire } from 'node:module';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import assert from 'node:assert/strict';

const require = createRequire(resolve(process.argv[2] ?? '.', 'package.json'));
const { PGlite } = require('@electric-sql/pglite');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const migration = fs.readFileSync(resolve(root, 'ditandnary_review_schedule_v2.sql'), 'utf8');
const db = new PGlite();

try {
  await db.exec(`
    CREATE ROLE anon;
    CREATE ROLE authenticated;
    CREATE TABLE public.user_vocabulary (
      id integer PRIMARY KEY,
      learning_level integer NOT NULL DEFAULT 0,
      next_review timestamptz,
      CONSTRAINT user_vocabulary_learning_level_check CHECK (learning_level >= 0)
    );
    INSERT INTO public.user_vocabulary(id, learning_level, next_review) VALUES
      (1, 0, NULL),
      (2, 1, '2030-01-01T12:00:00Z'),
      (3, 2, '2030-01-02T12:00:00Z'),
      (4, 6, '2030-01-03T12:00:00Z'),
      (5, 10, '2030-01-04T12:00:00Z'),
      (6, 11, '2030-01-05T12:00:00Z');
  `);

  await db.exec(migration);
  const rows = (await db.query('SELECT learning_level, next_review FROM public.user_vocabulary ORDER BY id')).rows;
  assert.deepEqual(rows.map((row) => row.learning_level), [null, 0, 1, 5, 9, 10]);
  assert.deepEqual(rows.map((row) => row.next_review ? new Date(row.next_review).toISOString() : null), [
    null,
    '2030-01-01T12:00:00.000Z',
    '2030-01-02T12:00:00.000Z',
    '2030-01-03T12:00:00.000Z',
    '2030-01-04T12:00:00.000Z',
    null
  ]);

  await db.exec(migration);
  assert.deepEqual((await db.query('SELECT learning_level, next_review FROM public.user_vocabulary ORDER BY id')).rows, rows);
  await db.exec('INSERT INTO public.user_vocabulary(id) VALUES (7)');
  assert.equal((await db.query('SELECT learning_level FROM public.user_vocabulary WHERE id = 7')).rows[0].learning_level, null);
  await assert.rejects(() => db.exec('UPDATE public.user_vocabulary SET learning_level = 11 WHERE id = 7'));
  console.log('PASS: legacy progress, review dates, idempotence, and New default');
} finally {
  await db.close();
}
