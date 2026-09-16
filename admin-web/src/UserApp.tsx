import {
  BarChart3,
  Bell,
  BookOpen,
  CalendarDays,
  Check,
  ChevronRight,
  Compass,
  Download,
  FolderPlus,
  Flame,
  Gauge,
  Home,
  Loader2,
  LogOut,
  Pencil,
  Plus,
  RefreshCw,
  Search,
  Send,
  Trash2,
  Upload,
  X
} from 'lucide-react';
import { FormEvent, ReactNode, useEffect, useMemo, useState } from 'react';
import AuthScreen from './components/AuthScreen';
import { exportVocabularyWorkbook, parseVocabularyWorkbook } from './lib/excel';
import { supabase } from './lib/supabase';
import {
  ActivityLog,
  AppNotification,
  ExploreTopic,
  ImportRow,
  Profile,
  Topic,
  UserStats,
  UserTopicSubmission,
  UserVocabSubmission,
  UserVocabulary,
  VocabCatalog,
  VocabInput
} from './lib/types';
import * as userApi from './lib/userApi';

type UserViewKey = 'home' | 'notifications' | 'explore' | 'learning' | 'library';

type TopicItem = {
  id: string;
  name: string;
  topic: Topic | null;
  vocabs: UserVocabulary[];
  submission?: UserTopicSubmission;
};

type WordGroup = {
  key: string;
  word: string;
  rows: UserVocabulary[];
};

type LibraryData = {
  vocabs: UserVocabulary[];
  privateTopics: Topic[];
  topicSubmissions: UserTopicSubmission[];
  wordSubmissions: UserVocabSubmission[];
};

type LevelStat = {
  key: string;
  label: string;
  description: string;
  count: number;
  color: string;
};

const learningLevelColors: Record<number, string> = {
  1: '#ef4444',
  2: '#f97316',
  3: '#eab308',
  4: '#22c55e',
  5: '#3b82f6',
  6: '#9333ea'
};

const userNavItems: Array<{ key: UserViewKey; label: string; icon: ReactNode }> = [
  { key: 'home', label: 'Trang chủ', icon: <Home size={18} /> },
  { key: 'notifications', label: 'Thông báo', icon: <Bell size={18} /> },
  { key: 'explore', label: 'Khám phá', icon: <Compass size={18} /> },
  { key: 'learning', label: 'Học tập', icon: <Gauge size={18} /> },
  { key: 'library', label: 'Thư viện', icon: <BookOpen size={18} /> }
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

function formatDateOnly(value: string | null | undefined) {
  if (!value) return 'Chưa có';
  return new Intl.DateTimeFormat('vi-VN', {
    dateStyle: 'medium'
  }).format(new Date(value));
}

function localDateKey(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function profileLabel(profile?: Profile | null) {
  if (!profile) return 'Người dùng';
  return profile.display_name || profile.email || profile.id.slice(0, 8);
}

function fieldValue(value: string | null | undefined) {
  return value?.trim() || 'Chưa có';
}

function normalize(value: string | null | undefined) {
  return value?.trim().toLowerCase() || '';
}

function uniqueText(values: Array<string | null | undefined>) {
  return Array.from(new Set(values.map((value) => value?.trim()).filter((value): value is string => Boolean(value))));
}

function topicName(row: UserVocabulary) {
  return row.vocab_catalog?.topics?.name?.trim() || 'Chưa phân loại';
}

function makeTopicItems(
  vocabs: UserVocabulary[],
  privateTopics: Topic[],
  topicSubmissions: UserTopicSubmission[]
): TopicItem[] {
  const items = new Map<string, TopicItem>();

  vocabs.forEach((row) => {
    const topic = row.vocab_catalog?.topics ?? null;
    const name = topic?.name?.trim() || 'Chưa phân loại';
    const key = row.vocab_catalog?.topic_id ?? `uncategorized-${name}`;
    const item = items.get(key) ?? { id: key, name, topic, vocabs: [] };
    item.vocabs.push(row);
    if (topic) item.topic = topic;
    items.set(key, item);
  });

  privateTopics.forEach((topic) => {
    const item = items.get(topic.id) ?? { id: topic.id, name: topic.name, topic, vocabs: [] };
    item.name = topic.name;
    item.topic = topic;
    items.set(topic.id, item);
  });

  const latestByTopic = new Map<string, UserTopicSubmission>();
  topicSubmissions
    .filter((submission) => submission.topic_id)
    .forEach((submission) => {
      const topicId = submission.topic_id ?? '';
      const current = latestByTopic.get(topicId);
      if (!current || (submission.created_at ?? '') > (current.created_at ?? '')) latestByTopic.set(topicId, submission);
    });

  latestByTopic.forEach((submission, topicId) => {
    const item = items.get(topicId);
    if (item) item.submission = submission;
  });

  return Array.from(items.values()).sort((a, b) => a.name.localeCompare(b.name, 'vi'));
}

function groupByWord(rows: UserVocabulary[]): WordGroup[] {
  const map = new Map<string, WordGroup>();
  rows.forEach((row) => {
    const word = row.vocab_catalog?.word?.trim() || 'Untitled';
    const key = word.toLowerCase();
    const group = map.get(key) ?? { key, word, rows: [] };
    group.rows.push(row);
    map.set(key, group);
  });
  return Array.from(map.values()).sort((a, b) => a.word.localeCompare(b.word, 'vi'));
}

function uniqueWordCount(vocabs: UserVocabulary[]) {
  return groupByWord(vocabs).length;
}

function joinedMeanings(group: WordGroup) {
  return uniqueText(group.rows.map((row) => row.vocab_catalog?.v_meaning || row.vocab_catalog?.ev_meaning || row.vocab_catalog?.e_meaning)).join('; ');
}

function learningLevel(group: WordGroup) {
  return group.rows.find((row) => (row.learning_level ?? 0) > 0)?.learning_level ?? 0;
}

function pronunciationAverage(group: WordGroup) {
  const scores = group.rows.map((row) => row.pronunciation_score).filter((score): score is number => typeof score === 'number');
  if (!scores.length) return null;
  return Math.round(scores.reduce((sum, score) => sum + score, 0) / scores.length);
}

function latestStatusByCatalog(submissions: UserVocabSubmission[]) {
  return submissions.reduce<Record<string, UserVocabSubmission>>((result, submission) => {
    if (!submission.catalog_id) return result;
    if (!result[submission.catalog_id]) result[submission.catalog_id] = submission;
    return result;
  }, {});
}

function buildLevelStats(groups: WordGroup[]): LevelStat[] {
  const stats: LevelStat[] = [
    { key: '1', label: 'Cấp 1', description: 'Đang học giai đoạn đầu', count: 0, color: learningLevelColors[1] },
    { key: '2', label: 'Cấp 2', description: 'Ôn sau 1 ngày', count: 0, color: learningLevelColors[2] },
    { key: '3', label: 'Cấp 3', description: 'Ôn sau 3 ngày', count: 0, color: learningLevelColors[3] },
    { key: '4', label: 'Cấp 4', description: 'Ôn sau 7 ngày', count: 0, color: learningLevelColors[4] },
    { key: '5', label: 'Cấp 5', description: 'Ôn sau 15 ngày', count: 0, color: learningLevelColors[5] },
    { key: 'master', label: 'Master', description: 'Cấp 6 trở lên', count: 0, color: learningLevelColors[6] }
  ];

  groups.forEach((group) => {
    const level = learningLevel(group);
    if (level <= 0) return;
    if (level >= 6) stats[5].count += 1;
    else stats[level - 1].count += 1;
  });

  return stats;
}

function donutGradient(stats: LevelStat[], total: number) {
  if (total <= 0) return 'conic-gradient(#e5e7eb 0deg 360deg)';
  let cursor = 0;
  const segments = stats
    .filter((item) => item.count > 0)
    .map((item) => {
      const start = cursor;
      const size = (item.count / total) * 360;
      cursor += size;
      return `${item.color} ${start}deg ${cursor}deg`;
    });
  return `conic-gradient(${segments.join(', ')})`;
}

function activeDaysInLast(logs: ActivityLog[], days: number) {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  start.setDate(start.getDate() - days + 1);
  const startKey = localDateKey(start);
  return logs.filter((log) => log.completed && log.date >= startKey).length;
}

async function safe<T>(task: Promise<T>, fallback: T) {
  try {
    return await task;
  } catch {
    return fallback;
  }
}

async function fetchLibraryData(userId: string): Promise<LibraryData> {
  const [vocabs, privateTopics, topicSubmissions, wordSubmissions] = await Promise.all([
    userApi.fetchUserVocabs(userId),
    userApi.fetchPrivateTopics(userId),
    userApi.fetchUserTopicSubmissions(userId),
    userApi.fetchUserVocabSubmissions(userId)
  ]);

  return { vocabs, privateTopics, topicSubmissions, wordSubmissions };
}

function UserApp() {
  const [activeView, setActiveView] = useState<UserViewKey>('home');
  const [profile, setProfile] = useState<Profile | null>(null);
  const [isBooting, setIsBooting] = useState(true);
  const [authError, setAuthError] = useState('');

  async function boot() {
    setIsBooting(true);
    try {
      const user = await userApi.getCurrentUser();
      const nextProfile = await userApi.getSignedInProfile(user);
      if (nextProfile?.role === 'admin') {
        window.location.replace('/admin');
        return;
      }
      setProfile(nextProfile);
    } catch (error) {
      setAuthError(error instanceof Error ? error.message : 'Không thể mở Omninary Web.');
    } finally {
      setIsBooting(false);
    }
  }

  useEffect(() => {
    let mounted = true;
    boot();
    const { data } = supabase.auth.onAuthStateChange(async (_event, session) => {
      if (!mounted) return;
      if (!session?.user) {
        setProfile(null);
        setIsBooting(false);
        return;
      }
      const nextProfile = await userApi.getSignedInProfile(session.user);
      if (nextProfile?.role === 'admin') {
        window.location.replace('/admin');
        return;
      }
      if (mounted) setProfile(nextProfile);
    });

    return () => {
      mounted = false;
      data.subscription.unsubscribe();
    };
  }, []);

  async function signOut() {
    await supabase.auth.signOut();
    setProfile(null);
  }

  if (isBooting) {
    return (
      <div className="boot-screen">
        <Loader2 className="spin" size={28} />
        <span>Đang mở Omninary Web</span>
      </div>
    );
  }

  if (!profile) {
    return <AuthScreen authError={authError} onAuthenticated={setProfile} />;
  }

  const activeLabel = userNavItems.find((item) => item.key === activeView)?.label ?? 'Trang chủ';

  return (
    <div className="app-shell user-shell">
      <aside className="sidebar user-sidebar">
        <div className="sidebar-head">
          <BrandLogo compact />
        </div>

        <nav className="nav-list">
          {userNavItems.map((item) => (
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
            <p className="eyebrow">Omninary Web</p>
            <h1>{activeLabel}</h1>
          </div>
          <div className="topbar-actions">
            <div className="admin-pill">
              <span>{profileLabel(profile)}</span>
              <small>{profile.email}</small>
            </div>
            <button className="icon-button" onClick={signOut} title="Đăng xuất">
              <LogOut size={18} />
            </button>
          </div>
        </header>

        <section className="content-area">
          {activeView === 'home' && <UserHomeView profile={profile} />}
          {activeView === 'notifications' && <UserNotificationsView profile={profile} />}
          {activeView === 'explore' && <UserExploreView profile={profile} />}
          {activeView === 'learning' && <UserLearningView profile={profile} />}
          {activeView === 'library' && <UserLibraryView profile={profile} />}
        </section>
      </main>
    </div>
  );
}

function UserHomeView({ profile }: { profile: Profile }) {
  const [stats, setStats] = useState<UserStats>({ user_id: profile.id, streak_count: 0, last_learning_date: null });
  const [activityLogs, setActivityLogs] = useState<ActivityLog[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const [monthOffset, setMonthOffset] = useState(0);

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      const [nextStats, logs] = await Promise.all([
        safe(userApi.fetchUserStats(profile.id), { user_id: profile.id, streak_count: 0, last_learning_date: null }),
        safe(userApi.fetchActivityLogs(profile.id), [])
      ]);
      setStats(nextStats);
      setActivityLogs(logs);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được trang chủ.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [profile.id]);

  const activeMonth = useMemo(() => {
    const date = new Date();
    date.setMonth(date.getMonth() + monthOffset);
    return date;
  }, [monthOffset]);

  if (isLoading) return <LoadingBlock label="Đang tải trang chủ" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  return (
    <div className="stack home-management-page">
      <section className="mobile-card streak-card home-streak-card">
        <div className="streak-icon">
          <Flame size={38} />
        </div>
        <div>
          <span>Chuỗi học tập</span>
          <strong>{stats.streak_count}</strong>
          <p>{stats.streak_count > 0 ? 'ngày liên tiếp' : 'Hãy học trên app iOS để bắt đầu chuỗi.'}</p>
        </div>
      </section>

      <section className="mobile-card calendar-card">
        <div className="panel-head">
          <div>
            <h2>Lịch học tập</h2>
            <p className="description">Đánh dấu các ngày bạn hoàn thành phiên học trên app iOS.</p>
          </div>
          <div className="button-row calendar-actions">
            <button className="icon-button" onClick={() => setMonthOffset((value) => value - 12)} title="Năm trước">«</button>
            <button className="icon-button" onClick={() => setMonthOffset((value) => value - 1)} title="Tháng trước">‹</button>
            <button className="ghost-button" onClick={() => setMonthOffset(0)}>Hôm nay</button>
            <button className="icon-button" onClick={() => setMonthOffset((value) => value + 1)} title="Tháng sau">›</button>
            <button className="icon-button" onClick={() => setMonthOffset((value) => value + 12)} title="Năm sau">»</button>
          </div>
        </div>
        <ActivityCalendar month={activeMonth} logs={activityLogs} />
        <div className="compact-list calendar-summary">
          <MetricRow label="Lần học gần nhất" value={formatDateOnly(stats.last_learning_date)} />
          <MetricRow label="Hoạt động 30 ngày gần nhất" value={`${activeDaysInLast(activityLogs, 30)} ngày`} />
        </div>
      </section>
    </div>
  );
}

function UserNotificationsView({ profile }: { profile: Profile }) {
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      setNotifications(await userApi.fetchNotifications(profile.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được thông báo.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [profile.id]);

  if (isLoading) return <LoadingBlock label="Đang tải thông báo" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  return (
    <div className="stack">
      <section className="panel">
        <div className="panel-head">
          <h2>Thông báo</h2>
          <button className="ghost-button" onClick={load}>
            <RefreshCw size={18} />
            Làm mới
          </button>
        </div>
        {notifications.length === 0 ? (
          <EmptyState label="Chưa có thông báo." />
        ) : (
          <div className="notification-list">
            {notifications.map((item) => (
              <article className={item.is_read ? 'notification-card' : 'notification-card unread'} key={item.id}>
                <div>
                  <h3>{item.title}</h3>
                  <p>{item.content}</p>
                </div>
                <span>{formatDate(item.created_at)}</span>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}

function UserExploreView({ profile }: { profile: Profile }) {
  const [topics, setTopics] = useState<ExploreTopic[]>([]);
  const [message, setMessage] = useState('');
  const [workingTopicId, setWorkingTopicId] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      setTopics(await userApi.fetchExploreTopics(profile.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được danh sách khám phá.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [profile.id]);

  async function downloadTopic(topic: ExploreTopic) {
    setWorkingTopicId(topic.topic.id);
    setMessage('');
    try {
      const result = await userApi.downloadSystemTopic(profile.id, topic.topic.id);
      setMessage(result.addedWords > 0 ? `Đã tải ${result.addedWords} từ trong topic ${topic.topic.name}.` : `${topic.topic.name} đã được cập nhật đầy đủ.`);
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Tải topic thất bại.');
    } finally {
      setWorkingTopicId('');
    }
  }

  if (isLoading) return <LoadingBlock label="Đang tải khám phá" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  return (
    <div className="stack">
      {message && <div className="notice">{message}</div>}
      <section className="panel">
        <div className="panel-head">
          <h2>Bộ từ hệ thống</h2>
          <button className="ghost-button" onClick={load}>
            <RefreshCw size={18} />
            Làm mới
          </button>
        </div>
        <div className="explore-list">
          {topics.length === 0 ? (
            <EmptyState label="Hiện chưa có bộ từ hệ thống nào." />
          ) : (
            topics.map((item) => {
              const isDownloaded = item.vocabs.length > 0 && item.newMeanings === 0;
              const hasUpdate = item.downloadedWords > 0 && item.newMeanings > 0;
              return (
                <article className="explore-row" key={item.topic.id}>
                  <div className="topic-folder">
                    <BookOpen size={20} />
                  </div>
                  <div>
                    <strong>{item.topic.name}</strong>
                    <span>{item.totalWords} từ · {item.vocabs.length} nghĩa</span>
                  </div>
                  {isDownloaded && <span className="status-pill approved">Đã tải</span>}
                  {hasUpdate && <span className="status-pill pending">+{item.newWords} từ</span>}
                  {!isDownloaded && !hasUpdate && <span className="status-pill">Mới</span>}
                  <button className="icon-button" disabled={isDownloaded || workingTopicId === item.topic.id} onClick={() => downloadTopic(item)} title={isDownloaded ? 'Đã tải' : 'Tải về'}>
                    {workingTopicId === item.topic.id ? <Loader2 className="spin" size={17} /> : <Download size={17} />}
                  </button>
                </article>
              );
            })
          )}
        </div>
      </section>
    </div>
  );
}

function UserLearningView({ profile }: { profile: Profile }) {
  const [data, setData] = useState<LibraryData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      setData(await fetchLibraryData(profile.id));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được thống kê học tập.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [profile.id]);

  const groups = useMemo(() => groupByWord(data?.vocabs ?? []), [data]);
  const levelStats = useMemo(() => buildLevelStats(groups), [groups]);
  const totalWords = groups.length;
  const learningWords = groups.filter((group) => learningLevel(group) > 0).length;
  const masterWords = groups.filter((group) => learningLevel(group) >= 6).length;
  const totalLevelWords = Math.max(1, learningWords);
  const learnedPercent = totalWords > 0 ? Math.round((learningWords / totalWords) * 100) : 0;
  const donutStyle = donutGradient(levelStats, learningWords);

  if (isLoading) return <LoadingBlock label="Đang tải học tập" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  return (
    <div className="stack">
      <section className="split-grid management-overview-grid">
        <div className="panel learning-progress-panel">
          <div className="panel-head">
            <h2>Biểu đồ tiến độ học tập</h2>
            <BarChart3 size={20} />
          </div>
          <div className="learning-donut-layout">
            <div className="learning-donut" style={{ background: donutStyle }}>
              <div>
                <strong>{learnedPercent}%</strong>
                <span>đã học</span>
              </div>
            </div>
            <div className="compact-list">
              <MetricRow label="Số từ đã tải về" value={`${totalWords} từ`} />
              <MetricRow label="Số từ đã đưa vào học" value={`${learningWords} từ`} />
              <MetricRow label="Số từ đã master" value={`${masterWords} từ`} />
            </div>
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <h2>Tiến độ theo cấp</h2>
            <span className="count-badge muted">{groups.length} từ</span>
          </div>
          <div className="level-bars">
            {levelStats.map((item) => {
              const percent = learningWords > 0 ? Math.max(item.count > 0 ? 5 : 0, (item.count / totalLevelWords) * 100) : 0;
              return (
                <div className="level-row management-level-row" key={item.key}>
                  <span style={{ color: item.color }}>{item.label}</span>
                  <div title={item.description}>
                    <i style={{ width: `${percent}%`, background: item.color }} />
                  </div>
                  <strong>{item.count}</strong>
                </div>
              );
            })}
          </div>
        </div>
      </section>
    </div>
  );
}

function StatCard({ label, value, tone }: { label: string; value: ReactNode; tone: 'green' | 'blue' | 'violet' | 'amber' | 'red' }) {
  return (
    <article className={`stat-card ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  );
}

function MetricRow({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="compact-row">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function ActivityCalendar({ month, logs }: { month: Date; logs: ActivityLog[] }) {
  const completed = new Set(logs.filter((log) => log.completed).map((log) => log.date));
  const days = useMemo(() => {
    const first = new Date(month.getFullYear(), month.getMonth(), 1);
    const startPadding = first.getDay();
    const count = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
    return [
      ...Array.from({ length: startPadding }, () => null),
      ...Array.from({ length: count }, (_, index) => new Date(month.getFullYear(), month.getMonth(), index + 1))
    ];
  }, [month]);

  return (
    <div className="activity-calendar">
      <div className="calendar-title">
        <CalendarDays size={18} />
        {new Intl.DateTimeFormat('vi-VN', { month: 'long', year: 'numeric' }).format(month)}
      </div>
      <div className="calendar-grid">
        {['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'].map((day) => (
          <span className="calendar-weekday" key={day}>{day}</span>
        ))}
        {days.map((day, index) => {
          if (!day) return <span className="calendar-day empty" key={`empty-${index}`} />;
          const key = localDateKey(day);
          const isToday = key === localDateKey();
          const isDone = completed.has(key);
          return (
            <span className={isDone ? 'calendar-day done' : isToday ? 'calendar-day today' : 'calendar-day'} key={key}>
              {day.getDate()}
            </span>
          );
        })}
      </div>
    </div>
  );
}

function UserLibraryView({ profile }: { profile: Profile }) {
  const [vocabs, setVocabs] = useState<UserVocabulary[]>([]);
  const [privateTopics, setPrivateTopics] = useState<Topic[]>([]);
  const [topicSubmissions, setTopicSubmissions] = useState<UserTopicSubmission[]>([]);
  const [wordSubmissions, setWordSubmissions] = useState<UserVocabSubmission[]>([]);
  const [selectedTopicId, setSelectedTopicId] = useState('');
  const [search, setSearch] = useState('');
  const [newTopicName, setNewTopicName] = useState('');
  const [newTopicDescription, setNewTopicDescription] = useState('');
  const [editing, setEditing] = useState<VocabInput | null>(null);
  const [selectedGroup, setSelectedGroup] = useState<WordGroup | null>(null);
  const [message, setMessage] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const [rows, setRows] = useState<ImportRow[]>([]);
  const [fileName, setFileName] = useState('');
  const [isImporting, setIsImporting] = useState(false);
  const [isExporting, setIsExporting] = useState(false);

  const topicItems = useMemo(() => makeTopicItems(vocabs, privateTopics, topicSubmissions), [vocabs, privateTopics, topicSubmissions]);
  const selectedTopic = topicItems.find((item) => item.id === selectedTopicId) ?? topicItems[0];
  const statusByCatalog = useMemo(() => latestStatusByCatalog(wordSubmissions), [wordSubmissions]);
  const wordGroups = useMemo(() => {
    const groups = groupByWord(selectedTopic?.vocabs ?? []);
    const keyword = normalize(search);
    if (!keyword) return groups;
    return groups.filter((group) => {
      const haystack = [group.word, joinedMeanings(group), ...group.rows.flatMap((row) => [row.vocab_catalog?.ipa, row.vocab_catalog?.word_form, topicName(row)])].join(' ').toLowerCase();
      return haystack.includes(keyword);
    });
  }, [search, selectedTopic]);

  const canSubmitTopic = selectedTopic?.topic?.visibility === 'private' && (selectedTopic?.vocabs.length ?? 0) > 0 && selectedTopic?.submission?.status !== 'pending';
  const canDeleteTopic = selectedTopic?.topic?.visibility === 'private' && (selectedTopic?.vocabs.length ?? 0) === 0 && selectedTopic?.submission?.status !== 'pending';
  const addTopicId = selectedTopic?.topic?.id ?? selectedTopic?.vocabs[0]?.vocab_catalog?.topic_id ?? null;
  const validRows = rows.filter((row) => !row.error && row.word.trim());

  async function load() {
    setIsLoading(true);
    setError('');
    try {
      const next = await fetchLibraryData(profile.id);
      setVocabs(next.vocabs);
      setPrivateTopics(next.privateTopics);
      setTopicSubmissions(next.topicSubmissions);
      setWordSubmissions(next.wordSubmissions);
      if (!selectedTopicId && (next.vocabs.length || next.privateTopics.length)) {
        const firstItems = makeTopicItems(next.vocabs, next.privateTopics, next.topicSubmissions);
        setSelectedTopicId(firstItems[0]?.id ?? '');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Không tải được kho từ.');
    } finally {
      setIsLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [profile.id]);

  async function createTopic() {
    if (!newTopicName.trim()) return;
    setMessage('');
    try {
      const topic = await userApi.createPrivateTopic(newTopicName, newTopicDescription, profile.id);
      setNewTopicName('');
      setNewTopicDescription('');
      setSelectedTopicId(topic.id);
      setMessage('Đã tạo topic riêng.');
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Tạo topic thất bại.');
    }
  }

  async function saveVocab(input: VocabInput) {
    if (input.id) await userApi.updatePrivateVocab(input);
    else await userApi.createPrivateVocab(input, profile.id);
    setEditing(null);
    setMessage(input.id ? 'Đã lưu từ.' : 'Đã thêm từ.');
    await load();
  }

  async function deleteRows(rowsToDelete: UserVocabulary[]) {
    if (!confirm(`Xoá "${rowsToDelete[0]?.vocab_catalog?.word ?? 'từ này'}" khỏi kho từ của bạn?`)) return;
    for (const row of rowsToDelete) await userApi.deleteUserVocab(row);
    setSelectedGroup(null);
    setMessage('Đã xoá từ.');
    await load();
  }

  async function submitWord(row: UserVocabulary) {
    try {
      await userApi.submitVocabContribution(row);
      setMessage('Đã gửi từ cho admin duyệt.');
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Gửi duyệt thất bại.');
    }
  }

  async function submitTopic() {
    if (!selectedTopic?.topic) return;
    try {
      await userApi.submitPrivateTopicForReview(selectedTopic.topic, selectedTopic.vocabs, profile.id);
      setMessage('Đã gửi topic cho admin duyệt.');
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Gửi topic thất bại.');
    }
  }

  async function deleteTopic() {
    if (!selectedTopic?.topic || !confirm(`Xoá topic "${selectedTopic.name}"?`)) return;
    try {
      await userApi.deletePrivateTopic(selectedTopic.topic, profile.id);
      setMessage('Đã xoá topic riêng.');
      setSelectedTopicId('');
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Xoá topic thất bại.');
    }
  }

  async function handleFile(file: File | null) {
    if (!file || !addTopicId) return;
    setMessage('');
    setFileName(file.name);
    setRows(await parseVocabularyWorkbook(file, addTopicId));
  }

  async function importRows() {
    if (!validRows.length || !addTopicId || !selectedTopic) return;
    setIsImporting(true);
    setMessage('');
    try {
      await userApi.importPrivateVocabs(validRows.map((row) => ({ ...row, topic_id: addTopicId })), profile.id);
      setRows([]);
      setFileName('');
      setMessage(`Đã import ${validRows.length} dòng vào ${selectedTopic.name}.`);
      await load();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Import thất bại.');
    } finally {
      setIsImporting(false);
    }
  }

  async function exportRows() {
    if (!selectedTopic) return;
    setIsExporting(true);
    setMessage('');
    try {
      const catalogRows = selectedTopic.vocabs.map((row) => row.vocab_catalog).filter((vocab): vocab is VocabCatalog => Boolean(vocab));
      await exportVocabularyWorkbook({ id: selectedTopic.id, name: selectedTopic.name }, catalogRows);
      setMessage(`Đã export ${catalogRows.length} nghĩa của ${selectedTopic.name}.`);
    } catch (err) {
      setMessage(err instanceof Error ? err.message : 'Export thất bại.');
    } finally {
      setIsExporting(false);
    }
  }

  if (isLoading) return <LoadingBlock label="Đang tải kho từ" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  return (
    <div className="library-layout">
      <aside className="topic-sidebar panel">
        <div className="panel-head">
          <h2>Topic</h2>
          <button className="icon-button" onClick={load} title="Làm mới">
            <RefreshCw size={17} />
          </button>
        </div>

        <div className="topic-create-box">
          <input placeholder="Tạo topic riêng" value={newTopicName} onChange={(event) => setNewTopicName(event.target.value)} />
          <input placeholder="Mô tả ngắn" value={newTopicDescription} onChange={(event) => setNewTopicDescription(event.target.value)} />
          <button className="primary-button" onClick={createTopic} disabled={!newTopicName.trim()}>
            <FolderPlus size={18} />
            Tạo topic
          </button>
        </div>

        <div className="topic-list">
          {topicItems.map((item) => (
            <button
              key={item.id}
              className={selectedTopic?.id === item.id ? 'topic-list-item active' : 'topic-list-item'}
              onClick={() => setSelectedTopicId(item.id)}
            >
              <span>{item.name}</span>
              <small>
                {uniqueWordCount(item.vocabs)} từ
                {item.topic?.visibility === 'private' ? ' · riêng tư' : ''}
              </small>
            </button>
          ))}
        </div>
      </aside>

      <section className="stack">
        {message && <div className="notice">{message}</div>}
        <div className="section-band">
          <div>
            <h2>{selectedTopic?.name ?? 'Chưa có topic'}</h2>
            <p>
              {selectedTopic?.topic?.visibility === 'private' ? 'Topic riêng' : 'Topic hệ thống'} · {uniqueWordCount(selectedTopic?.vocabs ?? [])} từ
              {selectedTopic?.submission?.status === 'pending' ? ' · đang chờ duyệt' : ''}
              {selectedTopic?.submission?.status === 'rejected' ? ' · không được duyệt' : ''}
            </p>
          </div>
          <div className="topbar-actions">
            {canSubmitTopic && (
              <button className="ghost-button" onClick={submitTopic}>
                <Send size={18} />
                Gửi duyệt topic
              </button>
            )}
            {canDeleteTopic && (
              <button className="danger-button" onClick={deleteTopic}>
                <Trash2 size={18} />
                Xoá topic
              </button>
            )}
            <button className="primary-button" disabled={!selectedTopic} onClick={() => setEditing(userApi.emptyVocabInput(addTopicId))}>
              <Plus size={18} />
              Thêm từ
            </button>
            <label className={addTopicId ? 'ghost-button file-action' : 'ghost-button file-action disabled'}>
              <Upload size={18} />
              Import
              <input type="file" accept=".xlsx" disabled={!addTopicId} onChange={(event) => handleFile(event.target.files?.[0] ?? null)} />
            </label>
            <button className="ghost-button" disabled={!selectedTopic || isExporting} onClick={exportRows}>
              {isExporting ? <Loader2 className="spin" size={18} /> : <Download size={18} />}
              Export
            </button>
          </div>
        </div>

        {rows.length > 0 && (
          <div className="panel">
            <div className="panel-head">
              <h2>{fileName}</h2>
              <span className="count-badge muted">{validRows.length} dòng hợp lệ</span>
            </div>
            <div className="preview-list">
              {rows.slice(0, 8).map((row) => (
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
          </div>
        )}

        <div className="toolbar-row user-toolbar">
          <div className="search-box">
            <Search size={18} />
            <input placeholder="Tìm trong topic..." value={search} onChange={(event) => setSearch(event.target.value)} />
          </div>
          <button className="ghost-button" onClick={load}>
            <RefreshCw size={18} />
            Làm mới
          </button>
        </div>

        <WordSummaryList groups={wordGroups} statusByCatalog={statusByCatalog} onSelect={setSelectedGroup} />
        <ContributionTracker
          wordSubmissions={wordSubmissions}
          topicSubmissions={topicSubmissions}
          profile={profile}
          onMessage={setMessage}
          onReload={load}
        />
      </section>

      {editing && (
        <UserVocabModal
          title={editing.id ? 'Sửa từ riêng' : 'Thêm từ riêng'}
          value={editing}
          onClose={() => setEditing(null)}
          onSave={saveVocab}
        />
      )}

      {selectedGroup && (
        <WordDetailModal
          group={selectedGroup}
          isPrivateTopic={selectedTopic?.topic?.visibility === 'private'}
          statusByCatalog={statusByCatalog}
          onClose={() => setSelectedGroup(null)}
          onEdit={(row) => row.vocab_catalog && setEditing(userApi.catalogToInput(row.vocab_catalog))}
          onDelete={deleteRows}
          onSubmit={submitWord}
        />
      )}
    </div>
  );
}

function WordSummaryList({
  groups,
  statusByCatalog,
  onSelect
}: {
  groups: WordGroup[];
  statusByCatalog: Record<string, UserVocabSubmission>;
  onSelect: (group: WordGroup) => void;
}) {
  if (!groups.length) return <EmptyState label="Topic này chưa có từ vựng." />;

  return (
    <div className="word-list">
      {groups.map((group) => {
        const first = group.rows[0]?.vocab_catalog;
        const level = learningLevel(group);
        const score = pronunciationAverage(group);
        const isPrivate = group.rows.some((row) => row.vocab_catalog?.visibility === 'private');
        const status = group.rows
          .map((row) => statusByCatalog[row.vocab_id ?? row.vocab_catalog?.id ?? '']?.status)
          .find(Boolean);
        return (
          <button className="word-row-card" key={group.key} onClick={() => onSelect(group)}>
            <div>
              <div className="word-row-title">
                <strong>{group.word}</strong>
                {isPrivate && <span className="status-pill private">Riêng tư</span>}
                {level >= 6 ? <span className="status-pill master">Master</span> : <span className="count-badge muted">{level}/6</span>}
                {score != null && <span className={score >= 70 ? 'status-pill approved' : 'status-pill pending'}>{score}/100</span>}
                {status && <span className={`status-pill ${status}`}>{status}</span>}
              </div>
              {first?.ipa && <span className="word-ipa">{first.ipa}</span>}
              <p>{joinedMeanings(group) || 'Chưa có nghĩa.'}</p>
            </div>
            <ChevronRight size={18} />
          </button>
        );
      })}
    </div>
  );
}

function WordDetailModal({
  group,
  isPrivateTopic,
  statusByCatalog,
  onClose,
  onEdit,
  onDelete,
  onSubmit
}: {
  group: WordGroup;
  isPrivateTopic: boolean;
  statusByCatalog: Record<string, UserVocabSubmission>;
  onClose: () => void;
  onEdit: (row: UserVocabulary) => void;
  onDelete: (rows: UserVocabulary[]) => Promise<void>;
  onSubmit: (row: UserVocabulary) => Promise<void>;
}) {
  const [message, setMessage] = useState('');
  const [isSubmitting, setIsSubmitting] = useState('');
  const level = learningLevel(group);
  const score = pronunciationAverage(group);
  const privateRows = group.rows.filter((row) => row.vocab_catalog?.visibility === 'private');
  const canSubmitWord = privateRows.length > 0 && !isPrivateTopic;

  async function submitPrivateRow(row: UserVocabulary) {
    setMessage('');
    setIsSubmitting(row.id);
    await onSubmit(row);
    setIsSubmitting('');
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-panel word-detail-panel" onClick={(event) => event.stopPropagation()}>
        <div className="modal-head">
          <div>
            <h2>{group.word}</h2>
            <p className="description">{group.rows.length} nghĩa · Cấp {level >= 6 ? 'Master' : `${level}/6`}</p>
          </div>
          <button className="icon-button" onClick={onClose} title="Đóng">
            <X size={18} />
          </button>
        </div>

        {message && <div className="notice">{message}</div>}

        <div className="word-action-card">
          <div className="compact-list">
            <MetricRow label="Topic" value={topicName(group.rows[0])} />
            <MetricRow label="Trạng thái học" value={level >= 6 ? 'Master' : `Cấp ${level}/6`} />
            <MetricRow label="Lần ôn tiếp theo" value={formatDate(group.rows.find((row) => row.next_review)?.next_review)} />
            <MetricRow label="Điểm phát âm" value={score == null ? 'Chưa có' : `${score}/100`} />
          </div>
          <div className="button-row">
            <button className="danger-button" onClick={() => onDelete(group.rows)}>
              <Trash2 size={18} />
              Xoá khỏi kho
            </button>
          </div>
        </div>

        {canSubmitWord && (
          <div className="contribution-inline">
            <h3>Gửi từ riêng lên hệ thống</h3>
            <p className="description">Các từ nằm trong topic riêng sẽ được gửi duyệt chung với topic, nên không cần gửi từng từ riêng lẻ.</p>
            {privateRows.map((row) => {
              const catalogId = row.vocab_id ?? row.vocab_catalog?.id ?? '';
              const submission = statusByCatalog[catalogId];
              const disabled = submission?.status === 'pending' || isSubmitting === row.id;
              return (
                <div className="compact-row" key={row.id}>
                  <span>{row.vocab_catalog?.v_meaning || row.vocab_catalog?.ev_meaning || row.vocab_catalog?.e_meaning || 'Từ riêng'}</span>
                  {submission?.status === 'pending' ? (
                    <strong>Chờ duyệt</strong>
                  ) : (
                    <button className="primary-button" disabled={disabled} onClick={() => submitPrivateRow(row)}>
                      {isSubmitting === row.id ? <Loader2 className="spin" size={18} /> : <Send size={18} />}
                      {submission?.status === 'rejected' ? 'Gửi duyệt lại' : 'Gửi duyệt'}
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )}

        <div className="meaning-list">
          {group.rows.map((row, index) => {
            const vocab = row.vocab_catalog;
            const isPrivate = vocab?.visibility === 'private';
            return (
              <article className="meaning-card" key={row.id}>
                <div className="meaning-head">
                  <div className="word-row-title">
                    <strong>Nghĩa {index + 1}</strong>
                    {isPrivate && <span className="status-pill private">Riêng tư</span>}
                    {vocab?.cefr && <span className="count-badge muted">{vocab.cefr}</span>}
                    {vocab?.word_form && <span className="count-badge muted">{vocab.word_form}</span>}
                  </div>
                  {isPrivate && (
                    <button className="icon-button" onClick={() => onEdit(row)} title="Sửa">
                      <Pencil size={17} />
                    </button>
                  )}
                </div>
                <DetailLine label="IPA" value={vocab?.ipa} />
                <DetailLine label="Nghĩa Anh" value={vocab?.e_meaning} tone="blue" />
                <DetailLine label="Anh - Việt" value={vocab?.ev_meaning} />
                <DetailLine label="Nghĩa Việt" value={vocab?.v_meaning} />
                <DetailLine label="Ví dụ Anh" value={vocab?.e_example} tone="blue" />
                <DetailLine label="Ví dụ Việt" value={vocab?.v_example} />
                <DetailLine label="Word family" value={vocab?.word_family} />
                <DetailLine label="Đồng nghĩa" value={vocab?.synonymous} />
                <DetailLine label="Trái nghĩa" value={vocab?.antonym} />
                <DetailLine label="Bonus" value={vocab?.bonus} tone="purple" />
              </article>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function DetailLine({ label, value, tone }: { label: string; value: string | null | undefined; tone?: 'blue' | 'purple' }) {
  return (
    <div className="detail-line">
      <span>{label}</span>
      <p className={tone ? `detail-${tone}` : undefined}>{fieldValue(value)}</p>
    </div>
  );
}

function ContributionTracker({
  wordSubmissions,
  topicSubmissions,
  profile,
  onMessage,
  onReload
}: {
  wordSubmissions: UserVocabSubmission[];
  topicSubmissions: UserTopicSubmission[];
  profile: Profile;
  onMessage: (message: string) => void;
  onReload: () => Promise<void>;
}) {
  async function resubmitWord(submission: UserVocabSubmission) {
    try {
      await userApi.resubmitVocabContribution(submission);
      onMessage('Đã gửi duyệt lại từ riêng.');
      await onReload();
    } catch (err) {
      onMessage(err instanceof Error ? err.message : 'Gửi lại thất bại.');
    }
  }

  async function resubmitTopic(submission: UserTopicSubmission) {
    try {
      await userApi.resubmitTopicSubmission(submission.id);
      onMessage('Đã gửi duyệt lại topic.');
      await onReload();
    } catch (err) {
      onMessage(err instanceof Error ? err.message : 'Gửi lại topic thất bại.');
    }
  }

  async function deleteTopicRequest(submission: UserTopicSubmission) {
    if (!confirm(`Xoá request "${submission.name}"?`)) return;
    try {
      await userApi.deleteRejectedTopicSubmission(submission.id, profile.id);
      onMessage('Đã xoá request topic.');
      await onReload();
    } catch (err) {
      onMessage(err instanceof Error ? err.message : 'Xoá request topic thất bại.');
    }
  }

  if (!wordSubmissions.length && !topicSubmissions.length) return null;

  return (
    <section className="panel contribution-tracker">
      <div className="panel-head">
        <h2>Theo dõi đóng góp</h2>
        <span className="count-badge muted">{wordSubmissions.length + topicSubmissions.length}</span>
      </div>
      <div className="contribution-list">
        {wordSubmissions.map((submission) => (
          <ContributionCard
            key={submission.id}
            title={submission.vocab_catalog?.word ?? 'Từ vựng'}
            subtitle={submission.vocab_catalog?.topics?.name ?? 'Chưa phân loại'}
            status={submission.status}
            date={submission.created_at}
            note={submission.admin_note}
            onResubmit={submission.status === 'rejected' ? () => resubmitWord(submission) : undefined}
          />
        ))}
        {topicSubmissions.map((submission) => (
          <ContributionCard
            key={submission.id}
            title={submission.name}
            subtitle={`${submission.topic_submission_words?.length ?? 0} từ`}
            status={submission.status}
            date={submission.created_at}
            note={submission.admin_note}
            onResubmit={submission.status === 'rejected' ? () => resubmitTopic(submission) : undefined}
            onDelete={submission.status === 'rejected' ? () => deleteTopicRequest(submission) : undefined}
          />
        ))}
      </div>
    </section>
  );
}

function ContributionCard({
  title,
  subtitle,
  status,
  date,
  note,
  onResubmit,
  onDelete
}: {
  title: string;
  subtitle: string;
  status: string;
  date: string | null;
  note?: string | null;
  onResubmit?: () => void;
  onDelete?: () => void;
}) {
  return (
    <article className="contribution-card">
      <div>
        <h3>{title}</h3>
        <p>{subtitle} · {formatDate(date)}</p>
        {note && <small>{note}</small>}
      </div>
      <span className={`status-pill ${status}`}>{status}</span>
      <div className="button-row">
        {onResubmit && (
          <button className="primary-button" onClick={onResubmit}>
            <Send size={18} />
            Gửi lại
          </button>
        )}
        {onDelete && (
          <button className="danger-button" onClick={onDelete}>
            <Trash2 size={18} />
            Xoá
          </button>
        )}
      </div>
    </article>
  );
}

function UserVocabModal({
  title,
  value,
  onClose,
  onSave
}: {
  title: string;
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
    <div className="modal-backdrop" onClick={onClose}>
      <form className="modal-panel" onSubmit={submit} onClick={(event) => event.stopPropagation()}>
        <div className="modal-head">
          <h2>{title}</h2>
          <button type="button" className="icon-button" onClick={onClose} title="Đóng">
            <X size={18} />
          </button>
        </div>
        <div className="form-grid two">
          <label>Từ vựng<input value={draft.word} onChange={(event) => update('word', event.target.value)} /></label>
          <label>CEFR<input value={draft.cefr} onChange={(event) => update('cefr', event.target.value)} /></label>
          <label>IPA<input value={draft.ipa} onChange={(event) => update('ipa', event.target.value)} /></label>
          <label>Loại từ<input value={draft.word_form} onChange={(event) => update('word_form', event.target.value)} /></label>
          <label>Nghĩa Anh<textarea value={draft.e_meaning} onChange={(event) => update('e_meaning', event.target.value)} /></label>
          <label>Nghĩa Anh - Việt<textarea value={draft.ev_meaning} onChange={(event) => update('ev_meaning', event.target.value)} /></label>
          <label>Nghĩa Việt<textarea value={draft.v_meaning} onChange={(event) => update('v_meaning', event.target.value)} /></label>
          <label>Ví dụ Anh<textarea value={draft.e_example} onChange={(event) => update('e_example', event.target.value)} /></label>
          <label>Ví dụ Việt<textarea value={draft.v_example} onChange={(event) => update('v_example', event.target.value)} /></label>
          <label>Word family<textarea value={draft.word_family} onChange={(event) => update('word_family', event.target.value)} /></label>
          <label>Đồng nghĩa<textarea value={draft.synonymous} onChange={(event) => update('synonymous', event.target.value)} /></label>
          <label>Trái nghĩa<textarea value={draft.antonym} onChange={(event) => update('antonym', event.target.value)} /></label>
          <label>Bonus<textarea value={draft.bonus} onChange={(event) => update('bonus', event.target.value)} /></label>
        </div>
        {error && <div className="form-error">{error}</div>}
        <div className="modal-actions">
          <button type="button" className="ghost-button" onClick={onClose}>Hủy</button>
          <button className="primary-button" disabled={isSaving}>
            {isSaving ? <Loader2 className="spin" size={18} /> : <Check size={18} />}
            Lưu
          </button>
        </div>
      </form>
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

export default UserApp;
