# ComfyUI compatibility

Khala implements a subset of ComfyUI. Point a compatible frontend at the Khala
origin; `/` serves the pinned ComfyUI frontend when installed. Unsupported
nodes or workflows fail validation with a `node_errors` entry that names the
node; a prompt is never run with one of its nodes ignored. Full ComfyUI node
and extension behavior is not implemented.

## Nodes

Every node below is listed by `/object_info` with ComfyUI's inputs, outputs
and defaults, so the ComfyUI frontend and saved workflows load unchanged.

Nodes that run today (text-to-image, and loading and saving images):

| Group | Nodes |
| --- | --- |
| Loaders | `CheckpointLoaderSimple`, `UNETLoader`, `CLIPLoader`, `DualCLIPLoader`, `VAELoader` |
| Conditioning | `CLIPTextEncode` |
| Latent | `EmptyLatentImage`, `KSampler`, `VAEDecode` |
| Image | `LoadImage`, `EmptyImage`, `SaveImage`, `PreviewImage` |

Nodes that are registered but do not run yet. A prompt that uses one is
rejected, and the error names the node:

| Group | Nodes |
| --- | --- |
| LoRA | `LoraLoader`, `LoraLoaderModelOnly` |
| Image-to-image | `VAEEncode` |
| Masks and inpainting | `SetLatentNoiseMask`, `VAEEncodeForInpaint` |
| Upscaling | `LatentUpscale`, `ImageScale`, `UpscaleModelLoader`, `ImageUpscaleWithModel` |

## Model lists

A loader's file list is read from a folder under `models_root`:

| Node | Folder |
| --- | --- |
| `CheckpointLoaderSimple` | `checkpoints` |
| `UNETLoader` | `diffusion_models` |
| `CLIPLoader`, `DualCLIPLoader` | `text_encoders` |
| `VAELoader` | `vae` |
| `LoraLoader`, `LoraLoaderModelOnly` | `loras` |
| `UpscaleModelLoader` | `upscale_models` |

`LoadImage` lists the files in `input_dir`.
