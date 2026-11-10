# Khala

Khala is a GNU Artanis application for running local AI models and exposing
focused ComfyUI and Ollama-compatible APIs. It provides a React web UI, model
catalog and download management, local image generation, and optional
SonicBoom execution.

Khala does not attempt to reproduce every ComfyUI node or every Ollama
endpoint. Compatibility is limited to the supported workflows and APIs
documented in this repository.

## Features

- ComfyUI-compatible text-to-image workflow validation and execution
- `/prompt`, `/queue`, `/history`, `/view`, upload, settings, userdata and
  `/ws` protocol routes
- A subset of Ollama and OpenAI chat/generation routes
- LLM and image-model catalogs with mirror selection, resume, cancellation,
  SHA-256 verification and directory-model downloads
- React 18 UI with Generate, History, Models, Chat and Settings pages
- Chinese, English and Japanese localization
- Deterministic fake engines for protocol development without a GPU
- Optional lazy-loaded SonicBoom image and LLM engines
- SQLite history and pending-queue persistence through Guile DBI

## Requirements

- GNU Guile 3.0
- GNU Artanis
- guile-json
- guile-curl with the Khala extensions (`khala` branch)
- Node.js and npm for the Khala UI
- Optional: a CUDA-capable SonicBoom build for real inference

Ensure Guile loads the patched guile-curl extension rather than an older system
package. In the development setup, `khala-private/tools/env.sh` configures:

```text
GUILE_EXTENSIONS_PATH
GUILE_LOAD_PATH
LD_LIBRARY_PATH
```

## Build and run

Build the Khala UI:

```sh
./tools/build-ui.sh
```

The optional ComfyUI-compatible frontend can be fetched with:

```sh
./tools/fetch-frontend.scm
```

Start the server:

```sh
art work
```

Open:

- Khala UI: `http://127.0.0.1:3000/khala/`
- ComfyUI-compatible node editor: `http://127.0.0.1:3000/`

To listen on a LAN interface:

```sh
art work -h 0.0.0.0 -p 3000
```

Khala does not currently provide authentication. Do not expose it directly to
an untrusted network.

## Configuration

Khala reads `conf/khala.conf`. Every supported option and its default is
documented in:

- [English](docs/usage/en/configuration.md)
- [中文](docs/usage/zh/configuration.md)
- [日本語](docs/usage/ja/configuration.md)

The default engine is `fake`. Image generation through SonicBoom requires
the SonicBoom runtime, CUDA, and an existing model directory.

## Models

- LLM catalog: `conf/llm-catalog.scm`
- Image catalog: `conf/image-catalog.scm`

File models are stored below `models/`. Directory models such as
`MOSS-Image-SFT` are represented as complete directories and are exposed in
the appropriate ComfyUI COMBO lists.

`models/` is ignored by Git. A local checkout may symlink it to a shared model
store, but generated model files must not be committed.

## Engines

### Fake

The default deterministic engine is used for development and tests. It does not
load models or require a GPU.

### SonicBoom

SonicBoom modules are resolved only when `engine = sonicboom`. The image adapter
uses an existing directory model and has been exercised with
`MOSS-Image-SFT`; the LLM adapter uses SonicBoom chat templates, sessions and
streaming inference.

Validate SonicBoom against the installed runtime and GPU before deployment.
Starting Khala must not automatically load SonicBoom or occupy the GPU.

## Documentation

- [Getting started](docs/usage/en/getting-started.md)
- [Models and licenses](docs/usage/en/models.md)
- [ComfyUI compatibility](docs/usage/en/comfyui-compat.md)
- [Ollama API subset](docs/usage/en/ollama.md)
- [Khala UI](docs/usage/ui.md)

Chinese and Japanese equivalents are under `docs/usage/zh/` and
`docs/usage/ja/`.

## Known limitations

- Only the documented text-to-image workflow shapes and node subset are
  supported.
- The ComfyUI cache implementation is limited compared with upstream ComfyUI.
- SonicBoom requires external runtime paths and an available GPU.
- Khala is not a complete replacement for ComfyUI or Ollama.

## Credit

Khala is developed and maintained by
Nala Ginrut <roy@hardenedlinux.org>.
