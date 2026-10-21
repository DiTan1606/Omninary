export type ReviewStatus = 'pending' | 'approved' | 'rejected';

export interface Profile {
  id: string;
  email: string | null;
  display_name: string | null;
  avatar_url: string | null;
  role: string | null;
  created_at: string | null;
}

export interface Topic {
  id: string;
  name: string;
  description?: string | null;
  visibility?: string | null;
  owner_id?: string | null;
  created_at?: string | null;
}

export interface VocabCatalog {
  topic_vocab?: Array<{ topics: Topic | null }>;
  id: string;
  created_at: string | null;
  topic_id: string | null;
  created_by: string | null;
  visibility: string | null;
  word: string | null;
  cefr: string | null;
  ipa: string | null;
  word_form: string | null;
  e_meaning: string | null;
  ev_meaning: string | null;
  v_meaning: string | null;
  e_example: string | null;
  v_example: string | null;
  word_family: string | null;
  synonymous: string | null;
  antonym: string | null;
  collocation: string | null;
  formula: string | null;
  note: string | null;
  bonus: string | null;
  topics?: Topic | null;
}

export interface VocabInput {
  topic_ids?: string[];
  id?: string;
  topic_id: string | null;
  word: string;
  cefr: string;
  ipa: string;
  word_form: string;
  e_meaning: string;
  ev_meaning: string;
  v_meaning: string;
  e_example: string;
  v_example: string;
  word_family: string;
  synonymous: string;
  antonym: string;
  collocation: string;
  formula: string;
  note: string;
  bonus: string;
}

export interface UserVocabulary {
  user_topic_vocab?: Array<{ topics: Topic | null }>;
  id: string;
  user_id: string | null;
  vocab_id: string | null;
  learning_level: number | null;
  next_review: string | null;
  pronunciation_score: number | null;
  saved_at: string | null;
  vocab_catalog: VocabCatalog | null;
}

export interface UserDashboardStats {
  savedWords: number;
  uniqueWords: number;
  learningWords: number;
  dueWords: number;
  masteredWords: number;
  privateTopics: number;
  pendingRequests: number;
  rejectedRequests: number;
}

export interface ExploreTopic {
  topic: Topic;
  vocabs: VocabCatalog[];
  totalWords: number;
  downloadedWords: number;
  newWords: number;
  newMeanings: number;
}

export interface TopicDownloadResult {
  addedMeanings: number;
  addedWords: number;
}

export interface VocabSubmission {
  id: string;
  requester_id: string;
  catalog_id: string | null;
  topic_id: string | null;
  status: ReviewStatus;
  created_at: string | null;
  admin_note?: string | null;
  vocab_catalog: VocabCatalog | null;
}

export interface UserVocabSubmission extends VocabSubmission {
  reviewed_at?: string | null;
}

export interface TopicSubmissionWord {
  id: string;
  catalog_id: string | null;
  word: string;
  cefr: string | null;
  ipa: string | null;
  word_form: string | null;
  e_meaning: string | null;
  ev_meaning: string | null;
  v_meaning: string | null;
  e_example: string | null;
  v_example: string | null;
  word_family: string | null;
  synonymous: string | null;
  antonym: string | null;
  collocation: string | null;
  formula: string | null;
  note: string | null;
  bonus: string | null;
}

export interface TopicSubmission {
  id: string;
  requester_id: string;
  topic_id: string | null;
  name: string;
  description: string | null;
  status: ReviewStatus;
  created_at: string | null;
  admin_note?: string | null;
  topic_submission_words: TopicSubmissionWord[] | null;
}

export interface UserTopicSubmission extends TopicSubmission {
  reviewed_at?: string | null;
}

export interface AppNotification {
  id: string;
  user_id: string | null;
  title: string;
  content: string;
  is_read: boolean;
  created_at: string | null;
}

export interface UserStats {
  user_id: string;
  streak_count: number;
  last_learning_date: string | null;
}

export interface ActivityLog {
  user_id: string;
  date: string;
  completed: boolean;
}

export interface DashboardStats {
  users: number;
  topics: number;
  systemVocabs: number;
  pendingWords: number;
  pendingTopics: number;
}

export interface ImportRow extends VocabInput {
  rowNumber: number;
  error?: string;
}
