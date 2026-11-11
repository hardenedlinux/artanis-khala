(define-module (khala engine llm-sonicboom)
  #:use-module (ice-9 format)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala config)
  #:use-module (khala json)
  #:export (engine-chat))

(define loaded-model #f)
(define loaded-path #f)
(define loaded-session #f)

(define (sonic-proc module name)
  (let ((entry (resolve-interface module)))
    (or (module-ref entry name)
        (error "SonicBoom procedure is unavailable" module name))))

(define (model-path model)
  (let* ((config (load-config))
         (dir (string-append (config-ref config 'models_root) "/llm"))
         ;; A catalog model "name:tag" is stored as "name-tag.gguf".
         (wanted (string-append (string-map (lambda (c) (if (char=? c #\:) #\- c))
                                            model)
                                ".gguf")))
    (and (file-exists? dir)
         (let ((files (scandir dir (lambda (name)
                                     (string-suffix? ".gguf" name)))))
           ;; The exact file first; only then any file of the same family,
           ;; so "qwen2.5:1.5b-..." never picks the 0.5b file beside it.
           (or (find (lambda (name) (string=? name wanted)) files)
               (find (lambda (name)
                       (string-prefix? (car (string-split model #\:)) name))
                     files))))))

(define (family arch)
  (cond ((string-contains arch "gemma") 'gemma)
        ((string-contains arch "qwen") 'qwen)
        (else (error "unsupported SonicBoom chat model architecture" arch))))

(define (option options key default)
  (let* ((name (if (symbol? key) (symbol->string key) key))
         (entry (and (list? options) (assoc name options))))
    (if entry (cdr entry) default)))

(define* (engine-chat model messages options #:key (on-token (lambda (_) #t))
                      (cancelled? (lambda () #f)))
  (catch #t
    (lambda ()
      (let* (;; A JSON request body decodes its message array to a vector;
             ;; SonicBoom's chat template takes a list.
             (messages (if (vector? messages) (vector->list messages) messages))
             (file (model-path model))
             (_ (unless file
                  (error "SonicBoom engine not available: model not found" model)))
             (path (string-append (string-append
                                   (config-ref (load-config) 'models_root) "/llm/")
                                  file))
             (inference '(sonicboom inference))
             (load-model (sonic-proc inference 'load-model))
             (make-session (sonic-proc inference 'make-session))
             (free-session! (sonic-proc inference 'free-session!))
             (free-model! (sonic-proc inference 'free-model!))
             (generate-stream (sonic-proc inference 'generate-stream))
             (tokenize-segments (sonic-proc inference 'tokenize-segments)))
        (when (or (not loaded-model) (not (equal? path loaded-path)))
          (when loaded-session (free-session! loaded-session))
          (when loaded-model (free-model! loaded-model))
          (set! loaded-model (load-model path))
          (set! loaded-session (make-session loaded-model 4096))
          (set! loaded-path path))
        (let* ((arch ((sonic-proc inference 'model-arch) loaded-model))
               (render (sonic-proc '(sonicboom serve chat-template)
                                   'render-chat-template-segments))
               (segments (render (family arch) messages))
               (prompt (tokenize-segments loaded-model segments))
               ;; The reply ends at one of the model's own end-of-sequence
               ;; tokens; generate-stream itself decodes up to the limit.
               (eos ((sonic-proc inference 'model-eos) loaded-model))
               (tokens 0)
               (chunks '())             ; reversed: the reply text so far
               (began (get-internal-real-time))
               ;; Constrained JSON is installed before generation. The
               ;; inference binding owns the schema compiler.
               (_ (when (equal? (option options "format" #f) "json")
                    ((sonic-proc inference 'set-json-schema!)
                     loaded-session "{\"type\":\"object\"}")))
               (_ (catch 'khala-end-of-turn
                    (lambda ()
                      (generate-stream
                       loaded-model loaded-session prompt
                       (or (option options "num_predict" #f) 256)
                       (lambda (token chunk)
                         (when (cancelled?) (throw 'khala-cancelled))
                         ;; An exception from this callback is how
                         ;; generate-stream is told to stop.
                         (when (and token (memv token eos))
                           (throw 'khala-end-of-turn))
                         (when token (set! tokens (+ tokens 1)))
                         (unless (string-null? chunk)
                           (set! chunks (cons chunk chunks))
                           (on-token chunk)))
                       #:temperature (or (option options "temperature" 0.0) 0.0)
                       #:top-p (or (option options "top_p" 1.0) 1.0)
                       #:top-k (or (option options "top_k" 0) 0)
                       #:seed (or (option options "seed" 0) 0)))
                    (lambda _ #t))))
          (let ((elapsed (* (- (get-internal-real-time) began)
                            (/ 1000000000 internal-time-units-per-second))))
            ;; The whole reply as text too: a non-streaming request has no
            ;; token callback to collect it from.
            `((text . ,(string-concatenate (reverse chunks)))
              (tokens . ,tokens) (total_duration . ,elapsed)
              (load_duration . 0) (prompt_eval_count . ,(length prompt))
              (prompt_eval_duration . 0) (eval_count . ,tokens)
              (eval_duration . ,elapsed) (done . ,(not (cancelled?))))))))
    (lambda (key . args)
      (if (eq? key 'khala-cancelled)
          `((text . "") (tokens . 0) (done . #f))
          (throw 'artanis-err 503 'llm-sonicboom
                 (format #f "SonicBoom engine not available: ~a ~s"
                         key args))))))
