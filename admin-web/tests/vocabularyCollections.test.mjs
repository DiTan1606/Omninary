// Compile vocabularyCollections.ts/types.ts to CommonJS in a temporary directory
// and pass that directory as argv[2]. No Supabase connection is used.
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
const require = createRequire(import.meta.url);
const { catalogTopics, savedTopics, inTopic, vocabularyIdentity } = require(resolve(process.argv[2], 'vocabularyCollections.js'));
const a = { id: 'business', name: 'Business', visibility: 'system' };
const b = { id: 'exam', name: 'IELTS', visibility: 'private' };
const vocab = { id: 'sense', word: 'bank', topic_id: a.id, topics: a, topic_vocab: [{ topics: a }, { topics: b }] };
const progress = { id: 'progress', vocab_id: 'sense', learning_level: 4, next_review: '2030-01-01', vocab_catalog: vocab,
  user_topic_vocab: [{ topics: a }, { topics: b }] };
assert.deepEqual(catalogTopics(vocab).map((t) => t.id), ['business', 'exam']);
assert.deepEqual(savedTopics(progress).map((t) => t.id), ['business', 'exam']);
const projected = inTopic(progress, b);
assert.equal(projected.id, progress.id);
assert.equal(projected.vocab_id, progress.vocab_id);
assert.equal(projected.learning_level, 4);
assert.equal(projected.next_review, progress.next_review);
assert.equal(projected.vocab_catalog.topics.id, 'exam');
assert.equal(progress.vocab_catalog.topics.id, 'business');
assert.deepEqual(savedTopics({ ...progress, user_topic_vocab: [] }), []);
assert.deepEqual(catalogTopics({ ...vocab, topic_vocab: [] }), []);
assert.equal(vocabularyIdentity({ ...vocab, word: 'Bank' }), vocabularyIdentity(vocab));
assert.equal(vocabularyIdentity({ id: 'legacy', word: '  credit   card  ' }), 'legacy');
assert.notEqual(vocabularyIdentity({ ...vocab, id: 'river' }), vocabularyIdentity(vocab));
console.log('PASS: 13 web collection checks');
