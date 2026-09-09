import { useEffect, useRef, useState } from 'react';
import {
  Search,
  FileText,
  BriefcaseBusiness,
  GraduationCap,
  UserRound,
  Plus,
  Settings as SettingsIcon,
  Code2,
  Focus,
  Upload,
  CheckCircle2,
  Menu,
  Mic,
  MicOff,
  Library,
  ArrowLeft,
  History,
  ChevronRight,
  WifiOff,
  RefreshCw,
} from 'lucide-react';
import {
  DEFAULT_LEGAL_METADATA,
  LEGAL_ACCEPTANCE_REQUIRED_EVENT,
  api,
  authClient,
  offlineProductConfig,
  type LegalMetadata,
  type LegalStatus,
  type ProductConfig,
  download,
} from './api';
import { local } from './storage';
import { useNotebook } from './useNotebook';
import type { Page, NotebookDocument } from '../shared/domain';
import { exampleDocument } from './fixtures';
import { Auth } from './components/Auth';
import { Editor } from './components/Editor';
import { Margin } from './components/Margin';
import { Modal } from './components/Modal';
import { Preparation } from './components/Preparation';
import { Settings } from './components/Settings';
import { Exports } from './components/Exports';
import { PrintDocument } from './components/PrintDocument';
import { Brand } from './components/Brand';
import { LiveCapture } from './components/LiveCapture';
import { LegalAcceptance } from './components/LegalAcceptance';
import { LegalDocument } from './components/LegalDocument';
import { CAPTURE_PAGE_EXIT_MESSAGE, runWithPageExitGuard } from './pageExit';

type Identity = { id: string; name: string; email: string };
export default function App() {
  const pathname = window.location.pathname.replace(/\/+$/, '') || '/';
  if (pathname === '/terms') return <LegalDocument kind="terms" />;
  if (pathname === '/privacy') return <LegalDocument kind="privacy" />;
  return <NotebookRoot />;
}
function NotebookRoot() {
  const [config, setConfig] = useState<ProductConfig | null>(null),
    [identity, setIdentity] = useState<Identity | null>(null),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(''),
    [legal, setLegal] = useState<LegalMetadata>(DEFAULT_LEGAL_METADATA),
    [legalAccepted, setLegalAccepted] = useState<boolean | null>(null),
    [legalError, setLegalError] = useState(''),
    [capturePageExitActive, setCapturePageExitActive] = useState(false),
    [legalReacceptPending, setLegalReacceptPending] = useState(false),
    [accountNotice, setAccountNotice] = useState('');
  const capturePageExitActiveRef = useRef(false);
  useEffect(() => {
    const requireCurrentTerms = (event: Event) => {
      const metadata = (event as CustomEvent<LegalMetadata>).detail;
      if (!metadata) return;
      setLegal(metadata);
      setConfig((current) => (current ? { ...current, legal: metadata } : current));
      if (capturePageExitActiveRef.current) setLegalReacceptPending(true);
      else setLegalAccepted(false);
      setLegalError('The Terms of Service changed. Review the current version to continue.');
      if (identity) void local.acceptedLegalVersion(identity.id, null).catch(() => undefined);
    };
    window.addEventListener(LEGAL_ACCEPTANCE_REQUIRED_EVENT, requireCurrentTerms);
    return () => window.removeEventListener(LEGAL_ACCEPTANCE_REQUIRED_EVENT, requireCurrentTerms);
  }, [identity]);
  useEffect(() => {
    if (!legalReacceptPending || capturePageExitActive) return;
    setLegalReacceptPending(false);
    setLegalAccepted(false);
  }, [capturePageExitActive, legalReacceptPending]);
  async function restoreLegalStatus(user: Identity, fallback: LegalMetadata) {
    setLegal(fallback);
    try {
      const status = await api<LegalStatus>('/legal/status');
      setLegal(status.legal);
      setLegalAccepted(status.accepted);
      setLegalError('');
      await local
        .acceptedLegalVersion(user.id, status.accepted ? status.legal.termsVersion : null)
        .catch(() => undefined);
    } catch {
      const cachedVersion = await local.acceptedLegalVersion(user.id).catch(() => null);
      if (cachedVersion === fallback.termsVersion) {
        setLegalAccepted(true);
        setLegalError('');
      } else {
        setLegalAccepted(false);
        setLegalError(
          'We could not confirm your acceptance. Reconnect, review the current terms, and try again.',
        );
      }
    }
  }
  async function boot() {
    setLoading(true);
    setError('');
    setAccountNotice('');
    setLegalError('');
    setLegalAccepted(null);
    let fetchedConfig: ProductConfig | null = config;
    try {
      const settings = await api<ProductConfig>('/config');
      const currentLegal = settings.legal || DEFAULT_LEGAL_METADATA;
      fetchedConfig = { ...settings, legal: currentLegal };
      setLegal(currentLegal);
      setConfig(fetchedConfig);
      document.title = settings.name;
      const result = await authClient.getSession();
      if (result.error) throw new Error('Session unavailable');
      setIdentity(result.data?.user || null);
      if (result.data?.user) {
        await local.identity(result.data.user);
        await restoreLegalStatus(result.data.user, currentLegal);
      } else {
        await local.identity(null);
        setLegalAccepted(null);
      }
    } catch {
      const cached = await local.identity();
      if (cached) {
        setIdentity(cached);
        const offlineConfig = offlineProductConfig(fetchedConfig);
        setConfig(offlineConfig);
        setLegal(offlineConfig.legal);
        const cachedVersion = await local.acceptedLegalVersion(cached.id).catch(() => null);
        setLegalAccepted(cachedVersion === offlineConfig.legal.termsVersion);
        if (cachedVersion !== offlineConfig.legal.termsVersion)
          setLegalError(
            'Connect to the internet to review and accept the current terms before continuing.',
          );
      } else setError('The notebook server is unavailable. Start the local server, then retry.');
    } finally {
      setLoading(false);
    }
  }
  async function clearAccountState(userId: string, deleted = false) {
    capturePageExitActiveRef.current = false;
    setCapturePageExitActive(false);
    setLegalReacceptPending(false);
    setIdentity(null);
    setLegalAccepted(null);
    setLegalError('');
    try {
      await local.clear(userId);
    } catch {
      setAccountNotice(
        deleted
          ? 'Your Sideleaf account was deleted, but this browser could not clear its offline copy. Clear Sideleaf site data before sharing this device.'
          : 'You are signed out, but this browser could not clear its offline copy. Clear Sideleaf site data before sharing this device.',
      );
    }
  }
  async function signOut(userId: string) {
    const result = await authClient.signOut();
    if (result.error) throw new Error('Sign-out failed. Reconnect and try again.');
    await clearAccountState(userId);
  }
  useEffect(() => {
    void boot();
  }, []);
  if (loading)
    return (
      <div className="loading">
        <Brand variant="icon" />
        <p>Opening your notebook…</p>
      </div>
    );
  if (error || !config)
    return (
      <div className="loading">
        <Brand variant="icon" />
        <p role="alert">{error}</p>
        <button onClick={boot}>Try again</button>
      </div>
    );
  if (!identity) return <Auth config={config} onDone={boot} accountNotice={accountNotice} />;
  if (legalAccepted === null)
    return (
      <div className="loading">
        <Brand variant="icon" />
        <p>Checking your agreements…</p>
      </div>
    );
  if (!legalAccepted)
    return (
      <LegalAcceptance
        key={legal.termsVersion}
        config={config}
        identity={identity}
        legal={legal}
        initialError={legalError}
        onLogout={() => signOut(identity.id)}
        onDeleted={() => clearAccountState(identity.id, true)}
        onAccepted={async (status) => {
          await local
            .acceptedLegalVersion(identity.id, status.legal.termsVersion)
            .catch(() => undefined);
          setLegal(status.legal);
          setLegalError('');
          setLegalAccepted(true);
        }}
      />
    );
  return (
    <NotebookApp
      key={identity.id}
      config={config}
      identity={identity}
      onLogout={() => signOut(identity.id)}
      onDeleted={() => clearAccountState(identity.id, true)}
      requiredPageExitNotice={
        legalReacceptPending
          ? 'The Terms of Service changed. Finish live transcription and resolve any unconfirmed text; then you’ll be asked to review the new terms.'
          : ''
      }
      onCaptureActiveChange={(active) => {
        capturePageExitActiveRef.current = active;
        setCapturePageExitActive(active);
      }}
    />
  );
}
function NotebookApp({
  config,
  identity,
  onLogout,
  onDeleted,
  requiredPageExitNotice,
  onCaptureActiveChange,
}: {
  config: ProductConfig;
  identity: Identity;
  onLogout: () => Promise<void>;
  onDeleted: () => Promise<void>;
  requiredPageExitNotice: string;
  onCaptureActiveChange: (active: boolean) => void;
}) {
  const book = useNotebook(identity.id);
  const [selected, setSelected] = useState<string | null>(null),
    [filter, setFilter] = useState<string | null>(null),
    [search, setSearch] = useState(''),
    [focus, setFocus] = useState(false),
    [captureActive, setCaptureActive] = useState(false),
    [microphoneLive, setMicrophoneLive] = useState(false),
    [mobileNav, setMobileNav] = useState(false),
    [mobileTab, setMobileTab] = useState('page');
  const [dialog, setDialog] = useState<
      'prepare' | 'settings' | 'export' | 'new-notebook' | 'delete' | 'history' | null
    >(() =>
      ['success', 'canceled', 'returned'].includes(
        new URLSearchParams(window.location.search).get('billing') || '',
      )
        ? 'settings'
        : null,
    ),
    [name, setName] = useState(''),
    [error, setError] = useState(''),
    [pageExitNotice, setPageExitNotice] = useState('');
  const [history, setHistory] = useState<
    { version: number; title: string; document: NotebookDocument; createdAt: string }[]
  >([]);
  const record = book.records.find((r) => r.page.id === selected),
    page = record?.page;
  const notebook = book.notebooks.find((n) => n.id === page?.notebookId);
  const pageSynced = Boolean(
    record &&
    page?.version &&
    !record.mutationId &&
    record.conflict === undefined &&
    !book.saving &&
    !book.error,
  );
  const captureReady = config.capture.ready && book.online && (captureActive || pageSynced);
  const captureReason = !config.capture.ready
    ? config.capture.reason
    : !book.online
      ? 'Reconnect to the internet to start live transcription. You can keep writing notes offline.'
      : 'Wait for this page to finish syncing before starting live transcription.';
  useEffect(() => {
    if (!captureActive) setPageExitNotice('');
  }, [captureActive]);
  function leavePage(action: () => void) {
    return runWithPageExitGuard(captureActive, setPageExitNotice, action);
  }
  function requirePageExit() {
    if (!captureActive) {
      setPageExitNotice('');
      return;
    }
    setPageExitNotice(CAPTURE_PAGE_EXIT_MESSAGE);
    throw new Error(CAPTURE_PAGE_EXIT_MESSAGE);
  }
  function updateCaptureActive(active: boolean) {
    setCaptureActive(active);
    onCaptureActiveChange(active);
  }
  async function run(fn: () => Promise<unknown>) {
    try {
      setError('');
      await fn();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unable to complete the operation.');
    }
  }
  async function createPage(example = false) {
    if (!leavePage(() => undefined)) return;
    let target = filter || book.notebooks[0]?.id;
    if (!target) target = (await book.addNotebook('Work')).id;
    const p = await book.addPage(
      target,
      example ? 'Project conversation (example)' : 'Untitled page',
      example ? exampleDocument() : undefined,
    );
    setSelected(p.id);
    setMobileNav(false);
  }
  function open(id: string) {
    leavePage(() => {
      setSelected(id);
      setMobileTab('page');
      setMobileNav(false);
    });
  }
  const filtered = book.records
    .filter(
      (r) =>
        (!filter || r.page.notebookId === filter) &&
        (!search ||
          `${r.page.title} ${r.page.document.blocks.map((b) => b.text).join(' ')}`
            .toLowerCase()
            .includes(search.toLowerCase())),
    )
    .sort((a, b) => b.page.updatedAt.localeCompare(a.page.updatedAt));
  return (
    <div className={`app ${focus ? 'focus-mode' : ''} ${mobileNav ? 'nav-open' : ''}`}>
      <aside className="sidebar">
        <button
          className="brand"
          onClick={() =>
            leavePage(() => {
              setSelected(null);
              setFilter(null);
            })
          }
        >
          <Brand name={config.name} />
        </button>
        <label className="search">
          <Search size={18} />
          <input
            placeholder="Search notes"
            aria-label="Search notes"
            value={search}
            onChange={(e) =>
              leavePage(() => {
                setSearch(e.target.value);
                setSelected(null);
              })
            }
          />
        </label>
        <div className="nav-label">Notebooks</div>
        <nav>
          <button
            className={!selected && !filter ? 'active' : ''}
            onClick={() =>
              leavePage(() => {
                setSelected(null);
                setFilter(null);
                setMobileNav(false);
              })
            }
          >
            <FileText />
            All pages
          </button>
          {book.notebooks.map((n, i) => {
            const Icon = i === 0 ? BriefcaseBusiness : i === 1 ? GraduationCap : UserRound;
            return (
              <button
                key={n.id}
                className={(page ? page.notebookId === n.id : filter === n.id) ? 'active' : ''}
                onClick={() =>
                  leavePage(() => {
                    setFilter(n.id);
                    setSelected(null);
                    setMobileNav(false);
                  })
                }
              >
                <Icon />
                {n.name}
              </button>
            );
          })}
          <button
            className="new-notebook"
            onClick={() =>
              leavePage(() => {
                setName('');
                setDialog('new-notebook');
              })
            }
          >
            <Plus />
            New notebook
          </button>
        </nav>
        <div className="sidebar-bottom">
          <button onClick={() => setDialog('settings')}>
            <SettingsIcon size={20} />
            Settings
          </button>
          <small>
            <Code2 size={17} />
            {config.development ? 'Local development' : identity.name}
          </small>
        </div>
      </aside>
      {mobileNav && (
        <button
          className="nav-scrim"
          aria-label="Close navigation"
          onClick={() => setMobileNav(false)}
        />
      )}
      <div className="workspace">
        <header className="topbar">
          <button
            className="icon-button mobile-menu"
            aria-label="Open navigation"
            onClick={() => setMobileNav(!mobileNav)}
          >
            <Menu size={21} />
          </button>
          <div className="breadcrumb">
            <button
              onClick={() =>
                leavePage(() => {
                  setSelected(null);
                  if (page) setFilter(page.notebookId);
                })
              }
            >
              {notebook?.name ||
                book.notebooks.find((n) => n.id === filter)?.name ||
                'Your notebooks'}
            </button>
            <span>/</span>
            <span>{page ? 'Notebook' : 'All pages'}</span>
          </div>
          <div className="top-actions">
            <span className="sync-status" role="status">
              {!book.online ? <WifiOff size={17} /> : <CheckCircle2 size={17} />}
              <span>
                {record?.deviceState === 'failed'
                  ? 'Device save failed'
                  : record?.deviceState === 'saving'
                    ? 'Saving to device…'
                    : !book.online
                      ? 'Saved on device'
                      : book.saving
                        ? 'Saving…'
                        : record?.conflict !== undefined
                          ? 'Review conflict'
                          : record?.mutationId
                            ? 'Saved on device'
                            : 'Saved'}
              </span>
            </span>
            <span
              className={`mic-status ${microphoneLive ? 'live' : ''}`}
              title={microphoneLive ? 'Your microphone is live' : 'Your microphone is off'}
              aria-label={microphoneLive ? 'Your microphone is live' : 'Your microphone is off'}
            >
              {microphoneLive ? <Mic size={17} /> : <MicOff size={17} />}
              <span>{microphoneLive ? 'Mic live' : 'Mic off'}</span>
            </span>
            {page && (
              <>
                <button
                  aria-label={focus ? 'Exit focus' : 'Focus'}
                  aria-pressed={focus}
                  onClick={() => setFocus(!focus)}
                >
                  <Focus size={18} />
                  <span>{focus ? 'Exit focus' : 'Focus'}</span>
                </button>
                <button aria-label="Export" onClick={() => setDialog('export')}>
                  <Upload size={18} />
                  <span>Export</span>
                </button>
              </>
            )}
          </div>
        </header>
        {(requiredPageExitNotice || pageExitNotice) && (
          <div className="status-banner" role="alert" aria-atomic="true">
            <span>{requiredPageExitNotice || pageExitNotice}</span>
            {!requiredPageExitNotice && (
              <button className="text-button" onClick={() => setPageExitNotice('')}>
                Dismiss
              </button>
            )}
          </div>
        )}
        {(book.error || error) && (
          <div className="status-banner" role="status">
            {error || book.error}
            <button className="text-button" onClick={() => void book.sync()}>
              <RefreshCw size={14} />
              Retry sync
            </button>
          </div>
        )}
        {!book.ready ? (
          <div className="loading">
            <Brand variant="icon" />
            <p>Loading your pages…</p>
          </div>
        ) : page ? (
          <>
            <div className="page-navigation">
              <button className="text-button" onClick={() => leavePage(() => setSelected(null))}>
                <ArrowLeft size={15} />
                Back to pages
              </button>
              <button
                className="text-button"
                onClick={() =>
                  run(async () => {
                    setHistory(await api(`/pages/${page.id}/history`));
                    setDialog('history');
                  })
                }
              >
                <History size={15} />
                Version history
              </button>
            </div>
            {record?.conflict !== undefined && (
              <div className="conflict-banner">
                <div>
                  <strong>There’s another saved version.</strong>
                  <p>Your edits are safe on this device. Keep both versions to compare them.</p>
                </div>
                <button
                  onClick={() =>
                    leavePage(
                      () =>
                        void run(async () => {
                          const copy = await book.resolveConflict(page.id, 'copy');
                          if (copy) open(copy.id);
                        }),
                    )
                  }
                >
                  Keep both versions
                </button>
                <button
                  onClick={() =>
                    run(async () => {
                      download(
                        JSON.stringify(page, null, 2),
                        'recovered-draft.json',
                        'application/json',
                      );
                      await book.resolveConflict(page.id, 'server');
                    })
                  }
                >
                  Download draft, use server version
                </button>
              </div>
            )}
            <div className="mobile-tabs">
              <button
                className={mobileTab === 'page' ? 'active' : ''}
                onClick={() => setMobileTab('page')}
              >
                Notebook
              </button>
              <button
                className={mobileTab === 'margin' ? 'active' : ''}
                onClick={() => setMobileTab('margin')}
              >
                Preparation & follow-ups
              </button>
            </div>
            <div className={`notebook-layout mobile-${mobileTab}`}>
              <div className="notebook-main">
                {page.version > 0 ? (
                  <LiveCapture
                    key={`capture-${page.id}`}
                    pageId={page.id}
                    ready={captureReady}
                    reason={captureReason}
                    onActiveChange={updateCaptureActive}
                    onMicrophoneChange={setMicrophoneLive}
                  />
                ) : (
                  <div className="notice" role="status">
                    Live transcription will be available after this page is saved.
                  </div>
                )}
                <Editor
                  key={`editor-${page.id}`}
                  page={page}
                  onChange={(p) => void book.edit(p)}
                  onDelete={() => leavePage(() => setDialog('delete'))}
                />
              </div>
              <Margin
                page={page}
                microphoneLive={microphoneLive}
                onPrepare={() => setDialog('prepare')}
                onChange={(p) => void book.edit(p)}
              />
            </div>
          </>
        ) : (
          <main className="library">
            <div className="library-heading">
              <div>
                <h1>
                  {search
                    ? 'Search your notes'
                    : filter
                      ? book.notebooks.find((n) => n.id === filter)?.name
                      : 'Your notebooks'}
                </h1>
                <p>
                  {search
                    ? `Results for “${search}”`
                    : 'Room for a thought. Space for a conversation.'}
                </p>
              </div>
              <button className="primary" onClick={() => run(() => createPage())}>
                <Plus size={18} />
                New page
              </button>
            </div>
            {filtered.length ? (
              <div className="page-list">
                {filtered.map(({ page: p, mutationId }) => (
                  <button className="page-row" key={p.id} onClick={() => open(p.id)}>
                    <FileText size={23} strokeWidth={1.3} />
                    <div>
                      <h3>{p.title || 'Untitled page'}</h3>
                      <p>
                        {p.document.blocks.find((b) => b.kind === 'paragraph' && b.text)?.text ||
                          'A little blank space, ready for you.'}
                      </p>
                      <small>
                        {book.notebooks.find((n) => n.id === p.notebookId)?.name} ·{' '}
                        {new Date(p.updatedAt).toLocaleDateString()} ·{' '}
                        {p.document.meetingState === 'prepared'
                          ? 'Prepared meeting'
                          : 'Personal notes'}
                        {mutationId ? ' · Pending sync' : ''}
                      </small>
                    </div>
                    <ChevronRight size={18} />
                  </button>
                ))}
              </div>
            ) : (
              <div className="empty-library">
                <Library size={45} strokeWidth={1.1} />
                <h2>{search ? 'No matching notes' : 'The next page is yours.'}</h2>
                <p>
                  {search
                    ? 'Search covers typed text. Handwriting is not searched.'
                    : 'Write, sketch, and gather your thoughts.\nStart a page before you start a meeting.'}
                </p>
                {!search && (
                  <>
                    <button onClick={() => run(() => createPage())}>Create a blank page</button>
                    {config.development && (
                      <button className="text-button" onClick={() => run(() => createPage(true))}>
                        Open a synthetic example
                      </button>
                    )}
                  </>
                )}
              </div>
            )}
            <div className="library-note">
              <MicOff size={16} />
              <p>Your microphone is off. Ordinary notes are always available.</p>
            </div>
          </main>
        )}
      </div>
      {dialog === 'prepare' && page && (
        <Preparation
          page={page}
          config={config}
          onSave={(p) => void book.edit(p)}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog === 'settings' && (
        <Settings
          onDeleted={onDeleted}
          config={config}
          email={identity.email}
          userId={identity.id}
          onClose={() => {
            setDialog(null);
            const url = new URL(window.location.href);
            url.searchParams.delete('billing');
            window.history.replaceState(window.history.state, '', url);
          }}
          beforePageExit={requirePageExit}
          onLogout={async () => {
            requirePageExit();
            await book.sync();
            requirePageExit();
            if (book.hasPending())
              throw new Error(
                'Some drafts are not synced. Export or resolve them before signing out.',
              );
            await onLogout();
          }}
        />
      )}
      {dialog === 'export' && page && <Exports page={page} onClose={() => setDialog(null)} />}
      {dialog === 'new-notebook' && (
        <Modal title="A new notebook" onClose={() => setDialog(null)}>
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (!leavePage(() => undefined)) return;
              void run(async () => {
                const n = await book.addNotebook(name);
                setFilter(n.id);
                setSelected(null);
                setDialog(null);
              });
            }}
          >
            <label>
              Notebook name
              <input
                autoFocus
                value={name}
                maxLength={80}
                required
                onChange={(e) => setName(e.target.value)}
                placeholder="Work, learning, ideas…"
              />
            </label>
            <div className="modal-actions">
              <button className="primary">Create notebook</button>
            </div>
            {error && <p className="error">{error}</p>}
          </form>
        </Modal>
      )}
      {dialog === 'delete' && page && (
        <Modal title="Delete this page?" onClose={() => setDialog(null)}>
          <p>
            “{page.title}” and its saved versions will be deleted from the active database. This
            cannot be undone here.
          </p>
          <div className="modal-actions">
            <button onClick={() => setDialog(null)}>Keep page</button>
            <button
              className="danger"
              onClick={() =>
                leavePage(
                  () =>
                    void run(async () => {
                      await book.deletePage(page.id);
                      setDialog(null);
                      setSelected(null);
                    }),
                )
              }
            >
              Delete page and history
            </button>
          </div>
          {error && <p className="error">{error}</p>}
        </Modal>
      )}
      {dialog === 'history' && page && (
        <Modal title="Saved versions" onClose={() => setDialog(null)}>
          <p className="muted">
            Restore a version as a new page to preserve your current notes. The latest 50 versions
            are shown.
          </p>
          {history.map((h) => (
            <div className="history-row" key={h.version}>
              <div>
                <strong>Version {h.version}</strong>
                <small>{new Date(h.createdAt).toLocaleString()}</small>
              </div>
              <button
                onClick={() =>
                  leavePage(
                    () =>
                      void run(async () => {
                        const p = await book.addPage(
                          page.notebookId,
                          `${h.title} (version ${h.version})`,
                          h.document,
                        );
                        setSelected(p.id);
                        setDialog(null);
                      }),
                  )
                }
              >
                Restore as copy
              </button>
            </div>
          ))}
        </Modal>
      )}
      {page && <PrintDocument page={page} />}
    </div>
  );
}
