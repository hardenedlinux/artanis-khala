# Configuration

Khala reads `conf/khala.conf`. Values use `key = value`; blank lines and `#` comments are ignored.

| Key | Default | Purpose |
|---|---:|---|
| `port` | `3000` | HTTP and WebSocket listen port. |
| `models_root` | `models` | Root containing ComfyUI model directories. |
| `input_dir` | `input` | Uploaded inputs and LoadImage files. |
| `output_dir` | `output` | Generated images. |
| `temp_dir` | `temp` | Temporary images and previews. |
| `engine` | `fake` | `fake` or `sonicboom` image engine. |
| `persist_history` | `no` | Persist history when `yes`. |
| `persist_queue` | `no` | Restore pending prompts when `yes`. |
| `history_db` | `var/history.sqlite3` | SQLite database path for persistence. |
| `extra_model_paths` | empty | Optional ComfyUI `extra_model_paths.yaml` path. |
| `mirror` | `auto` | Model source selection: `auto`, `huggingface`, `hf-mirror`, or `modelscope`. |
| `download_threads` | `4` | Concurrent model download chunks. |

The model folders below `models_root` are `checkpoints`, `diffusion_models`, `unet`, `text_encoders`, `clip`, `vae`, `loras`, `embeddings`, and `upscale_models`.

When either persistence option is enabled, Khala uses the installed Guile DBI
SQLite driver and the path in `history_db`. It does not require PostgreSQL.
