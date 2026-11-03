import { describe, expect, it } from "vitest";
import { buildPrompt } from "./prompt";

describe("buildPrompt", () => {
  it("builds the standard text-to-image graph", () => {
    const graph = buildPrompt({
      prompt: "lake", model: "model.safetensors", width: 64,
      height: 32, steps: 20, seed: 7,
    });
    expect(Object.keys(graph)).toEqual(["1", "2", "3", "4", "5", "6", "7"]);
    expect(graph["4"].inputs).toMatchObject({ width: 64, height: 32 });
    expect(graph["5"].inputs).toMatchObject({ seed: 7, steps: 20 });
    expect(graph["7"].inputs.images).toEqual(["6", 0]);
  });
});
