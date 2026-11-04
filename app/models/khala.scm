;; UI-facing model for downloads, catalog, system, and editable settings.

(define-module (app models khala)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 format)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 threads)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (app models ollama)
  #:use-module (khala config)
  #:use-module (khala download)
  #:use-module (khala json)
  #:export (khala-downloads
            khala-start-download!
            khala-cancel-download!
            khala-download-status
            khala-catalog
            khala-system
            khala-settings
            khala-save-settings!))

(define (obj . fields) (make-json-object fields))
(define (ref object key)
  (let ((entry (and (list? object) (assq key object))))
    (and entry (cdr entry))))
(define jobs (make-hash-table))
(define jobs-lock (make-mutex))
(define terminal-states '("done" "failed" "cancelled"))

(define (installed-path config entry)
  (string-append (ollama-llm-dir config) "/" (assq-ref entry 'path)))

(define (download-status id job)
  (let* ((st (if (directory-job? job) (directory-job-status job) (job-status job)))
         (directory? (directory-job? job)))
    (obj (cons "id" id)
         (cons "state" (assq-ref st 'state))
         (cons "bytes_done" (or (assq-ref st 'bytes-done) 0))
         (cons "bytes_total" (or (assq-ref st 'bytes-total) 0))
         (cons "speed" (exact->inexact (or (assq-ref st 'speed) 0)))
         (cons "files_done" (or (assq-ref st 'files-done) 0))
         (cons "files_total" (or (assq-ref st 'files-total) 0))
         (cons "kind" (if directory? "image" "llm"))
         (cons "source" (or (assq-ref st 'source) 'null))
         (cons "error" (or (assq-ref st 'error) 'null))
         (cons "verified" (and (assq-ref st 'verified) #t)))))

(define (khala-downloads)
  (with-mutex jobs-lock
    (map (lambda (entry) (download-status (car entry) (cdr entry)))
         (hash-map->list cons jobs))))

(define (khala-download-status id)
  (with-mutex jobs-lock
    (let ((job (hash-ref jobs id #f)))
      (and job (download-status id job)))))

(define (khala-start-download! config name)
  (let* ((llm-entry (ollama-catalog-entry name))
         (image-path "conf/image-catalog.scm")
         (image-entry
          (and (file-exists? image-path)
               (call-with-input-file image-path
                 (lambda (port)
                   (find (lambda (entry) (equal? (car entry) name)) (read port))))))
         (entry (or llm-entry image-entry)))
    (unless entry (throw 'artanis-err 404 'khala-download "Unknown catalog entry"))
    (with-mutex jobs-lock
      (let ((existing (hash-ref jobs name #f)))
        (if (and existing
                 (not (member (assq-ref (job-status existing) 'state)
                              terminal-states)))
            (download-status name existing)
            (let ((job (if image-entry
                           (start-directory-job (cdr entry)
                                                (config-ref config 'models_root))
                           (start-download-job (cdr entry) (ollama-llm-dir config)))))
              (hash-set! jobs name job)
              (download-status name job)))))))

(define (khala-cancel-download! id)
  (with-mutex jobs-lock
    (let ((job (hash-ref jobs id #f)))
      (unless job (throw 'artanis-err 404 'khala-cancel "Unknown download"))
      (if (directory-job? job) (cancel-directory-job! job) (cancel-job! job))
      (download-status id job))))

(define (read-catalog path)
  (if (file-exists? path) (call-with-input-file path read) '()))

(define (khala-catalog config)
  (append
   (map
    (lambda (entry)
      (let* ((body (cdr entry))
             (entry-path (assq-ref body 'path)))
        (obj (cons "name" (car entry))
             (cons "size" (or (assq-ref body 'size) 0))
             (cons "kind" "llm")
             (cons "installed"
                   (file-exists?
                    (string-append (ollama-llm-dir config) "/" entry-path))))))
    (read-catalog (or (getenv "KHALA_LLM_CATALOG") "conf/llm-catalog.scm")))
   (map
    (lambda (entry)
      (let* ((body (cdr entry))
             (license (ref body 'license))
             (target (string-append
                      (config-ref config 'models_root) "/"
                      (ref body 'folder) "/" (ref body 'directory))))
        (obj (cons "name" (car entry))
             (cons "display_name" (ref body 'display_name))
             (cons "size" 0)
             (cons "kind" "image")
             (cons "license" license)
             (cons "installed" (file-exists? target)))))
    (read-catalog "conf/image-catalog.scm"))))

(define (khala-system config)
  (obj (cons "engine" (config-ref config 'engine))
       (cons "version" "0.1.0")
       (cons "config"
             (obj (cons "port" (config-ref config 'port))
                  (cons "models_root" (config-ref config 'models_root))
                  (cons "mirror" (config-ref config 'mirror))
                  (cons "download_threads"
                        (config-ref config 'download_threads))))))

(define (khala-settings config)
  (obj (cons "mirror" (config-ref config 'mirror))
       (cons "download_threads" (config-ref config 'download_threads))
       (cons "enhance_model" (or (config-ref config 'enhance_model) ""))))

(define (config-file-path)
  (or (getenv "KHALA_CONFIG") "conf/khala.conf"))

(define (save-config-key! key value)
  (let* ((path (config-file-path))
         (lines (call-with-input-file path
                  (lambda (port) (let loop ((out '()))
                                   (let ((line (read-line port)))
                                     (if (eof-object? line) (reverse out)
                                         (loop (cons line out))))))))
         (key-prefix (string-append key " ="))
         (value-text (format #f "~a" value))
         (found #f)
         (updated
          (map (lambda (line)
                 (if (string-prefix? key-prefix line)
                     (begin (set! found #t)
                            (string-append key " = " value-text))
                     line))
               lines))
         (tmp (string-append path ".tmp")))
    (call-with-output-file tmp
      (lambda (port)
        (for-each (lambda (line) (display line port) (newline port))
                  (if found updated
                      (append updated
                              (list (string-append key " = " value-text)))))))
    (rename-file tmp path)))

(define (khala-save-settings! config payload)
  (let* ((mirror (assoc-ref payload "mirror"))
         (threads (assoc-ref payload "download_threads"))
         (enhance-model (assoc-ref payload "enhance_model")))
    (when (and mirror
               (not (member mirror '("auto" "huggingface" "hf-mirror"
                                     "modelscope"))))
      (throw 'artanis-err 400 'khala-settings "Invalid mirror"))
    (when (and threads
               (not (and (exact-integer? threads) (<= 1 threads 64))))
      (throw 'artanis-err 400 'khala-settings "Invalid download_threads"))
    (when (and enhance-model (not (string? enhance-model)))
      (throw 'artanis-err 400 'khala-settings "Invalid enhance_model"))
    (when mirror (save-config-key! "mirror" mirror))
    (when threads (save-config-key! "download_threads" threads))
    (when enhance-model (save-config-key! "enhance_model" enhance-model))
    (khala-settings (load-config))))
