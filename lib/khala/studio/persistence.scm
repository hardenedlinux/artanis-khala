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

(define (migrations) (list (cons 1 migration-1)))

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
