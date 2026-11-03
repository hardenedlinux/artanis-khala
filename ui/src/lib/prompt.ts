import type { ComfyNode } from "./api";

export interface GenerateOptions {
  prompt: string;
  model: string;
  width: number;
  height: number;
  steps: number;
  seed: number;
}

export function buildPrompt(options: GenerateOptions): Record<string, ComfyNode> {
  return {
    "1": { class_type: "CheckpointLoaderSimple", inputs: { ckpt_name: options.model } },
    "2": { class_type: "CLIPTextEncode", inputs: { text: options.prompt, clip: ["1", 1] } },
    "3": { class_type: "CLIPTextEncode", inputs: { text: "", clip: ["1", 1] } },
    "4": {
      class_type: "EmptyLatentImage",
      inputs: { width: options.width, height: options.height, batch_size: 1 },
    },
    "5": {
      class_type: "KSampler",
      inputs: {
        model: ["1", 0], positive: ["2", 0], negative: ["3", 0],
        latent_image: ["4", 0], seed: options.seed, steps: options.steps,
        cfg: 7, sampler_name: "euler", scheduler: "normal", denoise: 1,
      },
    },
    "6": { class_type: "VAEDecode", inputs: { samples: ["5", 0], vae: ["1", 2] } },
    "7": {
      class_type: "SaveImage",
      inputs: { images: ["6", 0], filename_prefix: "khala-ui" },
    },
  };
}
