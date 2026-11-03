export interface WsState {
  progress: number;
  max: number;
  previewUrl: string | null;
  promptId: string | null;
  completed: boolean;
}

export const initialWsState: WsState = {
  progress: 0, max: 0, previewUrl: null, promptId: null, completed: false,
};

export function reduceWsMessage(state: WsState, type: string, data: Record<string, unknown>): WsState {
  const promptId = typeof data.prompt_id === "string" ? data.prompt_id : state.promptId;
  if (type === "execution_start") return { ...state, promptId, completed: false };
  if (type === "progress") {
    return { ...state, promptId, progress: Number(data.value ?? 0), max: Number(data.max ?? 0) };
  }
  if (type === "execution_success") {
    return { ...state, promptId, completed: true };
  }
  return state;
}

export function previewFromBinary(buffer: ArrayBuffer): string {
  return URL.createObjectURL(new Blob([buffer.slice(8)], { type: "image/png" }));
}
