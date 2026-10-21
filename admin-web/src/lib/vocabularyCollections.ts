import type { Topic, UserVocabulary, VocabCatalog } from './types';

export function catalogTopics(vocab: VocabCatalog): Topic[] {
  if (vocab.topic_vocab !== undefined) return vocab.topic_vocab.flatMap((link) => link.topics ? [link.topics] : []);
  return vocab.topics ? [vocab.topics] : [];
}

export function savedTopics(row: UserVocabulary): Topic[] {
  if (row.user_topic_vocab !== undefined) return row.user_topic_vocab.flatMap((link) => link.topics ? [link.topics] : []);
  return row.vocab_catalog?.topics ? [row.vocab_catalog.topics] : [];
}

export function inTopic(row: UserVocabulary, topic: Topic): UserVocabulary {
  return { ...row, vocab_catalog: row.vocab_catalog ? { ...row.vocab_catalog, topic_id: topic.id, topics: topic } : null };
}

export function vocabularyIdentity(vocab: VocabCatalog): string {
  return vocab.id;
}
