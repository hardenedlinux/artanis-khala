export interface CatalogItem {
  name: string;
  size: number;
  installed: boolean;
}

export interface DownloadStatus {
  id: string;
  state: "queued" | "probing" | "downloading" | "verifying" | "done" | "failed" | "cancelled";
  bytes_done: number;
  bytes_total: number;
  speed: number;
  source: string | null;
  error: string | null;
  verified: boolean;
}

export interface KhalaSettings {
  mirror: string;
  download_threads: number;
}

export interface SystemInfo {
  engine: string;
  version: string;
  config: {
    port: number;
    models_root: string;
    mirror: string;
    download_threads: number;
  };
}

export interface ComfyNodeInfo {
  input?: {
    required?: Record<string, unknown[]>;
  };
  output_node?: boolean;
}

export interface HistoryImage {
  filename: string;
  subfolder: string;
  type: string;
}

export interface HistoryEntry {
  prompt?: [number, string, Record<string, ComfyNode>, Record<string, unknown>, string[]];
  outputs?: Record<string, { images?: HistoryImage[] }>;
  status?: { completed?: boolean; status_str?: string };
}

export interface ComfyNode {
  class_type: string;
  inputs: Record<string, unknown>;
}

export interface ChatMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: {
      ...(init?.body ? { "Content-Type": "application/json" } : {}),
      ...init?.headers,
    },
  });
  if (!response.ok) {
    const detail = await response.text();
    throw new Error(detail || `HTTP ${response.status}`);
  }
  return (await response.json()) as T;
}

export const api = {
  catalog: () => request<CatalogItem[]>("/khala/api/catalog"),
  downloads: () => request<DownloadStatus[]>("/khala/api/downloads"),
  startDownload: (catalog: string) =>
    request<DownloadStatus>("/khala/api/downloads", {
      method: "POST",
      body: JSON.stringify({ catalog }),
    }),
  cancelDownload: (id: string) =>
    request<DownloadStatus>(`/khala/api/downloads/${encodeURIComponent(id)}/cancel`, {
      method: "POST",
    }),
  system: () => request<SystemInfo>("/khala/api/system"),
  settings: () => request<KhalaSettings>("/khala/api/settings"),
  saveSettings: (settings: KhalaSettings) =>
    request<KhalaSettings>("/khala/api/settings", {
      method: "PUT",
      body: JSON.stringify(settings),
    }),
  objectInfo: () => request<Record<string, ComfyNodeInfo>>("/object_info"),
  history: () => request<Record<string, HistoryEntry>>("/history"),
  queuePrompt: (prompt: Record<string, ComfyNode>, clientId: string) =>
    request<{ prompt_id: string; number: number }>("/prompt", {
      method: "POST",
      body: JSON.stringify({ prompt, client_id: clientId }),
    }),
  models: () =>
    request<{ models: Array<{ name: string; model: string }> }>("/api/tags"),
};

export function downloadEvents(
  id: string,
  onStatus: (status: DownloadStatus) => void,
  onError?: () => void,
): () => void {
  const source = new EventSource(
    `/khala/api/downloads/${encodeURIComponent(id)}/events`,
  );
  source.onmessage = (event) => {
    const status = JSON.parse(event.data) as DownloadStatus;
    onStatus(status);
    if (["done", "failed", "cancelled"].includes(status.state)) source.close();
  };
  if (onError) source.onerror = onError;
  return () => source.close();
}

export function viewUrl(image: HistoryImage): string {
  const query = new URLSearchParams({
    filename: image.filename,
    subfolder: image.subfolder,
    type: image.type,
  });
  return `/view?${query.toString()}`;
}

export async function streamChat(
  model: string,
  messages: ChatMessage[],
  onToken: (token: string) => void,
): Promise<void> {
  const response = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ model, messages, stream: true }),
  });
  if (!response.ok || !response.body) throw new Error(await response.text());
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      const event = JSON.parse(line) as { message?: { content?: string } };
      if (event.message?.content) onToken(event.message.content);
    }
  }
}
