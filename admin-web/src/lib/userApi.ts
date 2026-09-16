import { User } from '@supabase/supabase-js';
import { supabase } from './supabase';
import {
  AppNotification,
  ExploreTopic,
  Profile,
  Topic,
  TopicDownloadResult,
  ActivityLog,
  UserDashboardStats,
  UserStats,
  UserTopicSubmission,
  UserVocabSubmission,
  UserVocabulary,
  VocabCatalog,
  VocabInput
} from './types';

const catalogSelect = `
id,created_at,topic_id,created_by,visibility,word,cefr,ipa,word_form,
e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,bonus,
topics(id,name,description,visibility,owner_id,created_at)
`;

const userVocabularySelect = `
id,user_id,vocab_id,learning_level,next_review,pronunciation_score,saved_at,
vocab_catalog(${catalogSelect})
`;

const topicSubmissionSelect = `
id,requester_id,topic_id,name,description,status,created_at,admin_note,reviewed_at,
topic_submission_words(id,catalog_id,word,cefr,ipa,word_form,e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,bonus)
`;

function clean(value: string | null | undefined) {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function cleanExample(value: string | null | undefined) {
  const trimmed = clean(value);
  return trimmed === '...' || trimmed === '…' ? null : trimmed;
}

function nowIso() {
  return new Date().toISOString();
}

function localDateKey(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function dayDiff(from: string, to = new Date()) {
  const [year, month, day] = from.split('-').map(Number);
  const fromDate = new Date(year, (month ?? 1) - 1, day ?? 1);
  const startFrom = new Date(fromDate.getFullYear(), fromDate.getMonth(), fromDate.getDate()).getTime();
  const startTo = new Date(to.getFullYear(), to.getMonth(), to.getDate()).getTime();
  return Math.round((startTo - startFrom) / 86400000);
}

export function emptyVocabInput(topicId: string | null = null): VocabInput {
  return {
    topic_id: topicId,
    word: '',
    cefr: '',
    ipa: '',
    word_form: '',
    e_meaning: '',
    ev_meaning: '',
    v_meaning: '',
    e_example: '',
    v_example: '',
    word_family: '',
    synonymous: '',
    antonym: '',
    bonus: ''
  };
}

export function catalogToInput(vocab: VocabCatalog): VocabInput {
  return {
    id: vocab.id,
    topic_id: vocab.topic_id,
    word: vocab.word ?? '',
    cefr: vocab.cefr ?? '',
    ipa: vocab.ipa ?? '',
    word_form: vocab.word_form ?? '',
    e_meaning: vocab.e_meaning ?? '',
    ev_meaning: vocab.ev_meaning ?? '',
    v_meaning: vocab.v_meaning ?? '',
    e_example: vocab.e_example ?? '',
    v_example: vocab.v_example ?? '',
    word_family: vocab.word_family ?? '',
    synonymous: vocab.synonymous ?? '',
    antonym: vocab.antonym ?? '',
    bonus: vocab.bonus ?? ''
  };
}

function toPrivateCatalogInsert(input: VocabInput, userId: string) {
  return {
    id: input.id ?? crypto.randomUUID(),
    topic_id: input.topic_id,
    created_by: userId,
    visibility: 'private',
    word: clean(input.word) ?? 'Untitled',
    cefr: clean(input.cefr),
    ipa: clean(input.ipa),
    word_form: clean(input.word_form),
    e_meaning: clean(input.e_meaning),
    ev_meaning: clean(input.ev_meaning),
    v_meaning: clean(input.v_meaning),
    e_example: cleanExample(input.e_example),
    v_example: cleanExample(input.v_example),
    word_family: clean(input.word_family),
    synonymous: clean(input.synonymous),
    antonym: clean(input.antonym),
    bonus: clean(input.bonus)
  };
}

function toCatalogUpdate(input: VocabInput) {
  return {
    topic_id: input.topic_id,
    word: clean(input.word) ?? 'Untitled',
    cefr: clean(input.cefr),
    ipa: clean(input.ipa),
    word_form: clean(input.word_form),
    e_meaning: clean(input.e_meaning),
    ev_meaning: clean(input.ev_meaning),
    v_meaning: clean(input.v_meaning),
    e_example: cleanExample(input.e_example),
    v_example: cleanExample(input.v_example),
    word_family: clean(input.word_family),
    synonymous: clean(input.synonymous),
    antonym: clean(input.antonym),
    bonus: clean(input.bonus)
  };
}

export async function getCurrentUser() {
  const { data, error } = await supabase.auth.getUser();
  if (error && !error.message.toLowerCase().includes('auth session missing')) throw error;
  return data.user;
}

export async function getProfile(userId: string) {
  const { data, error } = await supabase
    .from('profiles')
    .select('id,email,display_name,avatar_url,role,created_at')
    .eq('id', userId)
    .maybeSingle<Profile>();

  if (error) throw error;
  return data;
}

export async function getSignedInProfile(user: User | null) {
  if (!user) return null;
  return getProfile(user.id);
}

export async function fetchUserVocabs(userId: string) {
  const { data, error } = await supabase
    .from('user_vocabulary')
    .select(userVocabularySelect)
    .eq('user_id', userId)
    .order('saved_at', { ascending: false });

  if (error) throw error;
  return (data ?? []) as unknown as UserVocabulary[];
}

export async function fetchPrivateTopics(userId: string) {
  const { data, error } = await supabase
    .from('topics')
    .select('id,name,description,visibility,owner_id,created_at')
    .eq('owner_id', userId)
    .eq('visibility', 'private')
    .order('created_at', { ascending: false });

  if (error) throw error;
  return (data ?? []) as Topic[];
}

function wordKey(vocab: VocabCatalog) {
  return vocab.word?.trim().toLowerCase() || vocab.id;
}

function uniqueCatalogWordCount(vocabs: VocabCatalog[]) {
  return new Set(vocabs.map(wordKey)).size;
}

export async function fetchExploreTopics(userId: string): Promise<ExploreTopic[]> {
  const [{ data: topics, error: topicError }, { data: catalogRows, error: catalogError }, { data: userRows, error: userError }] =
    await Promise.all([
      supabase
        .from('topics')
        .select('id,name,description,visibility,owner_id,created_at')
        .eq('visibility', 'system')
        .order('name', { ascending: true }),
      supabase
        .from('vocab_catalog')
        .select(catalogSelect)
        .eq('visibility', 'system')
        .order('word', { ascending: true }),
      supabase
        .from('user_vocabulary')
        .select('vocab_id')
        .eq('user_id', userId)
    ]);

  if (topicError) throw topicError;
  if (catalogError) throw catalogError;
  if (userError) throw userError;

  const downloadedIds = new Set((userRows ?? []).map((row) => row.vocab_id).filter(Boolean));
  const vocabsByTopic = new Map<string, VocabCatalog[]>();

  ((catalogRows ?? []) as unknown as VocabCatalog[]).forEach((vocab) => {
    if (!vocab.topic_id) return;
    vocabsByTopic.set(vocab.topic_id, [...(vocabsByTopic.get(vocab.topic_id) ?? []), vocab]);
  });

  return ((topics ?? []) as Topic[]).map((topic) => {
    const vocabs = vocabsByTopic.get(topic.id) ?? [];
    const downloadedVocabs = vocabs.filter((vocab) => downloadedIds.has(vocab.id));
    const newVocabs = vocabs.filter((vocab) => !downloadedIds.has(vocab.id));

    return {
      topic,
      vocabs,
      totalWords: uniqueCatalogWordCount(vocabs),
      downloadedWords: uniqueCatalogWordCount(downloadedVocabs),
      newWords: uniqueCatalogWordCount(newVocabs),
      newMeanings: newVocabs.length
    };
  });
}

export async function downloadSystemTopic(userId: string, topicId: string): Promise<TopicDownloadResult> {
  const [{ data: catalogRows, error: catalogError }, { data: userRows, error: userError }] = await Promise.all([
    supabase
      .from('vocab_catalog')
      .select(catalogSelect)
      .eq('topic_id', topicId)
      .eq('visibility', 'system'),
    supabase
      .from('user_vocabulary')
      .select('vocab_id')
      .eq('user_id', userId)
  ]);

  if (catalogError) throw catalogError;
  if (userError) throw userError;

  const downloadedIds = new Set((userRows ?? []).map((row) => row.vocab_id).filter(Boolean));
  const newVocabs = ((catalogRows ?? []) as unknown as VocabCatalog[]).filter((vocab) => !downloadedIds.has(vocab.id));

  if (newVocabs.length > 0) {
    const payload = newVocabs.map((vocab) => ({
      id: crypto.randomUUID(),
      user_id: userId,
      vocab_id: vocab.id,
      learning_level: 0,
      next_review: null,
      pronunciation_score: null
    }));
    const { error } = await supabase
      .from('user_vocabulary')
      .upsert(payload, { onConflict: 'user_id,vocab_id', ignoreDuplicates: true });
    if (error) throw error;
  }

  return {
    addedMeanings: newVocabs.length,
    addedWords: uniqueCatalogWordCount(newVocabs)
  };
}

export async function createPrivateTopic(name: string, description: string, userId: string) {
  const payload = {
    id: crypto.randomUUID(),
    name: name.trim(),
    description: clean(description),
    visibility: 'private',
    owner_id: userId
  };

  const { data, error } = await supabase
    .from('topics')
    .insert(payload)
    .select('id,name,description,visibility,owner_id,created_at')
    .single<Topic>();

  if (error) throw error;
  return data;
}

export async function deletePrivateTopic(topic: Topic, userId: string) {
  const { data: linkedVocabs, error: vocabError } = await supabase
    .from('vocab_catalog')
    .select('id')
    .eq('topic_id', topic.id)
    .limit(1);

  if (vocabError) throw vocabError;
  if ((linkedVocabs ?? []).length > 0) throw new Error('Chỉ có thể xoá topic khi chưa có từ vựng nào.');

  const { data: pending, error: pendingError } = await supabase
    .from('topic_submissions')
    .select('id')
    .eq('requester_id', userId)
    .eq('topic_id', topic.id)
    .eq('status', 'pending')
    .limit(1);

  if (pendingError) throw pendingError;
  if ((pending ?? []).length > 0) throw new Error('Topic đang chờ duyệt, chưa thể xoá.');

  const { error: cleanupError } = await supabase
    .from('topic_submissions')
    .delete()
    .eq('requester_id', userId)
    .eq('topic_id', topic.id)
    .eq('status', 'rejected');

  if (cleanupError) throw cleanupError;

  const { error } = await supabase
    .from('topics')
    .delete()
    .eq('id', topic.id)
    .eq('owner_id', userId)
    .eq('visibility', 'private');

  if (error) throw error;
}

export async function createPrivateVocab(input: VocabInput, userId: string) {
  const catalog = toPrivateCatalogInsert(input, userId);
  const { error: catalogError } = await supabase.from('vocab_catalog').insert(catalog);
  if (catalogError) throw catalogError;

  const { error: linkError } = await supabase.from('user_vocabulary').insert({
    id: crypto.randomUUID(),
    user_id: userId,
    vocab_id: catalog.id,
    learning_level: 0,
    next_review: null,
    pronunciation_score: null
  });

  if (linkError) throw linkError;
}

export async function importPrivateVocabs(rows: VocabInput[], userId: string) {
  const rowsToImport = rows.filter((row) => row.word.trim());

  for (const row of rowsToImport) {
    await createPrivateVocab(row, userId);
  }
}

export async function updatePrivateVocab(input: VocabInput) {
  if (!input.id) throw new Error('Thiếu ID từ vựng.');
  const { error } = await supabase.from('vocab_catalog').update(toCatalogUpdate(input)).eq('id', input.id);
  if (error) throw error;
}

export async function deleteUserVocab(row: UserVocabulary) {
  if (!row.id) return;
  const catalogId = row.vocab_id ?? row.vocab_catalog?.id;
  const isPrivate = row.vocab_catalog?.visibility === 'private';

  const { error: linkError } = await supabase.from('user_vocabulary').delete().eq('id', row.id);
  if (linkError) throw linkError;

  if (isPrivate && catalogId) {
    const { error } = await supabase.from('vocab_catalog').delete().eq('id', catalogId);
    if (error) throw error;
  }
}

export async function submitVocabContribution(row: UserVocabulary) {
  const catalogId = row.vocab_id ?? row.vocab_catalog?.id;
  if (!catalogId || !row.user_id) throw new Error('Thiếu dữ liệu từ riêng.');

  const { error } = await supabase.from('vocab_submissions').insert({
    id: crypto.randomUUID(),
    requester_id: row.user_id,
    catalog_id: catalogId,
    topic_id: row.vocab_catalog?.topic_id ?? null,
    status: 'pending'
  });

  if (error) throw error;
}

export async function resubmitVocabContribution(submission: UserVocabSubmission) {
  if (!submission.catalog_id || !submission.requester_id) throw new Error('Thiếu dữ liệu gửi duyệt lại.');
  const { error } = await supabase.from('vocab_submissions').insert({
    id: crypto.randomUUID(),
    requester_id: submission.requester_id,
    catalog_id: submission.catalog_id,
    topic_id: submission.topic_id,
    status: 'pending'
  });

  if (error) throw error;
}

export async function fetchUserVocabSubmissions(userId: string) {
  const { data, error } = await supabase
    .from('vocab_submissions')
    .select(`id,requester_id,catalog_id,topic_id,status,created_at,admin_note,reviewed_at,vocab_catalog(${catalogSelect})`)
    .eq('requester_id', userId)
    .order('created_at', { ascending: false });

  if (error) throw error;
  return (data ?? []) as unknown as UserVocabSubmission[];
}

export async function fetchUserTopicSubmissions(userId: string) {
  const { data, error } = await supabase
    .from('topic_submissions')
    .select(topicSubmissionSelect)
    .eq('requester_id', userId)
    .neq('status', 'approved')
    .order('created_at', { ascending: false });

  if (error) throw error;
  return (data ?? []) as UserTopicSubmission[];
}

export async function submitPrivateTopicForReview(topic: Topic, vocabs: UserVocabulary[], userId: string) {
  const validVocabs = vocabs.filter((row) => row.vocab_catalog?.word?.trim() && (row.vocab_id ?? row.vocab_catalog?.id));
  if (validVocabs.length === 0) throw new Error('Topic cần có ít nhất một từ để gửi duyệt.');

  const submissionId = crypto.randomUUID();
  const { error: submissionError } = await supabase.from('topic_submissions').insert({
    id: submissionId,
    requester_id: userId,
    topic_id: topic.id,
    name: topic.name.trim(),
    description: clean(topic.description),
    status: 'pending'
  });

  if (submissionError) throw submissionError;

  const wordRows = validVocabs.map((row) => {
    const vocab = row.vocab_catalog;
    return {
      id: crypto.randomUUID(),
      submission_id: submissionId,
      catalog_id: row.vocab_id ?? vocab?.id ?? null,
      word: clean(vocab?.word) ?? 'Untitled',
      cefr: clean(vocab?.cefr),
      ipa: clean(vocab?.ipa),
      word_form: clean(vocab?.word_form),
      e_meaning: clean(vocab?.e_meaning),
      ev_meaning: clean(vocab?.ev_meaning),
      v_meaning: clean(vocab?.v_meaning),
      e_example: cleanExample(vocab?.e_example),
      v_example: cleanExample(vocab?.v_example),
      word_family: clean(vocab?.word_family),
      synonymous: clean(vocab?.synonymous),
      antonym: clean(vocab?.antonym),
      bonus: clean(vocab?.bonus)
    };
  });

  const { error: wordsError } = await supabase.from('topic_submission_words').insert(wordRows);
  if (wordsError) throw wordsError;
}

export async function resubmitTopicSubmission(submissionId: string) {
  const { error } = await supabase.from('topic_submissions').update({ status: 'pending' }).eq('id', submissionId);
  if (error) throw error;
}

export async function deleteRejectedTopicSubmission(submissionId: string, userId: string) {
  const { data, error } = await supabase
    .from('topic_submissions')
    .delete()
    .eq('id', submissionId)
    .eq('requester_id', userId)
    .eq('status', 'rejected')
    .select('id');

  if (error) throw error;
  if (!data?.length) throw new Error('Không xoá được request này. Bạn cần chạy SQL cập nhật quyền xoá topic bị từ chối trên Supabase.');
}

export async function updateLearningData(rowId: string, learningLevel: number, nextReview: string | null) {
  const { error } = await supabase
    .from('user_vocabulary')
    .update({ learning_level: learningLevel, next_review: nextReview })
    .eq('id', rowId);

  if (error) throw error;
}

export async function fetchNotifications(userId: string) {
  const { data, error } = await supabase
    .from('notifications')
    .select('id,user_id,title,content,is_read,created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(20);

  if (error) throw error;
  return (data ?? []) as AppNotification[];
}

export async function fetchUserStats(userId: string): Promise<UserStats> {
  const { data, error } = await supabase
    .from('user_stats')
    .select('user_id,streak_count,last_learning_date')
    .eq('user_id', userId)
    .maybeSingle<UserStats>();

  if (error) throw error;

  if (!data) return { user_id: userId, streak_count: 0, last_learning_date: null };

  if (data.last_learning_date && dayDiff(data.last_learning_date) > 1 && data.streak_count > 0) {
    const next = { ...data, streak_count: 0 };
    const { error: updateError } = await supabase
      .from('user_stats')
      .update({ streak_count: 0 })
      .eq('user_id', userId);
    if (updateError) throw updateError;
    return next;
  }

  return data;
}

export async function fetchActivityLogs(userId: string): Promise<ActivityLog[]> {
  const { data, error } = await supabase
    .from('activity_logs')
    .select('user_id,date,completed')
    .eq('user_id', userId)
    .eq('completed', true)
    .order('date', { ascending: false });

  if (error) throw error;
  return (data ?? []) as ActivityLog[];
}

export async function recordDailyActivityAndUpdateStreak(userId: string) {
  const today = localDateKey();

  const { error: logError } = await supabase.from('activity_logs').upsert({
    user_id: userId,
    date: today,
    completed: true
  });
  if (logError) throw logError;

  const stats = await fetchUserStats(userId);
  let nextStreak = 1;
  if (stats.last_learning_date) {
    const diff = dayDiff(stats.last_learning_date);
    if (diff === 0) nextStreak = Math.max(stats.streak_count, 1);
    else if (diff === 1) nextStreak = stats.streak_count + 1;
  }

  const { error } = await supabase.from('user_stats').upsert({
    user_id: userId,
    streak_count: nextStreak,
    last_learning_date: today
  });
  if (error) throw error;

  return { user_id: userId, streak_count: nextStreak, last_learning_date: today };
}

export async function updateDisplayName(userId: string, displayName: string) {
  const { error } = await supabase
    .from('profiles')
    .update({ display_name: displayName.trim() })
    .eq('id', userId);

  if (error) throw error;
}

export async function updatePronunciationScore(rowId: string, score: number) {
  const { error } = await supabase
    .from('user_vocabulary')
    .update({ pronunciation_score: score })
    .eq('id', rowId);

  if (error) throw error;
}

export async function markNotificationAsRead(notificationId: string) {
  const { error } = await supabase
    .from('notifications')
    .update({ is_read: true })
    .eq('id', notificationId);

  if (error) throw error;
}

export function computeStats(
  vocabs: UserVocabulary[],
  privateTopics: Topic[],
  wordSubmissions: UserVocabSubmission[],
  topicSubmissions: UserTopicSubmission[]
): UserDashboardStats {
  const uniqueWords = new Set(
    vocabs
      .map((row) => row.vocab_catalog?.word?.trim().toLowerCase())
      .filter((word): word is string => Boolean(word))
  );
  const now = Date.now();
  const dueWords = vocabs.filter((row) => {
    const level = row.learning_level ?? 0;
    if (level <= 0) return false;
    if (!row.next_review) return true;
    return new Date(row.next_review).getTime() <= now;
  }).length;
  const pendingRequests =
    wordSubmissions.filter((item) => item.status === 'pending').length +
    topicSubmissions.filter((item) => item.status === 'pending').length;
  const rejectedRequests =
    wordSubmissions.filter((item) => item.status === 'rejected').length +
    topicSubmissions.filter((item) => item.status === 'rejected').length;

  return {
    savedWords: vocabs.length,
    uniqueWords: uniqueWords.size,
    learningWords: vocabs.filter((row) => (row.learning_level ?? 0) > 0).length,
    dueWords,
    masteredWords: vocabs.filter((row) => (row.learning_level ?? 0) >= 6).length,
    privateTopics: privateTopics.length,
    pendingRequests,
    rejectedRequests
  };
}

export function isDue(row: UserVocabulary) {
  if ((row.learning_level ?? 0) <= 0) return false;
  if (!row.next_review) return true;
  return new Date(row.next_review).getTime() <= Date.now();
}

export function nextReviewDateForLevel(level: number) {
  const delayByLevel: Record<number, number> = {
    1: 0,
    2: 1,
    3: 3,
    4: 7,
    5: 15,
    6: 30,
    7: 60,
    8: 120,
    9: 240
  };
  const delayDays = level >= 10 ? 365 : delayByLevel[level] ?? 365;
  const date = new Date();
  date.setDate(date.getDate() + delayDays);
  return date.toISOString();
}
