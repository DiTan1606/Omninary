import { User } from '@supabase/supabase-js';
import { supabase } from './supabase';
import {
  DashboardStats,
  Profile,
  ReviewStatus,
  Topic,
  TopicSubmission,
  TopicSubmissionWord,
  VocabCatalog,
  VocabInput,
  VocabSubmission
} from './types';

const catalogSelect = `
id,created_at,topic_id,created_by,visibility,word,cefr,ipa,word_form,
e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,bonus,
topics(id,name)
`;

const wordSubmissionSelect = `
id,requester_id,catalog_id,topic_id,status,created_at,admin_note,
vocab_catalog(${catalogSelect})
`;

const topicSubmissionSelect = `
id,requester_id,topic_id,name,description,status,created_at,admin_note,
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

function toCatalogInsert(input: VocabInput, userId: string, visibility = 'system') {
  return {
    id: input.id ?? crypto.randomUUID(),
    topic_id: input.topic_id,
    created_by: userId,
    visibility,
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

export async function requireAdmin(user: User | null) {
  if (!user) return null;
  const profile = await getProfile(user.id);
  if (profile?.role !== 'admin') {
    await supabase.auth.signOut();
    throw new Error('Tài khoản này không có quyền admin.');
  }
  return profile;
}

async function countRows(table: string, apply?: (query: any) => any) {
  let query = supabase.from(table).select('*', { head: true, count: 'exact' });
  if (apply) query = apply(query);
  const { count, error } = await query;
  if (error) throw error;
  return count ?? 0;
}

export async function fetchDashboardStats(): Promise<DashboardStats> {
  const [users, topics, systemVocabs, pendingWords, pendingTopics] = await Promise.all([
    countRows('profiles'),
    countRows('topics'),
    countRows('vocab_catalog', (q) => q.eq('visibility', 'system')),
    countRows('vocab_submissions', (q) => q.eq('status', 'pending')),
    countRows('topic_submissions', (q) => q.eq('status', 'pending'))
  ]);

  return { users, topics, systemVocabs, pendingWords, pendingTopics };
}

export async function fetchProfiles() {
  const { data, error } = await supabase
    .from('profiles')
    .select('id,email,display_name,avatar_url,role,created_at')
    .order('created_at', { ascending: false });

  if (error) throw error;
  return (data ?? []) as Profile[];
}

export async function updateProfile(profile: Profile) {
  const { error } = await supabase
    .from('profiles')
    .update({
      display_name: profile.display_name ?? '',
      role: profile.role ?? 'user'
    })
    .eq('id', profile.id);

  if (error) throw error;
}

export async function fetchTopics() {
  const { data, error } = await supabase.from('topics').select('id,name').order('name');
  if (error) throw error;
  return (data ?? []) as Topic[];
}

export async function createTopic(name: string) {
  const topic = { id: crypto.randomUUID(), name: name.trim() };
  const { data, error } = await supabase.from('topics').insert(topic).select('id,name').single<Topic>();
  if (error) throw error;
  return data;
}

export async function updateTopic(topic: Topic) {
  const { error } = await supabase.from('topics').update({ name: topic.name.trim() }).eq('id', topic.id);
  if (error) throw error;
}

export async function deleteTopic(topicId: string) {
  const { error } = await supabase.from('topics').delete().eq('id', topicId);
  if (error) throw error;
}

export async function fetchSystemVocabs(options: { topicId?: string; search?: string; uncategorized?: boolean } = {}) {
  let query = supabase
    .from('vocab_catalog')
    .select(catalogSelect)
    .eq('visibility', 'system')
    .order('created_at', { ascending: false });

  if (options.uncategorized) query = query.is('topic_id', null);
  else if (options.topicId) query = query.eq('topic_id', options.topicId);
  if (options.search?.trim()) query = query.ilike('word', `%${options.search.trim()}%`);

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as unknown as VocabCatalog[];
}

export async function fetchAllSystemVocabsForTopic(topicId: string) {
  const { data, error } = await supabase
    .from('vocab_catalog')
    .select(catalogSelect)
    .eq('visibility', 'system')
    .eq('topic_id', topicId)
    .order('word');

  if (error) throw error;
  return (data ?? []) as unknown as VocabCatalog[];
}

export async function createSystemVocab(input: VocabInput, adminId: string) {
  const { error } = await supabase.from('vocab_catalog').insert(toCatalogInsert(input, adminId));
  if (error) throw error;
}

export async function updateSystemVocab(input: VocabInput) {
  if (!input.id) throw new Error('Thiếu ID từ vựng.');
  const { error } = await supabase.from('vocab_catalog').update(toCatalogUpdate(input)).eq('id', input.id);
  if (error) throw error;
}

export async function deleteSystemVocab(id: string) {
  const { error } = await supabase.from('vocab_catalog').delete().eq('id', id);
  if (error) throw error;
}

export async function importSystemVocabs(rows: VocabInput[], adminId: string) {
  const payload = rows.map((row) => toCatalogInsert(row, adminId));
  const { error } = await supabase.from('vocab_catalog').insert(payload);
  if (error) throw error;
}

export async function fetchPendingVocabSubmissions() {
  const { data, error } = await supabase
    .from('vocab_submissions')
    .select(wordSubmissionSelect)
    .eq('status', 'pending')
    .order('created_at', { ascending: true });

  if (error) throw error;
  return (data ?? []) as unknown as VocabSubmission[];
}

export async function fetchPendingTopicSubmissions() {
  const { data, error } = await supabase
    .from('topic_submissions')
    .select(topicSubmissionSelect)
    .eq('status', 'pending')
    .order('created_at', { ascending: true });

  if (error) throw error;
  return (data ?? []) as TopicSubmission[];
}

export async function sendNotification(userId: string, title: string, content: string) {
  const { error } = await supabase.from('notifications').insert({
    id: crypto.randomUUID(),
    user_id: userId,
    title,
    content,
    is_read: false
  });

  if (error) throw error;
}

export async function markVocabSubmission(
  id: string,
  status: ReviewStatus,
  reviewerId: string,
  note?: string
) {
  const { error } = await supabase
    .from('vocab_submissions')
    .update({
      status,
      reviewed_by: reviewerId,
      reviewed_at: nowIso(),
      admin_note: clean(note)
    })
    .eq('id', id);

  if (error) throw error;
}

export async function approveVocabSubmission(submission: VocabSubmission, adminId: string) {
  if (!submission.catalog_id) throw new Error('Submission thiếu catalog_id.');

  const { error: catalogError } = await supabase
    .from('vocab_catalog')
    .update({ visibility: 'system' })
    .eq('id', submission.catalog_id);

  if (catalogError) throw catalogError;

  await markVocabSubmission(submission.id, 'approved', adminId);
  await sendNotification(
    submission.requester_id,
    'Từ đã được duyệt',
    `"${submission.vocab_catalog?.word ?? 'Từ vựng'}" đã được bổ sung vào bộ từ hệ thống.`
  );
}

export async function rejectVocabSubmission(submission: VocabSubmission, adminId: string, note: string) {
  await markVocabSubmission(submission.id, 'rejected', adminId, note);
  await sendNotification(
    submission.requester_id,
    'Từ chưa được duyệt',
    note.trim()
      ? `"${submission.vocab_catalog?.word ?? 'Từ vựng'}" chưa được duyệt: ${note.trim()}`
      : `"${submission.vocab_catalog?.word ?? 'Từ vựng'}" chưa được duyệt. Bạn có thể chỉnh lại rồi gửi duyệt lại.`
  );
}

async function getOrCreateTopic(name: string) {
  const trimmed = name.trim();
  const { data: existing, error: fetchError } = await supabase
    .from('topics')
    .select('id,name')
    .eq('name', trimmed)
    .limit(1);

  if (fetchError) throw fetchError;
  if (existing?.[0]) return existing[0] as Topic;
  return createTopic(trimmed);
}

function draftKey(word: TopicSubmissionWord) {
  return [word.word, word.e_meaning, word.ev_meaning, word.v_meaning]
    .map((value) => clean(value)?.toLowerCase() ?? '')
    .join('|');
}

function catalogKey(word: VocabCatalog) {
  return [word.word, word.e_meaning, word.ev_meaning, word.v_meaning]
    .map((value) => clean(value)?.toLowerCase() ?? '')
    .join('|');
}

async function fetchReusableCatalogRows(topicId: string, requesterId: string) {
  const { data, error } = await supabase
    .from('vocab_catalog')
    .select(catalogSelect)
    .eq('topic_id', topicId)
    .eq('created_by', requesterId)
    .eq('visibility', 'system');

  if (error) throw error;
  return (data ?? []) as unknown as VocabCatalog[];
}

export async function markTopicSubmission(
  id: string,
  status: ReviewStatus,
  reviewerId: string,
  note?: string
) {
  const { error } = await supabase
    .from('topic_submissions')
    .update({
      status,
      reviewed_by: reviewerId,
      reviewed_at: nowIso(),
      admin_note: clean(note)
    })
    .eq('id', id);

  if (error) throw error;
}

export async function approveTopicSubmission(
  submission: TopicSubmission,
  approvedWordIds: Set<string>,
  adminId: string
) {
  if (submission.topic_id) {
    const approvedWords = (submission.topic_submission_words ?? [])
      .filter((word) => approvedWordIds.has(word.id));
    const approvedCatalogIds = approvedWords
      .map((word) => word.catalog_id)
      .filter((id): id is string => Boolean(id));

    const { error: topicError } = await supabase
      .from('topics')
      .update({ visibility: 'system' })
      .eq('id', submission.topic_id);

    if (topicError) throw topicError;

    for (const catalogId of approvedCatalogIds) {
      const { error } = await supabase
        .from('vocab_catalog')
        .update({ visibility: 'system' })
        .eq('id', catalogId);

      if (error) throw error;
    }

    await markTopicSubmission(submission.id, 'approved', adminId);
    await sendNotification(
      submission.requester_id,
      'Topic đã được duyệt',
      `"${submission.name}" đã được đưa lên hệ thống với ${approvedCatalogIds.length} từ.`
    );
    return;
  }

  const topic = await getOrCreateTopic(submission.name);
  const approvedWords = (submission.topic_submission_words ?? []).filter((word) => approvedWordIds.has(word.id));
  const reusable = await fetchReusableCatalogRows(topic.id, submission.requester_id);
  const reusableByKey = new Map<string, VocabCatalog[]>();

  reusable.forEach((row) => {
    const key = catalogKey(row);
    reusableByKey.set(key, [...(reusableByKey.get(key) ?? []), row]);
  });

  const newRows: ReturnType<typeof toCatalogInsert>[] = [];
  const approvedCatalogIds: string[] = [];

  approvedWords.forEach((word) => {
    const key = draftKey(word);
    const reusableRows = reusableByKey.get(key) ?? [];
    const existing = reusableRows.pop();
    reusableByKey.set(key, reusableRows);

    if (existing) {
      approvedCatalogIds.push(existing.id);
      return;
    }

    const id = crypto.randomUUID();
    approvedCatalogIds.push(id);
    newRows.push({
      id,
      topic_id: topic.id,
      created_by: submission.requester_id,
      visibility: 'system',
      word: clean(word.word) ?? 'Untitled',
      cefr: clean(word.cefr),
      ipa: clean(word.ipa),
      word_form: clean(word.word_form),
      e_meaning: clean(word.e_meaning),
      ev_meaning: clean(word.ev_meaning),
      v_meaning: clean(word.v_meaning),
      e_example: cleanExample(word.e_example),
      v_example: cleanExample(word.v_example),
      word_family: clean(word.word_family),
      synonymous: clean(word.synonymous),
      antonym: clean(word.antonym),
      bonus: clean(word.bonus)
    });
  });

  if (newRows.length > 0) {
    const { error } = await supabase.from('vocab_catalog').insert(newRows);
    if (error) throw error;
  }

  if (approvedCatalogIds.length > 0) {
    const links = approvedCatalogIds.map((catalogId) => ({
      id: crypto.randomUUID(),
      user_id: submission.requester_id,
      vocab_id: catalogId,
      learning_level: 0,
      next_review: null,
      pronunciation_score: null
    }));

    const { error } = await supabase.from('user_vocabulary').insert(links);
    if (error) throw error;
  }

  await markTopicSubmission(submission.id, 'approved', adminId);
  await sendNotification(
    submission.requester_id,
    'Topic nháp đã được duyệt',
    `"${submission.name}" đã được duyệt với ${approvedCatalogIds.length} từ và tự động thêm vào kho từ của bạn.`
  );
}

export async function rejectTopicSubmission(submission: TopicSubmission, adminId: string, note: string) {
  await markTopicSubmission(submission.id, 'rejected', adminId, note);
  await sendNotification(
    submission.requester_id,
    'Topic nháp chưa được duyệt',
    note.trim()
      ? `"${submission.name}" chưa được duyệt: ${note.trim()}`
      : `"${submission.name}" chưa được duyệt. Bạn có thể chỉnh lại rồi gửi duyệt lại.`
  );
}
