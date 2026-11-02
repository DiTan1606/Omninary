import { requireVocabularyContent, normalizeSupplementaryText } from './vocabularyContent';
import { User } from '@supabase/supabase-js';
import { supabase } from './supabase';
import { catalogTopics } from './vocabularyCollections';
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
e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,collocation,formula,note,bonus,
topics!vocab_catalog_topic_id_fkey(id,name),topic_vocab(topics(id,name,visibility,owner_id))
`;

const wordSubmissionSelect = `
id,requester_id,catalog_id,topic_id,status,created_at,admin_note,
vocab_catalog(${catalogSelect})
`;

const topicSubmissionSelect = `
id,requester_id,topic_id,name,description,status,created_at,admin_note,
topic_submission_words(id,catalog_id,word,cefr,ipa,word_form,e_meaning,ev_meaning,v_meaning,e_example,v_example,word_family,synonymous,antonym,collocation,formula,note,bonus)
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
  requireVocabularyContent(input);
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
    word_family: normalizeSupplementaryText(input.word_family),
    synonymous: normalizeSupplementaryText(input.synonymous),
    antonym: normalizeSupplementaryText(input.antonym),
    collocation: normalizeSupplementaryText(input.collocation),
    formula: normalizeSupplementaryText(input.formula),
    note: normalizeSupplementaryText(input.note),
    bonus: normalizeSupplementaryText(input.bonus)
  };
}

function toCatalogUpdate(input: VocabInput) {
  requireVocabularyContent(input);
  return {
    word: clean(input.word) ?? 'Untitled',
    cefr: clean(input.cefr),
    ipa: clean(input.ipa),
    word_form: clean(input.word_form),
    e_meaning: clean(input.e_meaning),
    ev_meaning: clean(input.ev_meaning),
    v_meaning: clean(input.v_meaning),
    e_example: cleanExample(input.e_example),
    v_example: cleanExample(input.v_example),
    word_family: normalizeSupplementaryText(input.word_family),
    synonymous: normalizeSupplementaryText(input.synonymous),
    antonym: normalizeSupplementaryText(input.antonym),
    collocation: normalizeSupplementaryText(input.collocation),
    formula: normalizeSupplementaryText(input.formula),
    note: normalizeSupplementaryText(input.note),
    bonus: normalizeSupplementaryText(input.bonus)
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
    collocation: '',
    formula: '',
    note: '',
    bonus: ''
  };
}

export function catalogToInput(vocab: VocabCatalog): VocabInput {
  return {
    id: vocab.id,
    topic_id: vocab.topic_id,
    topic_ids: catalogTopics(vocab).filter((topic) => topic.visibility !== 'private').map((topic) => topic.id),
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
    collocation: vocab.collocation ?? '',
    formula: vocab.formula ?? '',
    note: vocab.note ?? '',
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
  const { data, error } = await supabase.from('topics').select('id,name,visibility,owner_id').eq('visibility', 'system').order('name');
  if (error) throw error;
  return (data ?? []) as Topic[];
}

export async function createTopic(name: string) {
  const topic = { id: crypto.randomUUID(), name: name.trim(), visibility: 'system' };
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


  if (options.search?.trim()) query = query.ilike('word', `%${options.search.trim()}%`);

  const { data, error } = await query;
  if (error) throw error;
  const rows = (data ?? []) as unknown as VocabCatalog[];
  return rows.filter((row) => options.uncategorized ? catalogTopics(row).filter((topic) => topic.visibility === 'system').length === 0 :
    !options.topicId || catalogTopics(row).some((topic) => topic.id === options.topicId));
}

export async function fetchAllSystemVocabsForTopic(topicId: string) {
  return fetchSystemVocabs({ topicId });
}

async function setCatalogTopics(id: string, input: VocabInput) {
  const { error } = await supabase.rpc('set_catalog_topics', {
    p_vocab_id: id, p_topic_ids: input.topic_ids ?? (input.topic_id ? [input.topic_id] : [])
  });
  if (error) throw error;
}

export async function createSystemVocab(input: VocabInput, adminId: string) {
  const { data, error } = await supabase.rpc('create_vocabulary_meaning', {
    p_vocab: toCatalogInsert(input, adminId), p_topic_id: input.topic_id, p_as_system: true
  });
  if (error) throw error;
  await setCatalogTopics(data as string, input);
}

export async function updateSystemVocab(input: VocabInput) {
  if (!input.id) throw new Error('Thiếu ID từ vựng.');
  const { error } = await supabase.from('vocab_catalog').update(toCatalogUpdate(input)).eq('id', input.id);
  if (error) throw error;
  await setCatalogTopics(input.id, input);
}

export async function deleteSystemVocab(id: string) {
  const { error } = await supabase.from('vocab_catalog').delete().eq('id', id);
  if (error) throw error;
}

export async function importSystemVocabs(rows: VocabInput[], adminId: string) {
  for (const row of rows) await createSystemVocab(row, adminId);
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
      admin_note: normalizeSupplementaryText(note)
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
    .eq('visibility', 'system')
    .limit(1);

  if (fetchError) throw fetchError;
  if (existing?.[0]) return existing[0] as Topic;
  return createTopic(trimmed);
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
      admin_note: normalizeSupplementaryText(note)
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
  const newRows: ReturnType<typeof toCatalogInsert>[] = [];
  const approvedCatalogIds: string[] = [];

  approvedWords.forEach((word) => {
    if (word.catalog_id) {
      approvedCatalogIds.push(word.catalog_id);
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
      word_family: normalizeSupplementaryText(word.word_family),
      synonymous: normalizeSupplementaryText(word.synonymous),
      antonym: normalizeSupplementaryText(word.antonym),
      collocation: normalizeSupplementaryText(word.collocation),
      formula: normalizeSupplementaryText(word.formula),
      note: normalizeSupplementaryText(word.note),
      bonus: normalizeSupplementaryText(word.bonus)
    });
  });

  for (const word of approvedWords) {
    if (!word.catalog_id) continue;
    const { error } = await supabase.from('vocab_catalog').update({ visibility: 'system' }).eq('id', word.catalog_id);
    if (error) throw error;
  }

  if (newRows.length > 0) {
    const { error } = await supabase.from('vocab_catalog').insert(newRows);
    if (error) throw error;
  }

  if (approvedCatalogIds.length > 0) {
    const links = approvedCatalogIds.map((catalogId) => ({
      id: crypto.randomUUID(),
      user_id: submission.requester_id,
      vocab_id: catalogId,
      learning_level: null,
      next_review: null,
      pronunciation_score: null
    }));

    const { error } = await supabase.from('user_vocabulary').upsert(links, { onConflict: 'user_id,vocab_id', ignoreDuplicates: true });
    if (error) throw error;
  }

  const { error: membershipError } = await supabase.rpc('attach_reviewed_topic_meanings', { p_topic_id: topic.id, p_vocab_ids: approvedCatalogIds, p_user_id: submission.requester_id });
  if (membershipError) throw membershipError;

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
