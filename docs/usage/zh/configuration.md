# 配置

Khala 读取 `conf/khala.conf`，格式为 `key = value`。主要配置包括端口、模型
与输入输出目录、engine、SQLite 持久化、下载线程/分块、镜像探测和自定义
镜像。每个键的默认值见英文 `configuration.md`。

Khala Studio 使用独立的 `studio_db = var/studio.sqlite3` SQLite 数据库；
`studio_model` 可指定默认写作模型，留空时使用已安装的 LLM 或 fake 测试模型。
