(define-module (khala comfy persistence)
  #:use-module (dbi dbi)
  #:use-module (json)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala json)
  #:export (save-history! fetch-history fetch-all-history!
            save-queue-item! mark-queue-item-done! clear-persisted-queue!
            fetch-pending-queue))

(define (enabled? config key) (eq? (assq-ref config key) #t))

(define (with-db config proc)
  (let* ((path (assq-ref config 'history_db))
         (directory (dirname path)))
    (unless (or (string-null? directory) (file-exists? directory))
      (mkdir-p directory))
    (let ((connection (dbi-open "sqlite3" path)))
      (dynamic-wind
        (lambda ()
          (dbi-query connection
            "CREATE TABLE IF NOT EXISTS khala_history (prompt_id TEXT PRIMARY KEY, history_json TEXT NOT NULL, created_at INTEGER NOT NULL)")
          (dbi-query connection
            "CREATE TABLE IF NOT EXISTS khala_queue (prompt_id TEXT PRIMARY KEY, number INTEGER NOT NULL, position INTEGER NOT NULL, client_id TEXT, prompt_json TEXT NOT NULL, extra_data_json TEXT NOT NULL, state INTEGER NOT NULL)"))
        (lambda () (proc connection))
        (lambda () (dbi-close connection))))))

(define (rows connection sql . args)
  (if (null? args) (dbi-query connection sql)
      (dbi-params-query connection sql args)))

(define (all-rows connection)
  (let loop ((result '()) (row (dbi-get_row connection)))
    (if row (loop (cons row result) (dbi-get_row connection))
        (reverse result))))

(define (value row key) (or (assoc-ref row key) (assoc-ref row (string->symbol key))))
(define (decode-history row)
  (cons (value row "prompt_id")
        (json-normalize (json-string->scm (value row "history_json")))))
(define (decode-queue row)
  `((prompt_id . ,(value row "prompt_id"))
    (number . ,(value row "number"))
    (client_id . ,(value row "client_id"))
    (prompt . ,(json-normalize (json-string->scm (value row "prompt_json"))))
    (extra_data . ,(json-normalize (json-string->scm (value row "extra_data_json"))))))

(define (save-history! config id record)
  (when (enabled? config 'persist_history)
    (with-db config
      (lambda (db)
        (rows db "INSERT OR REPLACE INTO khala_history(prompt_id,history_json,created_at) VALUES(?,?,strftime('%s','now'))"
              id (json-encode record))))))

(define (fetch-history config id)
  (and (enabled? config 'persist_history)
       (with-db config
         (lambda (db)
           (rows db "SELECT prompt_id,history_json FROM khala_history WHERE prompt_id=?" id)
           (let ((row (dbi-get_row db))) (and row (cdr (decode-history row))))))))

(define (fetch-all-history! config)
  (if (enabled? config 'persist_history)
      (with-db config
        (lambda (db)
          (rows db "SELECT prompt_id,history_json FROM khala_history ORDER BY created_at DESC")
          (map decode-history (all-rows db))))
      '()))

(define (save-queue-item! config item front?)
  (when (enabled? config 'persist_queue)
    (let* ((id (assq-ref item 'prompt_id))
           (number (assq-ref item 'number))
           (position (if front? (- number) number))
           (client (or (assq-ref item 'client_id) "")))
      (with-db config
        (lambda (db)
          (rows db "INSERT OR REPLACE INTO khala_queue(prompt_id,number,position,client_id,prompt_json,extra_data_json,state) VALUES(?,?,?,?,?,?,1)"
                id number position client
                (json-encode (json-normalize (assq-ref item 'prompt)))
                (json-encode (json-normalize (or (assq-ref item 'extra_data) '())))))))))

(define (fetch-pending-queue config)
  (if (enabled? config 'persist_queue)
      (with-db config
        (lambda (db)
          (rows db "SELECT prompt_id,number,client_id,prompt_json,extra_data_json FROM khala_queue WHERE state=1 ORDER BY position")
          (map decode-queue (all-rows db))))
      '()))

(define (mark-queue-item-done! config id)
  (when (enabled? config 'persist_queue)
    (with-db config (lambda (db) (rows db "UPDATE khala_queue SET state=0 WHERE prompt_id=?" id)))))

(define (clear-persisted-queue! config)
  (when (enabled? config 'persist_queue)
    (with-db config (lambda (db) (rows db "UPDATE khala_queue SET state=0 WHERE state=1")))))
