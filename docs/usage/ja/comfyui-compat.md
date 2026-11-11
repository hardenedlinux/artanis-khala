# ComfyUI 互換性

Khala は ComfyUI の一部を実装しています。互換フロントエンドの接続先を Khala
に向けてください。固定バージョンの ComfyUI フロントエンドをインストール済み
の場合は `/` がそれを配信します。未対応のノードやワークフローは検証で失敗
し、`node_errors` に該当ノードが示されます。ノードを無視したまま実行する
ことはありません。ComfyUI の全ノード・拡張機能を再実装したものではありません。

## ノード

以下のノードはすべて `/object_info` に含まれ、入力・出力・既定値は ComfyUI
と同じです。そのため ComfyUI フロントエンドと保存済みワークフローをそのまま
読み込めます。

現在実行できるノード（テキストからの画像生成、画像の読み込みと保存）:

| 分類 | ノード |
| --- | --- |
| ローダー | `CheckpointLoaderSimple`、`UNETLoader`、`CLIPLoader`、`DualCLIPLoader`、`VAELoader` |
| 条件付け | `CLIPTextEncode` |
| 潜在空間 | `EmptyLatentImage`、`KSampler`、`VAEDecode` |
| 画像 | `LoadImage`、`EmptyImage`、`SaveImage`、`PreviewImage` |

登録済みで、まだ実行できないノード。これらを使うワークフローは拒否され、
エラーに該当ノードが示されます:

| 分類 | ノード |
| --- | --- |
| LoRA | `LoraLoader`、`LoraLoaderModelOnly` |
| 画像から画像 | `VAEEncode` |
| マスクとインペイント | `SetLatentNoiseMask`、`VAEEncodeForInpaint` |
| アップスケール | `LatentUpscale`、`ImageScale`、`UpscaleModelLoader`、`ImageUpscaleWithModel` |

## モデル一覧

ローダーのファイル一覧は `models_root` 配下のフォルダーから読み込みます:

| ノード | フォルダー |
| --- | --- |
| `CheckpointLoaderSimple` | `checkpoints` |
| `UNETLoader` | `diffusion_models` |
| `CLIPLoader`、`DualCLIPLoader` | `text_encoders` |
| `VAELoader` | `vae` |
| `LoraLoader`、`LoraLoaderModelOnly` | `loras` |
| `UpscaleModelLoader` | `upscale_models` |

`LoadImage` は `input_dir` 内のファイルを一覧します。
