(use-modules (khala config)
             (khala studio persistence)
             (ice-9 format)
             (srfi srfi-1))

(define db-path "/tmp/khala-studio-persistence.sqlite3")
(define (cleanup)
  (for-each (lambda (path)
              (when (file-exists? path) (delete-file path)))
            (list db-path (string-append db-path "-journal")
                  (string-append db-path "-wal")
                  (string-append db-path "-shm"))))

(define (check name condition)
  (unless condition (error "studio persistence test failed" name))
  (format #t "ok ~a~%" name))

(cleanup)
(define config
  (map (lambda (entry)
         (case (car entry)
           ((studio_db) (cons 'studio_db db-path))
           ((engine) (cons 'engine "fake"))
           ((studio_model) (cons 'studio_model "fake"))
           (else entry)))
       (load-config)))

(check 'fresh-schema (= 1 (studio-schema-version config)))

(define workplace
  (studio-create-workplace! config (studio-new-id) "Persistence World"
                            "A test workplace" "#713D3B" #f))
(define workplace-id (assoc-ref workplace 'id))
(check 'workplace-created (and workplace-id (string? (assoc-ref workplace 'created_at))))
(check 'workplace-listed
       (equal? (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-workplaces config))
               (list workplace-id)))

(define document
  (studio-create-document! config (studio-new-id) workplace-id #f
                           "manuscript" "Book" "hello world" "markdown" 0))
(define document-id (assoc-ref document 'id))
(check 'document-roundtrip
       (equal? (assoc-ref (studio-get-document config workplace-id document-id)
                          'content)
               "hello world"))

(define same-result
  (studio-update-document! config workplace-id document-id
                           "Book" "hello world" "markdown" 1))
(check 'no-op-keeps-revision
       (and (eq? (car same-result) 'ok)
            (= 1 (assoc-ref (cdr same-result) 'revision))))

(define changed
  (studio-update-document! config workplace-id document-id
                           "Book" "hello brave world" "markdown" 1))
(check 'update-increments-revision
       (and (eq? (car changed) 'ok)
            (= 2 (assoc-ref (cdr changed) 'revision))))

(define stale
  (studio-update-document! config workplace-id document-id
                           "Book" "stale overwrite" "markdown" 1))
(check 'stale-update-conflicts
       (and (eq? (car stale) 'conflict)
            (= 2 (assoc-ref (cdr stale) 'revision))))
(check 'stale-update-does-not-overwrite
       (equal? (assoc-ref (studio-get-document config workplace-id document-id)
                          'content)
               "hello brave world"))

(define version
  (studio-create-version! config workplace-id document-id (studio-new-id)
                          "Before edits" "checkpoint"))
(define version-id (assoc-ref version 'id))
(studio-update-document! config workplace-id document-id
                         "Book" "later content" "markdown" 2)
(check 'version-is-immutable
       (equal? (assoc-ref (studio-get-version config workplace-id document-id
                                              version-id)
                          'content)
               "hello brave world"))

(define restored
  (studio-restore-version! config workplace-id document-id version-id))
(check 'restore-creates-new-revision
       (and (= 4 (assoc-ref restored 'revision))
            (equal? (assoc-ref restored 'content) "hello brave world")))
(check 'restore-preserves-historical-version
       (equal? (assoc-ref (studio-get-version config workplace-id document-id
                                              version-id)
                          'content)
               "hello brave world"))
(check 'restore-is-audited
       (any (lambda (entry) (equal? (assoc-ref entry 'source) "restore"))
            (studio-list-versions config workplace-id document-id)))

(define other-workplace
  (studio-create-workplace! config (studio-new-id) "Other" "" "#354B40" #f))
(check 'documents-are-workplace-scoped
       (not (studio-get-document config (assoc-ref other-workplace 'id)
                                 document-id)))

(cleanup)
(format #t "studio persistence tests passed~%")
