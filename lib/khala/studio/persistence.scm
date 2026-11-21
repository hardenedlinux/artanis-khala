(define-module (khala studio persistence)
  #:use-module (dbi dbi)
  #:use-module (ice-9 format)
  #:use-module (ice-9 threads)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala config)
  #:export (studio-schema-version
            studio-new-id
            studio-list-workplaces
            studio-create-workplace!
            studio-get-workplace
            studio-touch-workplace!
            studio-update-workplace!
            studio-list-characters
            studio-create-character!
            studio-get-character
            studio-update-character!
            studio-archive-character!
            studio-set-character-avatar!
            studio-list-character-drafts
            studio-get-character-draft
            studio-save-character-draft!
            studio-delete-character-draft!
            studio-apply-character-draft!
            studio-list-character-outfits
            studio-get-character-outfit
            studio-create-character-outfit!
            studio-update-character-outfit!
            studio-archive-character-outfit!
            studio-set-default-character-outfit!
            studio-set-character-outfit-reference!
            studio-list-scenes
            studio-create-scene!
            studio-get-scene
            studio-update-scene!
            studio-delete-scene!
            studio-list-scene-cast
            studio-replace-scene-cast!
            studio-list-assets
            studio-create-asset!
            studio-get-asset
            studio-update-asset!
            studio-archive-asset!
            studio-list-asset-links
            studio-add-asset-link!
            studio-remove-asset-link!
            studio-list-linked-assets
            studio-list-documents
            studio-create-document!
            studio-get-document
            studio-update-document!
            studio-create-version!
            studio-list-versions
            studio-get-version
            studio-restore-version!))

;; Studio storage is deliberately independent from ComfyUI history and queue
;; persistence. Every operation opens a short-lived DBI connection, as the
;; existing persistence layer does, and all writes run in an explicit SQLite
;; transaction.
(define schema-lock (make-mutex))

(define migration-1
  (list
   "CREATE TABLE IF NOT EXISTS studio_workplaces (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL CHECK(length(trim(title)) > 0),
      description TEXT NOT NULL DEFAULT '',
      cover_color TEXT NOT NULL DEFAULT '#713D3B',
      cover_asset_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_opened_at TEXT,
      archived_at TEXT
    )"
   "CREATE TABLE IF NOT EXISTS studio_documents (
      id TEXT PRIMARY KEY,
      workplace_id TEXT NOT NULL REFERENCES studio_workplaces(id) ON DELETE CASCADE,
      parent_id TEXT REFERENCES studio_documents(id) ON DELETE SET NULL,
      kind TEXT NOT NULL CHECK(kind IN ('manuscript', 'chapter', 'outline', 'note')),
      title TEXT NOT NULL CHECK(length(trim(title)) > 0),
      content TEXT NOT NULL DEFAULT '',
      content_format TEXT NOT NULL DEFAULT 'markdown' CHECK(content_format = 'markdown'),
      revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )"
   "CREATE INDEX IF NOT EXISTS studio_documents_workplace_order
      ON studio_documents(workplace_id, parent_id, sort_order, created_at)"
   "CREATE TABLE IF NOT EXISTS studio_document_versions (
      id TEXT PRIMARY KEY,
      document_id TEXT NOT NULL REFERENCES studio_documents(id) ON DELETE CASCADE,
      revision INTEGER NOT NULL CHECK(revision >= 1),
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      label TEXT,
      source TEXT NOT NULL CHECK(source IN ('manual', 'ai', 'restore', 'checkpoint')),
      created_at TEXT NOT NULL
    )"
   "CREATE INDEX IF NOT EXISTS studio_versions_document_created
      ON studio_document_versions(document_id, created_at DESC, revision DESC)"))

(define migration-2
  (list
   "CREATE TABLE IF NOT EXISTS studio_characters (
      id TEXT PRIMARY KEY,
      workplace_id TEXT NOT NULL REFERENCES studio_workplaces(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      role TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '',
      literary_identity TEXT NOT NULL DEFAULT '{}',
      visual_identity TEXT NOT NULL DEFAULT '{}',
      vocal_identity TEXT NOT NULL DEFAULT '{}',
      performance_identity TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      archived_at TEXT
    )"
   "CREATE INDEX IF NOT EXISTS studio_characters_workplace_activity
      ON studio_characters(workplace_id, archived_at, updated_at DESC)"))

(define migration-3
  (list
   "CREATE TABLE IF NOT EXISTS studio_scenes (
      id TEXT PRIMARY KEY,
      workplace_id TEXT NOT NULL REFERENCES studio_workplaces(id) ON DELETE CASCADE,
      title TEXT NOT NULL CHECK(length(trim(title)) > 0),
      summary TEXT NOT NULL DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft', 'ready', 'final')),
      time TEXT NOT NULL DEFAULT '',
      place TEXT NOT NULL DEFAULT '',
      environment TEXT NOT NULL DEFAULT '',
      background TEXT NOT NULL DEFAULT '',
      prior_events TEXT NOT NULL DEFAULT '',
      central_question TEXT NOT NULL DEFAULT '',
      primary_conflict TEXT NOT NULL DEFAULT '',
      turn TEXT NOT NULL DEFAULT '',
      dialogue TEXT NOT NULL DEFAULT '',
      blocking TEXT NOT NULL DEFAULT '',
      spatial TEXT NOT NULL DEFAULT '',
      performance_direction TEXT NOT NULL DEFAULT '',
      camera TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )"
   "CREATE INDEX IF NOT EXISTS studio_scenes_workplace_order
      ON studio_scenes(workplace_id, deleted_at, sort_order, created_at)"
   "CREATE TABLE IF NOT EXISTS studio_scene_cast (
      id TEXT PRIMARY KEY,
      scene_id TEXT NOT NULL REFERENCES studio_scenes(id) ON DELETE CASCADE,
      character_id TEXT NOT NULL REFERENCES studio_characters(id) ON DELETE RESTRICT,
      objective TEXT NOT NULL DEFAULT '',
      action TEXT NOT NULL DEFAULT '',
      conflict TEXT NOT NULL DEFAULT '',
      emotional_state TEXT NOT NULL DEFAULT '',
      performance_direction TEXT NOT NULL DEFAULT '',
      subtext TEXT NOT NULL DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(scene_id, character_id)
    )"
   "CREATE INDEX IF NOT EXISTS studio_scene_cast_order
      ON studio_scene_cast(scene_id, sort_order, created_at)"))

(define migration-4
  (list
   "CREATE TABLE IF NOT EXISTS studio_assets (
      id TEXT PRIMARY KEY,
      workplace_id TEXT NOT NULL REFERENCES studio_workplaces(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      description TEXT NOT NULL DEFAULT '',
      asset_type TEXT NOT NULL CHECK(asset_type IN ('image', 'audio', 'video', 'document', 'other')),
      storage_key TEXT NOT NULL DEFAULT '',
      original_filename TEXT NOT NULL DEFAULT '',
      mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
      file_size INTEGER NOT NULL DEFAULT 0 CHECK(file_size >= 0),
      checksum TEXT NOT NULL DEFAULT '',
      source TEXT NOT NULL DEFAULT 'imported' CHECK(source IN ('upload', 'generated', 'imported')),
      width INTEGER CHECK(width IS NULL OR width > 0),
      height INTEGER CHECK(height IS NULL OR height > 0),
      duration_ms INTEGER CHECK(duration_ms IS NULL OR duration_ms >= 0),
      author TEXT NOT NULL DEFAULT '',
      notes TEXT NOT NULL DEFAULT '',
      generation_metadata TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      archived_at TEXT
    )"
   "CREATE INDEX IF NOT EXISTS studio_assets_workplace_activity
      ON studio_assets(workplace_id, archived_at, updated_at DESC)"
   "CREATE INDEX IF NOT EXISTS studio_assets_checksum
      ON studio_assets(workplace_id, checksum)"
   "CREATE UNIQUE INDEX IF NOT EXISTS studio_assets_storage_key
      ON studio_assets(storage_key) WHERE storage_key <> ''"
   "CREATE TABLE IF NOT EXISTS studio_asset_tags (
      asset_id TEXT NOT NULL REFERENCES studio_assets(id) ON DELETE CASCADE,
      tag TEXT NOT NULL CHECK(length(trim(tag)) > 0),
      PRIMARY KEY(asset_id, tag)
    )"
   "CREATE TABLE IF NOT EXISTS studio_asset_links (
      asset_id TEXT NOT NULL REFERENCES studio_assets(id) ON DELETE CASCADE,
      resource_type TEXT NOT NULL CHECK(resource_type IN ('character', 'scene', 'document')),
      resource_id TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(asset_id, resource_type, resource_id)
    )"
   "CREATE INDEX IF NOT EXISTS studio_asset_links_resource
      ON studio_asset_links(resource_type, resource_id, asset_id)"))

;; Storyboards are small, scene-owned editorial documents. Keeping the shot
;; list on the Scene preserves its authorization and lifecycle without adding
;; another generic workflow table.
(define migration-5
  (list
   "ALTER TABLE studio_scenes
      ADD COLUMN storyboard TEXT NOT NULL DEFAULT '[]'"))

;; Character Studio keeps AI proposals physically separate from the approved
;; character identity. Outfits are character-owned records; artwork binaries
;; continue to live in studio_assets and are linked through studio_asset_links.
(define migration-6
  (list
   "ALTER TABLE studio_characters
      ADD COLUMN concept TEXT NOT NULL DEFAULT ''"
   "ALTER TABLE studio_characters
      ADD COLUMN avatar_asset_id TEXT"
   "CREATE TABLE IF NOT EXISTS studio_character_identity_drafts (
      character_id TEXT NOT NULL REFERENCES studio_characters(id) ON DELETE CASCADE,
      section TEXT NOT NULL CHECK(section IN
        ('literary_identity', 'visual_identity',
         'vocal_identity', 'performance_identity')),
      content TEXT NOT NULL DEFAULT '{}',
      source TEXT NOT NULL DEFAULT 'ai' CHECK(source IN ('ai', 'author')),
      model TEXT NOT NULL DEFAULT '',
      author_edited INTEGER NOT NULL DEFAULT 0 CHECK(author_edited IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(character_id, section)
    )"
   "CREATE TABLE IF NOT EXISTS studio_character_outfits (
      id TEXT PRIMARY KEY,
      character_id TEXT NOT NULL REFERENCES studio_characters(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK(length(trim(name)) > 0),
      kind TEXT NOT NULL DEFAULT 'custom' CHECK(kind IN
        ('standard', 'casual', 'battle', 'formal', 'custom')),
      description TEXT NOT NULL DEFAULT '',
      components TEXT NOT NULL DEFAULT '[]',
      materials TEXT NOT NULL DEFAULT '[]',
      colors TEXT NOT NULL DEFAULT '[]',
      accessories TEXT NOT NULL DEFAULT '[]',
      special_features TEXT NOT NULL DEFAULT '[]',
      image_prompt TEXT NOT NULL DEFAULT '',
      reference_asset_id TEXT,
      is_default INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN (0, 1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      archived_at TEXT
    )"
   "CREATE INDEX IF NOT EXISTS studio_character_outfits_character
      ON studio_character_outfits(character_id, archived_at, is_default DESC,
                                  updated_at DESC)"
   "CREATE UNIQUE INDEX IF NOT EXISTS studio_character_outfits_default
      ON studio_character_outfits(character_id) WHERE is_default = 1
        AND archived_at IS NULL"))

(define (migrations)
  (list (cons 1 migration-1) (cons 2 migration-2)
        (cons 3 migration-3) (cons 4 migration-4)
        (cons 5 migration-5) (cons 6 migration-6)))

(define (studio-now)
  (strftime "%Y-%m-%dT%H:%M:%SZ" (gmtime (current-time))))

;; Guile DBI has no UUID primitive. Sixteen bytes from /dev/urandom are
;; formatted as RFC 4122 version 4. The random fallback is only for systems
;; without /dev/urandom.
(define (random-bytevector size)
  (let ((bytes (make-bytevector size 0)))
    (catch #t
      (lambda ()
        (call-with-input-file "/dev/urandom"
          (lambda (port) (get-bytevector-n! port bytes 0 size)))
        bytes)
      (lambda _
        (let loop ((index 0))
          (unless (= index size)
            (bytevector-u8-set! bytes index (random 256))
            (loop (+ index 1))))
        bytes))))

(define (studio-new-id)
  (let ((bytes (random-bytevector 16)))
    (bytevector-u8-set! bytes 6
                        (logior #x40 (logand #x0f (bytevector-u8-ref bytes 6))))
    (bytevector-u8-set! bytes 8
                        (logior #x80 (logand #x3f (bytevector-u8-ref bytes 8))))
    (let ((hex (lambda (index)
                 (format #f "~2,'0x" (bytevector-u8-ref bytes index)))))
      (format #f "~a~a~a~a-~a~a-~a~a-~a~a-~a~a~a~a~a~a"
              (hex 0) (hex 1) (hex 2) (hex 3)
              (hex 4) (hex 5)
              (hex 6) (hex 7)
              (hex 8) (hex 9)
              (hex 10) (hex 11) (hex 12) (hex 13) (hex 14) (hex 15)))))

(define (studio-db-path config)
  (let ((path (config-ref config 'studio_db)))
    (if (and (string? path) (not (string-null? path)))
        path
        "var/studio.sqlite3")))

(define (ensure-directory path)
  (unless (or (string-null? path) (file-exists? path))
    (let ((parent (dirname path)))
      (unless (or (equal? parent path) (string-null? parent))
        (ensure-directory parent))
      (catch 'system-error
        (lambda () (mkdir path #o755))
        (lambda (key . args)
          (unless (file-exists? path)
            (apply throw key args)))))))

(define (query db sql . args)
  (if (null? args)
      (dbi-query db sql)
      (dbi-params-query db sql args)))

(define (all-rows db)
  (let loop ((rows '()) (row (dbi-get_row db)))
    (if row (loop (cons row rows) (dbi-get_row db)) (reverse rows))))

(define (row-value row key)
  (let* ((entry (or (assoc key row) (assoc (string->symbol key) row)))
         (value (and entry (cdr entry))))
    (if (unspecified? value) #f value)))

(define (db-int value)
  (cond ((number? value) value)
        ((string? value) (or (string->number value) 0))
        (else 0)))

(define (sql-value value)
  (if value value '()))

(define (schema-version db)
  (query db "CREATE TABLE IF NOT EXISTS studio_schema_migrations (
               version INTEGER PRIMARY KEY,
               applied_at TEXT NOT NULL)")
  (query db "SELECT COALESCE(MAX(version), 0) AS version FROM studio_schema_migrations")
  (db-int (row-value (dbi-get_row db) "version")))

(define (apply-migration! db version statements)
  (query db "BEGIN IMMEDIATE")
  (catch #t
    (lambda ()
      (for-each (lambda (statement) (query db statement)) statements)
      (query db "INSERT INTO studio_schema_migrations(version, applied_at) VALUES(?, ?)"
             version (studio-now))
      (query db "COMMIT"))
    (lambda (key . args)
      (catch #t (lambda () (query db "ROLLBACK")) (lambda _ #f))
      (apply throw key args))))

(define (ensure-schema! db)
  (with-mutex schema-lock
    (let ((current (schema-version db)))
      (for-each
       (lambda (migration)
         (when (> (car migration) current)
           (apply-migration! db (car migration) (cdr migration))
           (set! current (car migration))))
       (migrations)))))

(define (with-db config proc)
  (let ((path (studio-db-path config)))
    (ensure-directory (dirname path))
    (let ((db (dbi-open "sqlite3" path)))
      (dynamic-wind
        (lambda ()
          (query db "PRAGMA foreign_keys = ON")
          (query db "PRAGMA busy_timeout = 5000")
          (ensure-schema! db))
        (lambda () (proc db))
        (lambda () (dbi-close db))))))

(define (with-transaction db proc)
  (query db "BEGIN IMMEDIATE")
  (catch #t
    (lambda ()
      (let ((result (proc)))
        (query db "COMMIT")
        result))
    (lambda (key . args)
      (catch #t (lambda () (query db "ROLLBACK")) (lambda _ #f))
      (apply throw key args))))

(define (studio-schema-version config)
  (with-db config (lambda (db) (schema-version db))))

(define workplace-columns
  "id, title, description, cover_color, cover_asset_id,
   created_at, updated_at, last_opened_at, archived_at")

(define (workplace-from-row row)
  `((id . ,(row-value row "id"))
    (title . ,(row-value row "title"))
    (description . ,(row-value row "description"))
    (cover_color . ,(row-value row "cover_color"))
    (cover_asset_id . ,(row-value row "cover_asset_id"))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (last_opened_at . ,(row-value row "last_opened_at"))
    (archived_at . ,(row-value row "archived_at"))
    (document_count . ,(db-int (row-value row "document_count")))))

(define (workplace-by-id db id)
  (query db
         (string-append
          "SELECT w.id, w.title, w.description, w.cover_color, w.cover_asset_id,
                  w.created_at, w.updated_at, w.last_opened_at, w.archived_at,
                  (SELECT COUNT(*) FROM studio_documents d
                   WHERE d.workplace_id = w.id AND d.deleted_at IS NULL) AS document_count
           FROM studio_workplaces w
           WHERE w.id = ? AND w.archived_at IS NULL")
         id)
  (let ((row (dbi-get_row db))) (and row (workplace-from-row row))))

(define (studio-list-workplaces config)
  (with-db config
    (lambda (db)
      (query db
             "SELECT w.id, w.title, w.description, w.cover_color, w.cover_asset_id,
                     w.created_at, w.updated_at, w.last_opened_at, w.archived_at,
                     (SELECT COUNT(*) FROM studio_documents d
                      WHERE d.workplace_id = w.id AND d.deleted_at IS NULL) AS document_count
              FROM studio_workplaces w
              WHERE w.archived_at IS NULL
              ORDER BY COALESCE(w.last_opened_at, w.updated_at) DESC,
                       w.updated_at DESC, w.created_at DESC")
      (map workplace-from-row (all-rows db)))))

(define (studio-create-workplace! config id title description cover-color cover-asset-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now)))
            (query db
                   "INSERT INTO studio_workplaces
                      (id, title, description, cover_color, cover_asset_id,
                       created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?)"
                   id title description cover-color (sql-value cover-asset-id) now now)
            (workplace-by-id db id)))))))

(define (studio-get-workplace config id)
  (with-db config (lambda (db) (workplace-by-id db id))))

(define (studio-touch-workplace! config id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (query db "UPDATE studio_workplaces SET last_opened_at = ?
                     WHERE id = ? AND archived_at IS NULL"
                 (studio-now) id)
          (and (> (dbi-affected-rows db) 0) (workplace-by-id db id)))))))

(define (update-clause updates allowed)
  (let loop ((rest updates) (sets '()) (values '()))
    (if (null? rest)
        (cons (reverse sets) (reverse values))
        (let ((entry (car rest)))
          (if (memq (car entry) allowed)
              (loop (cdr rest)
                    (cons (format #f "~a = ?" (car entry)) sets)
                    (cons (sql-value (cdr entry)) values))
              (loop (cdr rest) sets values))))))

(define (studio-update-workplace! config id updates)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let* ((now (studio-now))
                 (clause (update-clause updates
                                        '(title description cover_color cover_asset_id)))
                 (sets (car clause))
                 (values (cdr clause)))
            (unless (null? sets)
              (dbi-params-query db
                (string-append
                 "UPDATE studio_workplaces SET "
                 (string-join sets ", ")
                 ", updated_at = ? WHERE id = ? AND archived_at IS NULL")
                (append values (list now id))))
            (workplace-by-id db id)))))))

(define character-columns
  "id, workplace_id, name, role, summary, concept,
   literary_identity, visual_identity, vocal_identity, performance_identity,
   avatar_asset_id, created_at, updated_at, archived_at")

(define (character-from-row row)
  `((id . ,(row-value row "id"))
    (workplace_id . ,(row-value row "workplace_id"))
    (name . ,(row-value row "name"))
    (role . ,(row-value row "role"))
    (summary . ,(row-value row "summary"))
    (concept . ,(or (row-value row "concept") ""))
    (literary_identity . ,(or (row-value row "literary_identity") "{}"))
    (visual_identity . ,(or (row-value row "visual_identity") "{}"))
    (vocal_identity . ,(or (row-value row "vocal_identity") "{}"))
    (performance_identity . ,(or (row-value row "performance_identity") "{}"))
    (avatar_asset_id . ,(row-value row "avatar_asset_id"))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (archived_at . ,(row-value row "archived_at"))))

(define (character-by-id db workplace-id character-id)
  (query db
         (string-append "SELECT " character-columns " FROM studio_characters
                         WHERE id = ? AND workplace_id = ? AND archived_at IS NULL")
         character-id workplace-id)
  (let ((row (dbi-get_row db))) (and row (character-from-row row))))

(define (studio-list-characters config workplace-id)
  (with-db config
    (lambda (db)
      (query db
             (string-append
              "SELECT " character-columns " FROM studio_characters
               WHERE workplace_id = ? AND archived_at IS NULL
               ORDER BY updated_at DESC, created_at DESC, name ASC")
             workplace-id)
      (map character-from-row (all-rows db)))))

(define* (studio-create-character! config id workplace-id name role summary
                                   literary visual vocal performance
                                   #:key (concept ""))
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now)))
            (query db
                   "INSERT INTO studio_characters
                      (id, workplace_id, name, role, summary, concept,
                       literary_identity, visual_identity,
                       vocal_identity, performance_identity,
                       created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                   id workplace-id name role summary concept
                   literary visual vocal performance now now)
            (character-by-id db workplace-id id)))))))

(define (studio-get-character config workplace-id character-id)
  (with-db config (lambda (db) (character-by-id db workplace-id character-id))))

(define (studio-update-character! config workplace-id character-id updates)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let* ((now (studio-now))
                 (clause (update-clause updates
                                        '(name role summary concept
                                          literary_identity visual_identity
                                          vocal_identity performance_identity
                                          avatar_asset_id)))
                 (sets (car clause))
                 (values (cdr clause)))
            (if (null? sets)
                (character-by-id db workplace-id character-id)
                (begin
                  (dbi-params-query db
                    (string-append
                     "UPDATE studio_characters SET "
                     (string-join sets ", ")
                     ", updated_at = ? WHERE id = ? AND workplace_id = ?
                       AND archived_at IS NULL")
                    (append values (list now character-id workplace-id)))
                  (and (> (dbi-affected-rows db) 0)
                       (character-by-id db workplace-id character-id))))))))))

(define (studio-archive-character! config workplace-id character-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now)))
            (query db
                   "UPDATE studio_characters
                       SET archived_at = ?, updated_at = ?
                     WHERE id = ? AND workplace_id = ? AND archived_at IS NULL"
                   now now character-id workplace-id)
            (and (> (dbi-affected-rows db) 0)
                 (begin
                   (query db "DELETE FROM studio_asset_links
                               WHERE resource_type = 'character' AND resource_id = ?"
                          character-id)
                   now))))))))

(define (set-character-avatar! db workplace-id character-id asset-id)
  (let ((now (studio-now)))
    (query db "UPDATE studio_characters
                  SET avatar_asset_id = ?, updated_at = ?
                WHERE id = ? AND workplace_id = ? AND archived_at IS NULL"
           (sql-value asset-id) now character-id workplace-id)
    (and (> (dbi-affected-rows db) 0)
         (character-by-id db workplace-id character-id))))

(define (studio-set-character-avatar! config workplace-id character-id asset-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (set-character-avatar! db workplace-id character-id asset-id))))))

(define (character-draft-from-row row)
  `((character_id . ,(row-value row "character_id"))
    (section . ,(row-value row "section"))
    (content . ,(or (row-value row "content") "{}"))
    (source . ,(or (row-value row "source") "ai"))
    (model . ,(or (row-value row "model") ""))
    (author_edited . ,(= 1 (db-int (row-value row "author_edited"))))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))))

(define (studio-list-character-drafts config workplace-id character-id)
  (with-db config
    (lambda (db)
      (and (character-by-id db workplace-id character-id)
           (begin
             (query db
                    "SELECT character_id, section, content, source, model,
                            author_edited, created_at, updated_at
                       FROM studio_character_identity_drafts
                      WHERE character_id = ?
                      ORDER BY CASE section
                        WHEN 'literary_identity' THEN 1
                        WHEN 'visual_identity' THEN 2
                        WHEN 'vocal_identity' THEN 3
                        ELSE 4 END"
                    character-id)
             (map character-draft-from-row (all-rows db)))))))

(define (studio-get-character-draft config workplace-id character-id section)
  (with-db config
    (lambda (db)
      (and (character-by-id db workplace-id character-id)
           (begin
             (query db
                    "SELECT character_id, section, content, source, model,
                            author_edited, created_at, updated_at
                       FROM studio_character_identity_drafts
                      WHERE character_id = ? AND section = ?"
                    character-id section)
             (let ((row (dbi-get_row db)))
               (and row (character-draft-from-row row))))))))

(define (studio-save-character-draft! config workplace-id character-id section
                                      content source model author-edited)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (character-by-id db workplace-id character-id)
            (throw 'studio-draft-error 'character-not-found))
          (let ((now (studio-now)))
            (query db
                   "INSERT INTO studio_character_identity_drafts
                      (character_id, section, content, source, model,
                       author_edited, created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(character_id, section) DO UPDATE SET
                      content = excluded.content,
                      source = excluded.source,
                      model = excluded.model,
                      author_edited = excluded.author_edited,
                      updated_at = excluded.updated_at"
                   character-id section content source model
                   (if author-edited 1 0) now now)
            (query db
                   "SELECT character_id, section, content, source, model,
                           author_edited, created_at, updated_at
                      FROM studio_character_identity_drafts
                     WHERE character_id = ? AND section = ?"
                   character-id section)
            (character-draft-from-row (dbi-get_row db))))))))

(define (studio-delete-character-draft! config workplace-id character-id section)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (character-by-id db workplace-id character-id)
            (throw 'studio-draft-error 'character-not-found))
          (query db "DELETE FROM studio_character_identity_drafts
                      WHERE character_id = ? AND section = ?"
                 character-id section)
          (> (dbi-affected-rows db) 0))))))

(define (studio-apply-character-draft! config workplace-id character-id
                                       section identity-json)
  (let ((column (case (string->symbol section)
                  ((literary_identity visual_identity vocal_identity
                    performance_identity) (string->symbol section))
                  (else #f))))
    (unless column (throw 'studio-draft-error 'invalid-section))
    (with-db config
      (lambda (db)
        (with-transaction db
          (lambda ()
            (unless (character-by-id db workplace-id character-id)
              (throw 'studio-draft-error 'character-not-found))
            (let ((now (studio-now)))
              (dbi-params-query db
                (format #f "UPDATE studio_characters SET ~a = ?, updated_at = ?
                             WHERE id = ? AND workplace_id = ? AND archived_at IS NULL"
                        column)
                (list identity-json now character-id workplace-id))
              (query db "DELETE FROM studio_character_identity_drafts
                          WHERE character_id = ? AND section = ?"
                     character-id section)
              (character-by-id db workplace-id character-id))))))))

(define outfit-columns
  "o.id, o.character_id, o.name, o.kind, o.description, o.components,
   o.materials, o.colors, o.accessories, o.special_features, o.image_prompt,
   o.reference_asset_id, o.is_default, o.created_at, o.updated_at,
   o.archived_at")

(define (outfit-from-row row)
  `((id . ,(row-value row "id"))
    (character_id . ,(row-value row "character_id"))
    (name . ,(row-value row "name"))
    (kind . ,(or (row-value row "kind") "custom"))
    (description . ,(or (row-value row "description") ""))
    (components . ,(or (row-value row "components") "[]"))
    (materials . ,(or (row-value row "materials") "[]"))
    (colors . ,(or (row-value row "colors") "[]"))
    (accessories . ,(or (row-value row "accessories") "[]"))
    (special_features . ,(or (row-value row "special_features") "[]"))
    (image_prompt . ,(or (row-value row "image_prompt") ""))
    (reference_asset_id . ,(row-value row "reference_asset_id"))
    (is_default . ,(= 1 (db-int (row-value row "is_default"))))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (archived_at . ,(row-value row "archived_at"))))

(define (outfit-by-id db workplace-id character-id outfit-id)
  (query db
         (string-append
          "SELECT " outfit-columns "
             FROM studio_character_outfits o
             JOIN studio_characters ch ON ch.id = o.character_id
            WHERE o.id = ? AND o.character_id = ? AND ch.workplace_id = ?
              AND ch.archived_at IS NULL AND o.archived_at IS NULL")
         outfit-id character-id workplace-id)
  (let ((row (dbi-get_row db))) (and row (outfit-from-row row))))

(define (studio-list-character-outfits config workplace-id character-id)
  (with-db config
    (lambda (db)
      (and (character-by-id db workplace-id character-id)
           (begin
             (query db
                    (string-append
                     "SELECT " outfit-columns "
                        FROM studio_character_outfits o
                        JOIN studio_characters ch ON ch.id = o.character_id
                       WHERE o.character_id = ? AND ch.workplace_id = ?
                         AND ch.archived_at IS NULL AND o.archived_at IS NULL
                       ORDER BY o.is_default DESC, o.created_at ASC, o.id ASC")
                    character-id workplace-id)
             (map outfit-from-row (all-rows db)))))))

(define (studio-get-character-outfit config workplace-id character-id outfit-id)
  (with-db config
    (lambda (db) (outfit-by-id db workplace-id character-id outfit-id))))

(define (clear-default-outfits! db character-id)
  (query db "UPDATE studio_character_outfits SET is_default = 0, updated_at = ?
              WHERE character_id = ? AND is_default = 1"
         (studio-now) character-id))

(define (active-outfit-count db character-id)
  (query db "SELECT COUNT(*) AS count FROM studio_character_outfits
              WHERE character_id = ? AND archived_at IS NULL"
         character-id)
  (db-int (row-value (dbi-get_row db) "count")))

(define (studio-create-character-outfit! config id workplace-id character-id values)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (character-by-id db workplace-id character-id)
            (throw 'studio-outfit-error 'character-not-found))
          (let* ((now (studio-now))
                 (first? (= 0 (active-outfit-count db character-id)))
                 (default? (or first? (eq? (assoc-ref values 'is_default) #t)))
                 (field (lambda (key default)
                          (let ((value (assoc-ref values key)))
                            (if value value default)))))
            (when default? (clear-default-outfits! db character-id))
            (query db
                   "INSERT INTO studio_character_outfits
                      (id, character_id, name, kind, description, components,
                       materials, colors, accessories, special_features,
                       image_prompt, reference_asset_id, is_default,
                       created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                   id character-id (assoc-ref values 'name)
                   (field 'kind "custom") (field 'description "")
                   (field 'components "[]") (field 'materials "[]")
                   (field 'colors "[]") (field 'accessories "[]")
                   (field 'special_features "[]") (field 'image_prompt "")
                   (sql-value (assoc-ref values 'reference_asset_id))
                   (if default? 1 0) now now)
            (outfit-by-id db workplace-id character-id id)))))))

(define (studio-update-character-outfit! config workplace-id character-id
                                         outfit-id updates)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (outfit-by-id db workplace-id character-id outfit-id)
            (throw 'studio-outfit-error 'outfit-not-found))
          (let* ((now (studio-now))
                 (make-default? (eq? (assoc-ref updates 'is_default) #t))
                 (clause (update-clause
                          updates
                          '(name kind description components materials colors
                            accessories special_features image_prompt
                            reference_asset_id is_default)))
                 (sets (car clause))
                 (values (cdr clause)))
            (when make-default? (clear-default-outfits! db character-id))
            (if (null? sets)
                (outfit-by-id db workplace-id character-id outfit-id)
                (begin
                  (dbi-params-query db
                    (string-append
                     "UPDATE studio_character_outfits SET "
                     (string-join sets ", ")
                     ", updated_at = ? WHERE id = ? AND character_id = ?
                       AND archived_at IS NULL")
                    (append values (list now outfit-id character-id)))
                  (and (> (dbi-affected-rows db) 0)
                       (outfit-by-id db workplace-id character-id outfit-id))))))))))

(define (studio-archive-character-outfit! config workplace-id character-id outfit-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((outfit (outfit-by-id db workplace-id character-id outfit-id)))
            (and outfit
                 (let* ((now (studio-now))
                        (was-default? (assoc-ref outfit 'is_default)))
                   (query db "UPDATE studio_character_outfits
                                 SET archived_at = ?, updated_at = ?, is_default = 0
                               WHERE id = ? AND character_id = ? AND archived_at IS NULL"
                          now now outfit-id character-id)
                   (when (and was-default? (> (dbi-affected-rows db) 0))
                     (query db
                            "SELECT id FROM studio_character_outfits
                              WHERE character_id = ? AND archived_at IS NULL
                              ORDER BY created_at ASC, id ASC LIMIT 1"
                            character-id)
                     (let ((row (dbi-get_row db)))
                       (when row
                         (query db "UPDATE studio_character_outfits
                                       SET is_default = 1, updated_at = ?
                                     WHERE id = ?"
                                now (row-value row "id")))))
                   `((id . ,outfit-id)
                     (character_id . ,character-id)
                     (archived_at . ,now))))))))))

(define (studio-set-default-character-outfit! config workplace-id character-id outfit-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (outfit-by-id db workplace-id character-id outfit-id)
            (throw 'studio-outfit-error 'outfit-not-found))
          (let ((now (studio-now)))
            (clear-default-outfits! db character-id)
            (query db "UPDATE studio_character_outfits
                          SET is_default = 1, updated_at = ?
                        WHERE id = ? AND character_id = ?"
                   now outfit-id character-id)
            (outfit-by-id db workplace-id character-id outfit-id)))))))

(define (studio-set-character-outfit-reference! config workplace-id character-id
                                                outfit-id asset-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (outfit-by-id db workplace-id character-id outfit-id)
            (throw 'studio-outfit-error 'outfit-not-found))
          (query db "UPDATE studio_character_outfits
                        SET reference_asset_id = ?, updated_at = ?
                      WHERE id = ? AND character_id = ? AND archived_at IS NULL"
                 (sql-value asset-id) (studio-now) outfit-id character-id)
          (and (> (dbi-affected-rows db) 0)
               (outfit-by-id db workplace-id character-id outfit-id)))))))

(define scene-columns
  "id, workplace_id, title, summary, sort_order, status,
   time, place, environment, background, prior_events,
   central_question, primary_conflict, turn, dialogue,
   blocking, spatial, performance_direction, camera,
   storyboard, created_at, updated_at, deleted_at")

(define (scene-from-row row)
  `((id . ,(row-value row "id"))
    (workplace_id . ,(row-value row "workplace_id"))
    (title . ,(row-value row "title"))
    (summary . ,(or (row-value row "summary") ""))
    (sort_order . ,(db-int (row-value row "sort_order")))
    (status . ,(row-value row "status"))
    (time . ,(or (row-value row "time") ""))
    (place . ,(or (row-value row "place") ""))
    (environment . ,(or (row-value row "environment") ""))
    (background . ,(or (row-value row "background") ""))
    (prior_events . ,(or (row-value row "prior_events") ""))
    (central_question . ,(or (row-value row "central_question") ""))
    (primary_conflict . ,(or (row-value row "primary_conflict") ""))
    (turn . ,(or (row-value row "turn") ""))
    (dialogue . ,(or (row-value row "dialogue") ""))
    (blocking . ,(or (row-value row "blocking") ""))
    (spatial . ,(or (row-value row "spatial") ""))
    (performance_direction . ,(or (row-value row "performance_direction") ""))
    (camera . ,(or (row-value row "camera") ""))
    (storyboard . ,(or (row-value row "storyboard") "[]"))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (deleted_at . ,(row-value row "deleted_at"))
    (cast_count . ,(db-int (row-value row "cast_count")))))

(define (scene-by-id db workplace-id scene-id)
  (query db
         (string-append
          "SELECT s.id, s.workplace_id, s.title, s.summary, s.sort_order,
                  s.status, s.time, s.place, s.environment, s.background,
                  s.prior_events, s.central_question, s.primary_conflict,
                  s.turn, s.dialogue, s.blocking, s.spatial,
                  s.performance_direction, s.camera, s.storyboard, s.created_at,
                  s.updated_at, s.deleted_at,
                  (SELECT COUNT(*) FROM studio_scene_cast c
                   WHERE c.scene_id = s.id) AS cast_count
             FROM studio_scenes s
            WHERE s.id = ? AND s.workplace_id = ? AND s.deleted_at IS NULL")
         scene-id workplace-id)
  (let ((row (dbi-get_row db))) (and row (scene-from-row row))))

(define (studio-list-scenes config workplace-id)
  (with-db config
    (lambda (db)
      (query db
             "SELECT s.id, s.workplace_id, s.title, s.summary, s.sort_order,
                     s.status, s.time, s.place, s.environment, s.background,
                     s.prior_events, s.central_question, s.primary_conflict,
                     s.turn, s.dialogue, s.blocking, s.spatial,
                     s.performance_direction, s.camera, s.storyboard, s.created_at,
                     s.updated_at, s.deleted_at,
                     (SELECT COUNT(*) FROM studio_scene_cast c
                      WHERE c.scene_id = s.id) AS cast_count
                FROM studio_scenes s
               WHERE s.workplace_id = ? AND s.deleted_at IS NULL
               ORDER BY s.sort_order ASC, s.created_at ASC, s.id ASC"
             workplace-id)
      (map scene-from-row (all-rows db)))))

(define (studio-create-scene! config id workplace-id values)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now))
                (field (lambda (key) (or (assoc-ref values key) ""))))
            (query db
                   "INSERT INTO studio_scenes
                      (id, workplace_id, title, summary, sort_order, status,
                       time, place, environment, background, prior_events,
                       central_question, primary_conflict, turn, dialogue,
                       blocking, spatial, performance_direction, camera,
                       created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                   id workplace-id (assoc-ref values 'title)
                   (field 'summary) (assoc-ref values 'sort_order)
                   (assoc-ref values 'status)
                   (field 'time) (field 'place) (field 'environment)
                   (field 'background) (field 'prior_events)
                   (field 'central_question) (field 'primary_conflict)
                   (field 'turn) (field 'dialogue) (field 'blocking)
                   (field 'spatial) (field 'performance_direction)
                   (field 'camera) now now)
            (scene-by-id db workplace-id id)))))))

(define (studio-get-scene config workplace-id scene-id)
  (with-db config (lambda (db) (scene-by-id db workplace-id scene-id))))

(define (studio-update-scene! config workplace-id scene-id updates)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let* ((now (studio-now))
                 (clause (update-clause
                          updates
                          '(title summary sort_order status time place
                            environment background prior_events
                            central_question primary_conflict turn dialogue
                            blocking spatial performance_direction camera
                            storyboard)))
                 (sets (car clause))
                 (values (cdr clause)))
            (if (null? sets)
                (scene-by-id db workplace-id scene-id)
                (begin
                  (dbi-params-query db
                    (string-append
                     "UPDATE studio_scenes SET "
                     (string-join sets ", ")
                     ", updated_at = ? WHERE id = ? AND workplace_id = ?
                       AND deleted_at IS NULL")
                    (append values (list now scene-id workplace-id)))
                  (and (> (dbi-affected-rows db) 0)
                       (scene-by-id db workplace-id scene-id))))))))))

(define (studio-delete-scene! config workplace-id scene-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now)))
            (query db
                   "UPDATE studio_scenes SET deleted_at = ?, updated_at = ?
                     WHERE id = ? AND workplace_id = ? AND deleted_at IS NULL"
                   now now scene-id workplace-id)
            (and (> (dbi-affected-rows db) 0)
                 (begin
                   (query db "DELETE FROM studio_asset_links
                               WHERE resource_type = 'scene' AND resource_id = ?"
                          scene-id)
                   now))))))))

(define scene-cast-columns
  "c.id, c.scene_id, c.character_id, c.objective, c.action, c.conflict,
   c.emotional_state, c.performance_direction, c.subtext, c.sort_order,
   c.created_at, c.updated_at, ch.name AS character_name,
   ch.role AS character_role")

(define (scene-cast-from-row row)
  `((id . ,(row-value row "id"))
    (scene_id . ,(row-value row "scene_id"))
    (character_id . ,(row-value row "character_id"))
    (objective . ,(or (row-value row "objective") ""))
    (action . ,(or (row-value row "action") ""))
    (conflict . ,(or (row-value row "conflict") ""))
    (emotional_state . ,(or (row-value row "emotional_state") ""))
    (performance_direction . ,(or (row-value row "performance_direction") ""))
    (subtext . ,(or (row-value row "subtext") ""))
    (sort_order . ,(db-int (row-value row "sort_order")))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (character_name . ,(or (row-value row "character_name") ""))
    (character_role . ,(or (row-value row "character_role") ""))))

(define (scene-cast-by-scene db scene-id)
  (query db
         (string-append "SELECT " scene-cast-columns "
                         FROM studio_scene_cast c
                         JOIN studio_characters ch ON ch.id = c.character_id
                         WHERE c.scene_id = ?
                         ORDER BY c.sort_order ASC, c.created_at ASC, c.id ASC")
         scene-id)
  (map scene-cast-from-row (all-rows db)))

(define (studio-list-scene-cast config workplace-id scene-id)
  (with-db config
    (lambda (db)
      (and (scene-by-id db workplace-id scene-id)
           (scene-cast-by-scene db scene-id)))))

(define (studio-replace-scene-cast! config workplace-id scene-id entries)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (scene-by-id db workplace-id scene-id)
            (throw 'studio-cast-error 'scene-not-found))
          (for-each
           (lambda (entry)
             (query db
                    "SELECT id FROM studio_characters
                      WHERE id = ? AND workplace_id = ? AND archived_at IS NULL"
                    (assoc-ref entry 'character_id) workplace-id)
             (unless (dbi-get_row db)
               (throw 'studio-cast-error 'character-not-found)))
           entries)
          (query db "DELETE FROM studio_scene_cast WHERE scene_id = ?" scene-id)
          (let ((now (studio-now))
                (field (lambda (entry key)
                         (or (assoc-ref entry key) ""))))
            (for-each
             (lambda (entry)
               (query db
                      "INSERT INTO studio_scene_cast
                         (id, scene_id, character_id, objective, action,
                          conflict, emotional_state, performance_direction,
                          subtext, sort_order, created_at, updated_at)
                       VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                      (studio-new-id) scene-id (assoc-ref entry 'character_id)
                      (field entry 'objective) (field entry 'action)
                      (field entry 'conflict) (field entry 'emotional_state)
                      (field entry 'performance_direction) (field entry 'subtext)
                      (or (assoc-ref entry 'sort_order) 0) now now))
             entries))
          (scene-cast-by-scene db scene-id))))))

(define asset-columns
  "id, workplace_id, name, description, asset_type, storage_key,
   original_filename, mime_type, file_size, checksum, source,
   width, height, duration_ms, author, notes, generation_metadata,
   created_at, updated_at, archived_at")

(define asset-columns-qualified
  "a.id, a.workplace_id, a.name, a.description, a.asset_type, a.storage_key,
   a.original_filename, a.mime_type, a.file_size, a.checksum, a.source,
   a.width, a.height, a.duration_ms, a.author, a.notes,
   a.generation_metadata, a.created_at, a.updated_at, a.archived_at")

(define (asset-from-row row)
  `((id . ,(row-value row "id"))
    (workplace_id . ,(row-value row "workplace_id"))
    (name . ,(row-value row "name"))
    (description . ,(or (row-value row "description") ""))
    (asset_type . ,(row-value row "asset_type"))
    (storage_key . ,(or (row-value row "storage_key") ""))
    (original_filename . ,(or (row-value row "original_filename") ""))
    (mime_type . ,(or (row-value row "mime_type") "application/octet-stream"))
    (file_size . ,(db-int (row-value row "file_size")))
    (checksum . ,(or (row-value row "checksum") ""))
    (source . ,(row-value row "source"))
    (width . ,(and (row-value row "width") (db-int (row-value row "width"))))
    (height . ,(and (row-value row "height") (db-int (row-value row "height"))))
    (duration_ms . ,(and (row-value row "duration_ms")
                         (db-int (row-value row "duration_ms"))))
    (author . ,(or (row-value row "author") ""))
    (notes . ,(or (row-value row "notes") ""))
    (generation_metadata . ,(or (row-value row "generation_metadata") "{}"))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (archived_at . ,(row-value row "archived_at"))
    (tags . ())))

(define (asset-tags db asset-id)
  (query db "SELECT tag FROM studio_asset_tags WHERE asset_id = ? ORDER BY tag COLLATE NOCASE"
         asset-id)
  (map (lambda (row) (row-value row "tag")) (all-rows db)))

(define (asset-with-tags db row)
  (let ((asset (asset-from-row row)))
    (acons 'tags (asset-tags db (assoc-ref asset 'id)) asset)))

(define (asset-by-id db workplace-id asset-id)
  (query db
         (string-append "SELECT " asset-columns " FROM studio_assets
                         WHERE id = ? AND workplace_id = ? AND archived_at IS NULL")
         asset-id workplace-id)
  (let ((row (dbi-get_row db))) (and row (asset-with-tags db row))))

(define (studio-list-assets config workplace-id)
  (with-db config
    (lambda (db)
      (query db
             (string-append "SELECT " asset-columns " FROM studio_assets
                             WHERE workplace_id = ? AND archived_at IS NULL
                             ORDER BY updated_at DESC, created_at DESC, name ASC")
             workplace-id)
      (map (lambda (row) (asset-with-tags db row)) (all-rows db)))))

(define (replace-asset-tags! db asset-id tags)
  (query db "DELETE FROM studio_asset_tags WHERE asset_id = ?" asset-id)
  (for-each
   (lambda (tag)
     (query db "INSERT OR IGNORE INTO studio_asset_tags(asset_id, tag) VALUES(?, ?)"
            asset-id tag))
   tags))

(define (studio-create-asset! config id workplace-id values)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now))
                (field (lambda (key default)
                         (let ((value (assoc-ref values key)))
                           (if value value default)))))
            (query db
                   "INSERT INTO studio_assets
                      (id, workplace_id, name, description, asset_type,
                       storage_key, original_filename, mime_type, file_size,
                       checksum, source, width, height, duration_ms, author,
                       notes, generation_metadata, created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
                   id workplace-id (assoc-ref values 'name)
                   (field 'description "") (assoc-ref values 'asset_type)
                   (field 'storage_key "") (field 'original_filename "")
                   (field 'mime_type "application/octet-stream")
                   (or (assoc-ref values 'file_size) 0)
                   (field 'checksum "") (field 'source "imported")
                   (sql-value (assoc-ref values 'width))
                   (sql-value (assoc-ref values 'height))
                   (sql-value (assoc-ref values 'duration_ms))
                   (field 'author "") (field 'notes "")
                   (field 'generation_metadata "{}") now now)
            (replace-asset-tags! db id (or (assoc-ref values 'tags) '()))
            (asset-by-id db workplace-id id)))))))

(define (studio-get-asset config workplace-id asset-id)
  (with-db config (lambda (db) (asset-by-id db workplace-id asset-id))))

(define* (studio-update-asset! config workplace-id asset-id updates
                               #:key (tags #f))
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let* ((now (studio-now))
                 (clause (update-clause
                          updates
                          '(name description asset_type source width height
                            duration_ms author notes generation_metadata
                            original_filename mime_type file_size checksum
                            storage_key)))
                 (sets (car clause))
                 (values (cdr clause)))
            (unless (and (null? sets) (not tags))
              (when (pair? sets)
                (dbi-params-query db
                  (string-append
                   "UPDATE studio_assets SET "
                   (string-join sets ", ")
                   ", updated_at = ? WHERE id = ? AND workplace_id = ?
                     AND archived_at IS NULL")
                  (append values (list now asset-id workplace-id))))
              (when tags
                (query db "UPDATE studio_assets SET updated_at = ?
                            WHERE id = ? AND workplace_id = ? AND archived_at IS NULL"
                       now asset-id workplace-id)
                (replace-asset-tags! db asset-id tags)))
            (asset-by-id db workplace-id asset-id)))))))

(define (studio-archive-asset! config workplace-id asset-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((asset (asset-by-id db workplace-id asset-id)))
            (and asset
                 (let ((now (studio-now)))
                   (query db "UPDATE studio_assets SET archived_at = ?, updated_at = ?
                               WHERE id = ? AND workplace_id = ? AND archived_at IS NULL"
                          now now asset-id workplace-id)
                   (when (> (dbi-affected-rows db) 0)
                     (query db "DELETE FROM studio_asset_links WHERE asset_id = ?"
                            asset-id)
                     `((id . ,asset-id)
                       (workplace_id . ,workplace-id)
                       (storage_key . ,(assoc-ref asset 'storage_key))
                       (archived_at . ,now)))))))))))

(define (link-from-row row)
  `((asset_id . ,(row-value row "asset_id"))
    (resource_type . ,(row-value row "resource_type"))
    (resource_id . ,(row-value row "resource_id"))
    (created_at . ,(row-value row "created_at"))))

(define (studio-list-asset-links config workplace-id asset-id)
  (with-db config
    (lambda (db)
      (and (asset-by-id db workplace-id asset-id)
           (begin
             (query db "SELECT asset_id, resource_type, resource_id, created_at
                          FROM studio_asset_links WHERE asset_id = ?
                          ORDER BY resource_type ASC, resource_id ASC"
                    asset-id)
             (map link-from-row (all-rows db)))))))

(define (studio-add-asset-link! config workplace-id asset-id resource-type resource-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (asset-by-id db workplace-id asset-id)
            (throw 'studio-asset-link-error 'asset-not-found))
          (let ((now (studio-now)))
            (query db "INSERT OR IGNORE INTO studio_asset_links
                         (asset_id, resource_type, resource_id, created_at)
                       VALUES(?, ?, ?, ?)"
                   asset-id resource-type resource-id now)
            `((asset_id . ,asset-id)
              (resource_type . ,resource-type)
              (resource_id . ,resource-id)
              (created_at . ,now))))))))

(define (studio-remove-asset-link! config workplace-id asset-id resource-type resource-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (unless (asset-by-id db workplace-id asset-id)
            (throw 'studio-asset-link-error 'asset-not-found))
          (query db "DELETE FROM studio_asset_links
                      WHERE asset_id = ? AND resource_type = ? AND resource_id = ?"
                 asset-id resource-type resource-id)
          (> (dbi-affected-rows db) 0))))))

(define (studio-list-linked-assets config workplace-id resource-type resource-id)
  (with-db config
    (lambda (db)
      (query db
             (string-append
              "SELECT " asset-columns-qualified "
                 FROM studio_assets a
                 JOIN studio_asset_links l ON l.asset_id = a.id
                WHERE a.workplace_id = ? AND a.archived_at IS NULL
                  AND l.resource_type = ? AND l.resource_id = ?
                ORDER BY a.updated_at DESC, a.created_at DESC, a.name ASC")
             workplace-id resource-type resource-id)
      (map (lambda (row) (asset-with-tags db row)) (all-rows db)))))

(define document-columns
  "id, workplace_id, parent_id, kind, title, content, content_format,
   revision, sort_order, created_at, updated_at, deleted_at")

(define (document-from-row row)
  `((id . ,(row-value row "id"))
    (workplace_id . ,(row-value row "workplace_id"))
    (parent_id . ,(row-value row "parent_id"))
    (kind . ,(row-value row "kind"))
    (title . ,(row-value row "title"))
    (content . ,(or (row-value row "content") ""))
    (content_format . ,(row-value row "content_format"))
    (revision . ,(db-int (row-value row "revision")))
    (sort_order . ,(db-int (row-value row "sort_order")))
    (created_at . ,(row-value row "created_at"))
    (updated_at . ,(row-value row "updated_at"))
    (deleted_at . ,(row-value row "deleted_at"))))

(define (document-by-id db workplace-id document-id)
  (query db
         (string-append "SELECT " document-columns " FROM studio_documents
                         WHERE id = ? AND workplace_id = ? AND deleted_at IS NULL")
         document-id workplace-id)
  (let ((row (dbi-get_row db))) (and row (document-from-row row))))

(define (studio-list-documents config workplace-id)
  (with-db config
    (lambda (db)
      (query db
             (string-append
              "SELECT " document-columns " FROM studio_documents
               WHERE workplace_id = ? AND deleted_at IS NULL
               ORDER BY sort_order ASC, created_at ASC, id ASC")
             workplace-id)
      (map document-from-row (all-rows db)))))

(define (studio-create-document! config id workplace-id parent-id kind title
                                 content content-format sort-order)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((now (studio-now)))
            (query db
                   "INSERT INTO studio_documents
                      (id, workplace_id, parent_id, kind, title, content,
                       content_format, revision, sort_order, created_at, updated_at)
                    VALUES(?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)"
                   id workplace-id (sql-value parent-id) kind title content
                   content-format sort-order now now)
            (document-by-id db workplace-id id)))))))

(define (studio-get-document config workplace-id document-id)
  (with-db config (lambda (db) (document-by-id db workplace-id document-id))))

;; Returns #f when the document is absent, (ok . document) on success, or
;; (conflict . current-document) when expected-revision is stale. The update
;; itself is conditional on the revision, so a newer revision can never be
;; overwritten after the comparison.
(define (studio-update-document! config workplace-id document-id title content
                                 content-format expected-revision)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((current (document-by-id db workplace-id document-id)))
            (cond
             ((not current) #f)
             ((not (= expected-revision (assoc-ref current 'revision)))
              (cons 'conflict current))
             ((and (equal? title (assoc-ref current 'title))
                   (equal? content (assoc-ref current 'content))
                   (equal? content-format (assoc-ref current 'content_format)))
              (cons 'ok current))
             (else
              (let ((next-revision (+ expected-revision 1)))
                (query db
                       "UPDATE studio_documents
                          SET title = ?, content = ?, content_format = ?,
                              revision = ?, updated_at = ?
                        WHERE id = ? AND workplace_id = ? AND revision = ?
                          AND deleted_at IS NULL"
                       title content content-format next-revision (studio-now)
                       document-id workplace-id expected-revision)
                (if (= (dbi-affected-rows db) 1)
                    (cons 'ok (document-by-id db workplace-id document-id))
                    (let ((latest (document-by-id db workplace-id document-id)))
                      (if latest (cons 'conflict latest) #f))))))))))))

(define version-columns
  "id, document_id, revision, title, content, label, source, created_at")

(define (version-from-row row)
  `((id . ,(row-value row "id"))
    (document_id . ,(row-value row "document_id"))
    (revision . ,(db-int (row-value row "revision")))
    (title . ,(row-value row "title"))
    (content . ,(or (row-value row "content") ""))
    (label . ,(row-value row "label"))
    (source . ,(row-value row "source"))
    (created_at . ,(row-value row "created_at"))))

(define (insert-version! db id document revision title content label source now)
  (query db
         "INSERT INTO studio_document_versions
            (id, document_id, revision, title, content, label, source, created_at)
          VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
         id document revision title content (sql-value label) source now))

(define (studio-create-version! config workplace-id document-id version-id
                                label source)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((document (document-by-id db workplace-id document-id)))
            (and document
                 (let ((now (studio-now)))
                   (insert-version! db version-id document-id
                                    (assoc-ref document 'revision)
                                    (assoc-ref document 'title)
                                    (assoc-ref document 'content)
                                    label source now)
                   `((id . ,version-id)
                     (document_id . ,document-id)
                     (revision . ,(assoc-ref document 'revision))
                     (title . ,(assoc-ref document 'title))
                     (content . ,(assoc-ref document 'content))
                     (label . ,label)
                     (source . ,source)
                     (created_at . ,now))))))))))

(define (studio-list-versions config workplace-id document-id)
  (with-db config
    (lambda (db)
      (query db
             "SELECT v.id, v.document_id, v.revision, v.title, v.content,
                     v.label, v.source, v.created_at
                FROM studio_document_versions v
                JOIN studio_documents d ON d.id = v.document_id
               WHERE v.document_id = ? AND d.workplace_id = ?
                 AND d.deleted_at IS NULL
               ORDER BY v.created_at DESC, v.revision DESC, v.rowid DESC"
             document-id workplace-id)
      (map version-from-row (all-rows db)))))

(define (studio-get-version config workplace-id document-id version-id)
  (with-db config
    (lambda (db)
      (query db
             "SELECT v.id, v.document_id, v.revision, v.title, v.content,
                     v.label, v.source, v.created_at
                FROM studio_document_versions v
                JOIN studio_documents d ON d.id = v.document_id
               WHERE v.id = ? AND v.document_id = ? AND d.workplace_id = ?
                 AND d.deleted_at IS NULL"
             version-id document-id workplace-id)
      (let ((row (dbi-get_row db))) (and row (version-from-row row))))))

(define (studio-restore-version! config workplace-id document-id version-id)
  (with-db config
    (lambda (db)
      (with-transaction db
        (lambda ()
          (let ((document (document-by-id db workplace-id document-id)))
            (query db
                   "SELECT v.id, v.document_id, v.revision, v.title, v.content,
                           v.label, v.source, v.created_at
                      FROM studio_document_versions v
                      JOIN studio_documents d ON d.id = v.document_id
                     WHERE v.id = ? AND v.document_id = ? AND d.workplace_id = ?
                       AND d.deleted_at IS NULL"
                   version-id document-id workplace-id)
            (let ((row (dbi-get_row db)))
              (and document row
                   (let* ((version (version-from-row row))
                          (now (studio-now))
                          (next-revision (+ (assoc-ref document 'revision) 1))
                          (title (assoc-ref version 'title))
                          (content (assoc-ref version 'content)))
                     (query db
                            "UPDATE studio_documents
                                SET title = ?, content = ?, content_format = 'markdown',
                                    revision = ?, updated_at = ?
                              WHERE id = ? AND workplace_id = ? AND deleted_at IS NULL"
                            title content next-revision now document-id workplace-id)
                     ;; Restore is an auditable event. The selected historical
                     ;; row remains untouched; this new snapshot records the
                     ;; revision produced by the restore.
                     (insert-version! db (studio-new-id) document-id next-revision
                                      title content #f "restore" now)
                     (document-by-id db workplace-id document-id))))))))))
