;; Ollama/OpenAI compatibility model state.

(define-module (app models ollama)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 threads)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala json)
  #:use-module (khala config)
  #:export (ollama-llm-dir
            ollama-gguf-files
            ollama-model-name
            ollama-model-entries
            ollama-catalog-entry
            ollama-loaded-model
            ollama-loaded-model-set!
            ollama-now-string))

(define (obj . fields) (make-json-object fields))
(define (ollama-llm-dir config)
  (string-append (config-ref config 'models_root) "/llm"))
(define (ollama-gguf-files config)
  (let ((dir (ollama-llm-dir config)))
    (if (not (file-exists? dir))
        '()
        (filter (lambda (file) (string-suffix? ".gguf" file))
                (scandir dir (lambda (file)
                               (not (member file '("." "..")))))))))
(define (ollama-model-name file)
  (let* ((stem (substring file 0 (- (string-length file) 5)))
         (dash (string-index stem #\-)))
    (if dash
        (string-append (substring stem 0 dash) ":"
                       (substring stem (+ dash 1)))
        (string-append stem ":latest"))))
(define digest-cache (make-hash-table))
(define digest-lock (make-mutex))
(define (file-digest path)
  (with-mutex digest-lock
    (or (hash-ref digest-cache path #f)
        (let* ((port (open-pipe* OPEN_READ "sha256sum" path))
               (line (read-line port)))
          (close-pipe port)
          (let ((digest
                 (if (and (string? line) (>= (string-length line) 64))
                     (string-append "sha256:" (substring line 0 64))
                     "sha256:")))
            (hash-set! digest-cache path digest)
            digest)))))
(define loaded-model #f)
(define (ollama-loaded-model) loaded-model)
(define (ollama-loaded-model-set! value) (set! loaded-model value))
(define (ollama-now-string)
  (strftime "%Y-%m-%dT%H:%M:%SZ" (gmtime (current-time))))
(define (ollama-catalog-entry name)
  (let ((path (or (getenv "KHALA_LLM_CATALOG") "conf/llm-catalog.scm")))
    (and (file-exists? path)
         (call-with-input-file path
           (lambda (port)
             (find (lambda (entry) (equal? (car entry) name)) (read port)))))))
(define (model-entry config file)
  (let* ((path (string-append (ollama-llm-dir config) "/" file))
         (st (stat path)))
    (obj (cons "name" (ollama-model-name file))
         (cons "model" (ollama-model-name file))
         (cons "modified_at" (ollama-now-string))
         (cons "size" (stat:size st))
         (cons "digest" (file-digest path))
         (cons "details"
               (obj (cons "format" "gguf")
                    (cons "family" "unknown")
                    (cons "families" '("unknown"))
                    (cons "parameter_size" "unknown")
                    (cons "quantization_level" "unknown"))))))
(define (ollama-model-entries config)
  (map (lambda (file) (model-entry config file))
       (ollama-gguf-files config)))
