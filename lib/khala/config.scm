(define-module (khala config)
  #:use-module (ice-9 textual-ports)
  #:use-module (ice-9 rdelim)
  #:use-module (srfi srfi-13)
  #:export (load-config config-ref config-model-folders))

(define defaults
  '((port . 3000)
    (models_root . "models")
    (input_dir . "input")
    (output_dir . "output")
    (temp_dir . "temp")
    (user_dir . "var/user/default")
    (engine . "fake")
    (persist_history . #f)
    (persist_queue . #f)
    (history_db . "var/history.sqlite3")
    (extra_model_paths . "")
    (mirror . "auto")
    (download_threads . 4)
    (download_chunk_mib . 64)
    (mirror_probe_bytes . 4194304)
    (mirror_probe_timeout . 8)
    (mirror_cache_minutes . 30)))

(define (config-key text)
  (string->symbol (string-trim-both text)))

(define (parse-value key text)
  (let ((value (string-trim-both text)))
    (cond
     ((member key '(port download_threads download_chunk_mib mirror_probe_bytes
                         mirror_probe_timeout mirror_cache_minutes))
      (or (string->number value) 0))
     ((member key '(persist_history persist_queue))
      (and (member value '("yes" "true" "on")) #t))
     (else value))))

(define (load-config . maybe-path)
  (let ((path (if (null? maybe-path)
                  (or (getenv "KHALA_CONFIG") "conf/khala.conf")
                  (car maybe-path))))
    (if (not (file-exists? path))
        defaults
        (call-with-input-file path
          (lambda (port)
            (let loop ((result defaults))
              (let ((line (read-line port)))
                (if (eof-object? line)
                    result
                    (let* ((trimmed (string-trim-both line))
                           (split (string-index trimmed #\=)))
                      (if (or (string-null? trimmed)
                              (char=? (string-ref trimmed 0) #\#)
                              (not split))
                          (loop result)
                          (let* ((key (config-key (substring trimmed 0 split)))
                                 (value (parse-value key
                                                     (substring trimmed (+ split 1))))
                                 (old (assq key result)))
                            (loop (if old
                                      (map (lambda (entry)
                                             (if (eq? (car entry) key)
                                                 (cons key value) entry))
                                           result)
                                      (acons key value result))))))))))))))

(define (config-ref config key)
  (let ((entry (assq key config)))
    (if entry (cdr entry) #f)))

(define (config-model-folders)
  '("checkpoints" "diffusion_models" "unet" "text_encoders" "clip"
    "vae" "loras" "embeddings" "upscale_models"))
