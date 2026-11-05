import { describe, expect, it } from "vitest";
import { newClientId } from "./client-id";

describe("newClientId", () => {
  it("creates unique WebSocket client identifiers", () => {
    const ids = Array.from({ length: 100 }, () => newClientId());
    expect(new Set(ids).size).toBe(ids.length);
    expect(ids.every((id) => /^khala-[a-z0-9-]+$/.test(id))).toBe(true);
  });
});
