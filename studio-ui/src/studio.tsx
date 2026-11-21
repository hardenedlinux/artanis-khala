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
const RESUME_WORKPLACE_KEY = "khala.studio.lastWorkplaceId";
const RESUME_DOCUMENT_KEY = "khala.studio.lastDocumentId";
const RESUME_SECTION_KEY = "khala.studio.lastSection";

type Envelope<T> = { data: T };
type ApiErrorPayload = { error?: { code?: string; message?: string; current_revision?: number } };
interface Workplace {
  id: string; title: string; description: string; cover_color: string;
  cover_asset_id: string | null; document_count: number; created_at: string;
  updated_at: string; last_opened_at: string | null; archived_at: string | null;
  sample?: boolean;
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
  image_generation?: ImageGenerationCapabilities;
  model_profiles?: { id: string; name: string; model: string; protocol: string }[];
}
interface ImageGenerationCapabilities {
  engine: string; available: boolean; reference_images: boolean;
  reference_mode: string; max_references: number;
}
type IdentityKey = "literary_identity" | "visual_identity" | "vocal_identity" | "performance_identity";
interface StudioCharacter {
  id: string; workplace_id: string; name: string; role: string; summary: string;
  concept: string; avatar_asset_id: string | null; full_body_asset_id: string | null;
  literary_identity: Record<string, string>;
  visual_identity: Record<string, string>;
  vocal_identity: Record<string, string>;
  performance_identity: Record<string, string>;
  avatar?: StudioAsset | null; full_body?: StudioAsset | null;
  created_at: string; updated_at: string; archived_at: string | null;
}
interface CharacterDraft {
  name: string; role: string; summary: string; concept: string;
  identities: Record<IdentityKey, Record<string, string>>;
}
interface CharacterAiDraft {
  section: IdentityKey; content: Record<string, string>; source: "ai" | "author" | string;
  model: string; author_edited: boolean; created_at: string; updated_at: string;
}
type CharacterOutfitKind = "standard" | "casual" | "battle" | "formal" | "custom";
interface CharacterOutfit {
  id: string; character_id: string; name: string; kind: CharacterOutfitKind;
  description: string; components: string[]; materials: string[]; colors: string[];
  accessories: string[]; special_features: string[]; image_prompt: string;
  reference_asset_id: string | null; is_default: boolean;
  created_at: string; updated_at: string; archived_at: string | null;
}
interface CharacterOutfitDraft {
  name: string; kind: CharacterOutfitKind; description: string;
  components: string; materials: string; colors: string; accessories: string;
  special_features: string; image_prompt: string;
}
type CharacterArtworkType = "avatar" | "full_body" | "character_sheet" | "expression_sheet" | "outfit";
interface CharacterArtworkPrompt {
  character_id: string; artwork_type: CharacterArtworkType; outfit_id: string | null;
  prompt: string; width: number; height: number;
}
interface CharacterArtworkResult {
  character_id: string; artwork_type: CharacterArtworkType; outfit_id: string | null;
  prompt: string; asset: StudioAsset;
}
type CharacterTab = "overview" | "identity" | "outfits" | "artwork" | "canon";
interface SceneGivenCircumstances {
  time: string; place: string; environment: string; background: string; prior_events: string;
}
interface SceneDramaticSituation {
  central_question: string; primary_conflict: string; turn: string;
}
interface SceneDirection {
  blocking: string; spatial: string; performance_direction: string; camera: string;
}
interface StudioScene {
  id: string; workplace_id: string; title: string; summary: string; sort_order: number;
  status: "draft" | "ready" | "final";
  given_circumstances: SceneGivenCircumstances;
  dramatic_situation: SceneDramaticSituation;
  dialogue: string; direction: SceneDirection; cast_count: number; storyboard_count: number;
  reference_asset_ids?: string[]; reference_count?: number;
  source_document_id?: string | null; source_document_version_id?: string | null;
  source_document_revision?: number | null; source_text_snapshot?: string | null;
  source_selection_start?: number | null; source_selection_end?: number | null;
  created_at: string; updated_at: string; deleted_at: string | null;
}
interface SceneCastEntry {
  id: string; scene_id: string; character_id: string; character_name: string;
  character_role: string; objective: string; action: string; conflict: string;
  emotional_state: string; performance_direction: string; subtext: string;
  sort_order: number; created_at: string; updated_at: string;
}
interface SceneCastDraft {
  character_id: string; character_name: string; character_role: string;
  objective: string; action: string; conflict: string; emotional_state: string;
  performance_direction: string; subtext: string;
}
interface SceneDraft {
  title: string; summary: string; sort_order: number; status: StudioScene["status"];
  given_circumstances: SceneGivenCircumstances;
  dramatic_situation: SceneDramaticSituation;
  dialogue: string; direction: SceneDirection;
}

interface SceneExtractionCast {
  character_id: string; character_name: string; objective: string; action: string;
  conflict: string; emotional_state: string; performance_direction: string;
  subtext: string; sort_order?: number;
}
interface SceneExtractionUnresolved { name: string; reason: string }
interface SceneExtractionSource {
  document_id: string; document_revision: number; document_version_id: string | null;
  scope: "selection" | "document"; selection_start: number | null;
  selection_end: number | null; text: string;
}
interface SceneExtractionDraft {
  title: string; summary: string; given_circumstances: SceneGivenCircumstances;
  dramatic_situation: SceneDramaticSituation; dialogue: string;
  direction: SceneDirection; cast: SceneExtractionCast[];
  unresolved_characters: SceneExtractionUnresolved[];
  source: SceneExtractionSource; model: string; profile_id: string | null;
  protocol: string;
}
interface SceneExtractionResult { scene: StudioScene; cast: SceneCastEntry[] }
interface SceneExtractionSourceInput {
  document_id: string; document_title: string; document_content: string;
  revision: number; selected_text: string; context_before: string;
  context_after: string; selection_start: number | null;
  selection_end: number | null;
}

type ModelProtocol = "openai-compatible" | "gemini-native" | "anthropic-messages" | "fake";
interface ModelProfile {
  id: string; name: string; provider: string; protocol: ModelProtocol;
  base_url: string; model_id: string; custom_headers: Record<string, string>;
  timeout_seconds: number; parameters: Record<string, any>;
  capabilities: Record<string, boolean | number>; enabled: boolean;
  api_key_configured: boolean; api_key_masked: string | null;
  created_at: string; updated_at: string;
}
interface EmbeddingProfile {
  id: string; name: string; provider: string; protocol: "openai-embeddings";
  base_url: string; model_id: string; dimensions: number | null;
  batch_size: number; timeout_seconds: number; custom_headers: Record<string, string>;
  enabled: boolean; api_key_configured: boolean; api_key_masked: string | null;
  created_at: string; updated_at: string;
}
interface ModelSettings {
  llm_profiles: ModelProfile[]; embedding_profiles: EmbeddingProfile[];
  default_llm_profile_id: string | null; default_embedding_profile_id: string | null;
  task_assignments: Record<string, string | null>;
  provider_presets: Record<string, { name: string; protocol: ModelProtocol; base_url: string; model_id: string }>;
  protocols: Record<string, { label: string; supports_model_list: boolean; supports_streaming: boolean; supports_json: boolean }>;
  tasks: string[]; legacy: { engine: string; model: string | null; fallback_available: boolean };
}
interface AcceptanceTask {
  task: string; label: string; configured: boolean; profile_id: string | null;
  profile_name: string | null; model: string | null; protocol: string | null;
  base_url: string | null; external_provider: boolean; may_incur_charges: boolean;
}
interface AcceptanceOverview {
  tasks: AcceptanceTask[];
  embedding: {
    configured: boolean; profile_id: string | null; profile_name: string | null;
    model: string | null; protocol: string | null; dimensions: number | null;
    may_incur_charges: boolean;
  };
  warning: string; embedding_note: string;
}
interface AcceptanceRun {
  task: string; profile_id: string | null; profile_name: string | null;
  model: string | null; protocol: string | null; valid: boolean;
  validation: Record<string, unknown>; elapsed_ms: number; preview: string;
}
interface StoryboardShot {
  id: string; number: number; dramatic_beat: string; action: string;
  content: string; character_ids: string[]; characters: string[];
  camera: string; expression: string; performance: string;
  expression_action: string; visual_description: string; image_prompt: string;
  asset_id: string | null; file_url: string | null; status: string;
  source: "ai" | "deterministic" | "manual" | string; model: string;
  author_edited: boolean;
  character_outfits?: StoryboardCharacterOutfit[];
  reference_usage?: ReferenceUsage | null;
}
interface StoryboardCharacterOutfit { character_id: string; outfit_id: string }
interface ReferenceTrace {
  role: "character" | "outfit" | "scene" | string; reference_kind: string;
  asset_id: string; character_id: string | null; outfit_id: string | null;
  name: string; mime_type: string; width: number | null; height: number | null;
  file_url: string; applied: boolean;
}
interface ReferenceUsage {
  engine: string; mode: string; applied: boolean; reference_mode: string;
  message: string; references: ReferenceTrace[];
}
interface SceneStoryboard {
  scene_id: string; shots: StoryboardShot[]; generation_available: boolean;
  image_generation?: ImageGenerationCapabilities; updated_at: string;
}
interface GeneratedShotImage {
  shot: StoryboardShot; asset: StudioAsset; reference_usage?: ReferenceUsage;
}
type AssetType = "image" | "audio" | "video" | "document" | "other";
type AssetResourceType = "character" | "scene" | "document";
interface AssetLink {
  resource_type: AssetResourceType; resource_id: string; name: string;
  available: boolean; created_at: string;
}
interface StudioAsset {
  id: string; workplace_id: string; name: string; description: string;
  asset_type: AssetType; storage_key: string; has_file: boolean;
  file_url: string | null; original_filename: string; mime_type: string;
  file_size: number; checksum: string; source: "upload" | "generated" | "imported";
  width: number | null; height: number | null; duration_ms: number | null;
  author: string; notes: string; tags: string[];
  generation_metadata: Record<string, unknown>; created_at: string;
  updated_at: string; archived_at: string | null; links: AssetLink[];
}
interface AssetDraft { name: string; description: string; author: string; notes: string; tags: string }
interface PageSpread { left: string; right: string }
type Section = "writing" | "characters" | "scenes" | "assets" | "settings";
type SaveState = "已保存" | "正在保存…" | "版本冲突" | "保存失败" | "AI 生成中";

const CHARACTER_SECTIONS: { key: IdentityKey; title: string; en: string; icon: string; description: string; fields: { key: string; label: string; hint: string; wide?: boolean }[] }[] = [
  {
    key: "literary_identity", title: "文学身份", en: "LITERARY IDENTITY", icon: "book",
    description: "人物的经历、内在驱动力与变化轨迹。先写下已经确定的部分，未回答的问题可以留白。",
    fields: [
      { key: "background", label: "背景经历", hint: "成长环境、关键事件、来到故事开始前的人生。", wide: true },
      { key: "personality", label: "性格", hint: "稳定倾向、矛盾之处、面对压力时的样子。", wide: true },
      { key: "values", label: "价值观", hint: "认为什么重要，愿意为什么妥协或拒绝。" },
      { key: "motivations", label: "动机", hint: "当下推动行动的欲望与理由。" },
      { key: "fears", label: "恐惧", hint: "最想避免的失去、羞辱或真相。" },
      { key: "goals", label: "目标", hint: "明确想得到或完成的事情。" },
      { key: "relationships", label: "关系", hint: "重要关系、依赖与未解决的亏欠。", wide: true },
      { key: "arc", label: "人物弧线", hint: "从何处出发，可能走向怎样的变化。", wide: true },
    ],
  },
  {
    key: "visual_identity", title: "视觉身份", en: "VISUAL CANON", icon: "images",
    description: "作者批准的标准形象。这里只记录 Canon；AI 生成结果提出的新特征必须由你确认后再写入。",
    fields: [
      { key: "standard_appearance", label: "标准外貌", hint: "第一眼可辨认的整体形象。", wide: true },
      { key: "face", label: "脸部", hint: "骨相、眼睛、鼻子、嘴、肤色、年龄感。" },
      { key: "body", label: "体型", hint: "身高、体态、力量感、行动方式。" },
      { key: "hair", label: "发型", hint: "长度、质地、颜色、日常整理方式。" },
      { key: "eyes", label: "眼睛", hint: "眼型、眼色、目光习惯。" },
      { key: "skin", label: "皮肤", hint: "肤色、质感、日晒与疤痕等稳定特征。" },
      { key: "distinctive_features", label: "辨识特征", hint: "不会随场景变化的伤疤、义肢、饰物或体态。" },
      { key: "clothing", label: "服装", hint: "标志性着装、材质、磨损与配件。", wide: true },
      { key: "palette", label: "色彩", hint: "属于这个角色的稳定色彩关系。" },
      { key: "expressions", label: "表情", hint: "常见表情与情绪显露方式。" },
      { key: "posture", label: "姿态", hint: "站姿、坐姿、习惯性的身体重心。", wide: true },
    ],
  },
  {
    key: "vocal_identity", title: "声音身份", en: "VOCAL IDENTITY", icon: "lightbulb",
    description: "稳定的声音 Canon，供对白、朗读和未来的声音制作共同参考。",
    fields: [
      { key: "timbre", label: "音色", hint: "明亮、沙哑、温暖、干涩等稳定质感。" },
      { key: "voice_character", label: "声音性格", hint: "声音给人的第一印象与表达气质。" },
      { key: "range", label: "音域", hint: "自然音域与情绪升高或压低时的变化。" },
      { key: "pitch", label: "音高", hint: "日常说话的基准高度。" },
      { key: "accent", label: "口音", hint: "地域、阶层或混合口音。" },
      { key: "pronunciation", label: "发音习惯", hint: "特定音节、吞音、咬字与语汇习惯。", wide: true },
      { key: "pace", label: "语速", hint: "节奏、停顿与情绪变化时的加速或放慢。" },
      { key: "speech_habits", label: "说话习惯", hint: "口头禅、称呼方式、回避或强调的措辞。", wide: true },
    ],
  },
  {
    key: "performance_identity", title: "表演身份", en: "PERFORMANCE IDENTITY", icon: "scene",
    description: "角色如何行动、反应和在情境中表现自己。它连接文学内在与视觉、声音外在。",
    fields: [
      { key: "habits", label: "行为习惯", hint: "反复出现的小动作、仪式与偏好。", wide: true },
      { key: "movement", label: "动作方式", hint: "走路、转身、进入空间时的节奏。" },
      { key: "gestures", label: "手势", hint: "说话和思考时的手部语言。" },
      { key: "emotional_responses", label: "情绪反应", hint: "愤怒、害怕、亲近或受伤时的表现。", wide: true },
      { key: "behavioral_traits", label: "行为特征", hint: "长期稳定、可被旁人观察到的行为模式。" },
      { key: "typical_reactions", label: "典型反应", hint: "面对压力、羞辱、亲密或危险时的第一反应。" },
      { key: "situations", label: "不同情境下的表现", hint: "面对权力、亲密、危险、失败或成功时的差异。", wide: true },
    ],
  },
];

function emptyIdentities(): Record<IdentityKey, Record<string, string>> {
  return { literary_identity: {}, visual_identity: {}, vocal_identity: {}, performance_identity: {} };
}

function characterDraft(character: StudioCharacter): CharacterDraft {
  return {
    name: character.name || "",
    role: character.role || "",
    summary: character.summary || "",
    concept: character.concept || "",
    identities: {
      literary_identity: { ...(character.literary_identity || {}) },
      visual_identity: { ...(character.visual_identity || {}) },
      vocal_identity: { ...(character.vocal_identity || {}) },
      performance_identity: { ...(character.performance_identity || {}) },
    },
  };
}

function characterAppearance(character: StudioCharacter): string {
  const visual = character.visual_identity || {};
  return visual.standard_appearance || visual.clothing || visual.face || character.summary || "视觉 Canon 尚未填写";
}

function sceneDraft(scene: StudioScene): SceneDraft {
  return {
    title: scene.title || "",
    summary: scene.summary || "",
    sort_order: scene.sort_order || 0,
    status: scene.status || "draft",
    given_circumstances: {
      time: scene.given_circumstances?.time || "",
      place: scene.given_circumstances?.place || "",
      environment: scene.given_circumstances?.environment || "",
      background: scene.given_circumstances?.background || "",
      prior_events: scene.given_circumstances?.prior_events || "",
    },
    dramatic_situation: {
      central_question: scene.dramatic_situation?.central_question || "",
      primary_conflict: scene.dramatic_situation?.primary_conflict || "",
      turn: scene.dramatic_situation?.turn || "",
    },
    dialogue: scene.dialogue || "",
    direction: {
      blocking: scene.direction?.blocking || "",
      spatial: scene.direction?.spatial || "",
      performance_direction: scene.direction?.performance_direction || "",
      camera: scene.direction?.camera || "",
    },
  };
}

function castDraft(entry: SceneCastEntry): SceneCastDraft {
  return {
    character_id: entry.character_id,
    character_name: entry.character_name || "Unknown Character",
    character_role: entry.character_role || "",
    objective: entry.objective || "",
    action: entry.action || "",
    conflict: entry.conflict || "",
    emotional_state: entry.emotional_state || "",
    performance_direction: entry.performance_direction || "",
    subtext: entry.subtext || "",
  };
}

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

async function uploadAsset(workplaceId: string, form: FormData): Promise<StudioAsset> {
  const response = await fetch(`${API_BASE}/workplaces/${workplaceId}/assets/upload`, {
    method: "POST",
    body: form,
  });
  let payload: any = null;
  try { payload = await response.json(); } catch { payload = null; }
  if (!response.ok) throw new StudioApiError(response.status, payload);
  return payload?.data as StudioAsset;
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

const ASSET_TYPE_INFO: Record<AssetType, { label: string; en: string; icon: string }> = {
  image: { label: "图片", en: "IMAGE", icon: "image" },
  audio: { label: "音频", en: "AUDIO", icon: "audio" },
  video: { label: "视频", en: "VIDEO", icon: "video" },
  document: { label: "文档", en: "DOCUMENT", icon: "file" },
  other: { label: "其他", en: "OTHER", icon: "file" },
};
const ASSET_RESOURCE_INFO: Record<AssetResourceType, { label: string; plural: string }> = {
  character: { label: "Character", plural: "characters" },
  scene: { label: "Scene", plural: "scenes" },
  document: { label: "Document", plural: "documents" },
};

function formatBytes(value: number): string {
  if (!value) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  let size = value; let index = 0;
  while (size >= 1024 && index < units.length - 1) { size /= 1024; index += 1; }
  return `${size >= 10 || index === 0 ? size.toFixed(0) : size.toFixed(1)} ${units[index]}`;
}
function formatDuration(value: number | null): string {
  if (value === null || value === undefined) return "";
  const seconds = Math.max(0, Math.round(value / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
function assetMediaMeta(asset: StudioAsset): string {
  const parts: string[] = [];
  if (asset.width && asset.height) parts.push(`${asset.width}×${asset.height}`);
  if (asset.duration_ms !== null) parts.push(formatDuration(asset.duration_ms));
  if (asset.file_size) parts.push(formatBytes(asset.file_size));
  return parts.join(" · ");
}
function resourcePath(type: AssetResourceType): string { return ASSET_RESOURCE_INFO[type].plural; }

function inspectMedia(file: File): Promise<{ width?: number; height?: number; duration_ms?: number }> {
  return new Promise(resolve => {
    if (!file.type.startsWith("image/") && !file.type.startsWith("audio/") && !file.type.startsWith("video/")) {
      resolve({}); return;
    }
    const url = URL.createObjectURL(file);
    let settled = false;
    const finish = (value: { width?: number; height?: number; duration_ms?: number }) => {
      if (settled) return;
      settled = true; URL.revokeObjectURL(url); resolve(value);
    };
    const timer = window.setTimeout(() => finish({}), 5000);
    try {
      if (file.type.startsWith("image/")) {
        const image = new Image();
        image.onload = () => { window.clearTimeout(timer); finish({ width: image.naturalWidth, height: image.naturalHeight }); };
        image.onerror = () => { window.clearTimeout(timer); finish({}); };
        image.src = url;
      } else {
        const media = document.createElement(file.type.startsWith("audio/") ? "audio" : "video");
        media.preload = "metadata";
        media.onloadedmetadata = () => {
          window.clearTimeout(timer);
          finish({
            width: media instanceof HTMLVideoElement ? media.videoWidth : undefined,
            height: media instanceof HTMLVideoElement ? media.videoHeight : undefined,
            duration_ms: Number.isFinite(media.duration) ? Math.round(media.duration * 1000) : undefined,
          });
        };
        media.onerror = () => { window.clearTimeout(timer); finish({}); };
        media.src = url;
      }
    } catch {
      window.clearTimeout(timer); finish({});
    }
  });
}

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
    audio: "M9 18V5l10-2v13 M9 18a3 3 0 1 1-3-3 3 3 0 0 1 3 3 M19 16a3 3 0 1 1-3-3 3 3 0 0 1 3 3",
    video: "M3 6h13v12H3z M16 10l5-3v10l-5-3",
    file: "M6 3h8l4 4v14H6z M14 3v5h4 M9 13h6 M9 17h6",
    grid: "M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z",
    list: "M8 6h12 M8 12h12 M8 18h12 M4 6h.01 M4 12h.01 M4 18h.01",
    link: "M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1 M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1",
    trash: "M4 7h16 M9 7V4h6v3 M7 7l1 13h8l1-13 M10 11v5 M14 11v5",
    upload: "M12 16V4 M7 9l5-5 5 5 M4 16v4h16v-4",
    image: "M4 4h16v16H4z M4 15l5-5 4 4 3-3 4 4 M9 8h.01",
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

function AssetPreview({ asset, compact = false, interactive = false }: {
  asset: StudioAsset; compact?: boolean; interactive?: boolean;
}) {
  const [broken, setBroken] = React.useState(false);
  React.useEffect(() => setBroken(false), [asset.id, asset.updated_at]);
  const info = ASSET_TYPE_INFO[asset.asset_type] || ASSET_TYPE_INFO.other;
  if (asset.file_url && !broken && asset.asset_type === "image") {
    return <div className={`asset-preview image-preview ${compact ? "compact" : ""}`}><img src={asset.file_url} alt={asset.name} loading="lazy" onError={() => setBroken(true)}/><span className="asset-type-stamp"><Icon name={info.icon}/>{info.en}</span></div>;
  }
  if (asset.file_url && !broken && interactive && asset.asset_type === "audio") {
    return <div className="asset-preview native-media"><div className="asset-native-head"><Icon name="audio"/><strong>{asset.name}</strong></div><audio controls preload="metadata" src={asset.file_url} onError={() => setBroken(true)}/></div>;
  }
  if (asset.file_url && !broken && interactive && asset.asset_type === "video") {
    return <div className={`asset-preview video-preview ${compact ? "compact" : ""}`}><video controls preload="metadata" src={asset.file_url} onError={() => setBroken(true)}/><span className="asset-type-stamp"><Icon name="video"/>{info.en}</span></div>;
  }
  return <div className={`asset-preview asset-placeholder ${compact ? "compact" : ""}`}><Icon name={info.icon}/><span>{asset.mime_type || info.en}</span>{broken && <small>文件不可读取</small>}</div>;
}

function AssetLibraryPicker({ workplaceId, resourceType, resourceId, linked, onChanged, onClose }: {
  workplaceId: string; resourceType: AssetResourceType; resourceId: string;
  linked: StudioAsset[]; onChanged: (assets: StudioAsset[]) => void; onClose: () => void;
}) {
  const [assets, setAssets] = React.useState<StudioAsset[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [busy, setBusy] = React.useState("");
  const [error, setError] = React.useState("");
  const linkedIds = new Set(linked.map(asset => asset.id));

  React.useEffect(() => {
    let alive = true;
    setLoading(true);
    api<StudioAsset[]>(`/workplaces/${workplaceId}/assets`)
      .then(list => { if (alive) setAssets(list); })
      .catch((cause: any) => { if (alive) setError(cause?.message || "无法读取资源库"); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [workplaceId]);

  async function toggle(asset: StudioAsset) {
    const isLinked = linkedIds.has(asset.id);
    setBusy(asset.id); setError("");
    try {
      if (isLinked) {
        await api(`/workplaces/${workplaceId}/assets/${asset.id}/links/${resourceType}/${resourceId}`, { method: "DELETE" });
        onChanged(linked.filter(item => item.id !== asset.id));
      } else {
        await api<AssetLink>(`/workplaces/${workplaceId}/assets/${asset.id}/links`, {
          method: "POST", body: { resource_type: resourceType, resource_id: resourceId },
        });
        onChanged([...linked, asset]);
      }
    } catch (cause: any) {
      setError(cause?.message || "无法更新资源关联");
    } finally {
      setBusy("");
    }
  }

  return <div className="asset-picker">
    <div className="asset-picker-head"><div><div className="eyebrow">ASSET LIBRARY</div><h3>从资源库选择</h3><p>关联只保存稳定 Asset ID，不复制文件或元数据。</p></div><button className="quiet-button" onClick={onClose}>收起</button></div>
    {error && <p className="form-error">{error}</p>}
    {loading ? <div className="asset-picker-state">正在读取资源库……</div> : !assets.length ? <div className="asset-picker-state">资源库还是空的。请先在 Assets 页面上传文件。</div> : <div className="asset-picker-grid">{assets.map(asset => {
      const isLinked = linkedIds.has(asset.id);
      return <article className={`asset-picker-card ${isLinked ? "linked" : ""}`} key={asset.id}>
        <AssetPreview asset={asset} compact/>
        <div className="asset-picker-copy"><strong>{asset.name}</strong><small>{ASSET_TYPE_INFO[asset.asset_type].label}{assetMediaMeta(asset) ? ` · ${assetMediaMeta(asset)}` : ""}</small></div>
        <button className={isLinked ? "quiet-button" : "tool-button primary"} disabled={busy === asset.id} onClick={() => void toggle(asset)}>{busy === asset.id ? "更新中…" : isLinked ? "解除" : "关联"}</button>
      </article>;
    })}</div>}
  </div>;
}

function AssetLinkPanel({ workplaceId, resourceType, resourceId, notify }: {
  workplaceId: string; resourceType: AssetResourceType; resourceId: string; notify: (message: string) => void;
}) {
  const [assets, setAssets] = React.useState<StudioAsset[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState("");
  const [picking, setPicking] = React.useState(false);

  React.useEffect(() => {
    let alive = true;
    setLoading(true); setError(""); setPicking(false);
    api<StudioAsset[]>(`/workplaces/${workplaceId}/${resourcePath(resourceType)}/${resourceId}/assets`)
      .then(list => { if (alive) setAssets(list); })
      .catch((cause: any) => { if (alive) setError(cause?.message || "无法读取关联资源"); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [workplaceId, resourceType, resourceId]);

  function changed(next: StudioAsset[]) {
    setAssets(next);
    notify("资源关联已更新");
  }

  return <section className="asset-link-panel">
    <div className="asset-link-panel-head"><div><div className="eyebrow">LINKED ASSETS</div><h3>{ASSET_RESOURCE_INFO[resourceType].label} 的创作资源</h3><p>标准形象、参考图、声音或其他文件都从这里复用。</p></div><button className="tool-button" onClick={() => setPicking(value => !value)}><Icon name="link"/>{picking ? "收起资源库" : "关联资源"}</button></div>
    {error && <p className="form-error">{error}</p>}
    {loading ? <div className="asset-inline-state">正在读取关联资源……</div> : !assets.length ? <div className="asset-inline-empty">尚未关联任何资源。文件本身独立存在于 Assets 中。</div> : <div className="linked-asset-grid">{assets.map(asset => <article className="linked-asset-card" key={asset.id}>
      <AssetPreview asset={asset} compact interactive/>
      <div><strong>{asset.name}</strong><small>{ASSET_TYPE_INFO[asset.asset_type].label}{assetMediaMeta(asset) ? ` · ${assetMediaMeta(asset)}` : ""}</small></div>
    </article>)}</div>}
    {picking && <AssetLibraryPicker workplaceId={workplaceId} resourceType={resourceType} resourceId={resourceId} linked={assets} onChanged={changed} onClose={() => setPicking(false)}/>}
  </section>;
}

const CHARACTER_TABS: { key: CharacterTab; title: string; en: string; icon: string }[] = [
  { key: "overview", title: "概览", en: "OVERVIEW", icon: "book" },
  { key: "identity", title: "身份", en: "IDENTITY", icon: "users" },
  { key: "outfits", title: "服装", en: "OUTFITS", icon: "grid" },
  { key: "artwork", title: "视觉作品", en: "ARTWORK", icon: "images" },
  { key: "canon", title: "正式设定", en: "CANON", icon: "history" },
];

const OUTFIT_KIND_INFO: Record<CharacterOutfitKind, { label: string; en: string }> = {
  standard: { label: "标准", en: "STANDARD" },
  casual: { label: "日常", en: "CASUAL" },
  battle: { label: "战斗", en: "BATTLE" },
  formal: { label: "正式", en: "FORMAL" },
  custom: { label: "自定义", en: "CUSTOM" },
};

const ARTWORK_TYPE_INFO: Record<CharacterArtworkType, { label: string; en: string; hint: string }> = {
  avatar: { label: "头像", en: "AVATAR", hint: "用于角色索引与正式头像的胸像构图。" },
  full_body: { label: "全身立绘", en: "FULL BODY", hint: "完整展示体型、姿态与默认服装。" },
  character_sheet: { label: "角色设定图", en: "CHARACTER SHEET", hint: "包含多角度、色板与视觉 Canon 摘要。" },
  expression_sheet: { label: "表情参考", en: "EXPRESSION SHEET", hint: "同一张脸的多种稳定表情。" },
  outfit: { label: "服装设计图", en: "OUTFIT", hint: "指定服装的材料、结构与穿着效果。" },
};

function blankOutfitDraft(): CharacterOutfitDraft {
  return {
    name: "", kind: "standard", description: "", components: "", materials: "",
    colors: "", accessories: "", special_features: "", image_prompt: "",
  };
}

function outfitDraftFrom(outfit: CharacterOutfit): CharacterOutfitDraft {
  return {
    name: outfit.name || "", kind: outfit.kind || "custom",
    description: outfit.description || "",
    components: outfit.components.join(", "), materials: outfit.materials.join(", "),
    colors: outfit.colors.join(", "), accessories: outfit.accessories.join(", "),
    special_features: outfit.special_features.join(", "),
    image_prompt: outfit.image_prompt || "",
  };
}

function outfitList(value: string): string[] {
  return value.split(/[,，\n]/).map(item => item.trim()).filter(Boolean);
}

function outfitPayload(draft: CharacterOutfitDraft) {
  return {
    name: draft.name.trim(),
    kind: draft.kind,
    description: draft.description.trim(),
    components: outfitList(draft.components),
    materials: outfitList(draft.materials),
    colors: outfitList(draft.colors),
    accessories: outfitList(draft.accessories),
    special_features: outfitList(draft.special_features),
    image_prompt: draft.image_prompt.trim(),
  };
}

function artworkTypeOf(asset: StudioAsset): string {
  const metadata = asset.generation_metadata as any;
  return typeof metadata?.artwork_type === "string" ? metadata.artwork_type : "reference";
}

function artworkOutfitId(asset: StudioAsset): string {
  const metadata = asset.generation_metadata as any;
  return typeof metadata?.outfit_id === "string" ? metadata.outfit_id : "";
}

function CharacterAvatar({ character, compact = false }: { character: StudioCharacter; compact?: boolean }) {
  const avatar = character.avatar;
  if (avatar?.file_url) return <div className={`character-avatar ${compact ? "compact" : ""}`}><img src={avatar.file_url} alt={character.name}/></div>;
  return <div className={`character-avatar placeholder ${compact ? "compact" : ""}`}><span>{character.name.trim().slice(0, 1) || "K"}</span></div>;
}

function CharacterOverviewPanel({ character, draft, dirty, saving, onEdit, onSave, onTab }: {
  character: StudioCharacter; draft: CharacterDraft; dirty: boolean; saving: boolean;
  onEdit: (field: "name" | "role" | "summary" | "concept", value: string) => void;
  onSave: () => void; onTab: (tab: CharacterTab) => void;
}) {
  const visual = character.visual_identity || {};
  const defaultAppearance = visual.standard_appearance || visual.face || character.summary || "视觉 Canon 仍在形成。";
  return <div className="character-tab-body overview-body">
    <section className="character-overview-grid">
      <div className="character-portrait-frame">
        <CharacterAvatar character={character}/>
        <div className="portrait-caption"><span>{character.avatar ? "APPROVED AVATAR" : "AUTHOR PORTRAIT PENDING"}</span><small>{character.avatar ? "作者已确认" : "生成头像并在 Artwork 中设为正式头像。"}</small></div>
      </div>
      <div className="character-overview-copy">
        <div className="eyebrow brass-text">CHARACTER STUDIO</div>
        <h2>{character.name}</h2>
        <p className="character-role-line">{character.role || "未指定角色定位"}</p>
        <p className="character-intro">{character.summary || "从一个简单的人物概念开始，逐步建立文学、视觉、声音与表演身份。"}</p>
        <div className="character-quick-facts">
          <div><span>默认服装</span><strong>由 Outfits 管理</strong></div>
          <div><span>正式立绘</span><strong>{character.full_body_asset_id ? "已确认" : "待确认"}</strong></div>
          <div><span>视觉 Canon</span><strong>{visual.standard_appearance ? "已建立" : "待补充"}</strong></div>
          <div><span>稳定 ID</span><strong>{character.id.slice(0, 8)}</strong></div>
        </div>
        <div className="character-overview-actions">
          <button className="tool-button primary" onClick={() => onTab("identity")}><Icon name="pen"/>编辑四类身份</button>
          <button className="tool-button" onClick={() => onTab("artwork")}><Icon name="sparkle"/>生成视觉作品</button>
          <button className="tool-button" onClick={() => onTab("outfits")}><Icon name="grid"/>设计服装</button>
        </div>
        <p className="character-appearance-note"><span>标准形象</span>{defaultAppearance}</p>
      </div>
    </section>
    <section className="character-meta-panel studio-meta-panel">
      <div className="character-section-heading wide"><div><div className="eyebrow">AUTHOR NOTES</div><h3>人物档案信息</h3></div><span className={dirty ? "identity-dirty" : ""}>{dirty ? "有未保存修改" : "已保存"}</span></div>
      <label className="identity-field"><span>角色名</span><small>稳定、可识别的正式称呼。</small><input value={draft.name} maxLength={512} onChange={(event: any) => onEdit("name", event.target.value)}/></label>
      <label className="identity-field"><span>角色定位</span><small>主角、对手、配角或叙述者。</small><input value={draft.role} maxLength={256} onChange={(event: any) => onEdit("role", event.target.value)}/></label>
      <label className="identity-field wide"><span>人物概念</span><small>最初的创作种子。AI 以此为起点补全身份，但不会替换这里。</small><textarea rows={3} value={draft.concept} onChange={(event: any) => onEdit("concept", event.target.value)}/></label>
      <label className="identity-field wide"><span>一句话档案</span><small>迅速回到这个角色是谁。</small><textarea rows={3} value={draft.summary} onChange={(event: any) => onEdit("summary", event.target.value)}/></label>
      <div className="identity-panel-actions wide"><span>这些信息属于正式档案，不会由 AI 自动覆盖。</span><button className="tool-button primary" disabled={saving || !dirty} onClick={onSave}>{saving ? "保存中…" : "保存档案信息"}</button></div>
    </section>
  </div>;
}

function CharacterIdentityPanel({ character, draft, sectionKey, setSectionKey, dirtySections, saving, aiBusy, drafts, onEdit, onSave, onRegenerate, onDraftEdit, onDraftSave, onApply, onDiscard }: {
  character: StudioCharacter; draft: CharacterDraft; sectionKey: IdentityKey;
  setSectionKey: (key: IdentityKey) => void; dirtySections: Record<IdentityKey, boolean>;
  saving: boolean; aiBusy: string; drafts: CharacterAiDraft[];
  onEdit: (key: IdentityKey, field: string, value: string) => void;
  onSave: (key: IdentityKey) => void;
  onRegenerate: (key?: IdentityKey) => void;
  onDraftEdit: (key: IdentityKey, field: string, value: string) => void;
  onDraftSave: (key: IdentityKey) => void;
  onApply: (key: IdentityKey) => void;
  onDiscard: (key: IdentityKey) => void;
}) {
  const current = CHARACTER_SECTIONS.find(section => section.key === sectionKey) || CHARACTER_SECTIONS[0];
  const aiDraft = drafts.find(item => item.section === current.key);
  const identity = draft.identities[current.key] || {};
  return <div className="character-tab-body identity-body">
    <div className="identity-toolbar">
      <div><div className="eyebrow">FOUR IDENTITIES</div><h3>角色的稳定身份</h3><p>每一部分独立保存。AI 生成的内容先进入草稿，只有你明确应用后才写入 Canon。</p></div>
      <button className="tool-button" disabled={!!aiBusy} onClick={() => onRegenerate()}><Icon name="sparkle"/>{aiBusy === "all" ? "AI 正在补全…" : "AI 补全全部身份"}</button>
    </div>
    <div className="identity-tabs">{CHARACTER_SECTIONS.map(section => <button key={section.key} className={sectionKey === section.key ? "active" : ""} onClick={() => setSectionKey(section.key)}><Icon name={section.icon}/><span>{section.title}</span><small>{section.en}</small>{dirtySections[section.key] && <i/>}</button>)}</div>
    <section className="identity-panel">
      <div className="identity-panel-head"><div><div className="eyebrow">{current.en}</div><h3>{current.title}</h3><p>{current.description}</p></div><span className={dirtySections[current.key] ? "identity-dirty" : ""}>{dirtySections[current.key] ? "Canon 有未保存修改" : "Canon 已保存"}</span></div>
      {current.key === "visual_identity" && <div className="canon-note"><strong>视觉 Canon 由作者控制</strong><span>生成图片里的机械手臂、新服装、伤痕等新特征不会自动写回这里。只有你保存或应用草稿后，才会成为正式视觉设定。</span></div>}
      <div className="identity-grid">{current.fields.map(field => <label key={field.key} className={`identity-field ${field.wide ? "wide" : ""}`}><span>{field.label}</span><small>{field.hint}</small><textarea rows={field.wide ? 4 : 3} value={identity[field.key] || ""} onChange={(event: any) => onEdit(current.key, field.key, event.target.value)}/></label>)}</div>
      <div className="identity-panel-actions"><span>{dirtySections[current.key] ? "只保存当前部分，不影响其他身份资料。" : "可以随时回来继续补充。"}</span><div className="identity-action-group"><button className="tool-button" disabled={!!aiBusy} onClick={() => onRegenerate(current.key)}>{aiBusy === current.key ? "正在生成…" : "只重新生成本节"}</button><button className="tool-button primary" disabled={saving || !dirtySections[current.key]} onClick={() => onSave(current.key)}>保存{current.title}</button></div></div>
    </section>
    {aiDraft ? <section className="ai-draft-panel">
      <div className="ai-draft-head"><div><div className="eyebrow">AI PROPOSAL · NOT CANON</div><h3>{current.title}草稿</h3><p>这是模型根据人物概念生成的建议。可以逐字修改、保存草稿，或应用为正式设定。</p></div><span className={aiDraft.author_edited ? "draft-edited" : "draft-ai"}>{aiDraft.author_edited ? "作者已修改" : "AI 原始草稿"}</span></div>
      <div className="identity-grid draft-grid">{current.fields.map(field => <label key={field.key} className={`identity-field ${field.wide ? "wide" : ""}`}><span>{field.label}</span><small>{field.hint}</small><textarea rows={field.wide ? 4 : 3} value={aiDraft.content[field.key] || ""} onChange={(event: any) => onDraftEdit(current.key, field.key, event.target.value)}/></label>)}</div>
      <div className="ai-draft-actions"><span>{aiDraft.model ? `模型：${aiDraft.model}` : "模型草稿"}</span><div className="identity-action-group"><button className="quiet-button danger-quiet" disabled={!!aiBusy} onClick={() => onDiscard(current.key)}>丢弃草稿</button><button className="tool-button" disabled={!!aiBusy} onClick={() => onDraftSave(current.key)}>保存草稿修改</button><button className="tool-button primary" disabled={!!aiBusy} onClick={() => onApply(current.key)}>应用为正式 {current.title}</button></div></div>
    </section> : <div className="ai-draft-empty"><Icon name="sparkle"/><span>本节还没有 AI 草稿。可以使用「只重新生成本节」获取建议。</span></div>}
  </div>;
}

function CharacterOutfitsPanel({ workplaceId, characterId, outfits, artworks, reload, notify }: {
  workplaceId: string; characterId: string; outfits: CharacterOutfit[];
  artworks: StudioAsset[]; reload: () => Promise<void>; notify: (message: string) => void;
}) {
  const [editing, setEditing] = React.useState<string | null>(null);
  const [draft, setDraft] = React.useState<CharacterOutfitDraft>(blankOutfitDraft());
  const [busy, setBusy] = React.useState("");
  const [error, setError] = React.useState("");

  function startNew() { setEditing("new"); setDraft(blankOutfitDraft()); setError(""); }
  function startEdit(outfit: CharacterOutfit) { setEditing(outfit.id); setDraft(outfitDraftFrom(outfit)); setError(""); }
  function edit(field: keyof CharacterOutfitDraft, value: string) { setDraft(previous => ({ ...previous, [field]: value })); }

  async function save() {
    if (!draft.name.trim() || busy) { if (!draft.name.trim()) setError("服装名称不能为空"); return; }
    setBusy("save"); setError("");
    try {
      const path = editing === "new"
        ? `/workplaces/${workplaceId}/characters/${characterId}/outfits`
        : `/workplaces/${workplaceId}/characters/${characterId}/outfits/${editing}`;
      await api(path, { method: editing === "new" ? "POST" : "PUT", body: outfitPayload(draft) });
      await reload(); setEditing(null); notify("服装设定已保存");
    } catch (cause: any) { setError(cause?.message || "无法保存服装设定"); }
    finally { setBusy(""); }
  }

  async function makeDefault(outfit: CharacterOutfit) {
    setBusy(outfit.id); setError("");
    try {
      await api(`/workplaces/${workplaceId}/characters/${characterId}/outfits/${outfit.id}/default`, { method: "POST" });
      await reload(); notify(`${outfit.name} 已设为默认服装`);
    } catch (cause: any) { setError(cause?.message || "无法设置默认服装"); }
    finally { setBusy(""); }
  }

  async function archive(outfit: CharacterOutfit) {
    if (!window.confirm(`归档服装「${outfit.name}」？已有引用与历史图片不会被删除。`)) return;
    setBusy(outfit.id); setError("");
    try {
      await api(`/workplaces/${workplaceId}/characters/${characterId}/outfits/${outfit.id}`, { method: "DELETE" });
      await reload(); notify("服装已归档");
    } catch (cause: any) { setError(cause?.message || "无法归档服装"); }
    finally { setBusy(""); }
  }

  async function setReference(outfit: CharacterOutfit, assetId: string) {
    if (!assetId) return;
    setBusy(outfit.id); setError("");
    try {
      await api(`/workplaces/${workplaceId}/characters/${characterId}/outfits/${outfit.id}/reference`, { method: "PUT", body: { asset_id: assetId } });
      await reload(); notify("服装参考图已确认");
    } catch (cause: any) { setError(cause?.message || "无法设置参考图"); }
    finally { setBusy(""); }
  }

  return <div className="character-tab-body outfits-body">
    <div className="identity-toolbar"><div><div className="eyebrow">WARDROBE</div><h3>服装方案</h3><p>每套服装是独立设计，不会改写角色的基础 Visual Identity。场景与分镜以后会按 Outfit ID 引用。</p></div><button className="tool-button primary" onClick={startNew}><Icon name="plus"/>建立服装</button></div>
    {error && <p className="form-error">{error}</p>}
    {!outfits.length ? <div className="studio-empty-panel"><Icon name="grid"/><h3>衣橱还是空的</h3><p>先建立一套 Standard Outfit，确定角色最常被识别的服装轮廓。</p><button className="tool-button primary" onClick={startNew}>建立第一套服装</button></div> : <div className="outfit-grid">{outfits.map(outfit => {
      const reference = artworks.find(asset => asset.id === outfit.reference_asset_id);
      return <article className={`outfit-card ${outfit.is_default ? "default" : ""}`} key={outfit.id}>
        <div className="outfit-card-visual">{reference?.file_url ? <img src={reference.file_url} alt={`${outfit.name} reference`}/> : <div className="outfit-placeholder"><Icon name="grid"/><span>{OUTFIT_KIND_INFO[outfit.kind]?.en || "OUTFIT"}</span></div>}</div>
        <div className="outfit-card-copy"><div className="outfit-card-title"><div><small>{OUTFIT_KIND_INFO[outfit.kind]?.en || "CUSTOM"}</small><h3>{outfit.name}</h3></div>{outfit.is_default && <span className="default-badge">默认</span>}</div><p>{outfit.description || "尚未填写服装说明。"}</p>{outfit.colors.length > 0 && <div className="outfit-chips">{outfit.colors.map(color => <span key={color}>{color}</span>)}</div>}
          <div className="outfit-card-actions"><button className="quiet-button" disabled={busy === outfit.id} onClick={() => startEdit(outfit)}>编辑</button>{!outfit.is_default && <button className="quiet-button" disabled={busy === outfit.id} onClick={() => void makeDefault(outfit)}>设为默认</button>}<button className="quiet-button danger-quiet" disabled={busy === outfit.id} onClick={() => void archive(outfit)}>归档</button></div>
          <label className="outfit-reference-select"><span>正式参考图</span><select value="" disabled={!artworks.length || busy === outfit.id} onChange={(event: any) => void setReference(outfit, event.target.value)}><option value="">{reference ? "更换参考图…" : "选择已关联图片…"}</option>{artworks.filter(asset => asset.file_url).map(asset => <option key={asset.id} value={asset.id}>{asset.name}</option>)}</select></label>
        </div>
      </article>;
    })}</div>}
    {editing && <section className="outfit-editor">
      <div className="outfit-editor-head"><div><div className="eyebrow">{editing === "new" ? "NEW OUTFIT" : "EDIT OUTFIT"}</div><h3>{editing === "new" ? "建立服装方案" : "编辑服装方案"}</h3></div><button className="icon-button" onClick={() => setEditing(null)} aria-label="关闭"><Icon name="close"/></button></div>
      <div className="outfit-editor-grid">
        <label className="identity-field"><span>名称</span><small>例如 Standard Outfit 或 Battle Outfit。</small><input value={draft.name} maxLength={512} onChange={(event: any) => edit("name", event.target.value)}/></label>
        <label className="identity-field"><span>类型</span><small>用于衣橱分类，不影响 Canon。</small><select value={draft.kind} onChange={(event: any) => edit("kind", event.target.value)}>{Object.entries(OUTFIT_KIND_INFO).map(([key, info]) => <option key={key} value={key}>{info.label} · {info.en}</option>)}</select></label>
        <label className="identity-field wide"><span>说明</span><small>整体轮廓、场合与穿着状态。</small><textarea rows={3} value={draft.description} onChange={(event: any) => edit("description", event.target.value)}/></label>
        <label className="identity-field"><span>服装组成</span><small>用逗号分隔：外套、衬衫、裤装……</small><textarea rows={3} value={draft.components} onChange={(event: any) => edit("components", event.target.value)}/></label>
        <label className="identity-field"><span>材料</span><small>用逗号分隔：皮革、黄铜、粗呢……</small><textarea rows={3} value={draft.materials} onChange={(event: any) => edit("materials", event.target.value)}/></label>
        <label className="identity-field"><span>颜色</span><small>稳定的服装色彩关系。</small><textarea rows={3} value={draft.colors} onChange={(event: any) => edit("colors", event.target.value)}/></label>
        <label className="identity-field"><span>配件</span><small>护目镜、工具带、饰针……</small><textarea rows={3} value={draft.accessories} onChange={(event: any) => edit("accessories", event.target.value)}/></label>
        <label className="identity-field wide"><span>特殊结构</span><small>机械护臂、可拆卸披风、隐藏口袋等。</small><textarea rows={3} value={draft.special_features} onChange={(event: any) => edit("special_features", event.target.value)}/></label>
        <label className="identity-field wide"><span>服装图像提示</span><small>给图像生成的稳定设计说明，不替代视觉 Canon。</small><textarea rows={4} value={draft.image_prompt} onChange={(event: any) => edit("image_prompt", event.target.value)}/></label>
      </div>
      <div className="identity-panel-actions"><span>服装不会自动成为场景中的默认外观；默认项需要你明确选择。</span><button className="tool-button primary" disabled={busy === "save"} onClick={() => void save()}>{busy === "save" ? "保存中…" : "保存服装"}</button></div>
    </section>}
  </div>;
}

function CharacterArtworkPanel({ workplaceId, character, outfits, artworks, reloadArtworks, reloadOutfits, onCharacterChange, notify }: {
  workplaceId: string; character: StudioCharacter; outfits: CharacterOutfit[];
  artworks: StudioAsset[]; reloadArtworks: () => Promise<void>; reloadOutfits: () => Promise<void>;
  onCharacterChange: (character: StudioCharacter) => void; notify: (message: string) => void;
}) {
  const [type, setType] = React.useState<CharacterArtworkType>("avatar");
  const [outfitId, setOutfitId] = React.useState("");
  const [extra, setExtra] = React.useState("");
  const [prompt, setPrompt] = React.useState("");
  const [busy, setBusy] = React.useState("");
  const [error, setError] = React.useState("");
  const [selectedId, setSelectedId] = React.useState("");

  React.useEffect(() => {
    if (!outfits.length) { setOutfitId(""); return; }
    if (!outfits.some(outfit => outfit.id === outfitId)) {
      setOutfitId((outfits.find(outfit => outfit.is_default) || outfits[0]).id);
    }
  }, [outfits, outfitId]);

  const selected = artworks.find(asset => asset.id === selectedId) || artworks[0] || null;
  const selectedOutfit = outfits.find(outfit => outfit.id === outfitId) || null;

  async function composePrompt() {
    setBusy("prompt"); setError("");
    try {
      const result = await api<CharacterArtworkPrompt>(`/workplaces/${workplaceId}/characters/${character.id}/artworks/prompt`, {
        method: "POST", body: { artwork_type: type, outfit_id: outfitId || undefined, extra_description: extra },
      });
      setPrompt(result.prompt);
      if (result.outfit_id) setOutfitId(result.outfit_id);
      notify("图像提示已组合，可继续编辑");
      return result.prompt;
    } catch (cause: any) { setError(cause?.message || "无法组合图像提示"); throw cause; }
    finally { setBusy(""); }
  }

  async function generate(finalPrompt?: string) {
    if (busy) return;
    setBusy("generate"); setError("");
    try {
      let value = (finalPrompt ?? prompt).trim();
      if (!value) {
        const result = await api<CharacterArtworkPrompt>(`/workplaces/${workplaceId}/characters/${character.id}/artworks/prompt`, {
          method: "POST", body: { artwork_type: type, outfit_id: outfitId || undefined, extra_description: extra },
        });
        value = result.prompt; setPrompt(value);
      }
      const result = await api<CharacterArtworkResult>(`/workplaces/${workplaceId}/characters/${character.id}/artworks/generate`, {
        method: "POST", body: { artwork_type: type, outfit_id: outfitId || undefined, prompt: value, extra_description: extra },
      });
      setSelectedId(result.asset.id);
      await reloadArtworks();
      notify("视觉作品已生成并保存到 Assets");
    } catch (cause: any) { setError(cause?.message || "图像生成失败，角色 Canon 未被修改"); }
    finally { setBusy(""); }
  }

  async function setAvatar(asset: StudioAsset) {
    setBusy("avatar"); setError("");
    try {
      const updated = await api<StudioCharacter>(`/workplaces/${workplaceId}/characters/${character.id}/avatar`, { method: "POST", body: { asset_id: asset.id } });
      onCharacterChange(updated); notify("已确认为正式 Avatar");
    } catch (cause: any) { setError(cause?.message || "无法设置 Avatar"); }
    finally { setBusy(""); }
  }

  async function setFullBody(asset: StudioAsset) {
    setBusy("full-body"); setError("");
    try {
      const updated = await api<StudioCharacter>(`/workplaces/${workplaceId}/characters/${character.id}/full-body`, { method: "POST", body: { asset_id: asset.id } });
      onCharacterChange(updated); notify("已确认为正式全身立绘");
    } catch (cause: any) { setError(cause?.message || "无法设置全身立绘"); }
    finally { setBusy(""); }
  }

  async function setOutfitReference(asset: StudioAsset) {
    if (!outfitId) { setError("请先选择一套服装，再指定参考图。"); return; }
    setBusy("outfit-reference"); setError("");
    try {
      await api(`/workplaces/${workplaceId}/characters/${character.id}/outfits/${outfitId}/reference`, { method: "PUT", body: { asset_id: asset.id } });
      await reloadOutfits(); notify("已确认为该服装的正式参考图");
    } catch (cause: any) { setError(cause?.message || "无法设置服装参考图"); }
    finally { setBusy(""); }
  }

  return <div className="character-tab-body artwork-body">
    <div className="identity-toolbar"><div><div className="eyebrow">MOSS-IMAGE · SINGLE STILLS</div><h3>角色视觉作品</h3><p>每次生成一张独立图片。结果进入 Assets 并关联角色，旧图片不会被覆盖，也不会自动修改 Canon。</p></div><span className="artwork-count">{artworks.length} 张作品</span></div>
    {error && <p className="form-error">{error}</p>}
    <div className="artwork-workbench">
      <section className="artwork-stage">
        {selected?.file_url ? <img src={selected.file_url} alt={selected.name}/> : <div className="artwork-stage-empty"><Icon name="images"/><h3>还没有生成的视觉作品</h3><p>选择构图类型，组合 Prompt，然后启动一次单张图像生成。</p></div>}
        {selected && <div className="artwork-stage-caption"><div><small>{artworkTypeOf(selected).toUpperCase()}</small><strong>{selected.name}</strong><span>{selected.width && selected.height ? `${selected.width} × ${selected.height}` : assetMediaMeta(selected)}</span></div><div className="artwork-stage-actions"><button className="quiet-button" disabled={busy !== ""} onClick={() => void setAvatar(selected)}>{character.avatar_asset_id === selected.id ? "已是正式 Avatar" : "设为正式 Avatar"}</button><button className="quiet-button" disabled={busy !== ""} onClick={() => void setFullBody(selected)}>{character.full_body_asset_id === selected.id ? "已是正式全身立绘" : "设为正式全身立绘"}</button>{selectedOutfit && <button className="quiet-button" disabled={busy !== ""} onClick={() => void setOutfitReference(selected)}>设为「{selectedOutfit.name}」参考图</button>}</div></div>}
      </section>
      <section className="artwork-controls">
        <div className="artwork-control-row"><label className="identity-field"><span>作品类型</span><small>{ARTWORK_TYPE_INFO[type].hint}</small><select value={type} onChange={(event: any) => { setType(event.target.value); setPrompt(""); }}>{Object.entries(ARTWORK_TYPE_INFO).map(([key, info]) => <option key={key} value={key}>{info.label} · {info.en}</option>)}</select></label><label className="identity-field"><span>服装</span><small>头像与立绘也可使用默认服装。</small><select value={outfitId} onChange={(event: any) => { setOutfitId(event.target.value); setPrompt(""); }}><option value="">不使用服装</option>{outfits.map(outfit => <option key={outfit.id} value={outfit.id}>{outfit.name}{outfit.is_default ? " · 默认" : ""}</option>)}</select></label></div>
        <label className="identity-field"><span>额外创作说明</span><small>例如姿态、光线、背景或情绪；不会写回角色 Canon。</small><textarea rows={3} value={extra} onChange={(event: any) => setExtra(event.target.value)} placeholder="站在工作室窗边，午后侧光，克制的表情……"/></label>
        <div className="artwork-prompt-head"><div><span>图像 Prompt</span><small>生成前完全可见、可编辑。</small></div><button className="quiet-button" disabled={busy !== ""} onClick={() => void composePrompt()}>{busy === "prompt" ? "组合中…" : "重新组合"}</button></div>
        <textarea className="artwork-prompt" rows={9} value={prompt} onChange={(event: any) => setPrompt(event.target.value)} placeholder="点击「组合 Prompt」根据 Visual Canon、服装与构图类型生成，然后在这里调整。"/>
        <div className="artwork-generate-row"><button className="tool-button" disabled={busy !== ""} onClick={() => void composePrompt()}>预览 Prompt</button><button className="tool-button primary" disabled={busy !== ""} onClick={() => void generate()}>{busy === "generate" ? "生成中…" : prompt ? "生成图像" : "组合并生成"}</button><button className="quiet-button" disabled={!prompt || busy !== ""} onClick={() => void generate(prompt)}>重新生成</button></div>
        <p className="artwork-limit-note">当前只生成单张静态图片。图像生成不可用时会明确报错，不会伪造结果。</p>
      </section>
    </div>
    <section className="artwork-gallery-section"><div className="artwork-gallery-head"><div><div className="eyebrow">ARTWORK ARCHIVE</div><h3>全部视觉作品与参考图</h3></div><span>只有作者确认的 Avatar、全身立绘与服装参考图会进入 Storyboard 图像生成。</span></div>{!artworks.length ? <div className="studio-empty-panel compact"><Icon name="images"/><p>生成的第一张作品会出现在这里。</p></div> : <div className="artwork-gallery">{artworks.map(asset => <button key={asset.id} className={`artwork-thumb ${selected?.id === asset.id ? "active" : ""}`} onClick={() => setSelectedId(asset.id)}><AssetPreview asset={asset} compact/><span>{asset.name}</span><small>{artworkTypeOf(asset)}</small>{character.avatar_asset_id === asset.id && <i className="avatar-stamp">AVATAR</i>}{character.full_body_asset_id === asset.id && <i className="avatar-stamp full-body-stamp">FULL BODY</i>}</button>)}</div>}</section>
    <AssetLinkPanel workplaceId={workplaceId} resourceType="character" resourceId={character.id} notify={(message) => { notify(message); void reloadArtworks(); }}/>
  </div>;
}

function CharacterCanonPanel({ character, outfits, drafts, onTab }: {
  character: StudioCharacter; outfits: CharacterOutfit[]; drafts: CharacterAiDraft[];
  onTab: (tab: CharacterTab) => void;
}) {
  return <div className="character-tab-body canon-body">
    <div className="identity-toolbar"><div><div className="eyebrow">AUTHOR APPROVED</div><h3>正式角色设定</h3><p>Canon 只包含作者明确保存或确认的内容。AI 草稿、生成的图片和新视觉特征不会自动进入这里。</p></div><span className="canon-seal">AUTHOR SEAL</span></div>
    <section className="canon-overview-card"><div className="canon-avatar">{character.avatar?.file_url ? <img src={character.avatar.file_url} alt={character.name}/> : <div className="character-avatar placeholder"><span>{character.name.slice(0, 1)}</span></div>}</div><div><div className="eyebrow">OFFICIAL AVATAR</div><h2>{character.name}</h2><p>{character.summary || "这个人物的正式档案仍在书写。"}</p><small>{character.avatar ? "作者已确认这张图片为正式头像。" : "还没有确认正式头像。"}{character.full_body_asset_id ? " 全身立绘也已确认，将优先用于场景与分镜参考。" : ""}</small></div><button className="tool-button" onClick={() => onTab("artwork")}>管理视觉作品</button></section>
    <div className="canon-columns">
      <section className="canon-identity-list"><div className="canon-section-title"><h3>身份 Canon</h3><button className="quiet-button" onClick={() => onTab("identity")}>编辑身份</button></div>{CHARACTER_SECTIONS.map(section => {
        const identity = character[section.key] || {};
        const values = section.fields.filter(field => (identity[field.key] || "").trim());
        return <article key={section.key} className="canon-identity-item"><div><span>{section.en}</span><h4>{section.title}</h4></div>{values.length ? <dl>{values.map(field => <div key={field.key}><dt>{field.label}</dt><dd>{identity[field.key]}</dd></div>)}</dl> : <p>尚未建立正式内容。</p>}</article>;
      })}</section>
      <section className="canon-outfit-list"><div className="canon-section-title"><h3>服装 Canon</h3><button className="quiet-button" onClick={() => onTab("outfits")}>管理服装</button></div>{!outfits.length ? <p className="canon-empty">尚未建立服装方案。</p> : outfits.map(outfit => <article key={outfit.id} className={`canon-outfit-item ${outfit.is_default ? "default" : ""}`}><div><span>{OUTFIT_KIND_INFO[outfit.kind]?.en || "CUSTOM"}</span><h4>{outfit.name}</h4></div><p>{outfit.description || "尚未填写说明。"}</p><small>{outfit.reference_asset_id ? "已确认正式参考图" : "尚无正式参考图"}{outfit.is_default ? " · 默认服装" : ""}</small></article>)}</section>
      <section className="canon-draft-status"><div className="eyebrow">PENDING PROPOSALS</div><strong>{drafts.length}</strong><p>{drafts.length ? "节 AI 草稿等待审核。它们尚未进入 Canon。" : "没有待审核的 AI 草稿。"}</p>{drafts.length > 0 && <button className="tool-button" onClick={() => onTab("identity")}>审核草稿</button>}</section>
    </div>
  </div>;
}

function CharactersWorkspace({ workplace, notify, onStartWriting }: {
  workplace: Workplace; notify: (message: string) => void; onStartWriting: () => void;
}) {
  const [characters, setCharacters] = React.useState<StudioCharacter[]>([]);
  const [active, setActive] = React.useState<StudioCharacter | null>(null);
  const [draft, setDraft] = React.useState<CharacterDraft | null>(null);
  const [aiDrafts, setAiDrafts] = React.useState<CharacterAiDraft[]>([]);
  const [outfits, setOutfits] = React.useState<CharacterOutfit[]>([]);
  const [artworks, setArtworks] = React.useState<StudioAsset[]>([]);
  const [tab, setTab] = React.useState<CharacterTab>("overview");
  const [sectionKey, setSectionKey] = React.useState<IdentityKey>("literary_identity");
  const [dirtySections, setDirtySections] = React.useState<Record<IdentityKey, boolean>>({
    literary_identity: false, visual_identity: false,
    vocal_identity: false, performance_identity: false,
  });
  const [metaDirty, setMetaDirty] = React.useState(false);
  const [loading, setLoading] = React.useState(true);
  const [saving, setSaving] = React.useState(false);
  const [aiBusy, setAiBusy] = React.useState("");
  const [error, setError] = React.useState("");
  const [modal, setModal] = React.useState<"create" | "archive" | null>(null);
  const [newConcept, setNewConcept] = React.useState("");
  const [newName, setNewName] = React.useState("");
  const [newRole, setNewRole] = React.useState("");

  function resetDirty() {
    setMetaDirty(false);
    setDirtySections({ literary_identity: false, visual_identity: false, vocal_identity: false, performance_identity: false });
  }

  function updateCharacterList(character: StudioCharacter) {
    setCharacters(previous => {
      const exists = previous.some(item => item.id === character.id);
      return exists ? previous.map(item => item.id === character.id ? character : item) : [character, ...previous];
    });
  }

  function install(character: StudioCharacter, drafts: CharacterAiDraft[], nextOutfits: CharacterOutfit[], nextArtworks: StudioAsset[]) {
    setActive(character);
    setDraft(characterDraft(character));
    setAiDrafts(drafts);
    setOutfits(nextOutfits);
    setArtworks(nextArtworks);
    resetDirty();
  }

  async function loadDetails(id: string) {
    const [character, drafts, nextOutfits, nextArtworks] = await Promise.all([
      api<StudioCharacter>(`/workplaces/${workplace.id}/characters/${id}`),
      api<CharacterAiDraft[]>(`/workplaces/${workplace.id}/characters/${id}/ai/drafts`),
      api<CharacterOutfit[]>(`/workplaces/${workplace.id}/characters/${id}/outfits`),
      api<StudioAsset[]>(`/workplaces/${workplace.id}/characters/${id}/artworks`),
    ]);
    install(character, drafts, nextOutfits, nextArtworks);
    updateCharacterList(character);
  }

  React.useEffect(() => {
    let alive = true;
    setLoading(true); setError("");
    api<StudioCharacter[]>(`/workplaces/${workplace.id}/characters`)
      .then(async list => {
        if (!alive) return;
        setCharacters(list);
        if (!list.length) { setActive(null); setDraft(null); setAiDrafts([]); setOutfits([]); setArtworks([]); resetDirty(); return; }
        await loadDetails(list[0].id);
      })
      .catch((cause: any) => { if (alive) setError(cause?.message || "无法读取角色列表"); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [workplace.id]);

  const hasChanges = metaDirty || Object.values(dirtySections).some(Boolean);

  async function selectCharacter(id: string) {
    if (active?.id === id) return;
    if (hasChanges && !window.confirm("当前角色还有未保存的修改。切换角色会放弃这些修改，继续吗？")) return;
    setLoading(true); setError("");
    try { await loadDetails(id); setTab("overview"); }
    catch (cause: any) { setError(cause?.message || "无法打开角色"); }
    finally { setLoading(false); }
  }

  async function createCharacter() {
    const concept = newConcept.trim();
    if (!concept || saving) { if (!concept) setError("请先写下一个人物概念"); return; }
    const name = newName.trim() || concept.slice(0, 28);
    setSaving(true); setError("");
    try {
      const created = await api<StudioCharacter>(`/workplaces/${workplace.id}/characters`, {
        method: "POST", body: { name, role: newRole.trim(), concept, summary: concept.slice(0, 400) },
      });
      updateCharacterList(created);
      let aiError = "";
      try {
        await api<CharacterAiDraft[]>(`/workplaces/${workplace.id}/characters/${created.id}/ai/develop`, { method: "POST", body: { concept } });
      } catch (cause: any) { aiError = cause?.message || "AI 人物补全暂时不可用"; }
      await loadDetails(created.id);
      setModal(null); setNewConcept(""); setNewName(""); setNewRole(""); setTab("identity");
      if (aiError) setError(`角色已建立，但 AI 补全失败：${aiError}`); else notify("角色已建立，四类身份草稿等待审核");
    } catch (cause: any) { setError(cause?.message || "创建角色失败"); }
    finally { setSaving(false); }
  }

  async function saveMetadata() {
    if (!active || !draft || saving) return;
    if (!draft.name.trim()) { setError("角色名不能为空"); return; }
    setSaving(true); setError("");
    try {
      const saved = await api<StudioCharacter>(`/workplaces/${workplace.id}/characters/${active.id}`, {
        method: "PUT", body: { name: draft.name.trim(), role: draft.role.trim(), concept: draft.concept.trim(), summary: draft.summary.trim() },
      });
      setActive(saved); updateCharacterList(saved);
      setDraft(previous => previous ? { ...previous, name: saved.name, role: saved.role, concept: saved.concept, summary: saved.summary } : previous);
      setMetaDirty(false); notify("角色档案信息已保存");
    } catch (cause: any) { setError(cause?.message || "保存角色档案失败"); }
    finally { setSaving(false); }
  }

  async function saveIdentity(key: IdentityKey) {
    if (!active || !draft || saving) return;
    setSaving(true); setError("");
    try {
      const saved = await api<StudioCharacter>(`/workplaces/${workplace.id}/characters/${active.id}`, { method: "PUT", body: { [key]: draft.identities[key] } });
      setActive(saved); updateCharacterList(saved);
      setDraft(previous => previous ? { ...previous, identities: { ...previous.identities, [key]: { ...(saved[key] || {}) } } } : previous);
      setDirtySections(previous => ({ ...previous, [key]: false }));
      notify(`${CHARACTER_SECTIONS.find(section => section.key === key)?.title || "身份"}已保存为 Canon`);
    } catch (cause: any) { setError(cause?.message || "保存身份失败"); }
    finally { setSaving(false); }
  }

  async function regenerateIdentity(key?: IdentityKey) {
    if (!active || aiBusy) return;
    setAiBusy(key || "all"); setError("");
    const body = { concept: draft?.concept || active.concept || "" };
    try {
      const path = key
        ? `/workplaces/${workplace.id}/characters/${active.id}/ai/develop/${key}`
        : `/workplaces/${workplace.id}/characters/${active.id}/ai/develop`;
      let next: CharacterAiDraft[];
      try { next = await api<CharacterAiDraft[]>(path, { method: "POST", body }); }
      catch (cause: any) {
        if (cause?.status === 409 && window.confirm("这一节已有你修改过的草稿。重新生成会覆盖它，继续吗？")) {
          next = await api<CharacterAiDraft[]>(path, { method: "POST", body: { ...body, force: true } });
        } else throw cause;
      }
      setAiDrafts(next); notify(key ? "本节 AI 草稿已更新" : "四类身份 AI 草稿已更新");
    } catch (cause: any) { setError(cause?.message || "AI 人物补全失败"); }
    finally { setAiBusy(""); }
  }

  function editDraft(key: IdentityKey, field: string, value: string) {
    setAiDrafts(previous => previous.map(item => item.section === key ? { ...item, content: { ...item.content, [field]: value }, author_edited: true } : item));
  }

  async function saveDraft(key: IdentityKey) {
    if (!active) return;
    const item = aiDrafts.find(entry => entry.section === key);
    if (!item) return;
    setSaving(true); setError("");
    try {
      const saved = await api<CharacterAiDraft>(`/workplaces/${workplace.id}/characters/${active.id}/ai/drafts/${key}`, { method: "PUT", body: { content: item.content } });
      setAiDrafts(previous => previous.map(entry => entry.section === key ? saved : entry));
      notify("AI 草稿修改已保存");
    } catch (cause: any) { setError(cause?.message || "保存草稿失败"); }
    finally { setSaving(false); }
  }

  async function applyDraft(key: IdentityKey) {
    if (!active) return;
    setSaving(true); setError("");
    try {
      const saved = await api<StudioCharacter>(`/workplaces/${workplace.id}/characters/${active.id}/ai/drafts/${key}/apply`, { method: "POST" });
      setActive(saved); updateCharacterList(saved);
      setDraft(previous => previous ? { ...previous, identities: { ...previous.identities, [key]: { ...(saved[key] || {}) } } } : previous);
      setAiDrafts(previous => previous.filter(entry => entry.section !== key));
      notify(`${CHARACTER_SECTIONS.find(section => section.key === key)?.title || "身份"}已确认进入 Canon`);
    } catch (cause: any) { setError(cause?.message || "应用草稿失败"); }
    finally { setSaving(false); }
  }

  async function discardDraft(key: IdentityKey) {
    if (!active || !window.confirm("丢弃这份 AI 草稿？正式 Canon 不受影响。")) return;
    setError("");
    try {
      await api(`/workplaces/${workplace.id}/characters/${active.id}/ai/drafts/${key}`, { method: "DELETE" });
      setAiDrafts(previous => previous.filter(entry => entry.section !== key)); notify("AI 草稿已丢弃");
    } catch (cause: any) { setError(cause?.message || "无法丢弃草稿"); }
  }

  function editMeta(field: "name" | "role" | "summary" | "concept", value: string) {
    setDraft(previous => previous ? { ...previous, [field]: value } : previous); setMetaDirty(true);
  }

  function editIdentity(key: IdentityKey, field: string, value: string) {
    setDraft(previous => previous ? { ...previous, identities: { ...previous.identities, [key]: { ...previous.identities[key], [field]: value } } } : previous);
    setDirtySections(previous => ({ ...previous, [key]: true }));
  }

  async function reloadOutfits() {
    if (!active) return;
    const next = await api<CharacterOutfit[]>(`/workplaces/${workplace.id}/characters/${active.id}/outfits`);
    setOutfits(next);
  }

  async function reloadArtworks() {
    if (!active) return;
    const next = await api<StudioAsset[]>(`/workplaces/${workplace.id}/characters/${active.id}/artworks`);
    setArtworks(next);
  }

  function onCharacterChanged(character: StudioCharacter) {
    setActive(character); updateCharacterList(character);
  }

  async function archiveCharacter() {
    if (!active || saving) return;
    setSaving(true); setError("");
    try {
      await api(`/workplaces/${workplace.id}/characters/${active.id}`, { method: "DELETE" });
      const remaining = characters.filter(character => character.id !== active.id);
      setCharacters(remaining); setModal(null);
      if (remaining.length) await loadDetails(remaining[0].id); else { setActive(null); setDraft(null); setAiDrafts([]); setOutfits([]); setArtworks([]); }
      notify("角色已归档，稳定 ID 与历史引用保留");
    } catch (cause: any) { setError(cause?.message || "归档角色失败"); }
    finally { setSaving(false); }
  }

  function renderCharacterList() {
    if (loading && !characters.length) return <div className="character-state">正在装订角色档案……</div>;
    if (!characters.length) return <div className="character-state character-empty-state"><div className="placeholder-ornament">K</div><h2>还没有角色</h2><p>写下一个简单的人物概念，让 Character Studio 开始补全。</p><button className="head-btn" onClick={() => setModal("create")}><Icon name="plus"/>建立第一个角色</button></div>;
    return <div className="character-list">{characters.map(character => <button key={character.id} className={`character-row ${active?.id === character.id ? "active" : ""}`} onClick={() => void selectCharacter(character.id)}><CharacterAvatar character={character} compact/><div className="character-row-copy"><strong>{character.name}</strong><small>{character.role || "CHARACTER"}</small><span>{character.summary || "档案正在形成。"}</span></div></button>)}</div>;
  }

  function renderDetail() {
    if (!active || !draft) return <div className="character-empty-detail"><div className="placeholder-ornament">K</div><div className="eyebrow brass-text">CHARACTER STUDIO</div><h2>从一个人物概念开始。</h2><p>写下角色是谁、来自哪里、想要什么，AI 会提出四类身份草稿；你逐项审核后，才成为正式 Canon。</p><button className="tool-button primary" onClick={() => setModal("create")}><Icon name="sparkle"/>创建角色概念</button></div>;
    const current = CHARACTER_SECTIONS.find(section => section.key === sectionKey) || CHARACTER_SECTIONS[0];
    return <>
      <div className="character-detail-head"><div><div className="eyebrow">CHARACTER STUDIO · {active.role || "UNASSIGNED"}</div><h2>{active.name}</h2><p>{active.summary || active.concept || "这个角色的档案正在形成。"}</p></div><div className="character-detail-actions"><span className={`character-save-state ${hasChanges ? "dirty" : ""}`}>{hasChanges ? "有未保存修改" : "已保存"}</span><button className="tool-button character-write-next" onClick={onStartWriting}><Icon name="pen"/>去写作</button><button className="head-btn archive-character" disabled={saving} onClick={() => setModal("archive")}>归档角色</button></div></div>
      <div className="character-studio-tabs">{CHARACTER_TABS.map(item => <button key={item.key} className={tab === item.key ? "active" : ""} onClick={() => setTab(item.key)}><Icon name={item.icon}/><span>{item.title}</span><small>{item.en}</small></button>)}</div>
      {tab === "overview" && <CharacterOverviewPanel character={active} draft={draft} dirty={metaDirty} saving={saving} onEdit={editMeta} onSave={() => void saveMetadata()} onTab={setTab}/>}
      {tab === "identity" && <CharacterIdentityPanel character={active} draft={draft} sectionKey={current.key} setSectionKey={setSectionKey} dirtySections={dirtySections} saving={saving} aiBusy={aiBusy} drafts={aiDrafts} onEdit={editIdentity} onSave={(key) => void saveIdentity(key)} onRegenerate={(key) => void regenerateIdentity(key)} onDraftEdit={editDraft} onDraftSave={(key) => void saveDraft(key)} onApply={(key) => void applyDraft(key)} onDiscard={(key) => void discardDraft(key)}/>}
      {tab === "outfits" && <CharacterOutfitsPanel workplaceId={workplace.id} characterId={active.id} outfits={outfits} artworks={artworks} reload={reloadOutfits} notify={notify}/>}
      {tab === "artwork" && <CharacterArtworkPanel workplaceId={workplace.id} character={active} outfits={outfits} artworks={artworks} reloadArtworks={reloadArtworks} reloadOutfits={reloadOutfits} onCharacterChange={onCharacterChanged} notify={notify}/>}
      {tab === "canon" && <CharacterCanonPanel character={active} outfits={outfits} drafts={aiDrafts} onTab={setTab}/>}
    </>;
  }

  return <div className="book-stage character-stage">
    <div className="book-topline"><div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace.title}</span><span className="top-separator">/</span><span className="document-crumb">CHARACTER STUDIO</span></div><div className="book-actions"><span className="character-count">{characters.length} 个角色</span><button className="head-btn" onClick={() => setModal("create")}><Icon name="plus"/>新建角色</button></div></div>
    <div className="character-workspace">
      <aside className="character-index"><div className="character-index-head"><div className="eyebrow brass-text">THE LIVING ATELIER</div><h1>角色工作室</h1><p>从人物概念到四类身份、服装与视觉作品，最后由作者确认 Canon。</p></div>{error && <div className="character-error">{error}<button onClick={() => setError("")}>关闭</button></div>}{renderCharacterList()}</aside>
      <main className="character-detail">{renderDetail()}</main>
    </div>
    {modal === "create" && <Modal title="从一个人物概念开始" eyebrow="CHARACTER STUDIO" onClose={() => { setModal(null); setError(""); }} actions={<><button className="quiet-button" onClick={() => setModal(null)}>取消</button><button className="confirm-button" disabled={!newConcept.trim() || saving} onClick={() => void createCharacter()}>{saving ? "建立并生成草稿…" : "建立角色并补全"}</button></>} className="character-create-modal">
      <p className="modal-intro">只需要一段自然语言描述。AI 会补全文学、视觉、声音和表演身份；所有内容先作为草稿，由你逐项审核。</p>
      {error && <p className="form-error">{error}</p>}
      <label className="field-label">人物概念<textarea autoFocus rows={5} value={newConcept} maxLength={4000} onChange={(event: any) => setNewConcept(event.target.value)} placeholder="一个生活在蒸汽朋克世界的年轻机械师，性格独立，不喜欢依赖别人。"/></label>
      <div className="modal-two-column"><label className="field-label">角色名（可选）<input value={newName} maxLength={512} onChange={(event: any) => setNewName(event.target.value)} placeholder="留空则从概念自动取名"/></label><label className="field-label">角色定位（可选）<input value={newRole} maxLength={256} onChange={(event: any) => setNewRole(event.target.value)} placeholder="主角、对手、配角……"/></label></div>
    </Modal>}
    {modal === "archive" && active && <Modal title="归档这个角色？" eyebrow="SOFT ARCHIVE" onClose={() => setModal(null)} actions={<><button className="quiet-button" onClick={() => setModal(null)}>保留角色</button><button className="confirm-button danger-button" disabled={saving} onClick={() => void archiveCharacter()}>{saving ? "归档中…" : "确认归档"}</button></>}>
      <p className="modal-intro">“{active.name}”会从角色列表中隐藏，但数据库记录、Outfit、Artwork 和稳定 Character ID 会保留，避免破坏场景与资产引用。</p>
      {error && <p className="form-error">{error}</p>}
    </Modal>}
  </div>;
}

const SCENE_GIVEN_FIELDS: { key: keyof SceneGivenCircumstances; label: string; hint: string; wide?: boolean }[] = [
  { key: "time", label: "时间", hint: "一天中的时刻、时代、时序关系。" },
  { key: "place", label: "地点", hint: "人物实际聚集的具体空间。" },
  { key: "environment", label: "环境", hint: "天气、光线、声音、气味与空间压力。", wide: true },
  { key: "background", label: "背景", hint: "理解此情境所需的世界与人物背景。", wide: true },
  { key: "prior_events", label: "此前发生的事", hint: "直接推动本场戏的既有行动与后果。", wide: true },
];

const SCENE_DRAMATIC_FIELDS: { key: keyof SceneDramaticSituation; label: string; hint: string; wide?: boolean }[] = [
  { key: "central_question", label: "核心问题", hint: "观众与人物共同等待回答的问题。", wide: true },
  { key: "primary_conflict", label: "主要冲突", hint: "谁想要什么，谁或什么阻止了他。", wide: true },
  { key: "turn", label: "情境变化", hint: "这场戏结束时，什么已经不可逆地改变。", wide: true },
];

const SCENE_DIRECTION_FIELDS: { key: keyof SceneDirection; label: string; hint: string; wide?: boolean }[] = [
  { key: "blocking", label: "动作调度", hint: "人物的进入、离开、距离与身体行动。", wide: true },
  { key: "spatial", label: "空间位置", hint: "谁站在哪里，空间如何限制或推动冲突。" },
  { key: "performance_direction", label: "表演指导", hint: "节奏、停顿、情绪压力与表演选择。" },
  { key: "camera", label: "镜头指导", hint: "将来用于影像时的视线、景别与运动建议。", wide: true },
];

const SCENE_CAST_FIELDS: { key: keyof Pick<SceneCastDraft, "objective" | "action" | "conflict" | "emotional_state" | "performance_direction" | "subtext">; label: string; hint: string; wide?: boolean }[] = [
  { key: "objective", label: "当前目标", hint: "这个角色在这一场里想得到什么。", wide: true },
  { key: "action", label: "行动策略", hint: "为了目标正在做什么，如何试探或施压。" },
  { key: "conflict", label: "互动与冲突", hint: "主要阻力，以及与谁发生怎样的碰撞。", wide: true },
  { key: "emotional_state", label: "情绪状态", hint: "表层情绪与情绪之下的压力。" },
  { key: "subtext", label: "潜台词", hint: "没有说出口、但正在发生的意思。" },
  { key: "performance_direction", label: "表演指导", hint: "本场特有的身体、语气与节奏选择。", wide: true },
];

const SCENE_STATUS_LABELS: Record<StudioScene["status"], string> = {
  draft: "草稿", ready: "可排演", final: "定稿",
};

function StoryboardImage({ shot }: { shot: StoryboardShot }) {
  const [broken, setBroken] = React.useState(false);
  React.useEffect(() => setBroken(false), [shot.file_url, shot.asset_id]);
  if (shot.file_url && !broken) {
    return <div className="shot-image-frame generated"><img src={shot.file_url} alt={`Shot ${shot.number}`} onError={() => setBroken(true)}/><span className="shot-image-stamp">SHOT {String(shot.number).padStart(2, "0")}</span></div>;
  }
  return <div className="shot-image-frame empty">
    <span className="shot-frame-mark">✦</span>
    <strong>{shot.file_url ? "图片暂时无法读取" : "尚未生成画面"}</strong>
    <p>{shot.image_prompt ? shot.image_prompt.slice(0, 180) : "先编辑这一格的分镜与 Prompt。"}</p>
    <span className="shot-frame-stamp">SHOT {String(shot.number).padStart(2, "0")} · {shot.status.toUpperCase()}</span>
  </div>;
}

function ShotReferencePanel({ shot, cast, outfitsByCharacter }: {
  shot: StoryboardShot; cast: SceneCastDraft[];
  outfitsByCharacter: Record<string, CharacterOutfit[]>;
}) {
  const usage = shot.reference_usage;
  if (!usage) return null;
  const characterName = (id: string | null) => cast.find(entry => entry.character_id === id)?.character_name || "Character";
  const outfitName = (characterId: string | null, outfitId: string | null) =>
    outfitId ? (outfitsByCharacter[characterId || ""] || []).find(outfit => outfit.id === outfitId)?.name || "Outfit" : "";
  const referenceLabel = (reference: ReferenceTrace) => {
    if (reference.reference_kind === "scene_reference") return "Scene reference";
    if (reference.reference_kind === "outfit_reference") return `${characterName(reference.character_id)} · ${outfitName(reference.character_id, reference.outfit_id)}`;
    return `${characterName(reference.character_id)} · ${reference.reference_kind === "full_body" ? "Full body" : "Avatar"}`;
  };
  return <section className="shot-reference-panel">
    <div className="shot-reference-head"><div><div className="eyebrow">APPROVED REFERENCES</div><h4>本次生成使用的参考图</h4></div><span className={usage.applied ? "reference-applied" : "reference-text-only"}>{usage.applied ? "已传入图像字节" : "仅文本生成"}</span></div>
    <p>{usage.message}</p>
    {usage.references.length > 0 && <div className="shot-reference-list">{usage.references.map(reference => <a key={reference.asset_id} className="shot-reference-item" href={reference.file_url} target="_blank" rel="noreferrer"><img src={reference.file_url} alt={reference.name}/><span><strong>{referenceLabel(reference)}</strong><small>{reference.name}</small></span></a>)}</div>}
  </section>;
}

function StoryboardWorkspace({ workplace, scene, cast, outfitsByCharacter, board, onChange, onBack, onDirtyChange, notify, onOpenAsset }: {
  workplace: Workplace; scene: StudioScene; cast: SceneCastDraft[];
  outfitsByCharacter: Record<string, CharacterOutfit[]>; board: SceneStoryboard;
  onChange: (board: SceneStoryboard) => void; onBack: () => void;
  onDirtyChange: (dirty: boolean) => void; notify: (message: string) => void;
  onOpenAsset: (assetId: string) => void;
}) {
  const [shots, setShots] = React.useState<StoryboardShot[]>(board.shots);
  const [dirty, setDirty] = React.useState(false);
  const [saving, setSaving] = React.useState(false);
  const [regenerating, setRegenerating] = React.useState(false);
  const [generatingId, setGeneratingId] = React.useState("");
  const [editingId, setEditingId] = React.useState("");
  const [error, setError] = React.useState("");

  React.useEffect(() => { setShots(board.shots); setDirty(false); onDirtyChange(false); }, [board.scene_id, board.updated_at]);
  React.useEffect(() => { onDirtyChange(dirty); }, [dirty]);

  function markDirty(next: StoryboardShot[]) {
    setShots(next);
    setDirty(true);
  }

  function updateShot(id: string, patch: Partial<StoryboardShot>) {
    markDirty(shots.map(shot => shot.id === id ? { ...shot, ...patch } : shot));
  }

  function updateAction(shot: StoryboardShot, action: string) {
    updateShot(shot.id, { action, content: action });
  }

  function updateExpression(shot: StoryboardShot, expression: string) {
    updateShot(shot.id, {
      expression,
      expression_action: [expression, shot.performance].filter(Boolean).join("\n\n"),
    });
  }

  function updatePerformance(shot: StoryboardShot, performance: string) {
    updateShot(shot.id, {
      performance,
      expression_action: [shot.expression, performance].filter(Boolean).join("\n\n"),
    });
  }

  function toggleCharacter(shot: StoryboardShot, entry: SceneCastDraft) {
    const selected = shot.character_ids.includes(entry.character_id);
    const characterIds = selected
      ? shot.character_ids.filter(id => id !== entry.character_id)
      : [...shot.character_ids, entry.character_id];
    const entries = cast.filter(item => characterIds.includes(item.character_id));
    const existingOutfits = shot.character_outfits || [];
    const defaultOutfit = (outfitsByCharacter[entry.character_id] || []).find(outfit => outfit.is_default)
      || (outfitsByCharacter[entry.character_id] || [])[0];
    const characterOutfits = selected
      ? existingOutfits.filter(item => item.character_id !== entry.character_id)
      : defaultOutfit && !existingOutfits.some(item => item.character_id === entry.character_id)
        ? [...existingOutfits, { character_id: entry.character_id, outfit_id: defaultOutfit.id }]
        : existingOutfits;
    updateShot(shot.id, {
      character_ids: characterIds,
      characters: entries.map(item => item.character_name),
      character_outfits: characterOutfits,
    });
  }

  function setShotOutfit(shot: StoryboardShot, characterId: string, outfitId: string) {
    const existing = (shot.character_outfits || []).filter(item => item.character_id !== characterId);
    updateShot(shot.id, {
      character_outfits: outfitId ? [...existing, { character_id: characterId, outfit_id: outfitId }] : existing,
    });
  }

  async function persistShots(silent = false): Promise<SceneStoryboard | null> {
    if (saving) return null;
    setSaving(true); setError("");
    try {
      const saved = await api<SceneStoryboard>(`/workplaces/${workplace.id}/scenes/${scene.id}/storyboard`, {
        method: "PUT",
        body: { shots: shots.map((shot, index) => ({ ...shot, number: index + 1 })) },
      });
      setShots(saved.shots);
      setDirty(false);
      onChange(saved);
      if (!silent) notify("分镜已保存");
      return saved;
    } catch (cause: any) {
      setError(cause?.message || "保存分镜失败");
      return null;
    } finally {
      setSaving(false);
    }
  }

  async function regenerateStoryboard() {
    if (regenerating || saving || generatingId) return;
    if (dirty && !window.confirm("重新生成会替换当前分镜。未保存的分镜修改会丢失，继续吗？")) return;
    const protectedCount = shots.filter(shot =>
      shot.author_edited || !!shot.asset_id || shot.status === "generated"
    ).length;
    if (protectedCount && !window.confirm(
      `当前有 ${protectedCount} 个镜头已被编辑或生成过画面。重新生成会产生新的草稿镜头，旧图片 Asset 仍会保留。继续吗？`
    )) return;
    setRegenerating(true); setError("");
    const requestBoard = async (acknowledge: boolean) => api<SceneStoryboard>(
      `/workplaces/${workplace.id}/scenes/${scene.id}/storyboard`,
      {
        method: "POST",
        body: {
          force: true,
          acknowledge_protected: acknowledge,
        },
      },
    );
    try {
      let saved: SceneStoryboard;
      try {
        saved = await requestBoard(protectedCount > 0);
      } catch (cause: any) {
        if (!(cause instanceof StudioApiError)
            || cause.status !== 422 || cause.code !== "STORYBOARD_PROTECTED") throw cause;
        if (!window.confirm("服务器检测到受保护的分镜内容。确认用新的草稿替换当前分镜吗？旧图片仍会保留。")) return;
        saved = await requestBoard(true);
      }
      setShots(saved.shots);
      setDirty(false);
      setEditingId("");
      onChange(saved);
      notify(saved.shots.some(shot => shot.source === "ai")
        ? "AI 分镜草稿已生成，请逐格审阅、编辑并保存"
        : "分镜模板已重新生成");
    } catch (cause: any) {
      setError(cause?.message || "重新生成分镜失败。当前分镜没有被覆盖。");
    } finally {
      setRegenerating(false);
    }
  }

  async function generateImage(shotId: string) {
    if (generatingId || saving || regenerating) return;
    setError("");
    let latest = shots;
    if (dirty) {
      const saved = await persistShots(true);
      if (!saved) return;
      latest = saved.shots;
    }
    setGeneratingId(shotId);
    try {
      const result = await api<GeneratedShotImage>(
        `/workplaces/${workplace.id}/scenes/${scene.id}/storyboard/shots/${shotId}/image`,
        { method: "POST" },
      );
      const next = latest.map(shot => shot.id === result.shot.id ? result.shot : shot);
      setShots(next);
      onChange({ ...board, shots: next });
      setDirty(false);
      notify("画面已生成并存入 Assets，同时关联到当前 Scene");
    } catch (cause: any) {
      setError(cause?.message || "图像生成失败。分镜和原场景内容均未改变。");
    } finally {
      setGeneratingId("");
    }
  }

  function leave() {
    if (dirty && !window.confirm("分镜还有未保存的修改。返回场景会放弃它们，继续吗？")) return;
    onBack();
  }

  const editing = shots.find(shot => shot.id === editingId) || null;
  const generatedCount = shots.filter(shot => shot.file_url).length;

  return <div className="storyboard-workspace">
    <div className="storyboard-head">
      <div>
        <button className="storyboard-back" onClick={leave}>← 返回 Scene</button>
        <div className="eyebrow brass-text">STORYBOARD · {scene.title}</div>
        <h1>把这一场戏变成镜头。</h1>
        <p>既定情境、Cast 的目标与 Visual Canon 已经自动收进每一格。镜头数量与戏剧推进由场景内容决定；生成结果只是可编辑草稿。</p>
      </div>
      <div className="storyboard-head-actions">
        <span className={dirty ? "scene-dirty" : ""}>{dirty ? "分镜有未保存修改" : `${generatedCount} / ${shots.length} 格已有画面`}</span>
        <button className="head-btn" disabled={regenerating || saving || !!generatingId} onClick={() => void regenerateStoryboard()}>{regenerating ? "正在生成分镜…" : "Regenerate Storyboard"}</button>
        <button className="tool-button primary" disabled={saving || regenerating || !dirty} onClick={() => void persistShots()}>{saving ? "保存中…" : "保存分镜"}</button>
        <button className="head-btn" onClick={leave}>返回 Scene</button>
      </div>
    </div>

    {error && <div className="character-error storyboard-error">{error}<button onClick={() => setError("")}>关闭</button></div>}
    {!board.generation_available && <div className="storyboard-service-warning"><strong>图像服务当前不可用。</strong><span>分镜和 Prompt 仍可完整编辑与保存；生成按钮会保持不可用，不会伪造结果。</span></div>}
    {board.image_generation && !board.image_generation.reference_images && <div className="storyboard-service-warning"><strong>当前引擎只支持 text-to-image。</strong><span>已批准的 Character、Outfit 与 Scene 参考图会显示在镜头中，但不会伪装成已传给模型。切换到支持参考图的适配器后才会实际使用图像字节。</span></div>}

    <div className="storyboard-strip-head">
      <div><div className="eyebrow">THE CONTINUITY BOARD</div><h2>{shots.length} 个镜头</h2></div>
      <p>人物外观严格来自 Visual Canon。镜头间的服装、发型、面部与空间关系应保持一致；不接受自动改写角色 Canon。</p>
    </div>

    <div className="storyboard-grid">{shots.map(shot => <article key={shot.id} className={`shot-card ${shot.file_url ? "has-image" : ""} ${generatingId === shot.id ? "generating" : ""}`} role="button" tabIndex={0} onClick={() => setEditingId(shot.id)} onKeyDown={(event: any) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); setEditingId(shot.id); } }}>
      <StoryboardImage shot={shot}/>
      <div className="shot-card-body">
        <div className="shot-card-topline"><span>SHOT {String(shot.number).padStart(2, "0")} · {shot.source === "ai" ? "AI DRAFT" : shot.source === "manual" ? "AUTHOR" : "TEMPLATE"}</span><em className={shot.file_url ? "ready" : ""}>{generatingId === shot.id ? "正在生成…" : shot.file_url ? "已有画面" : "待生成"}</em></div>
        {shot.dramatic_beat && <p className="shot-beat"><strong>BEAT</strong>{shot.dramatic_beat}</p>}
        <h3>{shot.action || shot.content || "这一格还没有动作描述"}</h3>
        <p className="shot-camera">{shot.camera || "镜头尚未写明"}</p>
        {(shot.expression || shot.performance) && <p className="shot-performance">{[shot.expression, shot.performance].filter(Boolean).join(" · ")}</p>}
        <div className="shot-cast-chips">{shot.characters.length ? shot.characters.map(name => <span key={name}>{name}</span>) : <small>无角色入镜</small>}</div>
        {shot.reference_usage && <p className="shot-reference-summary">{shot.reference_usage.applied ? `参考图 ${shot.reference_usage.references.length} 张 · 已传入图像字节` : shot.reference_usage.references.length ? `参考图 ${shot.reference_usage.references.length} 张 · 当前仅文本生成` : "本次生成未使用参考图"}</p>}
        <div className="shot-card-actions">
          <button className="quiet-button" onClick={(event: any) => { event.stopPropagation(); setEditingId(shot.id); }}>编辑分镜</button>
          {shot.asset_id && <button className="quiet-button" onClick={(event: any) => { event.stopPropagation(); onOpenAsset(shot.asset_id!); }}>在 Assets 中查看</button>}
          <button className="tool-button primary" disabled={!board.generation_available || !!generatingId || saving || regenerating} onClick={(event: any) => { event.stopPropagation(); void generateImage(shot.id); }}>{generatingId === shot.id ? "正在绘制…" : shot.file_url ? "重新生成" : "Generate Image"}</button>
        </div>
      </div>
    </article>)}</div>

    <div className="storyboard-footer"><span>每个镜头都保存独立的 Prompt 与 Asset ID。重新生成不会覆盖旧 Asset；受保护的作者编辑需要明确确认。</span><button className="tool-button primary" disabled={saving || regenerating || !dirty} onClick={() => void persistShots()}>{saving ? "保存中…" : "保存分镜"}</button></div>

    {editing && <Modal title={`Shot ${String(editing.number).padStart(2, "0")}`} eyebrow="EDIT THE FRAME" onClose={() => setEditingId("")} className="shot-editor-modal" actions={<><button className="quiet-button" onClick={() => setEditingId("")}>关闭</button><button className="confirm-button" disabled={saving} onClick={() => void persistShots()}>{saving ? "保存中…" : "保存分镜"}</button></>}>
      <div className="shot-editor">
        <div className="shot-editor-image"><StoryboardImage shot={editing}/></div>
        <label className="field-label">Dramatic Beat<textarea rows={2} value={editing.dramatic_beat} onChange={(event: any) => updateShot(editing.id, { dramatic_beat: event.target.value })}/><small>这一格推进了什么戏剧变化。</small></label>
        <label className="field-label">Action<textarea rows={3} value={editing.action || editing.content} onChange={(event: any) => updateAction(editing, event.target.value)}/><small>正在发生什么，角色如何行动与反应。</small></label>
        <label className="field-label">Expression<textarea rows={2} value={editing.expression} onChange={(event: any) => updateExpression(editing, event.target.value)}/><small>可见的情绪、表情与面部行为。</small></label>
        <label className="field-label">Performance<textarea rows={2} value={editing.performance} onChange={(event: any) => updatePerformance(editing, event.target.value)}/><small>姿态、手势、动作节奏与表演细节。</small></label>
        <label className="field-label">Camera / Composition<textarea rows={2} value={editing.camera} onChange={(event: any) => updateShot(editing.id, { camera: event.target.value })}/></label>
        <label className="field-label">Visual description<textarea rows={3} value={editing.visual_description} onChange={(event: any) => updateShot(editing.id, { visual_description: event.target.value })}/></label>
        <div className="shot-cast-editor"><span className="field-label-title">出场角色</span>{cast.length ? <div className="shot-cast-picker">{cast.map(entry => <label key={entry.character_id} className={editing.character_ids.includes(entry.character_id) ? "chosen" : ""}><input type="checkbox" checked={editing.character_ids.includes(entry.character_id)} onChange={() => toggleCharacter(editing, entry)}/><span>{entry.character_name}</span></label>)}</div> : <p>当前 Scene 没有 Cast。仍可生成无人物入镜的镜头。</p>}</div>
        {editing.character_ids.length > 0 && <div className="shot-outfit-editor"><span className="field-label-title">本镜头服装</span>{editing.character_ids.map(characterId => {
          const entry = cast.find(item => item.character_id === characterId);
          const outfits = outfitsByCharacter[characterId] || [];
          const selected = (editing.character_outfits || []).find(item => item.character_id === characterId)?.outfit_id || "";
          return <label key={characterId} className="identity-field"><span>{entry?.character_name || "Character"} · Outfit</span><small>只改变本镜头的服装，不修改 Character Visual Canon。</small><select value={selected} onChange={(event: any) => setShotOutfit(editing, characterId, event.target.value)}><option value="">默认服装 / 不指定</option>{outfits.map(outfit => <option key={outfit.id} value={outfit.id}>{outfit.name}{outfit.is_default ? " · 默认" : ""}{outfit.reference_asset_id ? " · 有正式参考图" : ""}</option>)}</select></label>;
        })}</div>}
        <label className="field-label shot-prompt-field">Image generation prompt<textarea rows={10} value={editing.image_prompt} onChange={(event: any) => updateShot(editing.id, { image_prompt: event.target.value })}/><small>Prompt 已从场景、Cast、Visual Canon 和参考 Assets 组合。可编辑，但不要把未获作者批准的永久外观变化写成 Canon。</small></label>
        <ShotReferencePanel shot={editing} cast={cast} outfitsByCharacter={outfitsByCharacter}/>
        <div className="shot-editor-generate"><button className="tool-button primary" disabled={!board.generation_available || !!generatingId || saving || regenerating} onClick={() => void generateImage(editing.id)}>{generatingId === editing.id ? "正在绘制…" : editing.file_url ? "重新生成这一格" : "Generate Image"}</button>{editing.asset_id && <button className="quiet-button" onClick={() => onOpenAsset(editing.asset_id!)}>在 Assets 中查看</button>}<span>{editing.file_url ? "新画面会作为新的 Asset 保存，旧画面仍保留。" : "只有明确点击才会生成。修改会先保存，生成不会自动改写分镜或 Character Canon。"}</span></div>
      </div>
    </Modal>}
  </div>;
}

function ScenesWorkspace({ workplace, notify, launch, onLaunchConsumed, onOpenSourceDocument, onOpenAsset }: {
  workplace: Workplace; notify: (message: string) => void;
  launch?: { sceneId: string; storyboard: boolean; nonce: number } | null;
  onLaunchConsumed?: () => void;
  onOpenSourceDocument?: (documentId: string) => void;
  onOpenAsset: (assetId: string) => void;
}) {
  const [scenes, setScenes] = React.useState<StudioScene[]>([]);
  const [characters, setCharacters] = React.useState<StudioCharacter[]>([]);
  const [active, setActive] = React.useState<StudioScene | null>(null);
  const [draft, setDraft] = React.useState<SceneDraft | null>(null);
  const [cast, setCast] = React.useState<SceneCastDraft[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [detailLoading, setDetailLoading] = React.useState(false);
  const [savingScene, setSavingScene] = React.useState(false);
  const [savingCast, setSavingCast] = React.useState(false);
  const [sceneDirty, setSceneDirty] = React.useState(false);
  const [castDirty, setCastDirty] = React.useState(false);
  const [storyboard, setStoryboard] = React.useState<SceneStoryboard | null>(null);
  const [storyboardOpen, setStoryboardOpen] = React.useState(false);
  const [storyboardLoading, setStoryboardLoading] = React.useState(false);
  const [storyboardDirty, setStoryboardDirty] = React.useState(false);
  const [characterOutfits, setCharacterOutfits] = React.useState<Record<string, CharacterOutfit[]>>({});
  const [error, setError] = React.useState("");
  const [modal, setModal] = React.useState<"create" | "delete" | null>(null);
  const [newTitle, setNewTitle] = React.useState("");
  const [newSummary, setNewSummary] = React.useState("");
  const launchHandledRef = React.useRef<number | null>(null);

  function installScene(scene: StudioScene, entries: SceneCastEntry[]) {
    setActive(scene);
    setDraft(sceneDraft(scene));
    setCast(entries.map(castDraft));
    setSceneDirty(false);
    setCastDirty(false);
    setStoryboard(null);
    setStoryboardOpen(false);
    setStoryboardDirty(false);
    setCharacterOutfits({});
    setError("");
  }

  async function loadCharacterOutfits(entries: SceneCastDraft[]) {
    const results = await Promise.all(entries.map(async entry => {
      try {
        const outfits = await api<CharacterOutfit[]>(`/workplaces/${workplace.id}/characters/${entry.character_id}/outfits`);
        return [entry.character_id, outfits] as [string, CharacterOutfit[]];
      } catch {
        return [entry.character_id, []] as [string, CharacterOutfit[]];
      }
    }));
    setCharacterOutfits(Object.fromEntries(results));
  }

  async function openScene(sceneId: string, confirmLeave = true) {
    if (active?.id === sceneId) {
      if (storyboardOpen && confirmLeave && storyboardDirty
          && !window.confirm("分镜还有未保存的修改。返回场景会放弃它们，继续吗？")) return;
      setStoryboardOpen(false);
      return;
    }
    if (confirmLeave && (storyboardDirty || sceneDirty || castDirty) && !window.confirm("当前还有未保存的修改。切换场景会放弃它们，继续吗？")) return;
    setDetailLoading(true); setError("");
    try {
      const [scene, entries] = await Promise.all([
        api<StudioScene>(`/workplaces/${workplace.id}/scenes/${sceneId}`),
        api<SceneCastEntry[]>(`/workplaces/${workplace.id}/scenes/${sceneId}/cast`),
      ]);
      installScene(scene, entries);
    } catch (cause: any) {
      setError(cause?.message || "无法打开场景");
    } finally {
      setDetailLoading(false);
    }
  }

  React.useEffect(() => {
    let alive = true;
    setLoading(true); setError("");
    Promise.all([
      api<StudioScene[]>(`/workplaces/${workplace.id}/scenes`),
      api<StudioCharacter[]>(`/workplaces/${workplace.id}/characters`),
    ]).then(async ([sceneList, characterList]) => {
      if (!alive) return;
      setScenes(sceneList);
      setCharacters(characterList);
      if (!sceneList.length) {
        setActive(null); setDraft(null); setCast([]);
        setSceneDirty(false); setCastDirty(false);
        return;
      }
      const [scene, entries] = await Promise.all([
        api<StudioScene>(`/workplaces/${workplace.id}/scenes/${sceneList[0].id}`),
        api<SceneCastEntry[]>(`/workplaces/${workplace.id}/scenes/${sceneList[0].id}/cast`),
      ]);
      if (alive) installScene(scene, entries);
    }).catch((cause: any) => {
      if (alive) setError(cause?.message || "无法读取场景");
    }).finally(() => {
      if (alive) setLoading(false);
    });
    return () => { alive = false; };
  }, [workplace.id]);

  React.useEffect(() => {
    if (!launch || loading || launchHandledRef.current === launch.nonce) return;
    const target = scenes.find(scene => scene.id === launch.sceneId);
    if (!target) {
      onLaunchConsumed?.();
      return;
    }
    let alive = true;
    launchHandledRef.current = launch.nonce;
    setDetailLoading(true); setError("");
    (async () => {
      try {
        const [scene, entries] = await Promise.all([
          api<StudioScene>(`/workplaces/${workplace.id}/scenes/${target.id}`),
          api<SceneCastEntry[]>(`/workplaces/${workplace.id}/scenes/${target.id}/cast`),
        ]);
        if (!alive) return;
        installScene(scene, entries);
        if (launch.storyboard) {
          const drafts = entries.map(castDraft);
          await loadCharacterOutfits(drafts);
          const storyboardResult = target.storyboard_count > 0
            ? await api<SceneStoryboard>(`/workplaces/${workplace.id}/scenes/${target.id}/storyboard`)
            : await api<SceneStoryboard>(`/workplaces/${workplace.id}/scenes/${target.id}/storyboard`, { method: "POST", body: {} });
          if (!alive) return;
          setStoryboard(storyboardResult);
          setStoryboardOpen(true);
          setStoryboardDirty(false);
          setActive(previous => previous ? { ...previous, storyboard_count: storyboardResult.shots.length } : previous);
          setScenes(previous => previous.map(item => item.id === scene.id ? { ...item, storyboard_count: storyboardResult.shots.length } : item));
        }
      } catch (cause: any) {
        if (alive) setError(cause?.message || "无法打开新建 Scene 的 Storyboard");
      } finally {
        if (alive) setDetailLoading(false);
        onLaunchConsumed?.();
      }
    })();
    return () => { alive = false; };
  }, [launch?.nonce, loading, scenes.length]);

  function editScene(update: (previous: SceneDraft) => SceneDraft) {
    setDraft(previous => previous ? update(previous) : previous);
    setSceneDirty(true);
  }

  function editGiven(key: keyof SceneGivenCircumstances, value: string) {
    editScene(previous => ({ ...previous, given_circumstances: { ...previous.given_circumstances, [key]: value } }));
  }

  function editDramatic(key: keyof SceneDramaticSituation, value: string) {
    editScene(previous => ({ ...previous, dramatic_situation: { ...previous.dramatic_situation, [key]: value } }));
  }

  function editDirection(key: keyof SceneDirection, value: string) {
    editScene(previous => ({ ...previous, direction: { ...previous.direction, [key]: value } }));
  }

  function editCast(index: number, key: keyof SceneCastDraft, value: string) {
    setCast(previous => previous.map((entry, itemIndex) => itemIndex === index ? { ...entry, [key]: value } : entry));
    setCastDirty(true);
  }

  function addToCast(character: StudioCharacter) {
    if (cast.some(entry => entry.character_id === character.id)) return;
    setCast(previous => [...previous, {
      character_id: character.id,
      character_name: character.name,
      character_role: character.role,
      objective: "", action: "", conflict: "", emotional_state: "",
      performance_direction: "", subtext: "",
    }]);
    setCastDirty(true);
  }

  function removeFromCast(index: number) {
    setCast(previous => previous.filter((_, itemIndex) => itemIndex !== index));
    setCastDirty(true);
  }

  function moveCast(index: number, direction: -1 | 1) {
    const target = index + direction;
    if (target < 0 || target >= cast.length) return;
    setCast(previous => {
      const next = [...previous];
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
    setCastDirty(true);
  }

  async function createScene() {
    if (!newTitle.trim() || savingScene) return;
    setSavingScene(true); setError("");
    try {
      const created = await api<StudioScene>(`/workplaces/${workplace.id}/scenes`, {
        method: "POST",
        body: {
          title: newTitle.trim(), summary: newSummary.trim(), sort_order: scenes.length,
          status: "draft", dialogue: "",
          given_circumstances: { time: "", place: "", environment: "", background: "", prior_events: "" },
          dramatic_situation: { central_question: "", primary_conflict: "", turn: "" },
          direction: { blocking: "", spatial: "", performance_direction: "", camera: "" },
        },
      });
      setScenes(previous => [...previous, created].sort((left, right) => left.sort_order - right.sort_order || left.created_at.localeCompare(right.created_at)));
      installScene(created, []);
      setModal(null); setNewTitle(""); setNewSummary("");
      notify("新场景已建立");
    } catch (cause: any) {
      setError(cause?.message || "创建场景失败");
    } finally {
      setSavingScene(false);
    }
  }

  async function saveScene(): Promise<StudioScene | null> {
    if (!active || !draft || savingScene) return null;
    if (!draft.title.trim()) { setError("场景标题不能为空"); return null; }
    setSavingScene(true); setError("");
    try {
      const saved = await api<StudioScene>(`/workplaces/${workplace.id}/scenes/${active.id}`, {
        method: "PUT",
        body: {
          title: draft.title.trim(), summary: draft.summary, sort_order: draft.sort_order,
          status: draft.status, given_circumstances: draft.given_circumstances,
          dramatic_situation: draft.dramatic_situation, dialogue: draft.dialogue,
          direction: draft.direction,
        },
      });
      setActive(saved);
      setDraft(sceneDraft(saved));
      setScenes(previous => previous.map(scene => scene.id === saved.id ? saved : scene)
        .sort((left, right) => left.sort_order - right.sort_order || left.created_at.localeCompare(right.created_at)));
      setSceneDirty(false);
      notify("场景已保存");
      return saved;
    } catch (cause: any) {
      setError(cause?.message || "保存场景失败");
      return null;
    } finally {
      setSavingScene(false);
    }
  }

  async function saveCast(): Promise<SceneCastEntry[] | null> {
    if (!active || savingCast) return null;
    setSavingCast(true); setError("");
    try {
      const entries = await api<SceneCastEntry[]>(`/workplaces/${workplace.id}/scenes/${active.id}/cast`, {
        method: "PUT",
        body: {
          cast: cast.map((entry, index) => ({
            character_id: entry.character_id, objective: entry.objective,
            action: entry.action, conflict: entry.conflict,
            emotional_state: entry.emotional_state,
            performance_direction: entry.performance_direction,
            subtext: entry.subtext, sort_order: index,
          })),
        },
      });
      setCast(entries.map(castDraft));
      setActive(previous => previous ? { ...previous, cast_count: entries.length } : previous);
      setScenes(previous => previous.map(scene => scene.id === active.id ? { ...scene, cast_count: entries.length } : scene));
      setCastDirty(false);
      notify("Cast 已整体保存");
      return entries;
    } catch (cause: any) {
      setError(cause?.message || "保存 Cast 失败");
      return null;
    } finally {
      setSavingCast(false);
    }
  }

  async function openStoryboard(create: boolean) {
    if (!active || storyboardLoading) return;
    setStoryboardLoading(true); setError("");
    try {
      if (sceneDirty) {
        const saved = await saveScene();
        if (!saved) return;
      }
      if (castDirty) {
        const entries = await saveCast();
        if (!entries) return;
      }
      await loadCharacterOutfits(cast);
      const loaded = await api<SceneStoryboard>(
        `/workplaces/${workplace.id}/scenes/${active.id}/storyboard`,
        create ? { method: "POST", body: {} } : {},
      );
      setStoryboard(loaded);
      setStoryboardOpen(true);
      setStoryboardDirty(false);
      setActive(previous => previous ? { ...previous, storyboard_count: loaded.shots.length } : previous);
      setScenes(previous => previous.map(scene => scene.id === active.id ? { ...scene, storyboard_count: loaded.shots.length } : scene));
      if (create) notify("分镜已根据场景、Cast 与 Visual Canon 生成");
    } catch (cause: any) {
      setError(cause?.message || "无法打开分镜");
    } finally {
      setStoryboardLoading(false);
    }
  }

  async function deleteScene() {
    if (!active || savingScene) return;
    setSavingScene(true); setError("");
    try {
      await api<{ id: string }>(`/workplaces/${workplace.id}/scenes/${active.id}`, { method: "DELETE" });
      const remaining = scenes.filter(scene => scene.id !== active.id);
      setScenes(remaining);
      setModal(null);
      if (remaining.length) {
        const [scene, entries] = await Promise.all([
          api<StudioScene>(`/workplaces/${workplace.id}/scenes/${remaining[0].id}`),
          api<SceneCastEntry[]>(`/workplaces/${workplace.id}/scenes/${remaining[0].id}/cast`),
        ]);
        installScene(scene, entries);
      } else {
        setActive(null); setDraft(null); setCast([]);
        setSceneDirty(false); setCastDirty(false);
        setStoryboard(null); setStoryboardOpen(false); setStoryboardDirty(false);
      }
      notify("场景已归档，Character 资源保持不变");
    } catch (cause: any) {
      setError(cause?.message || "删除场景失败");
    } finally {
      setSavingScene(false);
    }
  }

  const castIds = new Set(cast.map(entry => entry.character_id));

  function renderSceneList() {
    if (loading && !scenes.length) return <div className="character-state"><span className="thinking-mark">✦</span><p>正在展开场景册……</p></div>;
    if (!scenes.length) return <div className="character-state character-empty-state"><div className="empty-book">✦</div><h2>还没有场景。</h2><p>从一个具体的时刻开始：谁在这里，他们各自想要什么？</p><button className="tool-button primary" onClick={() => setModal("create")}><Icon name="plus"/>建立第一个场景</button></div>;
    return <div className="scene-list">{scenes.map((scene, index) => <button key={scene.id} className={`scene-row ${active?.id === scene.id ? "active" : ""}`} onClick={() => void openScene(scene.id)}>
      <span className="scene-row-number">{String(index + 1).padStart(2, "0")}</span>
      <span className="scene-row-copy"><strong>{scene.title}</strong><small>{SCENE_STATUS_LABELS[scene.status]} · {scene.cast_count} 位角色</small><span>{scene.summary || scene.dramatic_situation?.central_question || "情境尚未写明"}</span></span>
    </button>)}</div>;
  }

  function renderCastEditor() {
    return <section className="scene-section cast-section">
      <div className="scene-section-head"><div><div className="eyebrow">CASTING THE ROOM</div><h3>场景中的角色</h3><p>同一 Character 可以出现在多个场景中；这里的目标与冲突只属于当前情境，不会改写角色 Canon。</p></div><div className="scene-section-actions"><span className={castDirty ? "scene-dirty" : ""}>{castDirty ? "Cast 有未保存修改" : "Cast 已保存"}</span><button className="tool-button primary" disabled={savingCast || !castDirty} onClick={() => void saveCast()}>{savingCast ? "保存中…" : "保存整个 Cast"}</button></div></div>
      <div className="cast-layout">
        <div className="cast-entries">
          {!cast.length && <div className="cast-empty"><strong>房间里还没有人。</strong><p>从右侧角色池选择角色加入，再分别写下他们在这一场里的目标与行动。</p></div>}
          {cast.map((entry, index) => <article className="cast-card" key={entry.character_id}>
            <div className="cast-card-head"><span className="cast-monogram">{entry.character_name.trim().slice(0, 1) || "?"}</span><div><strong>{entry.character_name}</strong><small>{entry.character_role || "未设定角色定位"}</small></div><div className="cast-order"><button aria-label="上移" disabled={index === 0} onClick={() => moveCast(index, -1)}>↑</button><button aria-label="下移" disabled={index === cast.length - 1} onClick={() => moveCast(index, 1)}>↓</button><button aria-label="移出 Cast" onClick={() => removeFromCast(index)}><Icon name="close"/></button></div></div>
            <div className="scene-field-grid">{SCENE_CAST_FIELDS.map(field => <label key={field.key} className={`scene-field ${field.wide ? "wide" : ""}`}><span>{field.label}</span><small>{field.hint}</small><textarea rows={field.wide ? 3 : 2} value={entry[field.key]} onChange={(event: any) => editCast(index, field.key, event.target.value)}/></label>)}</div>
          </article>)}
        </div>
        <aside className="character-pool">
          <div className="character-pool-head"><div className="eyebrow brass-text">CHARACTER POOL</div><h4>可加入的角色</h4><p>身份来自现有 Character 资源，不在此处复制。</p></div>
          {!characters.length && <div className="pool-empty">这个 Workplace 还没有可用角色。请先在角色档案中建立角色。</div>}
          {characters.map(character => <button key={character.id} className={`pool-card ${castIds.has(character.id) ? "chosen" : ""}`} disabled={castIds.has(character.id)} onClick={() => addToCast(character)}>
            <span className="pool-monogram">{character.name.trim().slice(0, 1) || "?"}</span><span><strong>{character.name}</strong><small>{character.role || "未设定定位"}</small><em>{characterAppearance(character)}</em></span><b>{castIds.has(character.id) ? "已在场" : "＋"}</b>
          </button>)}
        </aside>
      </div>
      {cast.length > 0 && <div className="cast-map"><div className="eyebrow">RELATIONS IN THIS SCENE</div><div className="cast-map-lines">{cast.map(entry => <p key={entry.character_id}><strong>{entry.character_name}</strong><span>{entry.objective || "目标尚未写明"}</span>{entry.conflict && <em>↔ {entry.conflict}</em>}</p>)}</div></div>}
    </section>;
  }

  function renderSceneDetail() {
    if (detailLoading) return <div className="character-state scene-detail-state"><span className="thinking-mark">✦</span><p>正在读取场景……</p></div>;
    if (!active || !draft) return <div className="character-empty-detail"><div className="placeholder-ornament">✦</div><div className="eyebrow brass-text">SCENE &amp; CASTING</div><h2>给故事一个正在发生的时刻。</h2><p>场景不是另一份手稿。它记录人物为何聚集、彼此想要什么，以及这一场结束时发生了什么改变。</p><button className="tool-button primary" onClick={() => setModal("create")}><Icon name="plus"/>建立场景</button></div>;
    return <div className="scene-detail-body">
      <div className="scene-detail-head"><div><div className="eyebrow">SCENE {String(scenes.findIndex(scene => scene.id === active.id) + 1).padStart(2, "0")}</div><input className="scene-title-input" value={draft.title} maxLength={512} onChange={(event: any) => editScene(previous => ({ ...previous, title: event.target.value }))}/><label className="scene-status-field"><span>状态</span><select value={draft.status} onChange={(event: any) => editScene(previous => ({ ...previous, status: event.target.value as StudioScene["status"] }))}><option value="draft">草稿</option><option value="ready">可排演</option><option value="final">定稿</option></select></label></div><div className="scene-detail-actions"><span className={sceneDirty ? "scene-dirty" : ""}>{sceneDirty ? "场景有未保存修改" : "场景已保存"}</span><button className="head-btn delete-scene" onClick={() => setModal("delete")}>归档场景</button><button className="tool-button storyboard-cta" disabled={storyboardLoading} onClick={() => void openStoryboard(!(active.storyboard_count > 0))}><Icon name="scene"/>{active.storyboard_count > 0 ? "Open Storyboard" : "Create Storyboard"}</button><button className="tool-button primary" disabled={savingScene || !sceneDirty} onClick={() => void saveScene()}>{savingScene ? "保存中…" : "保存场景"}</button></div></div>
      <label className="scene-summary-field"><span>一句摘要</span><textarea rows={2} value={draft.summary} onChange={(event: any) => editScene(previous => ({ ...previous, summary: event.target.value }))} placeholder="用一句话说明这一场正在发生什么。"/></label>
      {active.source_document_id && <section className="scene-source-trace">
        <div className="scene-source-head"><div><div className="eyebrow">SOURCE TRACE</div><h3>从正文提取</h3><p>来源是创建时的文本快照，不会随着 Document 后续修改而自动同步。</p></div>{onOpenSourceDocument && <button className="tool-button" onClick={() => onOpenSourceDocument(active.source_document_id!)}><Icon name="pen"/>返回来源 Document</button>}</div>
        <div className="scene-source-meta"><span>DOCUMENT <strong>{active.source_document_id}</strong></span><span>REVISION <strong>{active.source_document_revision ?? "—"}</strong></span><span>RANGE <strong>{active.source_selection_start != null && active.source_selection_end != null ? `${active.source_selection_start}–${active.source_selection_end}` : "由 Document 快照定位"}</strong></span></div>
        {active.source_text_snapshot && <details><summary>查看来源文本快照</summary><pre>{active.source_text_snapshot}</pre></details>}
      </section>}
      <section className="storyboard-invite">
        <div><div className="eyebrow">FROM STAGE TO SCREEN</div><h3>{active.storyboard_count > 0 ? "这一场已经有分镜。" : "让引擎按这场戏的戏剧推进决定镜头数量。"}</h3><p>自动收集既定情境、冲突与 Turn、Cast 的目标和情绪、Character Visual Canon，以及 Scene 与角色已关联的参考 Assets。</p></div>
        <button className="storyboard-invite-button" disabled={storyboardLoading} onClick={() => void openStoryboard(!(active.storyboard_count > 0))}><Icon name="scene"/><span>{storyboardLoading ? "正在整理分镜…" : active.storyboard_count > 0 ? "Open Storyboard" : "Create Storyboard"}</span><small>{active.storyboard_count > 0 ? `${active.storyboard_count} 个镜头 · 继续制作` : "无需重复填写角色与场景资料"}</small></button>
      </section>
      <section className="scene-section"><div className="scene-section-head"><div className="eyebrow">GIVEN CIRCUMSTANCES</div><h3>既定情境</h3><p>人物无法选择、但必须回应的条件。</p></div><div className="scene-field-grid">{SCENE_GIVEN_FIELDS.map(field => <label key={field.key} className={`scene-field ${field.wide ? "wide" : ""}`}><span>{field.label}</span><small>{field.hint}</small><textarea rows={field.wide ? 3 : 2} value={draft.given_circumstances[field.key]} onChange={(event: any) => editGiven(field.key, event.target.value)}/></label>)}</div></section>
      <section className="scene-section"><div className="scene-section-head"><div className="eyebrow">DRAMATIC SITUATION</div><h3>戏剧情境</h3><p>把空间里的压力说清楚，而不是罗列事件。</p></div><div className="scene-field-grid">{SCENE_DRAMATIC_FIELDS.map(field => <label key={field.key} className={`scene-field ${field.wide ? "wide" : ""}`}><span>{field.label}</span><small>{field.hint}</small><textarea rows={field.wide ? 3 : 2} value={draft.dramatic_situation[field.key]} onChange={(event: any) => editDramatic(field.key, event.target.value)}/></label>)}</div></section>
      {renderCastEditor()}
      <AssetLinkPanel workplaceId={workplace.id} resourceType="scene" resourceId={active.id} notify={notify}/>
      <SceneReferencePanel workplaceId={workplace.id} scene={active} notify={notify} onChange={(updated) => { setActive(updated); setScenes(previous => previous.map(item => item.id === updated.id ? updated : item)); }}/>
      <section className="scene-section"><div className="scene-section-head"><div><div className="eyebrow">DIALOGUE</div><h3>台词与叙事</h3><p>写下对白、潜台词与必要的叙事内容。Markdown 会作为连续文本保存。</p></div></div><textarea className="scene-manuscript" rows={12} value={draft.dialogue} onChange={(event: any) => editScene(previous => ({ ...previous, dialogue: event.target.value }))} placeholder="MARA&#10;你回来，是为了地图，还是为了那盏灯？&#10;&#10;（IL YAN 没有回答。他把钥匙放回桌上。）"/></section>
      <section className="scene-section"><div className="scene-section-head"><div className="eyebrow">DIRECTION</div><h3>调度与镜头</h3><p>动作、空间、表演与未来影像的镜头建议。</p></div><div className="scene-field-grid">{SCENE_DIRECTION_FIELDS.map(field => <label key={field.key} className={`scene-field ${field.wide ? "wide" : ""}`}><span>{field.label}</span><small>{field.hint}</small><textarea rows={field.wide ? 3 : 2} value={draft.direction[field.key]} onChange={(event: any) => editDirection(field.key, event.target.value)}/></label>)}</div></section>
      <div className="scene-save-footer"><span>场景与 Cast 分开保存。Cast 使用一次事务替换，失败时不会留下部分更新。</span><button className="tool-button primary" disabled={savingScene || !sceneDirty} onClick={() => void saveScene()}>{savingScene ? "保存中…" : "保存场景"}</button></div>
    </div>;
  }

  return <div className="book-stage scene-stage">
    <div className="book-topline"><div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace.title}</span><span className="top-separator">/</span><span className="document-crumb">SCENES &amp; CASTING</span></div><div className="book-actions"><span className="character-count">{scenes.length} 个场景</span><button className="head-btn" onClick={() => { if ((!sceneDirty && !castDirty && !storyboardDirty) || window.confirm("当前场景还有未保存修改，建立新场景会放弃它们。继续吗？")) setModal("create"); }}><Icon name="plus"/>新建场景</button></div></div>
    <div className="scene-workspace">
      <aside className="scene-index"><div className="character-index-head"><div className="eyebrow brass-text">THE STAGE BOOK</div><h1>场景与 Casting</h1><p>把人物放进具体情境，看他们如何行动、碰撞和改变。</p></div>{error && <div className="character-error">{error}<button onClick={() => setError("")}>关闭</button></div>}{renderSceneList()}</aside>
      <main className="scene-detail">{storyboardOpen && storyboard && active ? <StoryboardWorkspace workplace={workplace} scene={active} cast={cast} outfitsByCharacter={characterOutfits} board={storyboard} onChange={(next) => { setStoryboard(next); setActive(previous => previous ? { ...previous, storyboard_count: next.shots.length } : previous); setScenes(previous => previous.map(scene => scene.id === active.id ? { ...scene, storyboard_count: next.shots.length } : scene)); }} onBack={() => { setStoryboardOpen(false); setStoryboardDirty(false); }} onDirtyChange={setStoryboardDirty} notify={notify} onOpenAsset={onOpenAsset}/> : storyboardLoading ? <div className="character-state scene-detail-state"><span className="thinking-mark">✦</span><p>正在从场景与角色档案整理分镜……</p></div> : renderSceneDetail()}</main>
    </div>
    {modal === "create" && <Modal title="建立新场景" eyebrow="A MOMENT ON STAGE" onClose={() => { setModal(null); setError(""); }} actions={<><button className="quiet-button" onClick={() => setModal(null)}>取消</button><button className="confirm-button" disabled={!newTitle.trim() || savingScene} onClick={() => void createScene()}>{savingScene ? "创建中…" : "建立场景"}</button></>}>
      <p className="modal-intro">先给这个具体时刻一个名字。既定情境、Cast、台词和调度都可以之后逐步补全。</p>
      {error && <p className="form-error">{error}</p>}
      <label className="field-label">场景标题<input autoFocus value={newTitle} maxLength={512} onChange={(event: any) => setNewTitle(event.target.value)} placeholder="例如：潮线下的对峙"/></label>
      <label className="field-label">一句摘要<textarea rows={3} value={newSummary} onChange={(event: any) => setNewSummary(event.target.value)} placeholder="谁在哪里，想要什么，阻力是什么。"/></label>
    </Modal>}
    {modal === "delete" && active && <Modal title="归档这个场景？" eyebrow="SOFT DELETE" onClose={() => setModal(null)} actions={<><button className="quiet-button" onClick={() => setModal(null)}>保留场景</button><button className="confirm-button danger-button" disabled={savingScene} onClick={() => void deleteScene()}>{savingScene ? "归档中…" : "确认归档"}</button></>}>
      <p className="modal-intro">“{active.title}”会从场景列表隐藏，但记录与稳定 Scene ID 会保留。Character 资源、角色档案和其他场景中的 Cast 都不会被删除。</p>
      {error && <p className="form-error">{error}</p>}
    </Modal>}
  </div>;
}

function assetDraft(asset: StudioAsset): AssetDraft {
  return {
    name: asset.name || "",
    description: asset.description || "",
    author: asset.author || "",
    notes: asset.notes || "",
    tags: (asset.tags || []).join(", "),
  };
}

function draftTags(value: string): string[] {
  return Array.from(new Set(value.split(",").map(tag => tag.trim()).filter(Boolean)));
}

function AssetTargetsEditor({ workplaceId, asset, onChange, notify }: {
  workplaceId: string; asset: StudioAsset; onChange: (links: AssetLink[]) => void;
  notify: (message: string) => void;
}) {
  const [targets, setTargets] = React.useState<{ character: StudioCharacter[]; scene: StudioScene[]; document: StudioDocument[] }>({
    character: [], scene: [], document: [],
  });
  const [selection, setSelection] = React.useState("");
  const [loading, setLoading] = React.useState(true);
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState("");

  React.useEffect(() => {
    let alive = true;
    setLoading(true); setError("");
    Promise.all([
      api<StudioCharacter[]>(`/workplaces/${workplaceId}/characters`),
      api<StudioScene[]>(`/workplaces/${workplaceId}/scenes`),
      api<StudioDocument[]>(`/workplaces/${workplaceId}/documents`),
    ]).then(([characters, scenes, documents]) => {
      if (alive) setTargets({ character: characters, scene: scenes, document: documents });
    }).catch((cause: any) => {
      if (alive) setError(cause?.message || "无法读取可关联对象");
    }).finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [workplaceId]);

  const linkedKeys = new Set((asset.links || []).map(link => `${link.resource_type}:${link.resource_id}`));
  const options = [
    ...targets.character.map(item => ({ type: "character" as AssetResourceType, id: item.id, name: item.name })),
    ...targets.scene.map(item => ({ type: "scene" as AssetResourceType, id: item.id, name: item.title })),
    ...targets.document.map(item => ({ type: "document" as AssetResourceType, id: item.id, name: item.title })),
  ].filter(option => !linkedKeys.has(`${option.type}:${option.id}`));

  async function addLink() {
    if (!selection || busy) return;
    const [resourceType, resourceId] = selection.split(":") as [AssetResourceType, string];
    setBusy(true); setError("");
    try {
      const link = await api<AssetLink>(`/workplaces/${workplaceId}/assets/${asset.id}/links`, {
        method: "POST", body: { resource_type: resourceType, resource_id: resourceId },
      });
      onChange([...(asset.links || []), link]);
      setSelection("");
      notify("资源已关联");
    } catch (cause: any) {
      setError(cause?.message || "无法关联这个对象");
    } finally { setBusy(false); }
  }

  async function removeLink(link: AssetLink) {
    setBusy(true); setError("");
    try {
      await api(`/workplaces/${workplaceId}/assets/${asset.id}/links/${link.resource_type}/${link.resource_id}`, { method: "DELETE" });
      onChange((asset.links || []).filter(item => item.resource_type !== link.resource_type || item.resource_id !== link.resource_id));
      notify("资源关联已解除");
    } catch (cause: any) {
      setError(cause?.message || "无法解除资源关联");
    } finally { setBusy(false); }
  }

  return <section className="asset-targets">
    <div className="asset-targets-head"><div><div className="eyebrow">USED BY</div><h3>关联对象</h3><p>同一份资源可以同时用于多个 Character、Scene 和 Document。</p></div></div>
    {error && <p className="form-error">{error}</p>}
    {loading ? <div className="asset-inline-state">正在读取可关联对象……</div> : <>
      {!(asset.links || []).length ? <div className="asset-inline-empty">还没有对象使用这份资源。</div> : <div className="asset-link-list">{(asset.links || []).map(link => <div className="asset-link-row" key={`${link.resource_type}:${link.resource_id}`}>
        <span className="asset-link-kind">{ASSET_RESOURCE_INFO[link.resource_type]?.label || link.resource_type}</span>
        <strong>{link.name || link.resource_id}</strong>
        {!link.available && <small>目标已不可用</small>}
        <button className="icon-button" aria-label="解除关联" disabled={busy} onClick={() => void removeLink(link)}><Icon name="close"/></button>
      </div>)}</div>}
      <div className="asset-link-add"><select value={selection} onChange={(event: any) => setSelection(event.target.value)} disabled={busy || !options.length}><option value="">选择要关联的 Character、Scene 或 Document</option>{options.map(option => <option key={`${option.type}:${option.id}`} value={`${option.type}:${option.id}`}>{ASSET_RESOURCE_INFO[option.type].label} · {option.name}</option>)}</select><button className="tool-button" disabled={!selection || busy} onClick={() => void addLink()}><Icon name="link"/>{busy ? "更新中…" : "建立关联"}</button></div>
    </>}
  </section>;
}

function SceneReferencePanel({ workplaceId, scene, onChange, notify }: {
  workplaceId: string; scene: StudioScene;
  onChange: (scene: StudioScene) => void; notify: (message: string) => void;
}) {
  const [assets, setAssets] = React.useState<StudioAsset[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [busy, setBusy] = React.useState(false);
  const [error, setError] = React.useState("");
  const selected = new Set(scene.reference_asset_ids || []);

  async function loadAssets() {
    setLoading(true); setError("");
    try {
      const list = await api<StudioAsset[]>(`/workplaces/${workplaceId}/scenes/${scene.id}/assets`);
      setAssets(list.filter(asset => asset.asset_type === "image" && asset.file_url));
    } catch (cause: any) {
      setError(cause?.message || "无法读取场景已关联图片");
    } finally {
      setLoading(false);
    }
  }

  React.useEffect(() => { void loadAssets(); }, [workplaceId, scene.id]);

  async function toggle(asset: StudioAsset) {
    if (busy) return;
    const ids = selected.has(asset.id)
      ? (scene.reference_asset_ids || []).filter(id => id !== asset.id)
      : [...(scene.reference_asset_ids || []), asset.id];
    setBusy(true); setError("");
    try {
      const updated = await api<StudioScene>(`/workplaces/${workplaceId}/scenes/${scene.id}/references`, {
        method: "PUT", body: { asset_ids: ids },
      });
      onChange(updated);
      notify(selected.has(asset.id) ? "已取消场景参考图" : "已确认为场景参考图");
    } catch (cause: any) {
      setError(cause?.message || "无法更新场景参考图");
    } finally {
      setBusy(false);
    }
  }

  return <section className="scene-section scene-reference-section">
    <div className="scene-section-head"><div><div className="eyebrow">APPROVED SCENE REFERENCES</div><h3>场景参考图</h3><p>只有这里勾选的图片会进入分镜图像生成。Character 与 Outfit 的正式参考图由各自模块确认。</p></div><button className="quiet-button" disabled={loading || busy} onClick={() => void loadAssets()}>{loading ? "读取中…" : "刷新已关联图片"}</button></div>
    {error && <p className="form-error">{error}</p>}
    {loading ? <div className="asset-inline-state">正在读取已关联图片……</div> : !assets.length ? <div className="asset-inline-empty">尚未关联任何图片。请先在上方「关联对象」或资源库中把图片关联到本场景，再回到这里确认。</div> : <div className="scene-reference-grid">{assets.map(asset => <button key={asset.id} className={`scene-reference-card ${selected.has(asset.id) ? "chosen" : ""}`} disabled={busy} onClick={() => void toggle(asset)}><AssetPreview asset={asset} compact/><span><strong>{asset.name}</strong><small>{selected.has(asset.id) ? "已批准为场景参考" : "点击批准"}</small></span>{selected.has(asset.id) && <i>✓</i>}</button>)}</div>}
  </section>;
}

function AssetsWorkspace({ workplace, notify, focusAssetId }: {
  workplace: Workplace; notify: (message: string) => void; focusAssetId?: string | null;
}) {
  const [assets, setAssets] = React.useState<StudioAsset[]>([]);
  const [active, setActive] = React.useState<StudioAsset | null>(null);
  const [draft, setDraft] = React.useState<AssetDraft | null>(null);
  const [view, setView] = React.useState<"grid" | "list">("grid");
  const [typeFilter, setTypeFilter] = React.useState<"all" | AssetType>("all");
  const [tagFilter, setTagFilter] = React.useState("all");
  const [loading, setLoading] = React.useState(true);
  const [detailLoading, setDetailLoading] = React.useState(false);
  const [uploading, setUploading] = React.useState(false);
  const [saving, setSaving] = React.useState(false);
  const [deleting, setDeleting] = React.useState(false);
  const [error, setError] = React.useState("");
  const [confirmDelete, setConfirmDelete] = React.useState(false);
  const fileInput = React.useRef<HTMLInputElement | null>(null);

  React.useEffect(() => {
    let alive = true;
    setLoading(true); setError(""); setActive(null); setDraft(null);
    api<StudioAsset[]>(`/workplaces/${workplace.id}/assets`)
      .then(async list => {
        if (!alive) return;
        setAssets(list);
        if (!list.length) return;
        const target = list.find(asset => asset.id === focusAssetId) || list[0];
        const detail = await api<StudioAsset>(`/workplaces/${workplace.id}/assets/${target.id}`);
        if (alive) { setActive(detail); setDraft(assetDraft(detail)); }
      })
      .catch((cause: any) => { if (alive) setError(cause?.message || "无法读取创作资源库"); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [workplace.id, focusAssetId]);

  const dirty = !!(active && draft && (
    draft.name !== active.name || draft.description !== active.description ||
    draft.author !== active.author || draft.notes !== active.notes ||
    draft.tags !== (active.tags || []).join(", ")
  ));

  async function selectAsset(assetId: string) {
    if (active?.id === assetId) return;
    if (dirty && !window.confirm("当前资源的编辑尚未保存。切换资源会放弃这些修改，继续吗？")) return;
    setDetailLoading(true); setError("");
    try {
      const detail = await api<StudioAsset>(`/workplaces/${workplace.id}/assets/${assetId}`);
      setActive(detail); setDraft(assetDraft(detail));
    } catch (cause: any) {
      setError(cause?.message || "无法打开资源");
    } finally { setDetailLoading(false); }
  }

  async function uploadFile(file: File) {
    if (!file || uploading) return;
    setUploading(true); setError("");
    try {
      const metadata = await inspectMedia(file);
      const form = new FormData();
      form.append("file", file);
      const dot = file.name.lastIndexOf(".");
      form.append("name", dot > 0 ? file.name.slice(0, dot) : file.name);
      if (metadata.width) form.append("width", String(metadata.width));
      if (metadata.height) form.append("height", String(metadata.height));
      if (metadata.duration_ms !== undefined) form.append("duration_ms", String(metadata.duration_ms));
      const created = await uploadAsset(workplace.id, form);
      const detail = await api<StudioAsset>(`/workplaces/${workplace.id}/assets/${created.id}`);
      setAssets(previous => [detail, ...previous]);
      setActive(detail); setDraft(assetDraft(detail));
      setTypeFilter("all"); setTagFilter("all");
      notify("文件已加入创作资源库");
    } catch (cause: any) {
      setError(cause?.message || "上传失败");
    } finally {
      setUploading(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }

  async function saveAsset() {
    if (!active || !draft || saving) return;
    const name = draft.name.trim();
    if (!name) { setError("资源名称不能为空"); return; }
    setSaving(true); setError("");
    try {
      const saved = await api<StudioAsset>(`/workplaces/${workplace.id}/assets/${active.id}`, {
        method: "PUT",
        body: {
          name, description: draft.description, author: draft.author,
          notes: draft.notes, tags: draftTags(draft.tags),
        },
      });
      setActive(saved); setDraft(assetDraft(saved));
      setAssets(previous => previous.map(asset => asset.id === saved.id ? saved : asset));
      notify("资源信息已保存");
    } catch (cause: any) {
      setError(cause?.message || "保存资源失败");
    } finally { setSaving(false); }
  }

  async function deleteAsset() {
    if (!active || deleting) return;
    setDeleting(true); setError("");
    try {
      await api(`/workplaces/${workplace.id}/assets/${active.id}`, { method: "DELETE" });
      const remaining = assets.filter(asset => asset.id !== active.id);
      setAssets(remaining);
      setConfirmDelete(false);
      if (remaining.length) {
        const detail = await api<StudioAsset>(`/workplaces/${workplace.id}/assets/${remaining[0].id}`);
        setActive(detail); setDraft(assetDraft(detail));
      } else {
        setActive(null); setDraft(null);
      }
      notify("资源已归档，关联记录已清理");
    } catch (cause: any) {
      setError(cause?.message || "删除资源失败");
    } finally { setDeleting(false); }
  }

  function replaceLinks(links: AssetLink[]) {
    if (!active) return;
    const next = { ...active, links };
    setActive(next);
    setAssets(previous => previous.map(asset => asset.id === next.id ? { ...asset, links } : asset));
  }

  const allTags = Array.from(new Set(assets.flatMap(asset => asset.tags || []))).sort((left, right) => left.localeCompare(right, "zh-CN"));
  const filtered = assets.filter(asset => (typeFilter === "all" || asset.asset_type === typeFilter) && (tagFilter === "all" || (asset.tags || []).includes(tagFilter)));

  function renderAssetCard(asset: StudioAsset) {
    return <article key={asset.id} role="button" tabIndex={0} className={`asset-card ${active?.id === asset.id ? "active" : ""}`} onClick={() => void selectAsset(asset.id)} onKeyDown={(event: any) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); void selectAsset(asset.id); } }}>
      <AssetPreview asset={asset} compact interactive/>
      <div className="asset-card-copy"><span className="asset-card-kind">{ASSET_TYPE_INFO[asset.asset_type].en}</span><strong>{asset.name}</strong><small>{asset.description || asset.original_filename || "未填写说明"}</small><div className="asset-card-meta"><span>{assetMediaMeta(asset) || asset.mime_type}</span>{(asset.links || []).length > 0 && <em>{asset.links.length} 处引用</em>}</div></div>
    </article>;
  }

  return <div className="book-stage asset-stage">
    <div className="book-topline">
      <div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace.title}</span><span className="top-separator">/</span><span className="document-crumb">CREATIVE ASSETS</span></div>
      <div className="book-actions"><span className="character-count">{assets.length} 份资源</span><button className="head-btn" disabled={uploading} onClick={() => fileInput.current?.click()}><Icon name="upload"/>{uploading ? "上传中…" : "上传资源"}</button></div>
    </div>
    <input ref={fileInput} className="asset-file-input" type="file" accept="image/png,image/jpeg,image/gif,image/webp,image/bmp,audio/mpeg,audio/wav,audio/ogg,audio/flac,audio/mp4,video/mp4,video/quicktime,video/webm,video/ogg,.md,.markdown,.txt,.csv,.json,.pdf,.docx,.odt,.epub,.zip,.7z,.rar" onChange={(event: any) => { const file = event.target.files?.[0]; if (file) void uploadFile(file); }}/>
    <div className="asset-workspace">
      <main className="asset-library">
        <div className="asset-library-head"><div><div className="eyebrow brass-text">THE WORKPLACE ARCHIVE</div><h1>创作资源库</h1><p>图片、声音、影像与参考文件独立存在，并可被多个创作对象共同使用。</p></div><div className="asset-view-toggle"><button className={view === "grid" ? "active" : ""} aria-label="网格视图" onClick={() => setView("grid")}><Icon name="grid"/></button><button className={view === "list" ? "active" : ""} aria-label="列表视图" onClick={() => setView("list")}><Icon name="list"/></button></div></div>
        <div className="asset-filter-bar">
          <label>类型<select value={typeFilter} onChange={(event: any) => setTypeFilter(event.target.value)}><option value="all">全部类型</option>{(Object.keys(ASSET_TYPE_INFO) as AssetType[]).map(type => <option key={type} value={type}>{ASSET_TYPE_INFO[type].label}</option>)}</select></label>
          <label>标签<select value={tagFilter} onChange={(event: any) => setTagFilter(event.target.value)}><option value="all">全部标签</option>{allTags.map(tag => <option key={tag} value={tag}>{tag}</option>)}</select></label>
          <span>{filtered.length} / {assets.length}</span>
          {uploading && <em className="uploading-state">正在校验并保存文件……</em>}
        </div>
        {error && <div className="character-error asset-error">{error}<button onClick={() => setError("")}>关闭</button></div>}
        {loading ? <div className="character-state"><span className="thinking-mark">✦</span><p>正在整理资源档案……</p></div> : !assets.length ? <div className="character-state character-empty-state asset-empty-state"><div className="empty-book">✦</div><h2>资源库还是空的。</h2><p>上传一张标准形象、一段声音或一份参考文件，建立可复用的创作基础。</p><button className="tool-button primary" onClick={() => fileInput.current?.click()}><Icon name="upload"/>上传第一份资源</button></div> : !filtered.length ? <div className="asset-inline-empty">当前筛选条件下没有资源。</div> : <div className={view === "grid" ? "asset-grid" : "asset-list-view"}>{filtered.map(renderAssetCard)}</div>}
      </main>
      <aside className="asset-detail-panel">
        {detailLoading ? <div className="character-state"><span className="thinking-mark">✦</span><p>正在读取资源详情……</p></div> : !active || !draft ? <div className="asset-detail-empty"><div className="placeholder-ornament">✦</div><div className="eyebrow brass-text">SELECT AN ASSET</div><h2>选择一份资源。</h2><p>查看预览、维护元数据，并管理它被哪些 Character、Scene 或 Document 使用。</p></div> : <>
          <div className="asset-detail-head"><div><div className="eyebrow">{ASSET_TYPE_INFO[active.asset_type].en} · {active.source.toUpperCase()}</div><h2>{active.name}</h2><p>{active.original_filename || "Studio managed file"}</p></div><button className="head-btn delete-asset" onClick={() => setConfirmDelete(true)}><Icon name="trash"/>删除</button></div>
          <AssetPreview asset={active} interactive/>
          {active.file_url && <a className="tool-button asset-open-file" href={active.file_url} target="_blank" rel="noreferrer"><Icon name="file"/>在新窗口打开文件</a>}
          <div className="asset-edit-form">
            <label className="field-label">名称<input value={draft.name} maxLength={512} onChange={(event: any) => setDraft(previous => previous ? { ...previous, name: event.target.value } : previous)}/></label>
            <label className="field-label">描述<textarea rows={3} value={draft.description} onChange={(event: any) => setDraft(previous => previous ? { ...previous, description: event.target.value } : previous)} placeholder="这份资源在创作中承担什么作用？"/></label>
            <label className="field-label">标签<input value={draft.tags} onChange={(event: any) => setDraft(previous => previous ? { ...previous, tags: event.target.value } : previous)} placeholder="用逗号分隔，例如：mara, portrait, canon"/></label>
            <label className="field-label">作者<input value={draft.author} maxLength={512} onChange={(event: any) => setDraft(previous => previous ? { ...previous, author: event.target.value } : previous)}/></label>
            <label className="field-label">制作备注<textarea rows={3} value={draft.notes} onChange={(event: any) => setDraft(previous => previous ? { ...previous, notes: event.target.value } : previous)}/></label>
            <div className="asset-save-row"><span>{dirty ? "元数据有未保存修改" : "元数据已保存"}</span><button className="tool-button primary" disabled={saving || !dirty} onClick={() => void saveAsset()}>{saving ? "保存中…" : "保存资源信息"}</button></div>
          </div>
          <div className="asset-readonly-grid">
            <div><span>MIME</span><strong>{active.mime_type}</strong></div>
            <div><span>大小</span><strong>{formatBytes(active.file_size)}</strong></div>
            <div><span>文件尺寸</span><strong>{active.width && active.height ? `${active.width} × ${active.height}` : "不适用"}</strong></div>
            <div><span>时长</span><strong>{formatDuration(active.duration_ms) || "不适用"}</strong></div>
            <div className="wide"><span>SHA-256</span><code title={active.checksum}>{active.checksum || "未记录"}</code></div>
            <div><span>更新</span><strong>{new Date(active.updated_at).toLocaleString("zh-CN")}</strong></div>
          </div>
          <AssetTargetsEditor workplaceId={workplace.id} asset={active} onChange={replaceLinks} notify={notify}/>
        </>}
      </aside>
    </div>
    {confirmDelete && active && <Modal title="删除这份资源？" eyebrow="ARCHIVE ASSET" onClose={() => setConfirmDelete(false)} actions={<><button className="quiet-button" onClick={() => setConfirmDelete(false)}>保留资源</button><button className="confirm-button danger-button" disabled={deleting} onClick={() => void deleteAsset()}>{deleting ? "删除中…" : "确认删除"}</button></>}>
      <p className="modal-intro">“{active.name}”会从资源库和所有 Character、Scene、Document 关联中移除，受控文件也会被清理。此操作不会删除任何创作对象本身。</p>
      {error && <p className="form-error">{error}</p>}
    </Modal>}
  </div>;
}

const MODEL_TASK_INFO = [
  { key: "writing", label: "Writing", zh: "写作、灵感与续写" },
  { key: "character_development", label: "Character Development", zh: "角色人设草稿" },
  { key: "scene_extraction", label: "Scene Extraction", zh: "正文提取场景" },
  { key: "storyboard_planning", label: "Storyboard Planning", zh: "场景转分镜" },
];

const MODEL_CAPABILITY_INFO = [
  { key: "temperature", label: "Temperature" },
  { key: "top_p", label: "Top P" },
  { key: "streaming", label: "Streaming" },
  { key: "json", label: "JSON Output" },
  { key: "reasoning", label: "Reasoning" },
];

interface ModelProfileDraft {
  id?: string; name: string; provider: string; protocol: ModelProtocol;
  base_url: string; model_id: string; api_key: string; headers: string;
  timeout_seconds: number; enabled: boolean;
  temperature: string; top_p: string; max_output_tokens: string;
  stream: boolean; json_mode: boolean; reasoning_effort: string;
  context_window: string; max_output_tokens_limit: string;
  capabilities: Record<string, boolean | undefined>;
}

interface EmbeddingProfileDraft {
  id?: string; name: string; provider: string; base_url: string; model_id: string;
  api_key: string; dimensions: string; batch_size: number; timeout_seconds: number;
  headers: string; enabled: boolean;
}

function defaultCapabilities(protocol: ModelProtocol): Record<string, boolean> {
  if (protocol === "anthropic-messages") return { temperature: true, top_p: true, streaming: true, json: false };
  return { temperature: true, top_p: true, streaming: true, json: true };
}

function blankModelDraft(protocol: ModelProtocol = "openai-compatible"): ModelProfileDraft {
  return {
    name: "", provider: "custom", protocol, base_url: "", model_id: "", api_key: "",
    headers: "{}", timeout_seconds: 60, enabled: true,
    temperature: "0.7", top_p: "1", max_output_tokens: "2048",
    stream: true, json_mode: true, reasoning_effort: "",
    context_window: "", max_output_tokens_limit: "",
    capabilities: defaultCapabilities(protocol),
  };
}

function modelDraftFrom(profile: ModelProfile): ModelProfileDraft {
  const parameters = profile.parameters || {};
  const capabilities = profile.capabilities || {};
  return {
    id: profile.id, name: profile.name, provider: profile.provider,
    protocol: profile.protocol, base_url: profile.base_url, model_id: profile.model_id,
    api_key: "", headers: JSON.stringify(profile.custom_headers || {}, null, 2),
    timeout_seconds: profile.timeout_seconds || 60, enabled: profile.enabled,
    temperature: parameters.temperature != null ? String(parameters.temperature) : "",
    top_p: parameters.top_p != null ? String(parameters.top_p) : "",
    max_output_tokens: parameters.max_output_tokens != null ? String(parameters.max_output_tokens) : "",
    stream: parameters.stream === true,
    json_mode: parameters.format === "json",
    reasoning_effort: parameters.reasoning_effort != null ? String(parameters.reasoning_effort) : "",
    context_window: capabilities.context_window != null ? String(capabilities.context_window) : "",
    max_output_tokens_limit: capabilities.max_output_tokens != null ? String(capabilities.max_output_tokens) : "",
    capabilities: Object.fromEntries(MODEL_CAPABILITY_INFO.flatMap(item => {
      const value = capabilities[item.key];
      return typeof value === "boolean" ? [[item.key, value]] : [];
    })),
  };
}

function parsedHeaders(text: string): Record<string, string> {
  if (!text.trim()) return {};
  const value = JSON.parse(text);
  if (!value || Array.isArray(value) || typeof value !== "object") throw new Error("自定义 Headers 必须是 JSON 对象");
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, String(item)]));
}

function modelProfilePayload(draft: ModelProfileDraft) {
  const parameters: Record<string, any> = {};
  if (draft.temperature.trim() !== "") parameters.temperature = Number(draft.temperature);
  if (draft.top_p.trim() !== "") parameters.top_p = Number(draft.top_p);
  if (draft.max_output_tokens.trim() !== "") parameters.max_output_tokens = Number(draft.max_output_tokens);
  parameters.stream = draft.stream;
  if (draft.json_mode) parameters.format = "json";
  if (draft.reasoning_effort.trim()) parameters.reasoning_effort = draft.reasoning_effort.trim();
  const capabilities: Record<string, any> = { ...draft.capabilities };
  if (draft.context_window.trim()) capabilities.context_window = Number(draft.context_window);
  if (draft.max_output_tokens_limit.trim()) capabilities.max_output_tokens = Number(draft.max_output_tokens_limit);
  return {
    name: draft.name.trim(), provider: draft.provider.trim() || "custom",
    protocol: draft.protocol, base_url: draft.base_url.trim(), model_id: draft.model_id.trim(),
    api_key: draft.api_key.trim() || undefined,
    custom_headers: parsedHeaders(draft.headers), timeout_seconds: draft.timeout_seconds,
    parameters, capabilities, enabled: draft.enabled,
  };
}

function blankEmbeddingDraft(): EmbeddingProfileDraft {
  return {
    name: "", provider: "custom", base_url: "", model_id: "", api_key: "",
    dimensions: "", batch_size: 16, timeout_seconds: 60, headers: "{}", enabled: true,
  };
}

function embeddingDraftFrom(profile: EmbeddingProfile): EmbeddingProfileDraft {
  return {
    id: profile.id, name: profile.name, provider: profile.provider,
    base_url: profile.base_url, model_id: profile.model_id, api_key: "",
    dimensions: profile.dimensions != null ? String(profile.dimensions) : "",
    batch_size: profile.batch_size || 16, timeout_seconds: profile.timeout_seconds || 60,
    headers: JSON.stringify(profile.custom_headers || {}, null, 2), enabled: profile.enabled,
  };
}

function embeddingProfilePayload(draft: EmbeddingProfileDraft) {
  return {
    name: draft.name.trim(), provider: draft.provider.trim() || "custom",
    protocol: "openai-embeddings", base_url: draft.base_url.trim(), model_id: draft.model_id.trim(),
    api_key: draft.api_key.trim() || undefined,
    dimensions: draft.dimensions.trim() ? Number(draft.dimensions) : null,
    batch_size: draft.batch_size, timeout_seconds: draft.timeout_seconds,
    custom_headers: parsedHeaders(draft.headers), enabled: draft.enabled,
  };
}

function ManualAcceptancePanel({ notify }: { notify: (message: string) => void }) {
  const [overview, setOverview] = React.useState<AcceptanceOverview | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [busyTask, setBusyTask] = React.useState("");
  const [error, setError] = React.useState("");
  const [results, setResults] = React.useState<Record<string, AcceptanceRun>>({});

  React.useEffect(() => {
    let alive = true;
    api<AcceptanceOverview>("/settings/acceptance")
      .then(data => { if (alive) setOverview(data); })
      .catch((cause: any) => { if (alive) setError(cause?.message || "无法读取最小验收配置"); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, []);

  async function runTask(task: AcceptanceTask) {
    if (busyTask) return;
    if (task.may_incur_charges && !window.confirm(
      `本次将向 ${task.profile_name || task.protocol || "外部服务"} 发送一次真实请求。\n\nModel: ${task.model || "(未配置)"}\n这可能产生费用，且不会自动重试。继续吗？`
    )) return;
    setBusyTask(task.task); setError("");
    try {
      const result = await api<AcceptanceRun>(`/settings/acceptance/${task.task}`, {
        method: "POST",
        body: { confirm_charge: true },
      });
      setResults(previous => ({ ...previous, [task.task]: result }));
      notify(`${task.label} 验收通过；结果仅用于校验，没有写入创作数据`);
    } catch (cause: any) {
      setError(`${task.label}：${cause?.code || "ACCEPTANCE_FAILED"} · ${cause?.message || "请求失败"}`);
    } finally {
      setBusyTask("");
    }
  }

  return <section className="settings-panel acceptance-panel">
    <div className="settings-panel-head"><div><div className="eyebrow">MANUAL MODEL ACCEPTANCE</div><h2>最小真实模型验收</h2><p>这不是批量测试。每次只执行一个任务、发送一次请求，并明确显示当前 Profile、Model 与协议；不会自动重试或遍历模型。</p></div><span className="acceptance-safety-stamp">手动触发 · NO RETRY</span></div>
    {loading ? <div className="acceptance-state">正在核对任务路由……</div> : error && !overview ? <div className="character-error">{error}<button onClick={() => setError("")}>关闭</button></div> : overview ? <>
      <p className="acceptance-warning">{overview.warning}</p>
      {error && <div className="character-error settings-error">{error}<button onClick={() => setError("")}>关闭</button></div>}
      <div className="acceptance-task-grid">{overview.tasks.map(task => {
        const result = results[task.task];
        return <article className={`acceptance-task ${task.configured ? "" : "unconfigured"}`} key={task.task}>
          <div className="acceptance-task-head"><div><span>{task.label.toUpperCase()}</span><h3>{task.label}</h3></div><em className={task.may_incur_charges ? "paid" : ""}>{task.may_incur_charges ? "POSSIBLE CHARGE" : "LOCAL / FAKE"}</em></div>
          <dl><div><dt>Profile</dt><dd>{task.profile_name || "Legacy fallback"}</dd></div><div><dt>Model</dt><dd>{task.model || "(not configured)"}</dd></div><div><dt>Protocol</dt><dd>{task.protocol || "(unknown)"}</dd></div></dl>
          <button className="tool-button" disabled={!!busyTask || !task.configured} onClick={() => void runTask(task)}>{busyTask === task.task ? "正在执行一次请求…" : `运行 ${task.label}`}</button>
          {result && <div className="acceptance-result"><strong>VALID · {result.elapsed_ms} ms</strong><pre>{JSON.stringify(result.validation, null, 2)}\n\n{result.preview}</pre></div>}
        </article>;
      })}</div>
      <div className="acceptance-embedding-note"><strong>Embedding</strong><span>{overview.embedding_note}</span><small>{overview.embedding.configured ? `${overview.embedding.profile_name || "Configured"} · ${overview.embedding.model || "model unset"}` : "尚未配置独立 Embedding Profile；不会影响写作、角色或场景。"}</small></div>
    </> : null}
  </section>;
}

function SettingsWorkspace({ workplace, capabilities, editorFontSize, setEditorFontSize, defaultCover, setDefaultCover, notify }: {
  workplace: Workplace; capabilities: Capabilities | null; editorFontSize: number;
  setEditorFontSize: (value: number) => void; defaultCover: string;
  setDefaultCover: (value: string) => void; notify: (message: string) => void;
}) {
  const [settings, setSettings] = React.useState<ModelSettings | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState("");
  const [profileDraft, setProfileDraft] = React.useState<ModelProfileDraft>(blankModelDraft());
  const [profileBusy, setProfileBusy] = React.useState(false);
  const [testResult, setTestResult] = React.useState("");
  const [discoveredModels, setDiscoveredModels] = React.useState<{ id: string; name: string }[]>([]);
  const [presetToAdd, setPresetToAdd] = React.useState("custom-openai");
  const [routingDraft, setRoutingDraft] = React.useState<Record<string, string>>({});
  const [defaultDraft, setDefaultDraft] = React.useState("");
  const [routingBusy, setRoutingBusy] = React.useState(false);
  const [embeddingDraft, setEmbeddingDraft] = React.useState<EmbeddingProfileDraft>(blankEmbeddingDraft());
  const [embeddingBusy, setEmbeddingBusy] = React.useState(false);
  const [embeddingTestText, setEmbeddingTestText] = React.useState("Khala Studio embedding connection test.");
  const [embeddingResult, setEmbeddingResult] = React.useState("");

  function installSettings(next: ModelSettings, preferredId?: string) {
    setSettings(next);
    const selected = next.llm_profiles.find(profile => profile.id === (preferredId || profileDraft.id))
      || next.llm_profiles[0];
    setProfileDraft(selected ? modelDraftFrom(selected) : blankModelDraft());
    setDefaultDraft(next.default_llm_profile_id || "");
    setRoutingDraft(Object.fromEntries(next.tasks.map(task => [task, next.task_assignments[task] || ""])));
    const embedding = next.embedding_profiles.find(profile => profile.id === embeddingDraft.id)
      || next.embedding_profiles[0];
    setEmbeddingDraft(embedding ? embeddingDraftFrom(embedding) : blankEmbeddingDraft());
  }

  async function loadSettings(preferredId?: string) {
    setLoading(true); setError("");
    try {
      installSettings(await api<ModelSettings>("/settings"), preferredId);
    } catch (cause: any) {
      setError(cause?.message || "无法读取模型设置");
    } finally { setLoading(false); }
  }

  React.useEffect(() => { void loadSettings(); }, []);

  function choosePreset(key: string) {
    if (!settings) return;
    const preset = settings.provider_presets[key];
    if (!preset) return;
    const draft = blankModelDraft(preset.protocol);
    setProfileDraft({
      ...draft, provider: key.replace(/^custom-/, ""), name: preset.name,
      protocol: preset.protocol, base_url: preset.base_url, model_id: preset.model_id,
    });
    setTestResult(""); setDiscoveredModels([]); setError("");
  }

  function selectProfile(profile: ModelProfile) {
    setProfileDraft(modelDraftFrom(profile));
    setTestResult(""); setDiscoveredModels([]); setError("");
  }

  function changeProtocol(protocol: ModelProtocol) {
    setProfileDraft(previous => ({
      ...previous, protocol, capabilities: defaultCapabilities(protocol),
      json_mode: protocol !== "anthropic-messages",
    }));
  }

  async function saveProfile() {
    if (!profileDraft.name.trim()) { setError("Profile 名称不能为空"); return; }
    if (profileDraft.protocol !== "fake" && (!profileDraft.base_url.trim() || !profileDraft.model_id.trim())) {
      setError("Base URL 与 Model ID 都必须填写；模型列表获取失败时也可以手动填写。"); return;
    }
    setProfileBusy(true); setError("");
    try {
      const payload = modelProfilePayload(profileDraft);
      const saved = await api<ModelProfile>(
        profileDraft.id ? `/settings/model-profiles/${profileDraft.id}` : "/settings/model-profiles",
        { method: profileDraft.id ? "PUT" : "POST", body: payload },
      );
      await loadSettings(saved.id);
      notify(profileDraft.id ? "模型 Profile 已保存；密钥不会通过读取接口返回。" : "模型 Profile 已建立");
    } catch (cause: any) {
      setError(cause?.message || "保存模型 Profile 失败");
    } finally { setProfileBusy(false); }
  }

  async function deleteProfile() {
    if (!profileDraft.id || !window.confirm(`归档“${profileDraft.name}”？已分配到该 Profile 的任务会回退到全局默认。`)) return;
    setProfileBusy(true); setError("");
    try {
      await api(`/settings/model-profiles/${profileDraft.id}`, { method: "DELETE" });
      await loadSettings();
      notify("模型 Profile 已归档");
    } catch (cause: any) {
      setError(cause?.message || "归档模型 Profile 失败");
    } finally { setProfileBusy(false); }
  }

  async function testProfile() {
    if (!profileDraft.id) { setError("请先保存 Profile，再测试连接。"); return; }
    setProfileBusy(true); setError(""); setTestResult("正在测试已保存的 Profile…");
    try {
      const result = await api<any>(`/settings/model-profiles/${profileDraft.id}/test`, { method: "POST", body: {} });
      setTestResult(`连接成功 · ${result.model || profileDraft.model_id} · ${result.protocol} · ${result.elapsed_ms} ms\n${result.preview || ""}`);
    } catch (cause: any) {
      setTestResult("");
      setError(`${cause?.code || "TEST_FAILED"}：${cause?.message || "连接测试失败"}`);
    } finally { setProfileBusy(false); }
  }

  async function discoverModels() {
    if (!profileDraft.id) { setError("请先保存 Profile，再获取模型列表；也可以直接手动填写 Model ID。"); return; }
    setProfileBusy(true); setError("");
    try {
      const result = await api<{ models: { id: string; name: string }[] }>(`/settings/model-profiles/${profileDraft.id}/models`, { method: "POST", body: {} });
      setDiscoveredModels(result.models || []);
      if (!profileDraft.model_id && result.models?.length) {
        setProfileDraft(previous => ({ ...previous, model_id: result.models[0].id }));
      }
      notify(`读取到 ${result.models?.length || 0} 个模型；仍可手动填写任意模型 ID`);
    } catch (cause: any) {
      setError(`模型列表读取失败，可继续手动填写：${cause?.message || "未知错误"}`);
    } finally { setProfileBusy(false); }
  }

  async function saveRouting() {
    setRoutingBusy(true); setError("");
    try {
      const tasks = Object.fromEntries(MODEL_TASK_INFO.map(task => [task.key, routingDraft[task.key] || null]));
      const next = await api<ModelSettings>("/settings/routing", {
        method: "PUT",
        body: { default_profile_id: defaultDraft || null, tasks },
      });
      setSettings(next);
      setDefaultDraft(next.default_llm_profile_id || "");
      setRoutingDraft(Object.fromEntries(next.tasks.map(task => [task, next.task_assignments[task] || ""])));
      notify("模型任务分配已保存");
    } catch (cause: any) {
      setError(cause?.message || "保存模型任务分配失败");
    } finally { setRoutingBusy(false); }
  }

  function selectEmbedding(profile: EmbeddingProfile) {
    setEmbeddingDraft(embeddingDraftFrom(profile));
    setEmbeddingResult(""); setError("");
  }

  async function saveEmbedding() {
    if (!embeddingDraft.name.trim() || !embeddingDraft.base_url.trim() || !embeddingDraft.model_id.trim()) {
      setError("Embedding Profile 的名称、Base URL 和 Model ID 都必须填写。"); return;
    }
    setEmbeddingBusy(true); setError("");
    try {
      const payload = embeddingProfilePayload(embeddingDraft);
      const saved = await api<EmbeddingProfile>(
        embeddingDraft.id ? `/settings/embedding-profiles/${embeddingDraft.id}` : "/settings/embedding-profiles",
        { method: embeddingDraft.id ? "PUT" : "POST", body: payload },
      );
      await loadSettings();
      setEmbeddingDraft(embeddingDraftFrom(saved));
      notify("Embedding Profile 已保存");
    } catch (cause: any) {
      setError(cause?.message || "保存 Embedding Profile 失败");
    } finally { setEmbeddingBusy(false); }
  }

  async function deleteEmbedding() {
    if (!embeddingDraft.id || !window.confirm(`归档“${embeddingDraft.name}”？`)) return;
    setEmbeddingBusy(true); setError("");
    try {
      await api(`/settings/embedding-profiles/${embeddingDraft.id}`, { method: "DELETE" });
      await loadSettings();
      notify("Embedding Profile 已归档");
    } catch (cause: any) {
      setError(cause?.message || "归档 Embedding Profile 失败");
    } finally { setEmbeddingBusy(false); }
  }

  async function testEmbedding() {
    if (!embeddingDraft.id) { setError("请先保存 Embedding Profile，再执行测试。"); return; }
    setEmbeddingBusy(true); setError(""); setEmbeddingResult("正在请求 Embedding…");
    try {
      const result = await api<any>(`/settings/embedding-profiles/${embeddingDraft.id}/test`, {
        method: "POST", body: { text: embeddingTestText },
      });
      setEmbeddingResult(`向量合法 · 实际模型 ${result.model} · 维度 ${result.dimensions}\n前三维：${JSON.stringify(result.sample)}`);
    } catch (cause: any) {
      setEmbeddingResult("");
      setError(`${cause?.code || "EMBEDDING_TEST_FAILED"}：${cause?.message || "Embedding 测试失败"}`);
    } finally { setEmbeddingBusy(false); }
  }

  async function setDefaultEmbedding() {
    if (!embeddingDraft.id) return;
    setEmbeddingBusy(true); setError("");
    try {
      const next = await api<ModelSettings>("/settings/routing", {
        method: "PUT", body: { default_embedding_profile_id: embeddingDraft.id },
      });
      setSettings(next);
      notify("默认 Embedding Profile 已更新");
    } catch (cause: any) {
      setError(cause?.message || "更新默认 Embedding 失败");
    } finally { setEmbeddingBusy(false); }
  }

  return <div className="book-stage settings-workspace-stage">
    <div className="book-topline"><div><span className="folio-brand">KHALA STUDIO</span><span className="top-separator">/</span><span className="world-title">{workplace.title}</span><span className="top-separator">/</span><span className="document-crumb">MODEL SETTINGS</span></div><div className="book-actions"><button className="head-btn" onClick={() => void loadSettings()}>{loading ? "读取中…" : "重新读取"}</button><button className="head-btn close-book-button" onClick={() => notify("设置已由服务端保存，关闭 Workplace 不会丢失。")}>服务端配置</button></div></div>
    <div className="settings-workspace">
      <header className="settings-workspace-head"><div><div className="eyebrow brass-text">UNIFIED MODEL SETTINGS</div><h1>让每个创作任务使用它真正需要的模型。</h1><p>Provider、Model Profile 与任务分配分层保存。API Key 只写入服务端本地密钥文件；读取接口只显示掩码。</p></div><span className="settings-engine-badge">ENGINE　{capabilities?.engine || settings?.legacy.engine || "unknown"}</span></header>
      {error && <div className="character-error settings-error">{error}<button onClick={() => setError("")}>关闭</button></div>}
      {loading || !settings ? <div className="character-state"><span className="thinking-mark">✦</span><p>正在展开模型配置……</p></div> : <>
        <section className="settings-panel routing-panel">
          <div className="settings-panel-head"><div><div className="eyebrow">TASK ASSIGNMENT</div><h2>全局默认与任务模型</h2><p>没有专属任务的模型会回退到全局默认；Embedding 不参与 LLM fallback。</p></div><button className="tool-button primary" disabled={routingBusy} onClick={() => void saveRouting()}>{routingBusy ? "保存中…" : "保存任务分配"}</button></div>
          <div className="routing-grid">
            <label className="field-label">全局默认 LLM<select value={defaultDraft} onChange={(event: any) => setDefaultDraft(event.target.value)}><option value="">使用 Khala 旧配置回退</option>{settings.llm_profiles.map(profile => <option key={profile.id} value={profile.id} disabled={!profile.enabled}>{profile.name} · {profile.model_id || profile.protocol}</option>)}</select></label>
            {MODEL_TASK_INFO.map(task => <label className="field-label" key={task.key}>{task.label}<small>{task.zh}</small><select value={routingDraft[task.key] || ""} onChange={(event: any) => setRoutingDraft(previous => ({ ...previous, [task.key]: event.target.value }))}><option value="">回退到全局默认</option>{settings.llm_profiles.map(profile => <option key={profile.id} value={profile.id} disabled={!profile.enabled}>{profile.name} · {profile.model_id || profile.protocol}</option>)}</select></label>)}
          </div>
          <div className="settings-legacy-note">旧配置：engine <code>{settings.legacy.engine}</code> · model <code>{settings.legacy.model || "(none)"}</code>{settings.legacy.fallback_available ? " · 可作为未分配任务时的兼容回退" : " · 目前没有可用的旧模型回退"}</div>
        </section>

        <section className="settings-panel">
          <div className="settings-panel-head"><div><div className="eyebrow">LANGUAGE MODELS</div><h2>LLM Profiles</h2><p>OpenAI-compatible、Gemini Native、Anthropic Messages 与 fake 测试引擎。自定义模型 ID 永远可以手动填写。</p></div><div className="settings-add-profile"><select value={presetToAdd} onChange={(event: any) => setPresetToAdd(event.target.value)}>{Object.entries(settings.provider_presets).map(([key, preset]) => <option key={key} value={key}>{preset.name}</option>)}</select><button className="tool-button" onClick={() => choosePreset(presetToAdd)}><Icon name="plus"/>从预设添加</button><button className="quiet-button" onClick={() => setProfileDraft(blankModelDraft())}>空白自定义</button></div></div>
          <div className="model-settings-layout">
            <aside className="model-profile-list">
              {!settings.llm_profiles.length && <div className="asset-inline-empty">还没有模型 Profile。</div>}
              {settings.llm_profiles.map(profile => <button key={profile.id} className={`model-profile-row ${profileDraft.id === profile.id ? "active" : ""} ${profile.enabled ? "" : "disabled"}`} onClick={() => selectProfile(profile)}><span className="model-protocol-mark">{profile.protocol === "openai-compatible" ? "OA" : profile.protocol === "gemini-native" ? "GM" : profile.protocol === "anthropic-messages" ? "AN" : "FX"}</span><span><strong>{profile.name}</strong><small>{profile.model_id || "model not set"} · {profile.provider}</small><em>{profile.api_key_configured ? `KEY ${profile.api_key_masked}` : "NO KEY"} · {profile.enabled ? "ENABLED" : "DISABLED"}</em></span></button>)}
            </aside>
            <div className="model-profile-editor">
              <div className="model-editor-heading"><div><div className="eyebrow">{profileDraft.id ? "EDIT PROFILE" : "NEW PROFILE"}</div><h3>{profileDraft.name || "未命名模型 Profile"}</h3></div><label className="switch-row"><input type="checkbox" checked={profileDraft.enabled} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, enabled: event.target.checked }))}/><span>启用</span></label></div>
              <div className="settings-form-grid">
                <label className="field-label">Profile 名称<input value={profileDraft.name} maxLength={256} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, name: event.target.value }))} placeholder="例如：DeepSeek 主写作模型"/></label>
                <label className="field-label">Provider 名称<input value={profileDraft.provider} maxLength={128} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, provider: event.target.value }))} placeholder="deepseek / openrouter / local"/></label>
                <label className="field-label">Protocol<select value={profileDraft.protocol} onChange={(event: any) => changeProtocol(event.target.value as ModelProtocol)}>{Object.entries(settings.protocols).map(([key, protocol]) => <option key={key} value={key}>{protocol.label}</option>)}</select></label>
                <label className="field-label">Timeout (seconds)<input type="number" min={1} max={300} value={profileDraft.timeout_seconds} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, timeout_seconds: Number(event.target.value) }))}/></label>
                <label className="field-label wide">Base URL<input value={profileDraft.base_url} maxLength={2048} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, base_url: event.target.value }))} placeholder="https://api.example.com/v1 或 http://127.0.0.1:11434/v1"/></label>
                <label className="field-label wide">Model ID<div className="model-id-control"><input value={profileDraft.model_id} maxLength={512} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, model_id: event.target.value }))} placeholder="任意模型 ID；不依赖白名单"/><button className="quiet-button" disabled={profileBusy} onClick={() => void discoverModels()}>获取模型</button>{discoveredModels.length > 0 && <select value="" onChange={(event: any) => { if (event.target.value) setProfileDraft(previous => ({ ...previous, model_id: event.target.value })); }}><option value="">从已读取列表选择</option>{discoveredModels.map(model => <option key={model.id} value={model.id}>{model.name} ({model.id})</option>)}</select>}</div></label>
                <label className="field-label wide">API Key<div className="secret-input"><input type="password" value={profileDraft.api_key} autoComplete="new-password" onChange={(event: any) => setProfileDraft(previous => ({ ...previous, api_key: event.target.value }))} placeholder={profileDraft.id ? "留空保留现有密钥" : "可留空用于本地服务"}/>{profileDraft.id && <small>{settings.llm_profiles.find(profile => profile.id === profileDraft.id)?.api_key_masked || "未配置密钥"}</small>}</div></label>
                <label className="field-label wide">自定义 Headers（JSON 对象）<textarea rows={4} spellCheck={false} value={profileDraft.headers} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, headers: event.target.value }))}/><small>认证头请使用 API Key 字段，不接受 Authorization、x-api-key 或 Cookie。</small></label>
              </div>
              <div className="capability-editor"><div className="eyebrow">CAPABILITIES · UNKNOWN IS ALLOWED</div><div className="capability-grid">{MODEL_CAPABILITY_INFO.map(item => <label key={item.key}><span>{item.label}</span><select value={profileDraft.capabilities[item.key] === true ? "yes" : profileDraft.capabilities[item.key] === false ? "no" : "unknown"} onChange={(event: any) => setProfileDraft(previous => { const capabilities = { ...previous.capabilities }; if (event.target.value === "unknown") delete capabilities[item.key]; else capabilities[item.key] = event.target.value === "yes"; return { ...previous, capabilities }; })}><option value="unknown">Unknown</option><option value="yes">Supported</option><option value="no">Not supported</option></select></label>)}</div><div className="settings-form-grid compact"><label className="field-label">Context Window<input value={profileDraft.context_window} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, context_window: event.target.value }))} placeholder="留空表示 Unknown"/></label><label className="field-label">Max Output Tokens<input value={profileDraft.max_output_tokens_limit} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, max_output_tokens_limit: event.target.value }))} placeholder="留空表示 Unknown"/></label></div></div>
              <div className="parameter-editor"><div className="eyebrow">DEFAULT GENERATION PARAMETERS</div><div className="settings-form-grid compact"><label className="field-label">Temperature<input value={profileDraft.temperature} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, temperature: event.target.value }))} placeholder="留空则不发送"/></label><label className="field-label">Top P<input value={profileDraft.top_p} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, top_p: event.target.value }))} placeholder="留空则不发送"/></label><label className="field-label">Max Output Tokens<input value={profileDraft.max_output_tokens} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, max_output_tokens: event.target.value }))} placeholder="例如 4096"/></label><label className="field-label">Reasoning Effort<input value={profileDraft.reasoning_effort} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, reasoning_effort: event.target.value }))} placeholder="仅在 capability 支持时发送"/></label></div><div className="parameter-checks"><label><input type="checkbox" checked={profileDraft.stream} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, stream: event.target.checked }))}/> 默认 Streaming</label><label><input type="checkbox" checked={profileDraft.json_mode} onChange={(event: any) => setProfileDraft(previous => ({ ...previous, json_mode: event.target.checked }))}/> 默认请求 JSON 输出</label></div></div>
              {testResult && <pre className="model-test-result">{testResult}</pre>}
              <div className="model-editor-actions">{profileDraft.id && <button className="quiet-button danger-text" disabled={profileBusy} onClick={() => void deleteProfile()}>归档 Profile</button>}<div><button className="tool-button" disabled={profileBusy} onClick={() => void testProfile()}>{profileBusy ? "处理中…" : "测试连接"}</button><button className="tool-button primary" disabled={profileBusy} onClick={() => void saveProfile()}>{profileBusy ? "保存中…" : "保存 Profile"}</button></div></div>
            </div>
          </div>
        </section>

        <section className="settings-panel">
          <div className="settings-panel-head"><div><div className="eyebrow">EMBEDDINGS · INDEPENDENT</div><h2>Embedding Profiles</h2><p>独立于文本生成模型。未配置时不会影响写作、角色或场景；语义检索类功能会明确提示尚未配置。</p></div><button className="quiet-button" onClick={() => setEmbeddingDraft(blankEmbeddingDraft())}><Icon name="plus"/>新建 Embedding</button></div>
          <div className="model-settings-layout">
            <aside className="model-profile-list">
              {!settings.embedding_profiles.length && <div className="asset-inline-empty">还没有 Embedding Profile。</div>}
              {settings.embedding_profiles.map(profile => <button key={profile.id} className={`model-profile-row ${embeddingDraft.id === profile.id ? "active" : ""}`} onClick={() => selectEmbedding(profile)}><span className="model-protocol-mark">EM</span><span><strong>{profile.name}</strong><small>{profile.model_id} · {profile.dimensions ? `${profile.dimensions} dim` : "dimension unknown"}</small><em>{profile.api_key_configured ? `KEY ${profile.api_key_masked}` : "NO KEY"} · {settings.default_embedding_profile_id === profile.id ? "DEFAULT" : "NOT DEFAULT"}</em></span></button>)}
            </aside>
            <div className="model-profile-editor">
              <div className="settings-form-grid">
                <label className="field-label">Profile 名称<input value={embeddingDraft.name} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, name: event.target.value }))} placeholder="例如：OpenAI text-embedding-3-small"/></label>
                <label className="field-label">Provider<input value={embeddingDraft.provider} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, provider: event.target.value }))} placeholder="openai / custom"/></label>
                <label className="field-label wide">Base URL<input value={embeddingDraft.base_url} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, base_url: event.target.value }))} placeholder="https://api.openai.com/v1"/></label>
                <label className="field-label wide">Model ID<input value={embeddingDraft.model_id} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, model_id: event.target.value }))} placeholder="text-embedding-3-small 或任意兼容模型"/></label>
                <label className="field-label wide">API Key<div className="secret-input"><input type="password" autoComplete="new-password" value={embeddingDraft.api_key} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, api_key: event.target.value }))} placeholder={embeddingDraft.id ? "留空保留现有密钥" : "可留空用于本地服务"}/>{embeddingDraft.id && <small>{settings.embedding_profiles.find(profile => profile.id === embeddingDraft.id)?.api_key_masked || "未配置密钥"}</small>}</div></label>
                <label className="field-label">Dimensions<input value={embeddingDraft.dimensions} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, dimensions: event.target.value }))} placeholder="留空由服务返回"/></label>
                <label className="field-label">Batch Size<input type="number" min={1} max={256} value={embeddingDraft.batch_size} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, batch_size: Number(event.target.value) }))}/></label>
                <label className="field-label">Timeout (seconds)<input type="number" min={1} max={300} value={embeddingDraft.timeout_seconds} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, timeout_seconds: Number(event.target.value) }))}/></label>
                <label className="switch-row"><input type="checkbox" checked={embeddingDraft.enabled} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, enabled: event.target.checked }))}/><span>启用</span></label>
                <label className="field-label wide">自定义 Headers（JSON）<textarea rows={3} value={embeddingDraft.headers} onChange={(event: any) => setEmbeddingDraft(previous => ({ ...previous, headers: event.target.value }))}/></label>
              </div>
              <div className="embedding-test-box"><label className="field-label">测试文本<textarea rows={3} value={embeddingTestText} onChange={(event: any) => setEmbeddingTestText(event.target.value)}/></label><div><button className="tool-button" disabled={embeddingBusy} onClick={() => void testEmbedding()}>发送测试向量</button>{embeddingDraft.id && <button className="quiet-button" disabled={embeddingBusy || settings.default_embedding_profile_id === embeddingDraft.id} onClick={() => void setDefaultEmbedding()}>设为默认 Embedding</button>}</div>{embeddingResult && <pre className="model-test-result">{embeddingResult}</pre>}</div>
              <div className="model-editor-actions">{embeddingDraft.id && <button className="quiet-button danger-text" disabled={embeddingBusy} onClick={() => void deleteEmbedding()}>归档 Profile</button>}<button className="tool-button primary" disabled={embeddingBusy} onClick={() => void saveEmbedding()}>{embeddingBusy ? "保存中…" : "保存 Embedding Profile"}</button></div>
            </div>
          </div>
        </section>

        <ManualAcceptancePanel notify={notify}/>

        <section className="settings-panel local-preferences-panel"><div className="settings-panel-head"><div><div className="eyebrow">LOCAL EDITOR PREFERENCES</div><h2>本地阅读偏好</h2><p>字号和默认封面只影响当前浏览器的阅读体验，不属于服务端创作数据。</p></div></div><div className="settings-form-grid compact"><label className="setting-row"><span><strong>正文字号</strong><small>Adjust manuscript reading size.</small></span><div className="range-control"><input type="range" min="14" max="22" value={editorFontSize} onChange={(event: any) => setEditorFontSize(Number(event.target.value))}/><b>{editorFontSize}px</b></div></label><div className="setting-row cover-setting"><span><strong>新书默认封面</strong><small>Only the initial cover selection.</small></span><div className="color-options">{COVER_PALETTE.map(color => <button key={color.color} aria-label={color.label} title={color.label} className={defaultCover === color.color ? "chosen" : ""} style={{ background: color.color }} onClick={() => setDefaultCover(color.color)}/>)}</div></div></div></section>
      </>}
    </div>
  </div>;
}

interface SceneExtractionInput {
  selectionText: string;
  contextBefore: string;
  contextAfter: string;
  documentContent: string;
  revision: number;
}

function extractionDraftFrom(draft: SceneExtractionDraft): SceneExtractionDraft {
  return {
    ...draft,
    given_circumstances: { ...draft.given_circumstances },
    dramatic_situation: { ...draft.dramatic_situation },
    direction: { ...draft.direction },
    cast: (draft.cast || []).map((entry, index) => ({ ...entry, sort_order: entry.sort_order ?? index })),
    unresolved_characters: [...(draft.unresolved_characters || [])],
    source: { ...draft.source },
  };
}

function SceneExtractionModal({ workplace, document, input, onClose, onCreated }: {
  workplace: Workplace; document: StudioDocument; input: SceneExtractionInput;
  onClose: () => void; onCreated: (result: SceneExtractionResult) => void;
}) {
  const selectionAvailable = Boolean(input.selectionText.trim());
  const [scope, setScope] = React.useState<"selection" | "document">(selectionAvailable ? "selection" : "document");
  const [characters, setCharacters] = React.useState<StudioCharacter[]>([]);
  const [charactersLoading, setCharactersLoading] = React.useState(true);
  const [draft, setDraft] = React.useState<SceneExtractionDraft | null>(null);
  const [busy, setBusy] = React.useState(false);
  const [confirmBusy, setConfirmBusy] = React.useState(false);
  const [error, setError] = React.useState("");
  const [manualCharacter, setManualCharacter] = React.useState("");

  React.useEffect(() => {
    let alive = true;
    api<StudioCharacter[]>(`/workplaces/${workplace.id}/characters`)
      .then(list => { if (alive) setCharacters(list); })
      .catch((cause: any) => { if (alive) setError(cause?.message || "无法读取 Character Pool"); })
      .finally(() => { if (alive) setCharactersLoading(false); });
    return () => { alive = false; };
  }, [workplace.id]);

  const sourceText = scope === "selection" ? input.selectionText : input.documentContent;
  const castIds = new Set((draft?.cast || []).map(entry => entry.character_id));

  async function generateDraft() {
    if (!sourceText.trim() || busy) return;
    setBusy(true); setError("");
    try {
      const result = await api<SceneExtractionDraft>(
        `/workplaces/${workplace.id}/documents/${document.id}/scene-extraction`,
        {
          method: "POST",
          body: {
            expected_revision: input.revision,
            scope,
            selected_text: scope === "selection" ? input.selectionText : "",
            context_before: input.contextBefore,
            context_after: input.contextAfter,
          },
        },
      );
      setDraft(extractionDraftFrom(result));
    } catch (cause: any) {
      const revision = cause instanceof StudioApiError && cause.status === 409
        ? ` 当前服务器版本为 v${cause.currentRevision ?? "?"}；请重新打开文档后再提取。`
        : "";
      setError(`${cause?.code || "EXTRACTION_FAILED"}：${cause?.message || "Scene 提取失败"}${revision}`);
    } finally {
      setBusy(false);
    }
  }

  function editScene(update: (previous: SceneExtractionDraft) => SceneExtractionDraft) {
    setDraft(previous => previous ? update(previous) : previous);
  }

  function editGiven(key: keyof SceneGivenCircumstances, value: string) {
    editScene(previous => ({ ...previous, given_circumstances: { ...previous.given_circumstances, [key]: value } }));
  }

  function editDramatic(key: keyof SceneDramaticSituation, value: string) {
    editScene(previous => ({ ...previous, dramatic_situation: { ...previous.dramatic_situation, [key]: value } }));
  }

  function editDirection(key: keyof SceneDirection, value: string) {
    editScene(previous => ({ ...previous, direction: { ...previous.direction, [key]: value } }));
  }

  function editCast(index: number, key: keyof SceneExtractionCast, value: string) {
    editScene(previous => ({
      ...previous,
      cast: previous.cast.map((entry, itemIndex) => itemIndex === index ? { ...entry, [key]: value } : entry),
    }));
  }

  function addCast(character: StudioCharacter, seed?: Partial<SceneExtractionCast>) {
    if (!character || castIds.has(character.id)) return;
    editScene(previous => ({
      ...previous,
      cast: [...previous.cast, {
        character_id: character.id, character_name: character.name,
        objective: seed?.objective || "", action: seed?.action || "",
        conflict: seed?.conflict || "", emotional_state: seed?.emotional_state || "",
        performance_direction: seed?.performance_direction || "", subtext: seed?.subtext || "",
        sort_order: previous.cast.length,
      }],
    }));
  }

  function resolveUnresolved(index: number, characterId: string) {
    const character = characters.find(item => item.id === characterId);
    if (!character) return;
    editScene(previous => ({
      ...previous,
      cast: [...previous.cast, {
        character_id: character.id, character_name: character.name,
        objective: "", action: "", conflict: "", emotional_state: "",
        performance_direction: "", subtext: "", sort_order: previous.cast.length,
      }],
      unresolved_characters: previous.unresolved_characters.filter((_, itemIndex) => itemIndex !== index),
    }));
  }

  function ignoreUnresolved(index: number) {
    editScene(previous => ({
      ...previous,
      unresolved_characters: previous.unresolved_characters.filter((_, itemIndex) => itemIndex !== index),
    }));
  }

  function removeCast(index: number) {
    editScene(previous => ({
      ...previous,
      cast: previous.cast.filter((_, itemIndex) => itemIndex !== index),
    }));
  }

  async function confirmDraft() {
    if (!draft || confirmBusy) return;
    if (!draft.title.trim()) { setError("Scene 标题不能为空"); return; }
    setConfirmBusy(true); setError("");
    try {
      const result = await api<SceneExtractionResult>(
        `/workplaces/${workplace.id}/documents/${document.id}/scene-extractions/confirm`,
        {
          method: "POST",
          body: {
            title: draft.title.trim(), summary: draft.summary,
            given_circumstances: draft.given_circumstances,
            dramatic_situation: draft.dramatic_situation,
            dialogue: draft.dialogue, direction: draft.direction,
            expected_revision: draft.source.document_revision,
            source_text_snapshot: draft.source.text,
            source_selection_start: draft.source.selection_start,
            source_selection_end: draft.source.selection_end,
            cast: draft.cast.map((entry, index) => ({
              character_id: entry.character_id, objective: entry.objective,
              action: entry.action, conflict: entry.conflict,
              emotional_state: entry.emotional_state,
              performance_direction: entry.performance_direction,
              subtext: entry.subtext, sort_order: index,
            })),
          },
        },
      );
      onCreated(result);
    } catch (cause: any) {
      setError(`${cause?.code || "SCENE_CREATE_FAILED"}：${cause?.message || "无法创建 Scene"}`);
    } finally {
      setConfirmBusy(false);
    }
  }

  const actions = draft
    ? <>
        <button className="quiet-button" onClick={() => setDraft(null)} disabled={confirmBusy}>返回来源确认</button>
        <button className="quiet-button" onClick={onClose} disabled={confirmBusy}>取消</button>
        <button className="confirm-button" onClick={() => void confirmDraft()} disabled={confirmBusy || !draft.title.trim()}>
          {confirmBusy ? "创建 Scene…" : "确认并创建 Scene"}
        </button>
      </>
    : <>
        <button className="quiet-button" onClick={onClose} disabled={busy}>取消</button>
        <button className="confirm-button" onClick={() => void generateDraft()} disabled={busy || !sourceText.trim()}>
          {busy ? "正在提取…" : "确认原文并提取 Scene"}
        </button>
      </>;

  return <Modal title={draft ? "审核 Scene Draft" : "从正文提取 Scene"} eyebrow={draft ? "AUTHOR REVIEW REQUIRED" : "WRITING → SCENE"} onClose={onClose} className="scene-extraction-modal" actions={actions}>
    {error && <div className="character-error extraction-error">{error}<button onClick={() => setError("")}>关闭</button></div>}
    {!draft ? <div className="extraction-source-step">
      <p className="modal-intro">AI 只会读取下面这段原文。原始 Document 不会被修改；提取结果会先成为可编辑草稿，只有你确认后才会创建 Scene 与 Cast。</p>
      <div className="extraction-scope-options">
        <button className={scope === "selection" ? "active" : ""} disabled={!selectionAvailable || busy} onClick={() => setScope("selection")}>
          <strong>当前选区</strong><span>{selectionAvailable ? `${input.selectionText.length.toLocaleString("zh-CN")} 字` : "没有可靠选区"}</span>
        </button>
        <button className={scope === "document" ? "active" : ""} disabled={busy} onClick={() => setScope("document")}>
          <strong>整个 Document</strong><span>{input.documentContent.length.toLocaleString("zh-CN")} 字</span>
        </button>
      </div>
      <div className="extraction-source-meta"><span>{document.title}</span><small>REVISION {input.revision} · {scope === "selection" ? "SELECTION SNAPSHOT" : "DOCUMENT SNAPSHOT"}</small></div>
      <pre className="scene-extraction-source">{sourceText || "没有可提交的原文。"}</pre>
      <p className="extraction-model-note">使用 Settings 中 Scene Extraction 任务分配的模型。Character Pool 会随请求一起提交，模型只能匹配已有 Character ID，不能创建新角色或修改 Canon。</p>
    </div> : <div className="extraction-review">
      <div className="extraction-review-head"><div><div className="eyebrow">SCENE DRAFT</div><h3>{draft.title || "未命名场景"}</h3><p>模型 {draft.model || "unknown"} · {draft.protocol || "unknown"} · 来源 {document.title} v{draft.source.document_revision}</p></div><span className="canon-seal">DRAFT · NOT CANON</span></div>
      <div className="extraction-source-strip"><span>{draft.source.scope === "selection" ? "选区来源" : "全文来源"}</span><p>{draft.source.text.slice(0, 420)}{draft.source.text.length > 420 ? "…" : ""}</p></div>
      <div className="settings-form-grid extraction-form">
        <label className="field-label wide">Scene 标题<input value={draft.title} maxLength={512} onChange={(event: any) => editScene(previous => ({ ...previous, title: event.target.value }))}/></label>
        <label className="field-label wide">摘要<textarea rows={3} value={draft.summary} onChange={(event: any) => editScene(previous => ({ ...previous, summary: event.target.value }))}/></label>
      </div>

      <section className="extraction-section"><div className="extraction-section-head"><div className="eyebrow">GIVEN CIRCUMSTANCES</div><h4>规定情境</h4><p>时间、地点与人物进入这一场之前已经发生的事。</p></div><div className="settings-form-grid"><label className="field-label">时间<input value={draft.given_circumstances.time} onChange={(event: any) => editGiven("time", event.target.value)}/></label><label className="field-label">地点<input value={draft.given_circumstances.place} onChange={(event: any) => editGiven("place", event.target.value)}/></label><label className="field-label">环境<input value={draft.given_circumstances.environment} onChange={(event: any) => editGiven("environment", event.target.value)}/></label><label className="field-label wide">背景<textarea rows={3} value={draft.given_circumstances.background} onChange={(event: any) => editGiven("background", event.target.value)}/></label><label className="field-label wide">此前事件<textarea rows={3} value={draft.given_circumstances.prior_events} onChange={(event: any) => editGiven("prior_events", event.target.value)}/></label></div></section>

      <section className="extraction-section"><div className="extraction-section-head"><div className="eyebrow">DRAMATIC SITUATION</div><h4>戏剧情境</h4><p>这一场真正需要被回答的问题，以及情境发生转向的时刻。</p></div><div className="settings-form-grid"><label className="field-label wide">核心问题<textarea rows={2} value={draft.dramatic_situation.central_question} onChange={(event: any) => editDramatic("central_question", event.target.value)}/></label><label className="field-label wide">主要冲突<textarea rows={3} value={draft.dramatic_situation.primary_conflict} onChange={(event: any) => editDramatic("primary_conflict", event.target.value)}/></label><label className="field-label wide">转折<textarea rows={3} value={draft.dramatic_situation.turn} onChange={(event: any) => editDramatic("turn", event.target.value)}/></label></div></section>

      <section className="extraction-section"><div className="extraction-section-head"><div className="eyebrow">CAST & OBJECTIVES</div><h4>角色与场景目标</h4><p>这些目标只属于当前 Scene，不会改写 Character Identity 或 Visual Canon。</p></div>
        {!draft.cast.length && <div className="extraction-empty">模型没有可靠匹配任何已有 Character。你可以从 Character Pool 手动加入。</div>}
        <div className="extraction-cast-list">{draft.cast.map((entry, index) => <article className="extraction-cast-card" key={entry.character_id}>
          <div className="extraction-cast-head"><span className="cast-monogram">{entry.character_name.slice(0, 1)}</span><div><strong>{entry.character_name}</strong><small>{characters.find(character => character.id === entry.character_id)?.role || "来自现有 Character Pool"}</small></div><button className="quiet-button danger-text" onClick={() => removeCast(index)}>移出 Cast</button></div>
          <div className="settings-form-grid"><label className="field-label wide">Objective<textarea rows={2} value={entry.objective} onChange={(event: any) => editCast(index, "objective", event.target.value)}/></label><label className="field-label">Action<input value={entry.action} onChange={(event: any) => editCast(index, "action", event.target.value)}/></label><label className="field-label">Conflict<input value={entry.conflict} onChange={(event: any) => editCast(index, "conflict", event.target.value)}/></label><label className="field-label">情绪状态<input value={entry.emotional_state} onChange={(event: any) => editCast(index, "emotional_state", event.target.value)}/></label><label className="field-label wide">表演指导<textarea rows={2} value={entry.performance_direction} onChange={(event: any) => editCast(index, "performance_direction", event.target.value)}/></label><label className="field-label wide">潜台词<textarea rows={2} value={entry.subtext} onChange={(event: any) => editCast(index, "subtext", event.target.value)}/></label></div>
        </article>)}</div>
        <div className="extraction-add-cast"><select value={manualCharacter} disabled={charactersLoading} onChange={(event: any) => setManualCharacter(event.target.value)}><option value="">从 Character Pool 加入角色…</option>{characters.filter(character => !castIds.has(character.id)).map(character => <option key={character.id} value={character.id}>{character.name}</option>)}</select><button className="tool-button" disabled={!manualCharacter} onClick={() => { const character = characters.find(item => item.id === manualCharacter); if (character) addCast(character); setManualCharacter(""); }}><Icon name="plus"/>加入 Cast</button></div>
      </section>

      {!!draft.unresolved_characters.length && <section className="extraction-section unresolved-section"><div className="extraction-section-head"><div className="eyebrow">NEEDS AUTHOR DECISION</div><h4>待确认人物</h4><p>这些人物未能可靠匹配到现有 Character。不会自动创建角色，也不会仅凭同名认定身份。</p></div><div className="unresolved-list">{draft.unresolved_characters.map((entry, index) => <div className="unresolved-row" key={`${entry.name}:${index}`}><div><strong>{entry.name}</strong><small>{entry.reason}</small></div><select defaultValue="" onChange={(event: any) => { if (event.target.value) resolveUnresolved(index, event.target.value); }}><option value="">匹配已有 Character…</option>{characters.filter(character => !castIds.has(character.id)).map(character => <option key={character.id} value={character.id}>{character.name}</option>)}</select><button className="quiet-button" onClick={() => ignoreUnresolved(index)}>忽略</button></div>)}</div></section>}

      <section className="extraction-section"><div className="extraction-section-head"><div className="eyebrow">DIALOGUE & DIRECTION</div><h4>对白与导演设计</h4><p>台词、潜台词、调度与镜头建议都可以在创建后继续修改。</p></div><div className="settings-form-grid"><label className="field-label wide">Dialogue<textarea rows={6} value={draft.dialogue} onChange={(event: any) => editScene(previous => ({ ...previous, dialogue: event.target.value }))}/></label><label className="field-label">Blocking<textarea rows={3} value={draft.direction.blocking} onChange={(event: any) => editDirection("blocking", event.target.value)}/></label><label className="field-label">空间位置<textarea rows={3} value={draft.direction.spatial} onChange={(event: any) => editDirection("spatial", event.target.value)}/></label><label className="field-label">表演指导<textarea rows={3} value={draft.direction.performance_direction} onChange={(event: any) => editDirection("performance_direction", event.target.value)}/></label><label className="field-label">镜头指导<textarea rows={3} value={draft.direction.camera} onChange={(event: any) => editDirection("camera", event.target.value)}/></label></div></section>

      <p className="extraction-confirm-note">确认后只会创建新的 Scene 与 Cast，并记录来源 Document、revision、快照和可用选区范围。不会修改原文、已有 Scene 或 Character Canon。</p>
    </div>}
  </Modal>;
}

function App() {
  const [screen, setScreen] = React.useState<"loading" | "shelf" | "opening" | "workplace" | "closing">("loading");
  const [section, setSection] = React.useState<Section>(() => {
    const stored = localStorage.getItem(RESUME_SECTION_KEY);
    return stored === "characters" || stored === "scenes" || stored === "assets" || stored === "settings" || stored === "writing" ? stored : "writing";
  });
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
  const [modal, setModal] = React.useState<"create-book" | "create-document" | "contents" | "inspire" | "continue" | "versions" | "assets" | "extract-scene" | "extraction-created" | "document-scenes" | null>(null);
  const [bookTitle, setBookTitle] = React.useState("");
  const [bookDescription, setBookDescription] = React.useState("");
  const [bookColor, setBookColor] = React.useState(COVER_PALETTE[0].color);
  const [docTitle, setDocTitle] = React.useState("");
  const [docKind, setDocKind] = React.useState<StudioDocument["kind"]>("chapter");
  const [versionList, setVersionList] = React.useState<VersionEntry[]>([]);
  const [inspiration, setInspiration] = React.useState("");
  const [inspireBusy, setInspireBusy] = React.useState(false);
  const [extractionInput, setExtractionInput] = React.useState<SceneExtractionInput | null>(null);
  const [createdExtraction, setCreatedExtraction] = React.useState<SceneExtractionResult | null>(null);
  const [sceneLaunch, setSceneLaunch] = React.useState<{ sceneId: string; storyboard: boolean; nonce: number } | null>(null);
  const [documentScenes, setDocumentScenes] = React.useState<StudioScene[]>([]);
  const [documentScenesLoading, setDocumentScenesLoading] = React.useState(false);
  const [continuation, setContinuation] = React.useState("");
  const [continueBusy, setContinueBusy] = React.useState(false);
  const [continueError, setContinueError] = React.useState("");
  const [editorFontSize, setEditorFontSize] = React.useState<number>(() => Number(localStorage.getItem("khala.studio.fontSize") || 17));
  const [defaultCover, setDefaultCover] = React.useState<string>(() => localStorage.getItem("khala.studio.coverColor") || COVER_PALETTE[0].color);
  const [toast, setToast] = React.useState("");
  const [savedRange, setSavedRange] = React.useState<Range | null>(null);
  const [turnDirection, setTurnDirection] = React.useState<"next" | "prev" | null>(null);
  const [openingTitle, setOpeningTitle] = React.useState("");
  const [openingColor, setOpeningColor] = React.useState(COVER_PALETTE[0].color);
  const [openingFoil, setOpeningFoil] = React.useState(COVER_PALETTE[0].foil);
  const [lastError, setLastError] = React.useState("");
  const [assetFocus, setAssetFocus] = React.useState<string | null>(null);
  const [demoBusy, setDemoBusy] = React.useState(false);

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
  const resumeAttemptedRef = React.useRef(false);

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
        const resumeId = localStorage.getItem(RESUME_WORKPLACE_KEY);
        const resumeBook = resumeId ? books.find(book => book.id === resumeId) : null;
        if (resumeBook && !resumeAttemptedRef.current) {
          resumeAttemptedRef.current = true;
          await openWorkplace(resumeBook, true);
        } else {
          setScreen("shelf");
        }
      } catch (cause: any) {
        if (!alive) return;
        setError(cause?.message || "无法连接 Studio API");
        setScreen("shelf");
      }
    })();
    return () => { alive = false; };
  }, []);

  React.useEffect(() => {
    if (screen !== "workplace" || !workplace) return;
    localStorage.setItem(RESUME_WORKPLACE_KEY, workplace.id);
    if (activeDocument) localStorage.setItem(RESUME_DOCUMENT_KEY, activeDocument.id);
    localStorage.setItem(RESUME_SECTION_KEY, section);
  }, [screen, workplace?.id, activeDocument?.id, section]);

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

  async function openSourceDocument(documentId: string) {
    if (!workplace) return;
    if (!(await flushSave())) {
      notify("当前文档尚未安全保存，无法切换来源文档。");
      return;
    }
    try {
      await loadDocument(documentId);
      setSection("writing");
      notify("已返回 Scene 的来源 Document；原文没有被提取流程修改");
    } catch (cause: any) {
      notify(cause?.message || "无法打开来源 Document");
    }
  }

  async function openWorkplace(item: Workplace, resume = false) {
    if (!(await flushSave())) return;
    const resumable = resume || localStorage.getItem(RESUME_WORKPLACE_KEY) === item.id;
    const storedDocumentId = resumable ? localStorage.getItem(RESUME_DOCUMENT_KEY) : null;
    const storedSection = resumable ? localStorage.getItem(RESUME_SECTION_KEY) : null;
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
      setAssetFocus(null);
      const list = await api<StudioDocument[]>(`/workplaces/${item.id}/documents`);
      setDocuments(list);
      let preferred = (storedDocumentId && list.find(doc => doc.id === storedDocumentId))
        || list.find(doc => doc.kind === "manuscript")
        || list.find(doc => doc.kind === "chapter")
        || list[0];
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
      const nextSection = storedSection === "characters" || storedSection === "scenes" || storedSection === "assets" || storedSection === "settings"
        ? storedSection as Section : "writing";
      setSection(nextSection);
      localStorage.setItem(RESUME_WORKPLACE_KEY, item.id);
      localStorage.setItem(RESUME_DOCUMENT_KEY, data.id);
      localStorage.setItem(RESUME_SECTION_KEY, nextSection);
      setMode("write");
      const delay = resume ? 120 : Math.max(0, 1650 - (Date.now() - started));
      window.setTimeout(() => setScreen("workplace"), delay);
    } catch (cause: any) {
      setError(cause?.message || "无法打开 Workplace");
      setScreen("shelf");
      notify(cause?.message || "无法打开 Workplace");
    }
  }

  async function closeWorkplace() {
    if (!(await flushSave())) return;
    localStorage.removeItem(RESUME_WORKPLACE_KEY);
    localStorage.removeItem(RESUME_DOCUMENT_KEY);
    localStorage.removeItem(RESUME_SECTION_KEY);
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

  async function loadDemo() {
    if (demoBusy) return;
    setDemoBusy(true); setError("");
    try {
      const result = await api<{ created: boolean; workplace: Workplace }>("/demo", { method: "POST" });
      await refreshWorkplaces();
      await openWorkplace(result.workplace);
      notify(result.created ? "示例故事已建立；图片明确标注为示意资料" : "已打开已有的示例故事");
    } catch (cause: any) {
      setError(cause?.message || "无法加载示例故事");
    } finally {
      setDemoBusy(false);
    }
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

  async function openSceneExtraction() {
    if (!workplace || !activeDocument || loading) return;
    if (conflict) {
      notify("请先重新载入服务器版本，再进行 Scene 提取。");
      return;
    }
    const captured = captureSelection();
    if (!(await flushSave())) {
      notify("文档尚未安全保存，暂时不能提取 Scene。");
      return;
    }
    const current = latestRef.current.document;
    if (!current) return;
    setExtractionInput({
      selectionText: captured.selected_text,
      contextBefore: captured.context_before,
      contextAfter: captured.context_after,
      documentContent: markdownFromPages(pageHtmlRef.current),
      revision: current.revision,
    });
    setModal("extract-scene");
  }

  function finishSceneExtraction(result: SceneExtractionResult, openBoard: boolean) {
    setCreatedExtraction(null);
    setModal(null);
    setSceneLaunch({ sceneId: result.scene.id, storyboard: openBoard, nonce: Date.now() });
    setSection("scenes");
    notify(openBoard ? "Scene 已创建；正在进入 Storyboard" : "Scene 已创建，来源记录已保存");
  }

  async function openDocumentScenes() {
    if (!workplace || !activeDocument) return;
    setModal("document-scenes"); setDocumentScenesLoading(true);
    try {
      setDocumentScenes(await api<StudioScene[]>(`/workplaces/${workplace.id}/documents/${activeDocument.id}/scenes`));
    } catch (cause: any) {
      notify(cause?.message || "无法读取这份 Document 提取出的 Scenes");
      setDocumentScenes([]);
    } finally {
      setDocumentScenesLoading(false);
    }
  }

  async function openExtractedScene(sceneId: string) {
    if (!(await flushSave())) {
      notify("当前文档尚未安全保存，无法打开提取出的 Scene。");
      return;
    }
    setModal(null);
    setSceneLaunch({ sceneId, storyboard: false, nonce: Date.now() });
    setSection("scenes");
  }

  async function requestInspiration() {
    if (!workplace || !activeDocument) return;
    const context = captureSelection();
    setInspiration(""); setInspireBusy(true); setModal("inspire");
    try {
      const result = await api<{ content: string; model: string }>(`/workplaces/${workplace.id}/documents/${activeDocument.id}/ai/inspire`, {
        method: "POST", body: { ...context, instruction: "Give me several distinct and specific creative directions. Do not rewrite the source text." },
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
        body: JSON.stringify({ ...context,
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
        <div className="shelf-intro-actions"><button className="outline-light-button" onClick={() => { setBookTitle(""); setBookDescription(""); setBookColor(defaultCover); setError(""); setModal("create-book"); }}>＋　创建 Workplace</button><button className="outline-light-button sample-load-button" disabled={demoBusy} onClick={() => void loadDemo()}>{demoBusy ? "正在装订示例…" : "打开示例故事"}</button><small>示例使用独立 [SAMPLE] Workplace；示意图片会明确标注，不冒充模型生成结果。</small></div>
      </div>
      {error && <div className="shelf-error">{error}</div>}
      <div className="shelf-grid">
        {workplaces.map((item, index) => {
          const theme = colorMeta(item.cover_color);
          return <button className={`book-card ${item.sample ? "sample-book" : ""}`} key={item.id} onClick={() => void openWorkplace(item)} style={{ "--cover": item.cover_color || theme.color, "--cover-edge": theme.edge, "--foil": theme.foil } as any}>
            <div className="book-object"><div className="book-pages-edge"/><div className="book-cover"><div className="book-spine"/><div className="cover-content">
              <div className="cover-sub">KHALA　·　STUDIO</div><div className="cover-rule"/><div className="cover-emblem">{index % 2 === 0 ? "✦" : "❧"}</div>{item.sample && <span className="sample-book-label">SAMPLE · 示例资料</span>}
              <h2 className="cover-title">{item.title}</h2><div className="cover-sub">{item.description || "A WORLD BETWEEN THE PAGES"}</div><div className="cover-rule"/>
              <div className="cover-bottom">{item.document_count} DOCUMENTS</div>
            </div></div></div>
            <div className="book-meta"><span>{item.title}</span><small>{item.document_count} 篇文档 · {item.sample ? "示例资料 · " : ""}{fmtDate(item.updated_at)}</small></div>
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
        <div className="book-actions"><button className="head-btn" onClick={() => setModal("contents")}>目录</button><button className="head-btn" onClick={() => void openVersions()}>版本</button><button className="head-btn" onClick={() => void openDocumentScenes()}>提取记录</button><button className="head-btn" onClick={() => setMode(current => current === "write" ? "read" : "write")}>{mode === "write" ? "阅读模式" : "写作模式"}</button><button className="head-btn close-book-button" onClick={() => void closeWorkplace()}>合上书本</button></div>
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
            {mode === "write" && <div className="writer-tools"><button className="tool-button" onMouseDown={(event: any) => event.preventDefault()} onClick={() => setModal("assets")}><Icon name="link"/>文档素材</button><button className="tool-button extract-scene-button" onMouseDown={(event: any) => event.preventDefault()} onClick={() => void openSceneExtraction()}><Icon name="scene"/>Extract Scene</button><button className="tool-button" onMouseDown={(event: any) => event.preventDefault()} onClick={() => void requestInspiration()}><Icon name="lightbulb"/>给我灵感</button><button className="tool-button primary" onMouseDown={(event: any) => event.preventDefault()} onClick={() => void startContinuation()}><Icon name="sparkle"/>AI 续写</button></div>}
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

  function renderWorkplace() {
    return <section className="workplace-screen" style={{ "--editor-font-size": `${editorFontSize}px` } as any}>
      <header className="workplace-header"><div className="header-brand"><div className="brand-mark small">K</div><span>KHALA STUDIO</span></div><div className="header-title">{workplace?.title || ""}</div><div className="header-right"><span className="server-state"><i/>LOCAL WORKSPACE</span><button className="close-workspace" onClick={() => void closeWorkplace()}>合上书本</button></div></header>
      {renderSectionNav()}
      {section === "writing" ? renderWritingSection() : section === "characters" ? <CharactersWorkspace workplace={workplace!} notify={notify} onStartWriting={() => setSection("writing")}/> : section === "scenes" ? <ScenesWorkspace workplace={workplace!} notify={notify} launch={sceneLaunch} onLaunchConsumed={() => setSceneLaunch(null)} onOpenSourceDocument={(documentId) => void openSourceDocument(documentId)} onOpenAsset={(assetId) => { setAssetFocus(assetId); setSection("assets"); }}/> : section === "assets" ? <AssetsWorkspace workplace={workplace!} notify={notify} focusAssetId={assetFocus}/> : section === "settings" ? <SettingsWorkspace workplace={workplace!} capabilities={capabilities} editorFontSize={editorFontSize} setEditorFontSize={setFontSize} defaultCover={defaultCover} setDefaultCover={setCoverDefault} notify={notify}/> : renderPlaceholderSection(section)}
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

  function renderWritingAssetsModal() {
    if (!workplace || !activeDocument) return null;
    return <Modal title="文档关联素材" eyebrow="WRITING REFERENCES" onClose={() => setModal(null)} className="writing-assets-modal" actions={<button className="quiet-button" onClick={() => setModal(null)}>关闭</button>}>
      <p className="modal-intro">这里管理当前文档引用的插图、参考资料与其他文件。资源仍保存在 Workplace 的统一资源库中。</p>
      <AssetLinkPanel workplaceId={workplace.id} resourceType="document" resourceId={activeDocument.id} notify={notify}/>
    </Modal>;
  }

  function renderDocumentScenesModal() {
    return <Modal title="这份手稿提取出的 Scenes" eyebrow="SOURCE TRACE" onClose={() => setModal(null)} className="document-scenes-modal" actions={<button className="quiet-button" onClick={() => setModal(null)}>关闭</button>}>
      <p className="modal-intro">这些 Scene 保存了从本文档提取时的 revision 与文本快照。原文之后继续修改，不会自动改动已有 Scene。</p>
      {documentScenesLoading ? <div className="thinking-state"><span className="thinking-mark">✦</span>正在查阅提取记录……</div> : documentScenes.length ? <div className="document-scene-list">{documentScenes.map(scene => <article key={scene.id}><div><span>SCENE</span><strong>{scene.title}</strong><small>{scene.cast_count} 位角色 · 来源 revision {scene.source_document_revision ?? "—"} · {scene.source_selection_start != null ? `范围 ${scene.source_selection_start}–${scene.source_selection_end}` : "全文或无法可靠定位的选区"}</small><p>{scene.summary || scene.dramatic_situation?.central_question || "尚未写摘要"}</p></div><button className="tool-button" onClick={() => void openExtractedScene(scene.id)}>打开 Scene</button></article>)}</div> : <div className="empty-versions">这份 Document 还没有提取过 Scene。选择正文或使用整个 Document，然后点击“Extract Scene”。</div>}
      {!documentScenesLoading && <button className="tool-button primary extracted-scene-cta" onClick={() => { setModal(null); void openSceneExtraction(); }}><Icon name="sparkle"/>从当前正文再提取一个 Scene</button>}
    </Modal>;
  }

  function renderSceneExtractionModal() {
    if (!workplace || !activeDocument || !extractionInput) return null;
    return <SceneExtractionModal workplace={workplace} document={activeDocument} input={extractionInput}
      onClose={() => { setModal(null); setExtractionInput(null); }}
      onCreated={result => { setCreatedExtraction(result); setExtractionInput(null); setModal("extraction-created"); }}/>;
  }

  function renderExtractionCreatedModal() {
    if (!createdExtraction) return null;
    const result = createdExtraction;
    return <Modal title="Scene 已建立" eyebrow="FROM PAGE TO STAGE" onClose={() => finishSceneExtraction(result, false)}
      actions={<><button className="quiet-button" onClick={() => finishSceneExtraction(result, false)}>打开 Scene</button><button className="confirm-button" onClick={() => finishSceneExtraction(result, true)}>创建 Storyboard</button></>}>
      <p className="modal-intro">“{result.scene.title}”已作为独立 Scene 保存。原文没有被修改，来源 Document、revision 与文本快照仍可追溯。</p>
      <div className="extraction-success-card"><div><span>SOURCE DOCUMENT</span><strong>{activeDocument?.title || result.scene.source_document_id}</strong><small>REVISION {result.scene.source_document_revision ?? "—"}</small></div><div><span>CAST</span><strong>{result.cast.length} 位角色</strong><small>全部来自当前 Workplace 的 Character Pool</small></div><div><span>NEXT</span><strong>Storyboard</strong><small>Scene 与 Cast 会作为分镜上下文</small></div></div>
      {result.scene.source_text_snapshot && <pre className="scene-extraction-source success-source">{result.scene.source_text_snapshot.slice(0, 1200)}{(result.scene.source_text_snapshot.length || 0) > 1200 ? "…" : ""}</pre>}
    </Modal>;
  }

  function renderModal() {
    if (modal === "create-book") return renderCreateBookModal();
    if (modal === "create-document") return renderCreateDocModal();
    if (modal === "contents") return renderContentsModal();
    if (modal === "inspire") return renderInspireModal();
    if (modal === "continue") return renderContinueModal();
    if (modal === "versions") return renderVersionsModal();
    if (modal === "assets") return renderWritingAssetsModal();
    if (modal === "document-scenes") return renderDocumentScenesModal();
    if (modal === "extract-scene") return renderSceneExtractionModal();
    if (modal === "extraction-created") return renderExtractionCreatedModal();
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
