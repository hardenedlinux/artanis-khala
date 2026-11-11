# ComfyUI 兼容性

Khala 实现了 ComfyUI 的一个子集。把兼容的前端指向 Khala 的地址即可；安装了
固定版本的 ComfyUI 前端后，`/` 会直接提供它。未支持的节点或工作流会验证
失败，并在 `node_errors` 中指出具体节点；Khala 不会在忽略某个节点的情况下
执行工作流。完整的 ComfyUI 节点和扩展行为尚未实现。

## 节点

下列节点都会出现在 `/object_info` 中，输入、输出和默认值与 ComfyUI 一致，
因此 ComfyUI 前端和已保存的工作流可以原样加载。

目前可以执行的节点（文生图，以及图片的加载和保存）：

| 分组 | 节点 |
| --- | --- |
| 加载器 | `CheckpointLoaderSimple`、`UNETLoader`、`CLIPLoader`、`DualCLIPLoader`、`VAELoader` |
| 条件 | `CLIPTextEncode` |
| 潜空间 | `EmptyLatentImage`、`KSampler`、`VAEDecode` |
| 图片 | `LoadImage`、`EmptyImage`、`SaveImage`、`PreviewImage` |

已注册但暂时不能执行的节点。使用其中任何一个的工作流会被拒绝，错误信息会
指出该节点：

| 分组 | 节点 |
| --- | --- |
| LoRA | `LoraLoader`、`LoraLoaderModelOnly` |
| 图生图 | `VAEEncode` |
| 蒙版与局部重绘 | `SetLatentNoiseMask`、`VAEEncodeForInpaint` |
| 放大 | `LatentUpscale`、`ImageScale`、`UpscaleModelLoader`、`ImageUpscaleWithModel` |

## 模型列表

加载器的文件列表来自 `models_root` 下的目录：

| 节点 | 目录 |
| --- | --- |
| `CheckpointLoaderSimple` | `checkpoints` |
| `UNETLoader` | `diffusion_models` |
| `CLIPLoader`、`DualCLIPLoader` | `text_encoders` |
| `VAELoader` | `vae` |
| `LoraLoader`、`LoraLoaderModelOnly` | `loras` |
| `UpscaleModelLoader` | `upscale_models` |

`LoadImage` 列出 `input_dir` 中的文件。
