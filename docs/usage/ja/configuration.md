# 設定

Khala は `conf/khala.conf` を読みます。主な設定はポート、モデル・入出力
ディレクトリ、engine、SQLite 永続化、ダウンロード、ミラーです。各キーの
既定値は英語版 `configuration.md` を参照してください。

Khala Studio は独立した `studio_db = var/studio.sqlite3` SQLite データベースを
使用します。`studio_model` で既定の執筆モデルを指定でき、空の場合はインストール
済み LLM または fake テストモデルを使用します。
