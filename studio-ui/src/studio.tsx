/// <reference path="./react-global.d.ts" />

const API_BASE = "/studio/api/v1";
const INITIAL_MANUSCRIPT = "";
const COVER_PALETTE = [
  { color: "#713D3B", edge: "#512C2A", foil: "#C9A77F", label: "酒红" },
  { color: "#354B40", edge: "#26382F", foil: "#C6B58D", label: "森林绿" },
  { color: "#34404C", edge: "#27323D", foil: "#BFB18D", label: "藏蓝" },
  { color: "#805D3E", edge: "#5D432F", foil: "#D4B98D", label: "焦糖棕" },
  { color: "#59483A", edge: "#3D3027", foil: "#C1A77C", label: "胡桃棕" },
  { color: "#7A4E48", edge: "#5A3934", foil: "#D0B194", label: "陶土红" },
];

type Envelope<T> = { data: T };
type ApiErrorPayload = { error?: { code?: string; message?: string; current_revision?: number } };
interface Workplace {
  id: string; title: string; description: string; cover_color: string;
  cover_asset_id: string | null; document_count: number; created_at: string;
  updated_at: string; last_opened_at: string | null; archived_at: string | null;
}
interface StudioDocument {
  id: string; workplace_id: string; parent_id: string | null;
  kind: "manuscript" | "chapter" | "outline" | "note";
  title: string; content?: string; content_format: "markdown"; revision: number;
  sort_order: number; word_count: number; created_at: string; updated_at: string;
}
interface VersionEntry {
  id: string; document_id: string; revision: number; title: string;
  label: string | null; source: string; created_at: string; content?: string;
}
interface Capabilities {
  api_version: number; storage: string; engine: string; default_model: string | null;
  models: { id: string; name: string; size: number }[]; ai_available: boolean;
}
interface PageSpread { left: string; right: string }
type Section = "writing" | "characters" | "scenes" | "assets" | "settings";
type SaveState = "已保存" | "正在保存…" | "版本冲突" | "保存失败" | "AI 生成中";

class StudioApiError extends Error {
  status: number;
  code: string;
  payload: ApiErrorPayload;
  currentRevision?: number;
  constructor(status: number, payload: ApiErrorPayload | null) {
    const detail = payload?.error || {};
    super(detail.message || `HTTP ${status}`);
    this.status = status;
    this.code = detail.code || "REQUEST_FAILED";
    this.payload = payload || {};
    this.currentRevision = detail.current_revision;
  }
}

async function api<T>(path: string, options: { method?: string; body?: unknown; signal?: AbortSignal } = {}): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    method: options.method || "GET",
    headers: options.body !== undefined ? { "Content-Type": "application/json" } : undefined,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    signal: options.signal,
  });
  let payload: any = null;
  try { payload = await response.json(); } catch { payload = null; }
  if (!response.ok) throw new StudioApiError(response.status, payload);
  return payload?.data as T;
}

function escapeHtml(value: string): string {
  return String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
function inlineMarkdown(value: string): string {
  return escapeHtml(value)
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
}
function markdownToHtml(markdown: string): string {
  const chunks = String(markdown || "").replace(/\r\n/g, "\n").split(/\n{2,}/).map(x => x.trim()).filter(Boolean);
  if (!chunks.length) return "<p><br></p>";
  return chunks.map(chunk => {
    const heading = /^(#{1,6})\s+(.*)$/.exec(chunk);
    if (heading) return `<h${heading[1].length}>${inlineMarkdown(heading[2])}</h${heading[1].length}>`;
    const lines = chunk.split("\n");
    if (lines.every(line => /^[-*]\s+/.test(line))) return `<ul>${lines.map(line => `<li>${inlineMarkdown(line.replace(/^[-*]\s+/, ""))}</li>`).join("")}</ul>`;
    if (lines.every(line => /^>\s?/.test(line))) return `<blockquote>${lines.map(line => inlineMarkdown(line.replace(/^>\s?/, ""))).join("<br>")}</blockquote>`;
    return `<p>${lines.map(inlineMarkdown).join("<br>")}</p>`;
  }).join("");
}
function htmlToMarkdown(html: string): string {
  const holder = document.createElement("div");
  holder.innerHTML = html || "";
  const blocks = Array.from(holder.children).map(element => {
    const text = (element as HTMLElement).innerText || element.textContent || "";
    const clean = text.replace(/\u00a0/g, " ").trim();
    if (!clean) return "";
    const tag = element.tagName.toLowerCase();
    if (/^h[1-6]$/.test(tag)) return `${"#".repeat(Number(tag[1]))} ${clean}`;
    if (tag === "li") return `- ${clean}`;
    if (tag === "ul" || tag === "ol") return Array.from(element.querySelectorAll("li")).map(item => `- ${(item as HTMLElement).innerText.trim()}`).join("\n");
    if (tag === "blockquote") return clean.split("\n").map(line => `> ${line}`).join("\n");
    return clean;
  });
  return blocks.filter(Boolean).join("\n\n");
}
function pagePlainText(html: string): string {
  const holder = document.createElement("div");
  holder.innerHTML = html || "";
  return (holder.innerText || holder.textContent || "").trim();
}
function paginate(markdown: string): string[] {
  const html = markdownToHtml(markdown);
  const holder = document.createElement("div");
  holder.innerHTML = html;
  const blocks = Array.from(holder.children);
  if (!blocks.length) return ["<p><br></p>"];
  const pages: string[] = [];
  let page = "";
  let length = 0;
  blocks.forEach(block => {
    const blockLength = ((block as HTMLElement).innerText || "").length;
    if (page && length + blockLength > 620) {
      pages.push(page); page = ""; length = 0;
    }
    page += (block as HTMLElement).outerHTML;
    length += blockLength;
  });
  if (page) pages.push(page);
  return pages.length ? pages : ["<p><br></p>"];
}
function countWords(value: string): number {
  const text = value || "";
  const cjk = (text.match(/[\u2E80-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]/g) || []).length;
  const rest = text.replace(/[\u2E80-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]/g, " ");
  const words = (rest.match(/[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*/g) || []).length;
  return cjk + words;
}
function fmtDate(value?: string | null): string {
  if (!value) return "尚未打开";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit" }).format(date);
}
function folio(value: number): string { return `— ${String(value).padStart(3, "0")} —`; }
function colorMeta(color: string) { return COVER_PALETTE.find(item => item.color.toLowerCase() === (color || "").toLowerCase()) || COVER_PALETTE[0]; }

function Icon({ name }: { name: string }) {
  const paths: Record<string, string> = {
    book: "M4 5.5A2.5 2.5 0 0 1 6.5 3H20v17H6.5A2.5 2.5 0 0 0 4 22z M4 5.5V22 M8 7h8 M8 11h8",
    pen: "M12 20h9 M16.5 3.5a2.12 2.12 0 0 1 3 3L8 18l-4 1 1-4Z",
    users: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8 M20 8v6 M23 11h-6",
    scene: "M3 4h18v13H3z M8 21h8 M12 17v4 M7 12l3-3 3 3 2-2 3 3",
    images: "M4 4h16v16H4z M4 15l5-5 4 4 3-3 4 4 M9 8h.01",
    settings: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M19.4 15a1.7 1.7 0 0 0 .34 1.87l.06.06-1.7 2.94-.08-.03a1.7 1.7 0 0 0-1.83.18l-.07.05h-3.4l-.07-.05a1.7 1.7 0 0 0-1.83-.18l-.08.03-1.7-2.94.06-.06A1.7 1.7 0 0 0 9.4 15l-.02-.08v-3.4l.02-.08a1.7 1.7 0 0 0-.34-1.87L9 9.51l1.7-2.94.08.03a1.7 1.7 0 0 0 1.83-.18l.07-.05h3.4l.07.05a1.7 1.7 0 0 0 1.83.18l.08-.03 1.7 2.94-.06.06a1.7 1.7 0 0 0-.34 1.87l.02.08v3.4z",
    lightbulb: "M9 18h6 M10 22h4 M8.5 14.5a6 6 0 1 1 7 0c-.8.6-1.2 1.4-1.4 2.5H9.9c-.2-1.1-.6-1.9-1.4-2.5Z M12 2v2 M4.9 4.9l1.4 1.4 M19.1 4.9l-1.4 1.4",
    sparkle: "m12 3 1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7z M19 17l.7 2.3L22 20l-2.3.7L19 23l-.7-2.3L16 20l2.3-.7z",
    history: "M3 12a9 9 0 1 0 2.64-6.36L3 8 M3 3v5h5 M12 7v5l3 2",
    close: "M18 6 6 18 M6 6l12 12",
    plus: "M12 5v14 M5 12h14",
    back: "M19 12H5 M12 19l-7-7 7-7",
    next: "M5 12h14 M12 5l7 7-7 7",
  };
  return <svg className="icon" viewBox="0 0 24 24" aria-hidden="true"><path d={paths[name] || paths.sparkle}/></svg>;
}

function Modal({ title, eyebrow, children, actions, onClose, className = "" }: {
  title: string; eyebrow?: string; children?: any; actions?: any; onClose: () => void; className?: string;
}) {
  React.useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);
  return <div className="modal-scrim" onMouseDown={(event: any) => { if (event.target === event.currentTarget) onClose(); }}>
    <section className={`modal ${className}`} role="dialog" aria-modal="true">
      <div className="modal-head"><div><div className="eyebrow">{eyebrow || "KHALA STUDIO"}</div><h2>{title}</h2></div><button className="icon-button close-modal" onClick={onClose} aria-label="关闭"><Icon name="close"/></button></div>
      <div className="modal-body">{children}</div>
      {actions && <div className="modal-actions">{actions}</div>}
    </section>
  </div>;
}

function App() {
  const [screen, setScreen] = React.useState<"loading" | "shelf" | "opening" | "workplace" | "closing">("loading");
  const [section, setSection] = React.useState<Section>("writing");
  const [capabilities, setCapabilities] = React.useState<Capabilities | null>(null);
  const [workplaces, setWorkplaces] = React.useState<Workplace[]>([]);
  const [workplace, setWorkplace] = React.useState<Workplace | null>(null);
  const [documents, setDocuments] = React.useState<StudioDocument[]>([]);
  const [activeDocument, setActiveDocument] = React.useState<StudioDocument | null>(null);
  const [pages, setPages] = React.useState<string[]>(["<p><br></p>"]);
  const [spread, setSpread] = React.useState(0);
  const [mode, setMode] = React.useState<"write" | "read">("write");
  const [saveState, setSaveState] = React.useState<SaveState>("已保存");
  const [conflict, setConflict] = React.useState(false);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState("");
  const [modal, setModal] = React.useState<"create-book" | "create-document" | "contents" | "inspire" | "continue" | "versions" | null>(null);
  const [bookTitle, setBookTitle] = React.useState("");
  const [bookDescription, setBookDescription] = React.useState("");
  const [bookColor, setBookColor] = React.useState(COVER_PALETTE[0].color);
  const [docTitle, setDocTitle] = React.useState("");
  const [docKind, setDocKind] = React.useState<StudioDocument["kind"]>("chapter");
  const [versionList, setVersionList] = React.useState<VersionEntry[]>([]);
  const [inspiration, setInspiration] = React.useState("");
  const [inspireBusy, setInspireBusy] = React.useState(false);
  const [continuation, setContinuation] = React.useState("");
  const [continueBusy, setContinueBusy] = React.useState(false);
  const [continueError, setContinueError] = React.useState("");
  const [selectedModel, setSelectedModel] = React.useState<string>(() => localStorage.getItem("khala.studio.model") || "");
  const [editorFontSize, setEditorFontSize] = React.useState<number>(() => Number(localStorage.getItem("khala.studio.fontSize") || 17));
  const [defaultCover, setDefaultCover] = React.useState<string>(() => localStorage.getItem("khala.studio.coverColor") || COVER_PALETTE[0].color);
  const [toast, setToast] = React.useState("");
  const [savedRange, setSavedRange] = React.useState<Range | null>(null);
  const [turnDirection, setTurnDirection] = React.useState<"next" | "prev" | null>(null);
  const [openingTitle, setOpeningTitle] = React.useState("");
  const [openingColor, setOpeningColor] = React.useState(COVER_PALETTE[0].color);
  const [openingFoil, setOpeningFoil] = React.useState(COVER_PALETTE[0].foil);
  const [lastError, setLastError] = React.useState("");

  const pageHtmlRef = React.useRef<string[]>(["<p><br></p>"]);
  const editorRefs = React.useRef<Record<number, HTMLDivElement | null>>({});
  const activePageIndexRef = React.useRef(1);
  const saveTimerRef = React.useRef<any>(null);
  const savePromiseRef = React.useRef<Promise<void> | null>(null);
  const latestRef = React.useRef({ workplace: null as Workplace | null, document: null as StudioDocument | null, revision: 1, conflict: false, saveState: "已保存" as SaveState });
  const continueAbortRef = React.useRef<AbortController | null>(null);
  const continuationRef = React.useRef("");
  const turnTimerRef = React.useRef<any>(null);
  const toastTimerRef = React.useRef<any>(null);
  const savedRangeRef = React.useRef<Range | null>(null);

  React.useEffect(() => {
    latestRef.current.workplace = workplace;
    latestRef.current.document = activeDocument;
    latestRef.current.conflict = conflict;
    latestRef.current.saveState = saveState;
    latestRef.current.revision = activeDocument?.revision || 1;
  }, [workplace, activeDocument, conflict, saveState]);

  React.useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const [caps, books] = await Promise.all([
          api<Capabilities>("/capabilities"),
          api<Workplace[]>("/workplaces"),
        ]);
        if (!alive) return;
        setCapabilities(caps);
        setWorkplaces(books);
        if (!selectedModel && caps.default_model) setSelectedModel(caps.default_model);
        setScreen("shelf");
      } catch (cause: any) {
        if (!alive) return;
        setError(cause?.message || "无法连接 Studio API");
        setScreen("shelf");
      }
    })();
    return () => { alive = false; };
  }, []);

  React.useEffect(() => {
    if (!toast) return;
    clearTimeout(toastTimerRef.current);
    toastTimerRef.current = setTimeout(() => setToast(""), 2400);
    return () => clearTimeout(toastTimerRef.current);
  }, [toast]);

  React.useEffect(() => {
    return () => {
      clearTimeout(saveTimerRef.current);
      clearTimeout(turnTimerRef.current);
      if (continueAbortRef.current) continueAbortRef.current.abort();
    };
  }, []);

  function notify(message: string) { setToast(message); }
  function updateSaveState(value: SaveState) { setSaveState(value); }

  async function refreshWorkplaces() {
    const list = await api<Workplace[]>("/workplaces");
    setWorkplaces(list);
    return list;
  }

  function markdownFromPages(values: string[]): string {
    return values.map(htmlToMarkdown).filter((value, index) => value || index === 0).join("\n\n").trim();
  }

  async function saveDocumentNow() {
    clearTimeout(saveTimerRef.current);
    saveTimerRef.current = null;
    if (savePromiseRef.current) return savePromiseRef.current;
    const current = latestRef.current;
    if (!current.workplace || !current.document || current.conflict) return;
    const content = markdownFromPages(pageHtmlRef.current);
    if (content === (current.document.content ?? "")) { updateSaveState("已保存"); return; }
    updateSaveState("正在保存…");
    const snapshotRevision = current.revision;
    const task = (async () => {
      try {
        const updated = await api<StudioDocument>(`/workplaces/${current.workplace!.id}/documents/${current.document!.id}`, {
          method: "PUT",
          body: { title: current.document!.title, content, content_format: "markdown", expected_revision: snapshotRevision },
        });
        setActiveDocument(updated);
        latestRef.current.document = updated;
        latestRef.current.revision = updated.revision;
        latestRef.current.conflict = false;
        updateSaveState("已保存");
        setDocuments(items => items.map(item => item.id === updated.id ? { ...item, ...updated } : item));
      } catch (cause: any) {
        if (cause instanceof StudioApiError && cause.status === 409) {
          latestRef.current.conflict = true;
          setConflict(true);
          updateSaveState("版本冲突");
          notify("这份文档已在其他位置更新。为避免覆盖新内容，自动保存已暂停；请重新打开文档。");
        } else {
          updateSaveState("保存失败");
          setLastError(cause?.message || "保存失败");
          notify(cause?.message || "保存失败");
        }
      }
    })();
    savePromiseRef.current = task;
    try { await task; } finally { if (savePromiseRef.current === task) savePromiseRef.current = null; }
  }

  function scheduleSave() {
    if (!latestRef.current.document || latestRef.current.conflict) return;
    updateSaveState("正在保存…");
    clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => { void saveDocumentNow(); }, 700);
  }

  async function flushSave(): Promise<boolean> {
    clearTimeout(saveTimerRef.current);
    saveTimerRef.current = null;
    await saveDocumentNow();
    return !latestRef.current.conflict && latestRef.current.saveState !== "保存失败";
  }

  function installDocument(document: StudioDocument) {
    const nextPages = paginate(document.content || "");
    pageHtmlRef.current = [...nextPages];
    setPages([...nextPages]);
    setSpread(0);
    setActiveDocument(document);
    latestRef.current.document = document;
    latestRef.current.revision = document.revision;
    latestRef.current.conflict = false;
    setConflict(false);
    updateSaveState("已保存");
    setLastError("");
    activePageIndexRef.current = 1;
  }

  async function loadDocument(documentId: string) {
    if (!workplace) return;
    const data = await api<StudioDocument>(`/workplaces/${workplace.id}/documents/${documentId}`);
    installDocument(data);
  }

  async function openWorkplace(item: Workplace) {
    if (!(await flushSave())) return;
    setError("");
    setOpeningTitle(item.title);
    const meta = colorMeta(item.cover_color);
    setOpeningColor(item.cover_color || meta.color);
    setOpeningFoil(meta.foil);
    setScreen("opening");
    const started = Date.now();
    try {
      const current = await api<Workplace>(`/workplaces/${item.id}`);
      setWorkplace(current);
      latestRef.current.workplace = current;
      const list = await api<StudioDocument[]>(`/workplaces/${item.id}/documents`);
      setDocuments(list);
      let preferred = list.find(doc => doc.kind === "manuscript") || list.find(doc => doc.kind === "chapter") || list[0];
      if (!preferred) {
        preferred = await api<StudioDocument>(`/workplaces/${item.id}/documents`, {
          method: "POST",
          body: { parent_id: null, kind: "manuscript", title: "未命名手稿", content_format: "markdown", content: INITIAL_MANUSCRIPT, sort_order: 0 },
        });
        setDocuments([preferred]);
        await refreshWorkplaces();
      }
      const data = await api<StudioDocument>(`/workplaces/${item.id}/documents/${preferred.id}`);
      installDocument(data);
      setSection("writing");
      setMode("write");
      const delay = Math.max(0, 1650 - (Date.now() - started));
      window.setTimeout(() => setScreen("workplace"), delay);
    } catch (cause: any) {
      setError(cause?.message || "无法打开 Workplace");
      setScreen("shelf");
      notify(cause?.message || "无法打开 Workplace");
    }
  }

  async function closeWorkplace() {
    if (!(await flushSave())) return;
    setScreen("closing");
    window.setTimeout(() => {
      setScreen("shelf");
      setWorkplace(null);
      latestRef.current.workplace = null;
      setActiveDocument(null);
      latestRef.current.document = null;
      setDocuments([]);
      pageHtmlRef.current = ["<p><br></p>"];
      setPages(["<p><br></p>"]);
    }, 620);
  }

  async function createWorkplace() {
    if (!bookTitle.trim()) return;
    setLoading(true); setError("");
    try {
      const created = await api<Workplace>("/workplaces", {
        method: "POST", body: { title: bookTitle.trim(), description: bookDescription.trim(), cover_color: bookColor },
      });
      const list = await refreshWorkplaces();
      setModal(null); setBookTitle(""); setBookDescription(""); setBookColor(defaultCover);
      await openWorkplace(list.find(item => item.id === created.id) || created);
    } catch (cause: any) {
      setError(cause?.message || "创建 Workplace 失败");
    } finally { setLoading(false); }
  }

  async function createDocument() {
    if (!workplace || !docTitle.trim()) return;
    setLoading(true); setError("");
    try {
      const created = await api<StudioDocument>(`/workplaces/${workplace.id}/documents`, {
        method: "POST", body: { parent_id: null, kind: docKind, title: docTitle.trim(), content_format: "markdown", content: "", sort_order: documents.length + 1 },
      });
      const list = await api<StudioDocument[]>(`/workplaces/${workplace.id}/documents`);
      setDocuments(list);
      await loadDocument(created.id);
      setSpread(0); setSection("writing"); setModal(null); setDocTitle("");
      await refreshWorkplaces();
      notify("已新建文档");
    } catch (cause: any) { setError(cause?.message || "创建文档失败"); }
    finally { setLoading(false); }
  }

  async function selectDocument(id: string) {
    if (!workplace || activeDocument?.id === id) { setModal(null); return; }
    if (!(await flushSave())) return;
    try {
      await loadDocument(id);
      setSection("writing"); setModal(null);
    } catch (cause: any) { notify(cause?.message || "打开文档失败"); }
  }

  function startPageTurn(direction: "next" | "prev") {
    if (turnDirection) return;
    const maxSpread = Math.max(0, Math.ceil(pages.length / 2) - 1);
    if (direction === "next" && spread >= maxSpread) return;
    if (direction === "prev" && spread <= 0) return;
    for (const [index, element] of Object.entries(editorRefs.current)) {
      if (element) pageHtmlRef.current[Number(index)] = element.innerHTML || "<p><br></p>";
    }
    setTurnDirection(direction);
    clearTimeout(turnTimerRef.current);
    turnTimerRef.current = setTimeout(() => {
      setSpread(current => Math.max(0, Math.min(maxSpread, current + (direction === "next" ? 1 : -1))));
      setPages([...pageHtmlRef.current]);
      setTurnDirection(null);
    }, 560);
  }

  function getCurrentPageEditor(): HTMLDivElement | null {
    return editorRefs.current[activePageIndexRef.current] || editorRefs.current[spread * 2 + 1] || null;
  }

  function captureSelection() {
    const selection = window.getSelection();
    const editor = getCurrentPageEditor();
    if (selection && selection.rangeCount && editor && editor.contains(selection.anchorNode)) {
      const range = selection.getRangeAt(0);
      savedRangeRef.current = range.cloneRange();
      setSavedRange(savedRangeRef.current);
      const before = document.createRange(); before.selectNodeContents(editor); before.setEnd(range.startContainer, range.startOffset);
      const after = document.createRange(); after.selectNodeContents(editor); after.setStart(range.endContainer, range.endOffset);
      const index = activePageIndexRef.current;
      const beforePages = pageHtmlRef.current.slice(0, index).map(pagePlainText).join("\n\n");
      const afterPages = pageHtmlRef.current.slice(index + 1).map(pagePlainText).join("\n\n");
      return {
        selected_text: selection.toString(),
        context_before: [beforePages, before.toString()].filter(Boolean).join("\n\n").slice(-18000),
        context_after: [after.toString(), afterPages].filter(Boolean).join("\n\n").slice(0, 18000),
      };
    }
    savedRangeRef.current = null; setSavedRange(null);
    const all = pageHtmlRef.current.map(pagePlainText).join("\n\n");
    return { selected_text: "", context_before: all.slice(-18000), context_after: "" };
  }

  async function requestInspiration() {
    if (!workplace || !activeDocument) return;
    const context = captureSelection();
    setInspiration(""); setInspireBusy(true); setModal("inspire");
    try {
      const result = await api<{ content: string; model: string }>(`/workplaces/${workplace.id}/documents/${activeDocument.id}/ai/inspire`, {
        method: "POST", body: { ...context, model: selectedModel || capabilities?.default_model || undefined, instruction: "Give me several distinct and specific creative directions. Do not rewrite the source text." },
      });
      setInspiration(result.content || "这次没有返回灵感内容。");
    } catch (cause: any) { setInspiration(`获取灵感失败：${cause?.message || "未知错误"}`); }
    finally { setInspireBusy(false); }
  }

  async function startContinuation() {
    if (!workplace || !activeDocument) return;
    if (continueAbortRef.current) continueAbortRef.current.abort();
    const context = captureSelection();
    const controller = new AbortController();
    continueAbortRef.current = controller;
    continuationRef.current = ""; setContinuation(""); setContinueError(""); setContinueBusy(true); setModal("continue");
    try {
      const response = await fetch(`${API_BASE}/workplaces/${workplace.id}/documents/${activeDocument.id}/ai/continue`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...context, model: selectedModel || capabilities?.default_model || undefined,
          instruction: "Continue naturally from the selected text or cursor, preserving the established character voice and scene context.", max_tokens: 1024 }),
        signal: controller.signal,
      });
      if (!response.ok || !response.body) {
        let body: any = null; try { body = await response.json(); } catch {}
        throw new StudioApiError(response.status, body);
      }
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let boundary: number;
        while ((boundary = buffer.indexOf("\n\n")) >= 0) {
          const block = buffer.slice(0, boundary); buffer = buffer.slice(boundary + 2);
          const lines = block.split(/\r?\n/);
          let eventName = "message"; const payload: string[] = [];
          for (const line of lines) {
            if (line.startsWith("event:")) eventName = line.slice(6).trim();
            else if (line.startsWith("data:")) payload.push(line.slice(5).trimStart());
          }
          const data = payload.join("\n");
          if (!data) continue;
          const parsed = JSON.parse(data);
          if (eventName === "token") {
            continuationRef.current += parsed.text || "";
            setContinuation(continuationRef.current);
          } else if (eventName === "error") {
            throw new Error(parsed.message || "生成失败");
          }
        }
      }
      if (!continuationRef.current.trim()) setContinueError("模型没有生成可插入的内容。");
    } catch (cause: any) {
      if (cause?.name !== "AbortError") setContinueError(cause?.message || "AI 续写失败");
    } finally {
      if (continueAbortRef.current === controller) continueAbortRef.current = null;
      setContinueBusy(false);
    }
  }

  function acceptContinuation() {
    const text = continuationRef.current.trim();
    if (!text || conflict) return;
    const range = savedRangeRef.current;
    const editor = getCurrentPageEditor();
    if (range && editor && editor.isConnected && editor.contains(range.startContainer)) {
      const paragraph = document.createElement("p"); paragraph.textContent = text;
      range.collapse(false); range.insertNode(paragraph);
      const selection = window.getSelection();
      if (selection) { const next = document.createRange(); next.setStartAfter(paragraph); next.collapse(true); selection.removeAllRanges(); selection.addRange(next); }
    } else if (editor) {
      const paragraph = document.createElement("p"); paragraph.textContent = text; editor.appendChild(paragraph);
    } else {
      const index = Math.max(0, activePageIndexRef.current);
      const page = document.createElement("div"); page.innerHTML = pageHtmlRef.current[index] || "";
      const paragraph = document.createElement("p"); paragraph.textContent = text; page.appendChild(paragraph);
      pageHtmlRef.current[index] = page.innerHTML;
    }
    if (editor) pageHtmlRef.current[activePageIndexRef.current] = editor.innerHTML;
    setPages([...pageHtmlRef.current]);
    scheduleSave();
    setModal(null); setSavedRange(null); savedRangeRef.current = null;
    notify("续写内容已插入。保存完成前请留在当前书稿中。");
  }

  async function openVersions() {
    if (!workplace || !activeDocument) return;
    await flushSave();
    try {
      const list = await api<VersionEntry[]>(`/workplaces/${workplace.id}/documents/${activeDocument.id}/versions`);
      setVersionList(list); setModal("versions");
    } catch (cause: any) { notify(cause?.message || "无法读取版本历史"); }
  }

  async function createCheckpoint() {
    if (!workplace || !activeDocument) return;
    if (!(await flushSave())) return;
    try {
      await api<VersionEntry>(`/workplaces/${workplace.id}/documents/${activeDocument.id}/versions`, {
        method: "POST", body: { label: "手动保存点", source: "manual" },
      });
      notify("已创建版本保存点");
      await openVersions();
    } catch (cause: any) { notify(cause?.message || "创建版本失败"); }
  }

  async function restoreVersion(version: VersionEntry) {
    if (!workplace || !activeDocument) return;
    if (!window.confirm(`恢复到 v${version.revision}？当前正文会保留为历史，不会被删除。`)) return;
    try {
      const restored = await api<StudioDocument>(`/workplaces/${workplace.id}/documents/${activeDocument.id}/versions/${version.id}/restore`, { method: "POST", body: {} });
      installDocument(restored); setModal(null); notify(`已恢复到 v${version.revision}，并创建新的当前版本。`);
    } catch (cause: any) { notify(cause?.message || "恢复版本失败"); }
  }

  function handlePageInput(index: number, element: HTMLDivElement) {
    pageHtmlRef.current[index] = element.innerHTML || "<p><br></p>";
    activePageIndexRef.current = index;
    scheduleSave();
    const plain = pagePlainText(element.innerHTML);
    if (plain.length > 760 && element.children.length > 1) {
      const blocks = Array.from(element.children) as HTMLElement[];
      const moved: string[] = [];
      let remaining = plain.length;
      while (blocks.length > 1 && remaining > 620) {
        const last = blocks.pop()!;
        const length = (last.innerText || "").length;
        moved.unshift(last.outerHTML); last.remove(); remaining -= length;
      }
      if (moved.length) {
        pageHtmlRef.current[index] = element.innerHTML;
        const target = index + 1;
        const targetContainer = document.createElement("div"); targetContainer.innerHTML = pageHtmlRef.current[target] || "";
        targetContainer.insertAdjacentHTML("afterbegin", moved.join(""));
        pageHtmlRef.current[target] = targetContainer.innerHTML;
        setPages([...pageHtmlRef.current]);
        scheduleSave();
        if (target === spread * 2 + 2) window.setTimeout(() => startPageTurn("next"), 180);
      }
    }
  }

  function focusPage(index: number) { activePageIndexRef.current = index; }

  React.useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if (screen !== "workplace" || modal) return;
      const target = event.target as HTMLElement | null;
      if (target && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))) return;
      if (event.key === "ArrowRight") { event.preventDefault(); startPageTurn("next"); }
      else if (event.key === "ArrowLeft") { event.preventDefault(); startPageTurn("prev"); }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [screen, modal, spread, pages, turnDirection]);

  function setModel(value: string) { setSelectedModel(value); localStorage.setItem("khala.studio.model", value); }
  function setFontSize(value: number) { const size = Math.max(14, Math.min(22, value)); setEditorFontSize(size); localStorage.setItem("khala.studio.fontSize", String(size)); }
  function setCoverDefault(value: string) { setDefaultCover(value); localStorage.setItem("khala.studio.coverColor", value); }

  const maxSpread = Math.max(0, Math.ceil(pages.length / 2) - 1);
  const visibleLeftIndex = spread * 2;
  const visibleRightIndex = spread * 2 + 1;
  const wordCount = countWords(pageHtmlRef.current.map(pagePlainText).join(" "));
  const currentCover = workplace ? colorMeta(workplace.cover_color) : COVER_PALETTE[0];

  function renderBookshelf() {
    return <section className="bookshelf-screen">
      <header className="brandbar">
        <div className="brand-lockup"><div className="brand-mark">K</div><div><strong>KHALA STUDIO</strong><small>THE LIVING ATELIER</small></div></div>
        <div className="top-note">A QUIET PLACE FOR IMAGINATION</div>
      </header>
      <div className="shelf-intro">
        <div><div className="eyebrow brass-text">YOUR CREATIVE LIBRARY</div><h1>每一本书，都是一个世界。</h1><p>在这里，打开你的下一个创造。</p></div>
        <button className="outline-light-button" onClick={() => { setBookTitle(""); setBookDescription(""); setBookColor(defaultCover); setError(""); setModal("create-book"); }}>＋　创建 Workplace</button>
      </div>
      {error && <div className="shelf-error">{error}</div>}
      <div className="shelf-grid">
        {workplaces.map((item, index) => {
          const theme = colorMeta(item.cover_color);
          return <button className="book-card" key={item.id} onClick={() => void openWorkplace(item)} style={{ "--cover": item.cover_color || theme.color, "--cover-edge": theme.edge, "--foil": theme.foil } as any}>
            <div className="book-object"><div className="book-pages-edge"/><div className="book-cover"><div className="book-spine"/><div className="cover-content">
              <div className="cover-sub">KHALA　·　STUDIO</div><div className="cover-rule"/><div className="cover-emblem">{index % 2 === 0 ? "✦" : "❧"}</div>
              <h2 className="cover-title">{item.title}</h2><div className="cover-sub">{item.description || "A WORLD BETWEEN THE PAGES"}</div><div className="cover-rule"/>
              <div className="cover-bottom">{item.document_count} DOCUMENTS</div>
            </div></div></div>
            <div className="book-meta"><span>{item.title}</span><small>{item.document_count} 篇文档 · {fmtDate(item.updated_at)}</small></div>
          </button>;
        })}
        {!workplaces.length && screen !== "loading" && <div className="empty-shelf"><div className="empty-book">✦</div><h2>书架还空着。</h2><p>创建第一本创作之书，让你的世界从这里开始。</p><button className="outline-light-button" onClick={() => { setBookTitle(""); setBookDescription(""); setBookColor(defaultCover); setError(""); setModal("create-book"); }}>创建第一本书</button></div>}
      </div>
      <footer className="shelf-caption"><span>KHALA STUDIO　/　THE BOOKSHELF</span><span>MAKE A WORLD OF YOUR OWN</span></footer>
      {screen === "loading" && <div className="loading-label">正在整理你的书架……</div>}
    </section>;
  }

  function renderSectionNav() {
    const items: { id: Section; title: string; en: string; icon: string }[] = [
      { id: "writing", title: "写作", en: "WRITING", icon: "pen" },
      { id: "characters", title: "角色", en: "CHARACTERS", icon: "users" },
      { id: "scenes", title: "场景", en: "SCENES & CASTING", icon: "scene" },
      { id: "assets", title: "素材", en: "ASSETS", icon: "images" },
      { id: "settings", title: "设置", en: "SETTINGS", icon: "settings" },
    ];
    return <nav className="section-nav" aria-label="Workplace sections">
      {items.map(item => <button key={item.id} className={section === item.id ? "active" : ""} onClick={() => setSection(item.id)}>
        <Icon name={item.icon}/><span>{item.title}</span><small>{item.en}</small>
      </button>)}
    </nav>;
  }

  function renderDocumentList() {
    if (!documents.length) return <p className="muted-small">这本书还没有文档。</p>;
    const depthOf = (doc: StudioDocument) => {
      let depth = 0; let parent = doc.parent_id; const byId = new Map(documents.map(item => [item.id, item]));
      while (parent && depth < 5) { depth += 1; parent = byId.get(parent)?.parent_id || null; }
      return depth;
    };
    return <ul className="doc-list">{documents.map((doc, index) => <li key={doc.id} style={{ paddingLeft: `${depthOf(doc) * 13}px` }}>
      <button className={activeDocument?.id === doc.id ? "selected" : ""} onClick={() => void selectDocument(doc.id)}>
        <span className="doc-index">{doc.kind === "manuscript" ? "M" : String(index + 1).padStart(2, "0")}</span><span className="doc-title">{doc.title}</span>
      </button></li>)}</ul>;
  }

  function renderWritingSection() {
    const leftIndex = visibleLeftIndex;
    const rightIndex = visibleRightIndex;
    return <div className="book-stage">
      <div className="book-topline">
        <div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace?.title}</span><span className="top-separator">/</span><span className="document-crumb">{activeDocument?.title || "未命名手稿"}</span></div>
        <div className="book-actions"><button className="head-btn" onClick={() => setModal("contents")}>目录</button><button className="head-btn" onClick={() => void openVersions()}>版本</button><button className="head-btn" onClick={() => setMode(current => current === "write" ? "read" : "write")}>{mode === "write" ? "阅读模式" : "写作模式"}</button><button className="head-btn close-book-button" onClick={() => void closeWorkplace()}>合上书本</button></div>
      </div>
      <div className="open-book">
        <section className="page page-left">
          <div className="page-head"><span>{activeDocument?.kind?.toUpperCase() || "MANUSCRIPT"}　·　{String(activeDocument?.revision || 1).padStart(2, "0")}</span><strong>THE STORY</strong></div>
          <div className="page-caption"><div className="eyebrow">{workplace?.title?.toUpperCase()}</div><h2>{activeDocument?.title || "未命名手稿"}</h2><p>每一个故事，都从一个尚未回答的问题开始。</p></div>
          <div className="page-body manuscript-body" style={{ "--editor-font-size": `${editorFontSize}px` } as any}>
            <div key={`${activeDocument?.id}-${leftIndex}`} ref={(element: HTMLDivElement | null) => { editorRefs.current[leftIndex] = element; }} className="manuscript-page" contentEditable={mode === "write"} suppressContentEditableWarning spellCheck={false} data-placeholder="从这里开始写下你的故事……"
              dangerouslySetInnerHTML={{ __html: pages[leftIndex] || "<p><br></p>" }}
              onFocus={() => focusPage(leftIndex)} onInput={(event: any) => handlePageInput(leftIndex, event.currentTarget)} onMouseUp={() => captureSelection()} onKeyUp={() => captureSelection()}/>
          </div>
          <div className="page-number">{folio(26 + leftIndex)}</div>
        </section>
        <section className="page page-right">
          <div className="page-head"><span>{`DRAFT V${activeDocument?.revision || 1}`}</span><strong className={`save-indicator ${saveState === "版本冲突" ? "danger" : ""}`}>{saveState}</strong></div>
          <div className="writer-heading">
            <div><div className="eyebrow">THE STORY CONTINUES</div><h1>{activeDocument?.title || "未命名手稿"}</h1><div className="writer-meta">字数 {wordCount.toLocaleString("zh-CN")}　·　{mode === "write" ? "写作中" : "阅读中"}</div></div>
            {mode === "write" && <div className="writer-tools"><button className="tool-button" onMouseDown={(event: any) => event.preventDefault()} onClick={() => void requestInspiration()}><Icon name="lightbulb"/>给我灵感</button><button className="tool-button primary" onMouseDown={(event: any) => event.preventDefault()} onClick={() => void startContinuation()}><Icon name="sparkle"/>AI 续写</button></div>}
          </div>
          <div className="page-body writer-body" style={{ "--editor-font-size": `${editorFontSize}px` } as any}>
            <div key={`${activeDocument?.id}-${rightIndex}`} ref={(element: HTMLDivElement | null) => { editorRefs.current[rightIndex] = element; }} className="manuscript-page" contentEditable={mode === "write"} suppressContentEditableWarning spellCheck={false} data-placeholder="从这里开始写下你的故事……"
              dangerouslySetInnerHTML={{ __html: pages[rightIndex] || "<p><br></p>" }}
              onFocus={() => focusPage(rightIndex)} onInput={(event: any) => handlePageInput(rightIndex, event.currentTarget)} onMouseUp={() => captureSelection()} onKeyUp={() => captureSelection()}/>
          </div>
          <div className="page-number">{folio(26 + rightIndex)}</div>
          <div className="edit-status">{mode === "write" ? "点击纸面即可编辑" : "阅读中 · 正文只读"}</div>
        </section>
        <div className="book-spine"/>
        {turnDirection && <div className={`turn-leaf ${turnDirection === "next" ? "turn-next" : "turn-prev"}`} />}
      </div>
      <div className="turn-controls"><button disabled={spread === 0 || !!turnDirection} onClick={() => startPageTurn("prev")}>←　上一页</button><span>第 {26 + spread * 2}–{27 + spread * 2} 页　/　{spread + 1} of {maxSpread + 1}</span><button disabled={spread >= maxSpread || !!turnDirection} onClick={() => startPageTurn("next")}>下一页　→</button></div>
      {conflict && <div className="conflict-banner"><strong>文档版本冲突</strong><span>另一处编辑已保存了更新版本，当前内容不会覆盖它。</span><button onClick={() => activeDocument && void loadDocument(activeDocument.id)}>重新载入服务器版本</button></div>}
    </div>;
  }

  function placeholderCopy(active: Section) {
    if (active === "characters") return {
      label: "CHARACTER STUDIO", title: "让角色拥有完整的生命。", subtitle: "从文学身份、视觉人设到声音与表演，让每个角色在不同场景中保持一致。",
      items: [{ icon: "IDENTITY", title: "文学身份", desc: "经历、性格、动机、恐惧、关系与角色弧线。" }, { icon: "APPEARANCE", title: "视觉人设", desc: "面貌、服装、配色、表情、姿势与标准形象。" }, { icon: "VOICE", title: "声音身份", desc: "音色、音域、口音、语速与表演状态。" }, { icon: "PERFORMANCE", title: "表演档案", desc: "肢体语言、情绪反应、行为习惯与角色行动。" }], status: "角色 API 尚未接入" };
    if (active === "scenes") return {
      label: "SCENE & CASTING", title: "把角色放进情境，让故事发生。", subtitle: "选择角色进入场景，为每个人确定目标、冲突、行动、对白和表演方式。",
      items: [{ icon: "SETTING", title: "规定情境", desc: "时间、地点、环境、事件背景与场景条件。" }, { icon: "CAST", title: "选角 Casting", desc: "从 Workplace 的角色库选择参与者。" }, { icon: "OBJECTIVES", title: "目标与冲突", desc: "角色想得到什么，以及彼此如何阻碍。" }, { icon: "DIRECTION", title: "导演设计", desc: "动作、对白、镜头、调度与情绪节奏。" }], status: "场景与选角 API 尚未接入" };
    return {
      label: "CREATIVE ASSETS", title: "让每一次创作都有自己的档案。", subtitle: "图片、声音、音乐、视频和分镜都应该回到它所属的角色与场景。",
      items: [{ icon: "IMAGE", title: "图像与视觉", desc: "标准形象、表情表、服装设计、插画与分镜。" }, { icon: "VOICE", title: "声音与对白", desc: "角色声线、对白录音、旁白与音效。" }, { icon: "MUSIC", title: "音乐与声音", desc: "主题动机、场景配乐与环境音。" }, { icon: "VIDEO", title: "视频与制作", desc: "镜头序列、动画、预演和最终作品。" }], status: "创作资产 API 尚未接入" };
  }

  function renderPlaceholderSection(active: Section) {
    const copy = placeholderCopy(active);
    return <div className="book-stage section-placeholder">
      <div className="book-topline"><div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace?.title}</span><span className="top-separator">/</span><span className="document-crumb">{copy.label}</span></div><div className="book-actions"><button className="head-btn" onClick={() => setSection("writing")}>返回写作</button><button className="head-btn close-book-button" onClick={() => void closeWorkplace()}>合上书本</button></div></div>
      <div className="open-book placeholder-book">
        <section className="page page-left"><div className="page-head"><span>THE LIVING ATELIER</span><strong>{copy.label}</strong></div><div className="placeholder-ornament">✦</div><div className="placeholder-quote">Every character<br/>has a life.<br/><small>Every story has a stage.</small></div><div className="page-number">— KHALA —</div></section>
        <section className="page page-right"><div className="page-head"><span>{copy.label}</span><strong>WORKPLACE</strong></div><div className="placeholder-content"><div className="eyebrow">{copy.label}</div><h1>{copy.title}</h1><p className="placeholder-subtitle">{copy.subtitle}</p><div className="placeholder-grid">{copy.items.map(item => <article className="placeholder-card" key={item.title}><span>{item.icon}</span><h3>{item.title}</h3><p>{item.desc}</p></article>)}</div><div className="api-pending"><span className="status-dot"/>{copy.status}<p>界面结构已纳入 Studio；等待对应资源 API 后接入持久化数据。</p></div></div><div className="page-number">— WORK IN PROGRESS —</div></section><div className="book-spine"/>
      </div>
    </div>;
  }

  function renderSettings() {
    return <div className="book-stage section-placeholder settings-stage">
      <div className="book-topline"><div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace?.title}</span><span className="top-separator">/</span><span className="document-crumb">SETTINGS</span></div><div className="book-actions"><button className="head-btn" onClick={() => setSection("writing")}>返回书稿</button><button className="head-btn close-book-button" onClick={() => void closeWorkplace()}>合上书本</button></div></div>
      <div className="open-book placeholder-book">
        <section className="page page-left"><div className="page-head"><span>THE WORKSHOP</span><strong>PREFERENCES</strong></div><div className="placeholder-ornament">K</div><div className="placeholder-quote">A quiet place<br/>for imagination.</div><div className="page-number">— KHALA —</div></section>
        <section className="page page-right"><div className="page-head"><span>STUDIO PREFERENCES</span><strong>LOCAL SETTINGS</strong></div><div className="settings-content"><div className="eyebrow">AI & WRITING</div><h1>创作偏好</h1>
          <label className="setting-row"><span><strong>写作模型</strong><small>此模型用于“给我灵感”和“AI 续写”。</small></span><select value={selectedModel || capabilities?.default_model || ""} onChange={(event: any) => setModel(event.target.value)}>{(capabilities?.models || []).map(model => <option key={model.id} value={model.id}>{model.name}</option>)}</select></label>
          <label className="setting-row"><span><strong>正文排版字号</strong><small>调整书页中正文的阅读大小。</small></span><div className="range-control"><input type="range" min="14" max="22" value={editorFontSize} onChange={(event: any) => setFontSize(Number(event.target.value))}/><b>{editorFontSize}px</b></div></label>
          <div className="setting-row cover-setting"><span><strong>新书默认封面</strong><small>创建 Workplace 时预选的封面颜色。</small></span><div className="color-options">{COVER_PALETTE.map(color => <button key={color.color} aria-label={color.label} title={color.label} className={defaultCover === color.color ? "chosen" : ""} style={{ background: color.color }} onClick={() => setCoverDefault(color.color)}/>)}</div></div>
          <div className="settings-note"><strong>存储说明</strong><p>写作模型选择和排版偏好目前保存在当前浏览器中。服务器默认模型由 Khala 配置项 <code>studio_model</code> 控制；当前后端尚未提供 Studio Settings 写入接口。</p><small>ENGINE　{capabilities?.engine || "unknown"}　·　STORAGE　{capabilities?.storage || "local"}　·　AI　{capabilities?.ai_available ? "AVAILABLE" : "UNAVAILABLE"}</small></div>
        </div><div className="page-number">— SETTINGS —</div></section><div className="book-spine"/>
      </div>
    </div>;
  }

  function renderWorkplace() {
    return <section className="workplace-screen" style={{ "--editor-font-size": `${editorFontSize}px` } as any}>
      <header className="workplace-header"><div className="header-brand"><div className="brand-mark small">K</div><span>KHALA STUDIO</span></div><div className="header-title">{workplace?.title || ""}</div><div className="header-right"><span className="server-state"><i/>LOCAL WORKSPACE</span><button className="close-workspace" onClick={() => void closeWorkplace()}>合上书本</button></div></header>
      {renderSectionNav()}
      {section === "writing" ? renderWritingSection() : section === "settings" ? renderSettings() : renderPlaceholderSection(section)}
      {toast && <div className="toast-message">{toast}</div>}
    </section>;
  }

  function renderOpening() {
    const meta = colorMeta(openingColor);
    return <section className={`opening-screen ${screen === "closing" ? "closing" : ""}`} style={{ "--cover-active": openingColor, "--foil-active": openingFoil } as any}>
      <div className="opening-book"><div className="opening-pages"/><div className="opening-cover"><div className="opening-inner"><div className="cover-sub">KHALA　·　STUDIO</div><div className="cover-rule"/><div className="cover-emblem">✦</div><h2>{openingTitle}</h2><div className="cover-sub">A WORLD BETWEEN THE PAGES</div></div></div></div>
      <div className="opening-caption">{screen === "closing" ? "正在合上这本书……" : "正在翻开你的世界……"}</div>
    </section>;
  }

  function renderCreateBookModal() {
    return <Modal title="创建一本新书" eyebrow="A NEW WORLD BEGINS" onClose={() => setModal(null)} actions={<><button className="quiet-button" onClick={() => setModal(null)}>取消</button><button className="confirm-button" disabled={!bookTitle.trim() || loading} onClick={() => void createWorkplace()}>{loading ? "创建中…" : "创建并打开"}</button></>}>
      <label className="field-label">书名<input autoFocus value={bookTitle} onChange={(event: any) => setBookTitle(event.target.value)} placeholder="为你的世界取一个名字" maxLength={512}/></label>
      <label className="field-label">创作简介<textarea value={bookDescription} onChange={(event: any) => setBookDescription(event.target.value)} placeholder="简单描述这本书里的世界……" rows={3}/></label>
      <div className="field-label">封面颜色<div className="color-options large">{COVER_PALETTE.map(color => <button key={color.color} className={bookColor === color.color ? "chosen" : ""} title={color.label} aria-label={color.label} style={{ background: color.color }} onClick={() => setBookColor(color.color)}/>)}</div></div>
      {error && <p className="form-error">{error}</p>}
    </Modal>;
  }

  function renderCreateDocModal() {
    return <Modal title="添加一页新内容" eyebrow="ADD TO THIS BOOK" onClose={() => setModal(null)} actions={<><button className="quiet-button" onClick={() => setModal(null)}>取消</button><button className="confirm-button" disabled={!docTitle.trim() || loading} onClick={() => void createDocument()}>{loading ? "创建中…" : "创建文档"}</button></>}>
      <label className="field-label">标题<input autoFocus value={docTitle} onChange={(event: any) => setDocTitle(event.target.value)} placeholder="例如：第二章 / 人物笔记"/></label>
      <label className="field-label">内容类型<select value={docKind} onChange={(event: any) => setDocKind(event.target.value)}><option value="chapter">章节正文</option><option value="manuscript">完整手稿</option><option value="outline">大纲</option><option value="note">笔记</option></select></label>
      {error && <p className="form-error">{error}</p>}
    </Modal>;
  }

  function renderContentsModal() {
    return <Modal title="章节目录" eyebrow="THE TABLE OF CONTENTS" onClose={() => setModal(null)} className="contents-modal" actions={<><button className="quiet-button" onClick={() => setModal(null)}>合上目录</button><button className="confirm-button" onClick={() => { setDocTitle(""); setDocKind("chapter"); setModal("create-document"); }}>＋ 添加文档</button></>}>
      <p className="modal-intro">像翻阅一本书一样，选择你要进入的章节。</p>
      {renderDocumentList()}
      {!documents.length && <p className="muted-small">还没有文档。</p>}
    </Modal>;
  }

  function renderInspireModal() {
    return <Modal title="给我一点灵感" eyebrow="A MOMENT OF INSPIRATION" onClose={() => setModal(null)} actions={<><button className="quiet-button" onClick={() => setModal(null)}>先不采用</button><button className="confirm-button" disabled={!inspiration || inspireBusy} onClick={() => { setModal(null); notify("灵感已留在侧边，不会自动写入正文。"); }}>留作参考</button></>}>
      <p className="modal-intro">不替你写作，只提供几个可以继续探索的方向。AI 不会自动修改手稿。</p>
      {inspireBusy ? <div className="thinking-state"><span className="thinking-mark">✦</span><p>正在阅读当前上下文，寻找不同的创作方向……</p></div> : <pre className="ai-result">{inspiration}</pre>}
    </Modal>;
  }

  function renderContinueModal() {
    return <Modal title="AI 续写预览" eyebrow="CONTINUE THE MANUSCRIPT" onClose={() => { if (continueAbortRef.current) continueAbortRef.current.abort(); setContinueBusy(false); setModal(null); }} actions={<><button className="quiet-button" onClick={() => { if (continueAbortRef.current) continueAbortRef.current.abort(); setContinueBusy(false); setModal(null); }}>放弃</button><button className="tool-button" disabled={continueBusy || !!continueError} onClick={() => void startContinuation()}>重新生成</button><button className="confirm-button" disabled={!continuation.trim() || continueBusy || !!continueError} onClick={acceptContinuation}>插入正文</button></>}>
      <p className="modal-intro">根据当前章节和光标位置继续创作。生成结果先放在这里，确认后才进入正文。</p>
      {continueBusy && <div className="stream-state"><span className="stream-dot"/>正在生成……</div>}
      {continueError && <div className="form-error">{continueError}</div>}
      <pre className="ai-result continuation-result">{continuation || (continueBusy ? "" : "等待生成内容……")}</pre>
    </Modal>;
  }

  function renderVersionsModal() {
    return <Modal title="版本历史" eyebrow="MANUSCRIPT REVISIONS" onClose={() => setModal(null)} className="versions-modal" actions={<><button className="quiet-button" onClick={() => setModal(null)}>关闭</button><button className="confirm-button" onClick={() => void createCheckpoint()}>创建当前保存点</button></>}>
      <p className="modal-intro">每次保存都更新当前稿件；这里的版本是作者明确创建的不可变保存点。</p>
      {versionList.length ? <div className="version-list">{versionList.map(version => <article className="version-row" key={version.id}><div><strong>{version.label || `草稿 v${version.revision}`}</strong><small>v{version.revision}　·　{version.source}　·　{fmtDate(version.created_at)}</small></div><button onClick={() => void restoreVersion(version)}>恢复此版本</button></article>)}</div> : <div className="empty-versions">还没有历史保存点。点击“创建当前保存点”，为这份手稿留下一个可恢复的版本。</div>}
    </Modal>;
  }

  function renderModal() {
    if (modal === "create-book") return renderCreateBookModal();
    if (modal === "create-document") return renderCreateDocModal();
    if (modal === "contents") return renderContentsModal();
    if (modal === "inspire") return renderInspireModal();
    if (modal === "continue") return renderContinueModal();
    if (modal === "versions") return renderVersionsModal();
    return null;
  }

  return <div className="khala-app">
    {(screen === "shelf" || screen === "loading") && renderBookshelf()}
    {(screen === "opening" || screen === "closing") && renderOpening()}
    {screen === "workplace" && renderWorkplace()}
    {renderModal()}
    {toast && screen !== "workplace" && <div className="toast-message global-toast">{toast}</div>}
  </div>;
}

const mount = document.getElementById("studio-root");
if (mount) ReactDOM.createRoot(mount).render(<App/>);
