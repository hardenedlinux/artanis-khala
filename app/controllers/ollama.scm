;; Ollama and OpenAI compatibility controller.

(define-artanis-controller ollama) ; DO NOT REMOVE THIS LINE!!!

(use-modules (artanis artanis)
             (artanis route)
             (artanis page)
             (rnrs bytevectors)
             (ice-9 rdelim)
             (ice-9 threads)
             (json)
             (srfi srfi-1)
             (srfi srfi-13)
             (srfi srfi-34)
             (app models ollama)
             (khala config)
             (khala json)
             (khala download))

(define (obj . fields) (make-json-object fields))
(define (emit-json value) (response-emit (json-encode value) #:headers '((content-type . (application/json)))))
(define (error-json message) (obj (cons "error" message)))
(define (read-request rc)
  (let ((body (rc-body rc)))
    (and body (json-string->scm (utf8->string body)))))
(define (write-line send value) (send (string-append (json-encode value) "\n")))
(define (generate-response config rc chat? openai?)
  (let* ((req (read-request rc))
         (model (or (and req (assoc-ref req "model")) ""))
         (messages (if chat? (or (and req (assoc-ref req "messages")) '())
                      (list `(("role" . "user")
                              ("content" . ,(or (and req (assoc-ref req "prompt")) ""))))))
         (stream? (not (and req (eq? #f (assoc-ref req "stream")))))
         (cancel? (make-parameter #f))
         (sonicboom?
          (equal? (config-ref config 'engine) "sonicboom"))
         (sonicboom-available?
          (and sonicboom?
               (catch #t
                 (lambda () (resolve-interface '(khala engine llm-sonicboom)) #t)
                 (lambda _ #f))))
         (engine-module
          (if (equal? (config-ref config 'engine) "sonicboom")
              '(khala engine llm-sonicboom)
              '(khala engine llm-fake))))
    (cond
     ((and sonicboom? (not sonicboom-available?))
      (response-emit
       (json-encode
        (obj (cons "error"
                   "SonicBoom engine not available: required Guile modules could not be loaded")))
       #:status 503 #:headers '((content-type . (application/json)))))
     ((string-null? model)
        (response-emit (json-encode (error-json "model is required")) #:status 400))
     (else
        (let* ((failure #f)   ; (status . message) once the engine has failed
               (producer
               (lambda (send)
                 (catch #t
                   (lambda ()
                     (let ((result
                            ((module-ref (resolve-interface engine-module) 'engine-chat)
                             model messages (or (and req (assoc-ref req "options")) (obj))
                             #:cancelled? (lambda () (cancel?))
                             #:on-token
                             (lambda (token)
                               (if (and openai? stream?)
                                   (send (string-append "data: " (json-encode
                                     (obj (cons "id" "chatcmpl-khala")
                                          (cons "object" "chat.completion.chunk")
                                          (cons "created" 0) (cons "model" model)
                                          (cons "choices" (list
                                            (obj (cons "index" 0)
                                                 (cons "delta" (obj (cons "content" token)))
                                                 (cons "finish_reason" 'null)))))) "\n\n"))
                                   (if openai? #t (write-line send
                                     (if chat?
                                         (obj (cons "model" model) (cons "created_at" (ollama-now-string))
                                              (cons "message" (obj (cons "role" "assistant")
                                                                   (cons "content" token)))
                                              (cons "done" #f))
                                         (obj (cons "model" model) (cons "created_at" (ollama-now-string))
                                              (cons "response" token) (cons "done" #f))))))))))
                       (ollama-loaded-model-set! model)
                       ;; A streamed reply has already been sent token by
                       ;; token: its closing message carries no text, or a
                       ;; client that appends every chunk shows it twice.
                       (let* ((text (if stream? "" (assoc-ref result 'text)))
                              (final (if chat?
                                (obj (cons "model" model) (cons "created_at" (ollama-now-string))
                                     (cons "message" (obj (cons "role" "assistant")
                                                          (cons "content" text)))
                                     (cons "done" #t) (cons "done_reason" "stop"))
                                (obj (cons "model" model) (cons "created_at" (ollama-now-string))
                                     (cons "response" text) (cons "done" #t)
                                     (cons "done_reason" "stop")))))
                         (for-each (lambda (key)
                           (set! final (make-json-object
                             (append (json-object-fields final)
                               (list (cons (symbol->string key) (assoc-ref result key)))))))
                           '(total_duration load_duration prompt_eval_count prompt_eval_duration
                             eval_count eval_duration))
                         (cond
                          ((and openai? stream?) (send "data: [DONE]\n\n"))
                          (openai?
                           (write-line send
                             (obj (cons "id" "chatcmpl-khala")
                                  (cons "object" "chat.completion") (cons "created" 0)
                                  (cons "model" model)
                                  (cons "choices" (list (obj (cons "index" 0)
                                    (cons "message" (obj (cons "role" "assistant")
                                                         (cons "content" (assoc-ref result 'text))))
                                    (cons "finish_reason" "stop"))))
                                  (cons "usage" (obj (cons "prompt_tokens" (assoc-ref result 'prompt_eval_count))
                                                     (cons "completion_tokens" (assoc-ref result 'eval_count))
                                                     (cons "total_tokens" (+ (assoc-ref result 'prompt_eval_count)
                                                                              (assoc-ref result 'eval_count))))))))
                          (else (write-line send final))))))
                   (lambda (key . args)
                     (if (eq? key 'artanis-err)
                         ;; An engine reports "cannot answer" as
                         ;; (artanis-err STATUS WHO MESSAGE). Answer with the
                         ;; message as JSON, as Ollama does, instead of the
                         ;; server's status page, which drops it.
                         (let ((message (format #f "~a" (last args))))
                           (set! failure (cons (car args) message))
                           (write-line send (obj (cons "error" message))))
                         (begin
                           (format (current-error-port)
                                   "Khala LLM request failed: ~s ~s~%" key args)
                           (cancel? #t))))))))
          (if stream?
              (response-emit-stream producer
                #:headers (if openai?
                              '((content-type . (text/event-stream)))
                              '((content-type . (application/x-ndjson))))
                #:on-close (lambda () (cancel? #t)))
              (let ((out (open-output-string)))
                (producer (lambda (part) (display part out)))
                (let* ((lines (filter (lambda (x) (not (string-null? x)))
                                      (string-split (get-output-string out) #\newline)))
                       (last-line (if (null? lines) "{}" (last lines))))
                  (response-emit last-line
                                 #:status (if failure (car failure) 200)
                                 #:headers '((content-type . (application/json))))))))))))

(define (register-ollama-routes! config)
  (get "/api/version" (lambda _ (emit-json (obj (cons "version" "0.1.0")))))
  (get "/api/tags" (lambda _ (emit-json (obj (cons "models" (ollama-model-entries config))))))
  (post "/api/show"
        (lambda (rc)
          (let* ((req (read-request rc)) (name (and req (assoc-ref req "model")))
                 (found (find (lambda (f) (equal? (ollama-model-name f) name))
                              (ollama-gguf-files config))))
            (if found (emit-json (obj (cons "modelfile" "") (cons "parameters" "")
                                      (cons "template" "") (cons "details" (obj))
                                      (cons "model_info" (obj)) (cons "capabilities" '("completion"))))
                (response-emit (json-encode (error-json "model not found")) #:status 404)))))
  (get "/api/ps" (lambda _ (emit-json (obj (cons "models"
    (if (ollama-loaded-model)
        (list (obj (cons "name" (ollama-loaded-model))
                   (cons "model" (ollama-loaded-model))
                   (cons "size" 0) (cons "digest" "")
                   (cons "expires_at" (ollama-now-string))
                   (cons "details" (obj))))
        '()))))))
  (post "/api/generate" (lambda (rc) (generate-response config rc #f #f)))
  (post "/api/chat" (lambda (rc) (generate-response config rc #t #f)))
  (post "/v1/chat/completions" (lambda (rc) (generate-response config rc #t #t)))
  (get "/v1/models" (lambda _ (emit-json (obj (cons "object" "list") (cons "data"
    (map (lambda (f) (obj (cons "id" (ollama-model-name f))
                          (cons "object" "model")
                          (cons "created" 0) (cons "owned_by" "khala")))
         (ollama-gguf-files config)))))))
  (post "/api/delete" (lambda (rc)
    (let* ((req (read-request rc)) (name (and req (assoc-ref req "model")))
           (file (find (lambda (f) (equal? (ollama-model-name f) name))
                       (ollama-gguf-files config))))
      (if file (begin (delete-file (string-append (ollama-llm-dir config) "/" file))
                      (emit-json (obj)))
          (response-emit (json-encode (error-json "model not found")) #:status 404)))))
  (post "/api/pull" (lambda (rc)
    (let* ((req (read-request rc)) (name (and req (assoc-ref req "model")))
           (entry (and name (ollama-catalog-entry name))))
      (if (not entry) (response-emit (json-encode (error-json "model not found in catalog")) #:status 404)
          (response-emit-stream
           (lambda (send)
             (let ((job (start-download-job (cdr entry) (ollama-llm-dir config))))
               (guard (ex
                       (#t
                        ;; A failed stream write means the client disconnected.
                        (cancel-job! job)
                        #t))
                 (let loop ()
                   (let* ((st (job-status job)) (state (assq-ref st 'state))
                          (done (or (assq-ref st 'bytes-done) 0))
                          (total (or (assq-ref st 'bytes-total) 0)))
                     (cond
                      ((equal? state "done")
                       (write-line send (obj (cons "status" "success"))))
                      ((member state '("failed" "cancelled"))
                       (write-line send (error-json (or (assq-ref st 'error) state))))
                      (else
                       (write-line send (obj (cons "status" "pulling model")
                                             (cons "digest" "")
                                             (cons "total" total) (cons "completed" done)))
                       (usleep 100000)
                       (loop))))))))
           #:headers '((content-type . (application/x-ndjson))))))))
  #t)

(register-ollama-routes! (load-config))
