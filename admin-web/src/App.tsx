import {
  Archive,
  BookOpen,
  Check,
  CircleAlert,
  Download,
  FileSpreadsheet,
  Inbox,
  Loader2,
  LogOut,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Trash2,
  Upload,
  Users,
  X
} from 'lucide-react';
import { FormEvent, ReactNode, useEffect, useMemo, useState } from 'react';
import AuthScreen from './components/AuthScreen';
import * as api from './lib/adminApi';
import { supabase } from './lib/supabase';
import {
  DashboardStats,
  ImportRow,
  Profile,
  Topic,
  TopicSubmission,
  TopicSubmissionWord,
  VocabCatalog,
  VocabInput,
  VocabSubmission
} from './lib/types';
import { exportVocabularyWorkbook, parseVocabularyWorkbook } from './lib/excel';

type ViewKey = 'dashboard' | 'topics' | 'vocabulary' | 'excel' | 'requests' | 'users';
const UNCATEGORIZED_TOPIC_FILTER = '__uncategorized__';

const navItems: Array<{ key: ViewKey; label: string; icon: ReactNode }> = [
  { key: 'dashboard', label: 'Tổng quan', icon: <Archive size={18} /> },
  { key: 'topics', label: 'Topic', icon: <BookOpen size={18} /> },
  { key: 'vocabulary', label: 'Vocabulary', icon: <Search size={18} /> },
  { key: 'excel', label: 'Import / Export', icon: <FileSpreadsheet size={18} /> },
  { key: 'requests', label: 'Duyệt đóng góp', icon: <Inbox size={18} /> },
  { key: 'users', label: 'Người dùng', icon: <Users size={18} /> }
];

function BrandLogo({ compact = false }: { compact?: boolean }) {
  return (
    <div className={compact ? 'brand compact-brand' : 'brand'}>
      <img className="brand-logo" src="/ditanary-logo.png" alt="Ditandnary thuộc Omninary" />
    </div>
  );
}

function formatDate(value: string | null | undefined) {
  if (!value) return 'Chưa có';
  return new Intl.DateTimeFormat('vi-VN', {
    dateStyle: 'medium',
    timeStyle: 'short'
  }).format(new Date(value));
}

function profileLabel(profile?: Profile) {
  if (!profile) return 'Không rõ';
  return profile.display_name || profile.email || profile.id.slice(0, 8);
}

function profileDisplayName(profile?: Profile) {
  if (!profile) return 'Không rõ';
  return profile.display_name || profile.email || 'Không rõ';
}

function fieldValue(value: string | null | undefined) {
  return value?.trim() || 'Chưa có';
}

type VocabSubmissionTopicGroup = {
  key: string;
  topicName: string;
  submissions: VocabSubmission[];
};

type VocabSubmissionUserGroup = {
  requesterId: string;
  profile?: Profile;
  total: number;
  topics: VocabSubmissionTopicGroup[];
};

type TopicSubmissionTopicGroup = {
  key: string;
  topicName: string;
  submissions: TopicSubmission[];
};

type TopicSubmissionUserGroup = {
  requesterId: string;
  profile?: Profile;
  totalTopics: number;
  totalWords: number;
  topics: TopicSubmissionTopicGroup[];
};

function sortByName<T extends { topicName: string }>(items: T[]) {
  return items.sort((a, b) => a.topicName.localeCompare(b.topicName, 'vi'));
}

function groupVocabSubmissions(
  submissions: VocabSubmission[],
  profiles: Record<string, Profile>
): VocabSubmissionUserGroup[] {
  const userMap = new Map<string, Map<string, VocabSubmissionTopicGroup>>();

  submissions.forEach((submission) => {
    const requesterId = submission.requester_id;
    const topicKey = submission.vocab_catalog?.topic_id ?? submission.topic_id ?? UNCATEGORIZED_TOPIC_FILTER;
    const topicName = submission.vocab_catalog?.topics?.name ?? 'Chưa phân loại';

    if (!userMap.has(requesterId)) userMap.set(requesterId, new Map());
    const topicMap = userMap.get(requesterId);
    if (!topicMap) return;
    if (!topicMap.has(topicKey)) {
      topicMap.set(topicKey, { key: topicKey, topicName, submissions: [] });
    }
    topicMap.get(topicKey)?.submissions.push(submission);
  });

  return Array.from(userMap.entries())
    .map(([requesterId, topicMap]) => {
      const topics = sortByName(Array.from(topicMap.values()));
      return {
        requesterId,
        profile: profiles[requesterId],
        total: topics.reduce((sum, topic) => sum + topic.submissions.length, 0),
        topics
      };
    })
    .sort((a, b) => profileLabel(a.profile).localeCompare(profileLabel(b.profile), 'vi'));
}

function groupTopicSubmissions(
  submissions: TopicSubmission[],
  profiles: Record<string, Profile>
): TopicSubmissionUserGroup[] {
  const userMap = new Map<string, Map<string, TopicSubmissionTopicGroup>>();

  submissions.forEach((submission) => {
    const requesterId = submission.requester_id;
    const topicName = submission.name.trim() || 'Topic chưa đặt tên';
    const topicKey = submission.topic_id ?? topicName.toLocaleLowerCase('vi');

    if (!userMap.has(requesterId)) userMap.set(requesterId, new Map());
    const topicMap = userMap.get(requesterId);
    if (!topicMap) return;
    if (!topicMap.has(topicKey)) {
      topicMap.set(topicKey, { key: topicKey, topicName, submissions: [] });
    }
    topicMap.get(topicKey)?.submissions.push(submission);
  });

  return Array.from(userMap.entries())
    .map(([requesterId, topicMap]) => {
      const topics = sortByName(Array.from(topicMap.values()));
      return {
        requesterId,
        profile: profiles[requesterId],
        totalTopics: topics.reduce((sum, topic) => sum + topic.submissions.length, 0),
        totalWords: topics.reduce(
          (sum, topic) =>
            sum +
            topic.submissions.reduce(
              (wordSum, submission) => wordSum + (submission.topic_submission_words?.length ?? 0),
              0
            ),
          0
        ),
        topics
      };
    })
    .sort((a, b) => profileLabel(a.profile).localeCompare(profileLabel(b.profile), 'vi'));
}

function App() {
  const [activeView, setActiveView] = useState<ViewKey>('dashboard');
  const [profile, setProfile] = useState<Profile | null>(null);
  const [isBooting, setIsBooting] = useState(true);
  const [authError, setAuthError] = useState('');

  useEffect(() => {
    let mounted = true;

    async function boot() {
      try {
        const user = await api.getCurrentUser();
        if (!user) {
          if (mounted) setProfile(null);
          return;
        }
        const nextProfile = await api.getProfile(user.id);
        if (nextProfile?.role === 'admin') {
          if (mounted) setProfile(nextProfile);
          return;
        }
        if (nextProfile) window.location.replace('/app');
      } catch (error) {
        if (mounted) setAuthError(error instanceof Error ? error.message : 'Không thể đăng nhập.');
      } finally {
        if (mounted) setIsBooting(false);
      }
    }

    boot();

    const { data } = supabase.auth.onAuthStateChange(async (_event, session) => {
      if (!session?.user) {
        setProfile(null);
        setIsBooting(false);
        return;
      }
      const nextProfile = await api.getProfile(session.user.id);
      if (nextProfile?.role === 'admin') {
        setProfile(nextProfile);
      } else if (nextProfile) {
        window.location.replace('/app');
      }
    });

    return () => {
      mounted = false;
      data.subscription.unsubscribe();
    };
  }, []);

  async function handleLoginSuccess(adminProfile: Profile) {
    setAuthError('');
    if (adminProfile.role === 'admin') setProfile(adminProfile);
    else window.location.replace('/app');
  }

  async function signOut() {
    await supabase.auth.signOut();
    setProfile(null);
  }

  if (isBooting) {
    return (
      <div className="boot-screen">
        <Loader2 className="spin" size={28} />
        <span>Đang mở Omninary Admin</span>
      </div>
    );
  }

  if (!profile) {
    return <AuthScreen authError={authError} onAuthenticated={handleLoginSuccess} />;
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="sidebar-head">
          <BrandLogo compact />
        </div>

        <nav className="nav-list">
          {navItems.map((item) => (
            <button
              key={item.key}
              className={activeView === item.key ? 'nav-item active' : 'nav-item'}
              onClick={() => setActiveView(item.key)}
              title={item.label}
            >
              {item.icon}
              <span>{item.label}</span>
            </button>
          ))}
        </nav>
      </aside>

      <main className="main-panel">
        <header className="topbar">
          <div>
            <p className="eyebrow">Quản trị hệ thống</p>
            <h1>{navItems.find((item) => item.key === activeView)?.label}</h1>
          </div>
          <div className="topbar-actions">
            <div className="admin-pill">
              <span>{profileLabel(profile)}</span>
              <small>{profile.role}</small>
            </div>
            <button className="icon-button" onClick={signOut} title="Đăng xuất">
              <LogOut size={18} />
            </button>
          </div>
        </header>

        <section className="content-area">
          {activeView === 'dashboard' && <DashboardView />}
          {activeView === 'topics' && <TopicsView />}
          {activeView === 'vocabulary' && <VocabularyView adminProfile={profile} />}
          {activeView === 'excel' && <ImportExportView adminProfile={profile} />}
          {activeView === 'requests' && <RequestsView adminProfile={profile} />}
          {activeView === 'users' && <UsersView />}
        </section>
      </main>
    </div>
  );
}

function DashboardView() {
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(true);

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      setStats(await api.fetchDashboardStats());
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được dữ liệu.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  if (isLoading) return <LoadingBlock label="Đang tải số liệu" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  const cards = [
    { label: 'Người dùng', value: stats?.users ?? 0, tone: 'green' },
    { label: 'Topic hệ thống', value: stats?.topics ?? 0, tone: 'blue' },
    { label: 'Từ hệ thống', value: stats?.systemVocabs ?? 0, tone: 'violet' },
    { label: 'Từ chờ duyệt', value: stats?.pendingWords ?? 0, tone: 'amber' },
    { label: 'Topic chờ duyệt', value: stats?.pendingTopics ?? 0, tone: 'red' }
  ];

  return (
    <div className="stack">
      <div className="stats-grid">
        {cards.map((card) => (
          <article className={`stat-card ${card.tone}`} key={card.label}>
            <span>{card.label}</span>
            <strong>{card.value.toLocaleString('vi-VN')}</strong>
          </article>
        ))}
      </div>

      <div className="section-band">
        <div>
          <h2>Ưu tiên vận hành</h2>
          <p>Duyệt đóng góp, chuẩn hóa topic, import dữ liệu mới và kiểm tra chất lượng từ hệ thống.</p>
        </div>
        <button className="ghost-button" onClick={load}>
          <RefreshCw size={18} />
          Làm mới
        </button>
      </div>
    </div>
  );
}

function TopicsView() {
  const [topics, setTopics] = useState<Topic[]>([]);
  const [vocabs, setVocabs] = useState<VocabCatalog[]>([]);
  const [newName, setNewName] = useState('');
  const [editingTopic, setEditingTopic] = useState<Topic | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  const counts = useMemo(() => {
    return vocabs.reduce<Record<string, number>>((result, vocab) => {
      if (vocab.topic_id) result[vocab.topic_id] = (result[vocab.topic_id] ?? 0) + 1;
      return result;
    }, {});
  }, [vocabs]);

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      const [topicRows, vocabRows] = await Promise.all([api.fetchTopics(), api.fetchSystemVocabs()]);
      setTopics(topicRows);
      setVocabs(vocabRows);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được topic.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function saveNewTopic() {
    if (!newName.trim()) return;
    await api.createTopic(newName);
    setNewName('');
    await load();
  }

  async function saveTopic() {
    if (!editingTopic) return;
    await api.updateTopic(editingTopic);
    setEditingTopic(null);
    await load();
  }

  async function removeTopic(topic: Topic) {
    if (!confirm(`Xóa topic "${topic.name}"?`)) return;
    await api.deleteTopic(topic.id);
    await load();
  }

  if (isLoading) return <LoadingBlock label="Đang tải topic" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  return (
    <div className="stack">
      <div className="toolbar-row">
        <input placeholder="Tên topic mới" value={newName} onChange={(event) => setNewName(event.target.value)} />
        <button className="primary-button" onClick={saveNewTopic} disabled={!newName.trim()}>
          <Plus size={18} />
          Tạo topic
        </button>
      </div>

      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Topic</th>
              <th>Số từ system</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {topics.map((topic) => (
              <tr key={topic.id}>
                <td>
                  {editingTopic?.id === topic.id ? (
                    <input
                      value={editingTopic.name}
                      onChange={(event) => setEditingTopic({ ...editingTopic, name: event.target.value })}
                    />
                  ) : (
                    <strong>{topic.name}</strong>
                  )}
                </td>
                <td>{counts[topic.id] ?? 0}</td>
                <td className="action-cell">
                  <div className="row-action-buttons">
                    {editingTopic?.id === topic.id ? (
                      <>
                        <button className="icon-button success" onClick={saveTopic} title="Lưu">
                          <Check size={17} />
                        </button>
                        <button className="icon-button" onClick={() => setEditingTopic(null)} title="Hủy">
                          <X size={17} />
                        </button>
                      </>
                    ) : (
                      <>
                        <button className="icon-button" onClick={() => setEditingTopic(topic)} title="Sửa">
                          <Pencil size={17} />
                        </button>
                        <button className="icon-button danger" onClick={() => removeTopic(topic)} title="Xóa">
                          <Trash2 size={17} />
                        </button>
                      </>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function VocabularyView({ adminProfile }: { adminProfile: Profile }) {
  const [topics, setTopics] = useState<Topic[]>([]);
  const [vocabs, setVocabs] = useState<VocabCatalog[]>([]);
  const [profilesById, setProfilesById] = useState<Record<string, Profile>>({});
  const [topicId, setTopicId] = useState('');
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState<VocabInput | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      const isUncategorized = topicId === UNCATEGORIZED_TOPIC_FILTER;
      const [topicRows, vocabRows, profileRows] = await Promise.all([
        api.fetchTopics(),
        api.fetchSystemVocabs({
          topicId: isUncategorized ? undefined : topicId || undefined,
          uncategorized: isUncategorized,
          search
        }),
        api.fetchProfiles()
      ]);
      setTopics(topicRows);
      setVocabs(vocabRows);
      setProfilesById(Object.fromEntries(profileRows.map((profile) => [profile.id, profile])));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được từ vựng.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function saveVocab(input: VocabInput) {
    if (input.id) {
      await api.updateSystemVocab(input);
    } else {
      await api.createSystemVocab(input, adminProfile.id);
    }
    setEditing(null);
    await load();
  }

  async function removeVocab(vocab: VocabCatalog) {
    if (!confirm(`Xóa "${vocab.word}" khỏi hệ thống?`)) return;
    await api.deleteSystemVocab(vocab.id);
    await load();
  }

  const addTopicId = topicId === UNCATEGORIZED_TOPIC_FILTER ? null : topicId || null;

  return (
    <div className="stack">
      <div className="toolbar-row">
        <select value={topicId} onChange={(event) => setTopicId(event.target.value)}>
          <option value="">Tất cả topic</option>
          <option value={UNCATEGORIZED_TOPIC_FILTER}>Chưa phân loại</option>
          {topics.map((topic) => (
            <option key={topic.id} value={topic.id}>
              {topic.name}
            </option>
          ))}
        </select>
        <div className="search-box">
          <Search size={18} />
          <input placeholder="Tìm từ..." value={search} onChange={(event) => setSearch(event.target.value)} />
        </div>
        <button className="ghost-button" onClick={load}>
          <RefreshCw size={18} />
          Lọc
        </button>
        <button className="primary-button" onClick={() => setEditing(api.emptyVocabInput(addTopicId))}>
          <Plus size={18} />
          Thêm từ
        </button>
      </div>

      {isLoading ? (
        <LoadingBlock label="Đang tải từ vựng" />
      ) : error ? (
        <ErrorBlock message={error} onRetry={load} />
      ) : (
        <VocabularyTable
          vocabs={vocabs}
          profilesById={profilesById}
          onEdit={(vocab) => setEditing(api.catalogToInput(vocab))}
          onDelete={removeVocab}
        />
      )}

      {editing && (
        <VocabEditorModal
          title={editing.id ? 'Sửa từ hệ thống' : 'Thêm từ hệ thống'}
          topics={topics}
          value={editing}
          onClose={() => setEditing(null)}
          onSave={saveVocab}
        />
      )}
    </div>
  );
}

function ImportExportView({ adminProfile }: { adminProfile: Profile }) {
  const [topics, setTopics] = useState<Topic[]>([]);
  const [importTopicId, setImportTopicId] = useState('');
  const [exportTopicId, setExportTopicId] = useState('');
  const [newTopicName, setNewTopicName] = useState('');
  const [rows, setRows] = useState<ImportRow[]>([]);
  const [fileName, setFileName] = useState('');
  const [importMessage, setImportMessage] = useState('');
  const [exportMessage, setExportMessage] = useState('');
  const [isImporting, setIsImporting] = useState(false);
  const [isExporting, setIsExporting] = useState(false);

  const selectedExportTopic = topics.find((topic) => topic.id === exportTopicId);
  const validRows = rows.filter((row) => !row.error && row.word.trim());

  async function loadTopics() {
    setTopics(await api.fetchTopics());
  }

  useEffect(() => {
    loadTopics();
  }, []);

  async function handleFile(file: File | null) {
    if (!file || !importTopicId) return;
    setImportMessage('');
    setFileName(file.name);
    setRows(await parseVocabularyWorkbook(file, importTopicId));
  }

  async function createTopicForImport() {
    if (!newTopicName.trim()) return;
    const topic = await api.createTopic(newTopicName);
    setNewTopicName('');
    await loadTopics();
    setImportTopicId(topic.id);
  }

  async function importRows() {
    if (!validRows.length) return;
    setIsImporting(true);
    setImportMessage('');
    try {
      await api.importSystemVocabs(validRows, adminProfile.id);
      setImportMessage(`Đã import ${validRows.length} từ vào hệ thống.`);
      setRows([]);
      setFileName('');
    } catch (err) {
      setImportMessage(err instanceof Error ? err.message : 'Import thất bại.');
    } finally {
      setIsImporting(false);
    }
  }

  async function exportRows() {
    if (!selectedExportTopic) return;
    setIsExporting(true);
    setExportMessage('');
    try {
      const vocabs = await api.fetchAllSystemVocabsForTopic(selectedExportTopic.id);
      await exportVocabularyWorkbook(selectedExportTopic, vocabs);
      setExportMessage(`Đã export ${vocabs.length} từ của topic ${selectedExportTopic.name}.`);
    } catch (err) {
      setExportMessage(err instanceof Error ? err.message : 'Export thất bại.');
    } finally {
      setIsExporting(false);
    }
  }

  return (
    <div className="split-grid">
      <section className="panel">
        <h2>Import Excel</h2>
        <div className="form-grid">
          <label>
            Topic nhận dữ liệu
            <select value={importTopicId} onChange={(event) => setImportTopicId(event.target.value)}>
              <option value="">Chọn topic</option>
              {topics.map((topic) => (
                <option key={topic.id} value={topic.id}>
                  {topic.name}
                </option>
              ))}
            </select>
          </label>

          <div className="inline-fields">
            <input
              placeholder="Tạo topic mới"
              value={newTopicName}
              onChange={(event) => setNewTopicName(event.target.value)}
            />
            <button className="ghost-button" onClick={createTopicForImport} disabled={!newTopicName.trim()}>
              <Plus size={18} />
              Tạo
            </button>
          </div>

          <label className={importTopicId ? 'file-picker' : 'file-picker disabled'}>
            <Upload size={18} />
            <span>{fileName || 'Chọn file .xlsx'}</span>
            <input type="file" accept=".xlsx" disabled={!importTopicId} onChange={(event) => handleFile(event.target.files?.[0] ?? null)} />
          </label>
        </div>

        {rows.length > 0 && (
          <>
            <div className="import-summary">
              <span>{validRows.length} dòng hợp lệ</span>
              <span>{rows.length - validRows.length} dòng lỗi</span>
            </div>
            <div className="preview-list">
              {rows.slice(0, 12).map((row) => (
                <div className={row.error ? 'preview-row error' : 'preview-row'} key={`${row.rowNumber}-${row.word}`}>
                  <strong>{row.word || `Dòng ${row.rowNumber}`}</strong>
                  <span>{row.v_meaning || row.ev_meaning || row.e_meaning || row.error || '...'}</span>
                </div>
              ))}
            </div>
            <button className="primary-button" onClick={importRows} disabled={!validRows.length || isImporting}>
              {isImporting ? <Loader2 className="spin" size={18} /> : <Upload size={18} />}
              Import dữ liệu
            </button>
          </>
        )}

        {importMessage && <div className="notice">{importMessage}</div>}
      </section>

      <section className="panel">
        <h2>Export Excel</h2>
        <div className="form-grid">
          <label>
            Topic cần export
            <select value={exportTopicId} onChange={(event) => setExportTopicId(event.target.value)}>
              <option value="">Chọn topic</option>
              {topics.map((topic) => (
                <option key={topic.id} value={topic.id}>
                  {topic.name}
                </option>
              ))}
            </select>
          </label>
          <button className="primary-button" onClick={exportRows} disabled={!selectedExportTopic || isExporting}>
            {isExporting ? <Loader2 className="spin" size={18} /> : <Download size={18} />}
            Export file
          </button>
        </div>

        {exportMessage && <div className="notice">{exportMessage}</div>}
      </section>
    </div>
  );
}

function RequestsView({ adminProfile }: { adminProfile: Profile }) {
  const [vocabSubmissions, setVocabSubmissions] = useState<VocabSubmission[]>([]);
  const [topicSubmissions, setTopicSubmissions] = useState<TopicSubmission[]>([]);
  const [profiles, setProfiles] = useState<Record<string, Profile>>({});
  const [topicSelections, setTopicSelections] = useState<Record<string, string[]>>({});
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [isLoading, setIsLoading] = useState(true);
  const [message, setMessage] = useState('');
  const vocabGroups = useMemo(() => groupVocabSubmissions(vocabSubmissions, profiles), [vocabSubmissions, profiles]);
  const topicGroups = useMemo(() => groupTopicSubmissions(topicSubmissions, profiles), [topicSubmissions, profiles]);

  async function load() {
    setIsLoading(true);
    setMessage('');
    const [words, topics, profileRows] = await Promise.all([
      api.fetchPendingVocabSubmissions(),
      api.fetchPendingTopicSubmissions(),
      api.fetchProfiles()
    ]);

    setVocabSubmissions(words);
    setTopicSubmissions(topics);
    setProfiles(Object.fromEntries(profileRows.map((profile) => [profile.id, profile])));
    setTopicSelections(
      Object.fromEntries(
        topics.map((submission) => [
          submission.id,
          (submission.topic_submission_words ?? []).map((word) => word.id)
        ])
      )
    );
    setIsLoading(false);
  }

  useEffect(() => {
    load().catch((err) => {
      setMessage(err instanceof Error ? err.message : 'Không tải được request.');
      setIsLoading(false);
    });
  }, []);

  function toggleWord(submissionId: string, wordId: string) {
    setTopicSelections((current) => {
      const selected = new Set(current[submissionId] ?? []);
      if (selected.has(wordId)) selected.delete(wordId);
      else selected.add(wordId);
      return { ...current, [submissionId]: Array.from(selected) };
    });
  }

  async function runAction(action: () => Promise<void>) {
    setMessage('');
    try {
      await action();
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Thao tác thất bại.');
    }
  }

  function updateNote(id: string, value: string) {
    setNotes((current) => ({ ...current, [id]: value }));
  }

  if (isLoading) return <LoadingBlock label="Đang tải request" />;

  return (
    <div className="stack">
      {message && <div className="notice">{message}</div>}

      <section className="request-section">
        <div className="section-title">
          <h2>Từ riêng chờ duyệt</h2>
          <span>{vocabSubmissions.length}</span>
        </div>

        {vocabSubmissions.length === 0 ? (
          <EmptyState label="Không có từ riêng chờ duyệt." />
        ) : (
          <div className="review-user-list">
            {vocabGroups.map((userGroup) => (
              <article className="review-user-group" key={userGroup.requesterId}>
                <div className="review-user-head">
                  <div>
                    <h3>{profileLabel(userGroup.profile)}</h3>
                    <p>{userGroup.profile?.email ?? userGroup.requesterId}</p>
                  </div>
                  <span className="count-badge">{userGroup.total} từ</span>
                </div>

                <div className="review-topic-list">
                  {userGroup.topics.map((topicGroup) => (
                    <section className="review-topic-group" key={topicGroup.key}>
                      <div className="review-topic-head">
                        <div>
                          <h4>{topicGroup.topicName}</h4>
                          <p>Topic có sẵn</p>
                        </div>
                        <span className="count-badge muted">{topicGroup.submissions.length} từ</span>
                      </div>
                      <VocabSubmissionReviewTable
                        submissions={topicGroup.submissions}
                        profilesById={profiles}
                        notes={notes}
                        onNoteChange={updateNote}
                        onApprove={(submission) =>
                          runAction(() => api.approveVocabSubmission(submission, adminProfile.id))
                        }
                        onReject={(submission) =>
                          runAction(() =>
                            api.rejectVocabSubmission(submission, adminProfile.id, notes[submission.id] ?? '')
                          )
                        }
                      />
                    </section>
                  ))}
                </div>
              </article>
            ))}
          </div>
        )}
      </section>

      <section className="request-section">
        <div className="section-title">
          <h2>Topic nháp chờ duyệt</h2>
          <span>{topicSubmissions.length}</span>
        </div>

        {topicSubmissions.length === 0 ? (
          <EmptyState label="Không có topic nháp chờ duyệt." />
        ) : (
          <div className="review-user-list">
            {topicGroups.map((userGroup) => (
              <article className="review-user-group" key={userGroup.requesterId}>
                <div className="review-user-head">
                  <div>
                    <h3>{profileLabel(userGroup.profile)}</h3>
                    <p>{userGroup.profile?.email ?? userGroup.requesterId}</p>
                  </div>
                  <span className="count-badge">
                    {userGroup.totalTopics} topic · {userGroup.totalWords} từ
                  </span>
                </div>

                <div className="review-topic-list">
                  {userGroup.topics.map((topicGroup) => (
                    <section className="review-topic-group" key={topicGroup.key}>
                      <div className="review-topic-head">
                        <div>
                          <h4>{topicGroup.topicName}</h4>
                          <p>Topic mới tạo</p>
                        </div>
                        <span className="count-badge muted">
                          {topicGroup.submissions.reduce(
                            (sum, submission) => sum + (submission.topic_submission_words?.length ?? 0),
                            0
                          )}{' '}
                          từ
                        </span>
                      </div>

                      {topicGroup.submissions.map((submission) => {
                        const selected = topicSelections[submission.id] ?? [];
                        return (
                          <TopicSubmissionReviewPanel
                            key={submission.id}
                            submission={submission}
                            selected={selected}
                            note={notes[submission.id] ?? ''}
                            onToggleWord={(wordId) => toggleWord(submission.id, wordId)}
                            onNoteChange={(value) => updateNote(submission.id, value)}
                            onApprove={() =>
                              runAction(() =>
                                api.approveTopicSubmission(submission, new Set(selected), adminProfile.id)
                              )
                            }
                            onReject={() =>
                              runAction(() =>
                                api.rejectTopicSubmission(submission, adminProfile.id, notes[submission.id] ?? '')
                              )
                            }
                          />
                        );
                      })}
                    </section>
                  ))}
                </div>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function UsersView() {
  const [profiles, setProfiles] = useState<Profile[]>([]);
  const [editing, setEditing] = useState<Profile | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [message, setMessage] = useState('');

  async function load() {
    setIsLoading(true);
    setProfiles(await api.fetchProfiles());
    setIsLoading(false);
  }

  useEffect(() => {
    load().catch((err) => {
      setMessage(err instanceof Error ? err.message : 'Không tải được người dùng.');
      setIsLoading(false);
    });
  }, []);

  async function saveProfile() {
    if (!editing) return;
    setMessage('');
    try {
      await api.updateProfile(editing);
      setEditing(null);
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Không lưu được user.');
    }
  }

  if (isLoading) return <LoadingBlock label="Đang tải người dùng" />;

  return (
    <div className="stack">
      {message && <div className="notice">{message}</div>}
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Tên</th>
              <th>Email</th>
              <th>Vai trò</th>
              <th>Ngày tạo</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {profiles.map((profile) => (
              <tr key={profile.id}>
                <td>
                  {editing?.id === profile.id ? (
                    <input
                      value={editing.display_name ?? ''}
                      onChange={(event) => setEditing({ ...editing, display_name: event.target.value })}
                    />
                  ) : (
                    <strong>{profile.display_name || 'Chưa có tên'}</strong>
                  )}
                </td>
                <td>{profile.email || '...'}</td>
                <td>
                  {editing?.id === profile.id ? (
                    <select value={editing.role ?? 'user'} onChange={(event) => setEditing({ ...editing, role: event.target.value })}>
                      <option value="user">user</option>
                      <option value="admin">admin</option>
                    </select>
                  ) : (
                    <span className={profile.role === 'admin' ? 'role-badge admin' : 'role-badge'}>{profile.role ?? 'user'}</span>
                  )}
                </td>
                <td>{formatDate(profile.created_at)}</td>
                <td className="action-cell">
                  <div className="row-action-buttons">
                    {editing?.id === profile.id ? (
                      <>
                        <button className="icon-button success" onClick={saveProfile} title="Lưu">
                          <Check size={17} />
                        </button>
                        <button className="icon-button" onClick={() => setEditing(null)} title="Hủy">
                          <X size={17} />
                        </button>
                      </>
                    ) : (
                      <button className="icon-button" onClick={() => setEditing(profile)} title="Sửa">
                        <Pencil size={17} />
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function VocabSubmissionReviewTable({
  submissions,
  profilesById,
  notes,
  onNoteChange,
  onApprove,
  onReject
}: {
  submissions: VocabSubmission[];
  profilesById: Record<string, Profile>;
  notes: Record<string, string>;
  onNoteChange: (id: string, value: string) => void;
  onApprove: (submission: VocabSubmission) => void;
  onReject: (submission: VocabSubmission) => void;
}) {
  return (
    <div className="table-wrap vocab-table-wrap review-table-wrap">
      <table className="vocab-table review-table">
        <thead>
          <tr>
            <th className="sticky-word-col">Từ</th>
            <th>CEFR</th>
            <th>IPA</th>
            <th>Loại từ</th>
            <th>Nghĩa Anh</th>
            <th>Nghĩa Anh - Việt</th>
            <th>Nghĩa Việt</th>
            <th>Ví dụ Anh</th>
            <th>Ví dụ Việt</th>
            <th>Word family</th>
            <th>Đồng nghĩa</th>
            <th>Trái nghĩa</th>
            <th>Bonus</th>
            <th>Visibility</th>
            <th>Created by</th>
            <th>Ngày gửi</th>
            <th>Ghi chú</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {submissions.map((submission) => {
            const vocab = submission.vocab_catalog;
            return (
              <tr key={submission.id}>
                <td className="sticky-word-col word-cell">
                  <strong>{fieldValue(vocab?.word)}</strong>
                  <small>{vocab?.word_form || vocab?.ipa || vocab?.visibility || '...'}</small>
                </td>
                <td><span className="count-badge muted">{vocab?.cefr || '...'}</span></td>
                <td>{fieldValue(vocab?.ipa)}</td>
                <td>{fieldValue(vocab?.word_form)}</td>
                <td className="long-cell">{fieldValue(vocab?.e_meaning)}</td>
                <td className="long-cell">{fieldValue(vocab?.ev_meaning)}</td>
                <td className="long-cell">{fieldValue(vocab?.v_meaning)}</td>
                <td className="long-cell">{fieldValue(vocab?.e_example)}</td>
                <td className="long-cell">{fieldValue(vocab?.v_example)}</td>
                <td className="long-cell">{fieldValue(vocab?.word_family)}</td>
                <td className="long-cell">{fieldValue(vocab?.synonymous)}</td>
                <td className="long-cell">{fieldValue(vocab?.antonym)}</td>
                <td className="long-cell">{fieldValue(vocab?.bonus)}</td>
                <td>{fieldValue(vocab?.visibility)}</td>
                <td>{vocab?.created_by ? profileDisplayName(profilesById[vocab.created_by]) : 'Không rõ'}</td>
                <td>{formatDate(submission.created_at)}</td>
                <td className="review-note-cell">
                  <textarea
                    className="table-note"
                    placeholder="Ghi chú khi từ chối"
                    value={notes[submission.id] ?? ''}
                    onChange={(event) => onNoteChange(submission.id, event.target.value)}
                  />
                </td>
                <td className="action-cell review-action-cell">
                  <div className="row-action-buttons">
                    <button
                      className="icon-button success"
                      disabled={!submission.catalog_id}
                      onClick={() => onApprove(submission)}
                      title="Duyệt"
                    >
                      <Check size={17} />
                    </button>
                    <button className="icon-button danger" onClick={() => onReject(submission)} title="Từ chối">
                      <X size={17} />
                    </button>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function TopicSubmissionReviewPanel({
  submission,
  selected,
  note,
  onToggleWord,
  onNoteChange,
  onApprove,
  onReject
}: {
  submission: TopicSubmission;
  selected: string[];
  note: string;
  onToggleWord: (wordId: string) => void;
  onNoteChange: (value: string) => void;
  onApprove: () => void;
  onReject: () => void;
}) {
  const words = submission.topic_submission_words ?? [];
  const selectedSet = new Set(selected);

  return (
    <article className="topic-review-card">
      <div className="topic-review-head">
        <div>
          <strong>{submission.name}</strong>
          <p>{formatDate(submission.created_at)}</p>
        </div>
        <span className="count-badge">
          {selected.length}/{words.length} từ được chọn
        </span>
      </div>

      {submission.description && <p className="description">{submission.description}</p>}

      <TopicSubmissionWordsReviewTable words={words} selected={selectedSet} onToggleWord={onToggleWord} />

      <div className="topic-review-footer">
        <textarea
          className="topic-note"
          placeholder="Ghi chú khi từ chối"
          value={note}
          onChange={(event) => onNoteChange(event.target.value)}
        />
        <div className="button-row">
          <button className="primary-button" disabled={selected.length === 0} onClick={onApprove}>
            <Check size={18} />
            Duyệt topic
          </button>
          <button className="danger-button" onClick={onReject}>
            <X size={18} />
            Từ chối
          </button>
        </div>
      </div>
    </article>
  );
}

function TopicSubmissionWordsReviewTable({
  words,
  selected,
  onToggleWord
}: {
  words: TopicSubmissionWord[];
  selected: Set<string>;
  onToggleWord: (wordId: string) => void;
}) {
  if (words.length === 0) return <EmptyState label="Topic này chưa có từ nào." />;

  return (
    <div className="table-wrap vocab-table-wrap review-table-wrap">
      <table className="vocab-table review-table topic-words-review-table">
        <thead>
          <tr>
            <th className="sticky-word-col">Từ</th>
            <th>Chọn duyệt</th>
            <th>CEFR</th>
            <th>IPA</th>
            <th>Loại từ</th>
            <th>Nghĩa Anh</th>
            <th>Nghĩa Anh - Việt</th>
            <th>Nghĩa Việt</th>
            <th>Ví dụ Anh</th>
            <th>Ví dụ Việt</th>
            <th>Word family</th>
            <th>Đồng nghĩa</th>
            <th>Trái nghĩa</th>
            <th>Bonus</th>
          </tr>
        </thead>
        <tbody>
          {words.map((word) => {
            const isSelected = selected.has(word.id);
            return (
              <tr key={word.id} className={isSelected ? 'selected-review-row' : undefined}>
                <td className="sticky-word-col word-cell">
                  <strong>{fieldValue(word.word)}</strong>
                  <small>{word.word_form || word.ipa || '...'}</small>
                </td>
                <td>
                  <button
                    className={isSelected ? 'select-button selected' : 'select-button'}
                    onClick={() => onToggleWord(word.id)}
                    aria-pressed={isSelected}
                  >
                    <Check size={16} />
                    {isSelected ? 'Duyệt' : 'Chọn'}
                  </button>
                </td>
                <td><span className="count-badge muted">{word.cefr || '...'}</span></td>
                <td>{fieldValue(word.ipa)}</td>
                <td>{fieldValue(word.word_form)}</td>
                <td className="long-cell">{fieldValue(word.e_meaning)}</td>
                <td className="long-cell">{fieldValue(word.ev_meaning)}</td>
                <td className="long-cell">{fieldValue(word.v_meaning)}</td>
                <td className="long-cell">{fieldValue(word.e_example)}</td>
                <td className="long-cell">{fieldValue(word.v_example)}</td>
                <td className="long-cell">{fieldValue(word.word_family)}</td>
                <td className="long-cell">{fieldValue(word.synonymous)}</td>
                <td className="long-cell">{fieldValue(word.antonym)}</td>
                <td className="long-cell">{fieldValue(word.bonus)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

function VocabularyTable({
  vocabs,
  profilesById,
  onEdit,
  onDelete
}: {
  vocabs: VocabCatalog[];
  profilesById: Record<string, Profile>;
  onEdit: (vocab: VocabCatalog) => void;
  onDelete: (vocab: VocabCatalog) => void;
}) {
  if (vocabs.length === 0) return <EmptyState label="Không có từ vựng phù hợp." />;

  return (
    <div className="table-wrap vocab-table-wrap">
      <table className="vocab-table">
        <thead>
          <tr>
            <th className="sticky-word-col">Từ</th>
            <th>Topic</th>
            <th>CEFR</th>
            <th>IPA</th>
            <th>Loại từ</th>
            <th>Nghĩa Anh</th>
            <th>Nghĩa Anh - Việt</th>
            <th>Nghĩa Việt</th>
            <th>Ví dụ Anh</th>
            <th>Ví dụ Việt</th>
            <th>Word family</th>
            <th>Đồng nghĩa</th>
            <th>Trái nghĩa</th>
            <th>Bonus</th>
            <th>Visibility</th>
            <th>Created by</th>
            <th>Ngày tạo</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {vocabs.map((vocab) => (
            <tr key={vocab.id}>
              <td className="sticky-word-col word-cell">
                <strong>{fieldValue(vocab.word)}</strong>
                <small>{vocab.word_form || vocab.ipa || vocab.visibility}</small>
              </td>
              <td>{vocab.topics?.name ?? 'Chưa phân loại'}</td>
              <td><span className="count-badge muted">{vocab.cefr || '...'}</span></td>
              <td>{fieldValue(vocab.ipa)}</td>
              <td>{fieldValue(vocab.word_form)}</td>
              <td className="long-cell">{fieldValue(vocab.e_meaning)}</td>
              <td className="long-cell">{fieldValue(vocab.ev_meaning)}</td>
              <td className="long-cell">{fieldValue(vocab.v_meaning)}</td>
              <td className="long-cell">{fieldValue(vocab.e_example)}</td>
              <td className="long-cell">{fieldValue(vocab.v_example)}</td>
              <td className="long-cell">{fieldValue(vocab.word_family)}</td>
              <td className="long-cell">{fieldValue(vocab.synonymous)}</td>
              <td className="long-cell">{fieldValue(vocab.antonym)}</td>
              <td className="long-cell">{fieldValue(vocab.bonus)}</td>
              <td>{fieldValue(vocab.visibility)}</td>
              <td>{vocab.created_by ? profileDisplayName(profilesById[vocab.created_by]) : 'Hệ thống'}</td>
              <td>{formatDate(vocab.created_at)}</td>
              <td className="action-cell">
                <div className="row-action-buttons">
                  <button className="icon-button" onClick={() => onEdit(vocab)} title="Sửa">
                    <Pencil size={17} />
                  </button>
                  <button className="icon-button danger" onClick={() => onDelete(vocab)} title="Xóa">
                    <Trash2 size={17} />
                  </button>
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function VocabEditorModal({
  title,
  topics,
  value,
  onClose,
  onSave
}: {
  title: string;
  topics: Topic[];
  value: VocabInput;
  onClose: () => void;
  onSave: (value: VocabInput) => Promise<void>;
}) {
  const [draft, setDraft] = useState(value);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState('');

  function update<K extends keyof VocabInput>(key: K, nextValue: VocabInput[K]) {
    setDraft((current) => ({ ...current, [key]: nextValue }));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    setError('');
    if (!draft.word.trim()) {
      setError('Vui lòng nhập từ vựng.');
      return;
    }
    setIsSaving(true);
    try {
      await onSave(draft);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không lưu được từ.');
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="modal-backdrop">
      <form className="modal-panel" onSubmit={submit}>
        <div className="modal-head">
          <h2>{title}</h2>
          <button type="button" className="icon-button" onClick={onClose} title="Đóng">
            <X size={18} />
          </button>
        </div>

        <div className="form-grid two">
          <label>
            Topic
            <select value={draft.topic_id ?? ''} onChange={(event) => update('topic_id', event.target.value || null)}>
              <option value="">Chưa phân loại</option>
              {topics.map((topic) => (
                <option key={topic.id} value={topic.id}>
                  {topic.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Từ vựng
            <input value={draft.word} onChange={(event) => update('word', event.target.value)} />
          </label>
          <label>
            CEFR
            <input value={draft.cefr} onChange={(event) => update('cefr', event.target.value)} />
          </label>
          <label>
            IPA
            <input value={draft.ipa} onChange={(event) => update('ipa', event.target.value)} />
          </label>
          <label>
            Loại từ
            <input value={draft.word_form} onChange={(event) => update('word_form', event.target.value)} />
          </label>
          <label>
            Nghĩa tiếng Việt
            <input value={draft.v_meaning} onChange={(event) => update('v_meaning', event.target.value)} />
          </label>
          <label>
            Nghĩa Anh
            <textarea value={draft.e_meaning} onChange={(event) => update('e_meaning', event.target.value)} />
          </label>
          <label>
            Nghĩa Anh - Việt
            <textarea value={draft.ev_meaning} onChange={(event) => update('ev_meaning', event.target.value)} />
          </label>
          <label>
            Ví dụ tiếng Anh
            <textarea value={draft.e_example} onChange={(event) => update('e_example', event.target.value)} />
          </label>
          <label>
            Ví dụ tiếng Việt
            <textarea value={draft.v_example} onChange={(event) => update('v_example', event.target.value)} />
          </label>
          <label>
            Word family
            <input value={draft.word_family} onChange={(event) => update('word_family', event.target.value)} />
          </label>
          <label>
            Đồng nghĩa
            <input value={draft.synonymous} onChange={(event) => update('synonymous', event.target.value)} />
          </label>
          <label>
            Trái nghĩa
            <input value={draft.antonym} onChange={(event) => update('antonym', event.target.value)} />
          </label>
          <label>
            Bonus
            <textarea value={draft.bonus} onChange={(event) => update('bonus', event.target.value)} />
          </label>
        </div>

        {error && <div className="form-error">{error}</div>}

        <div className="modal-actions">
          <button type="button" className="ghost-button" onClick={onClose}>
            <X size={18} />
            Hủy
          </button>
          <button className="primary-button" disabled={isSaving}>
            {isSaving ? <Loader2 className="spin" size={18} /> : <Check size={18} />}
            Lưu
          </button>
        </div>
      </form>
    </div>
  );
}

function ContributionWordPreview({ vocab }: { vocab: VocabCatalog | null }) {
  if (!vocab) return <EmptyState label="Không đọc được dữ liệu từ." />;

  return (
    <div className="word-preview">
      <div>
        <span>Topic</span>
        <strong>{vocab.topics?.name ?? 'Chưa phân loại'}</strong>
      </div>
      <div>
        <span>IPA</span>
        <strong>{vocab.ipa ?? '...'}</strong>
      </div>
      <div>
        <span>Nghĩa</span>
        <strong>{vocab.v_meaning || vocab.ev_meaning || vocab.e_meaning || '...'}</strong>
      </div>
      <div>
        <span>Ví dụ</span>
        <strong>{vocab.e_example || vocab.v_example || 'Chưa có ví dụ'}</strong>
      </div>
    </div>
  );
}

function LoadingBlock({ label }: { label: string }) {
  return (
    <div className="state-block">
      <Loader2 className="spin" size={22} />
      <span>{label}</span>
    </div>
  );
}

function ErrorBlock({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <div className="state-block error-state">
      <CircleAlert size={22} />
      <span>{message}</span>
      <button className="ghost-button" onClick={onRetry}>
        <RefreshCw size={18} />
        Thử lại
      </button>
    </div>
  );
}

function EmptyState({ label }: { label: string }) {
  return <div className="empty-state">{label}</div>;
}

export default App;
