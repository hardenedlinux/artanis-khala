import { describe, expect, it } from "vitest";
import { initialWsState, reduceWsMessage } from "./ws";

describe("WS reducer", () => {
  it("applies the run 5 event sequence", () => {
    let state = reduceWsMessage(initialWsState, "execution_start", { prompt_id: "p1" });
    state = reduceWsMessage(state, "progress", { prompt_id: "p1", value: 5, max: 20 });
    state = reduceWsMessage(state, "executed", { prompt_id: "p1", node: "7" });
    state = reduceWsMessage(state, "execution_success", { prompt_id: "p1" });
    expect(state).toEqual({ progress: 5, max: 20, previewUrl: null, promptId: "p1", completed: true });
  });
});
