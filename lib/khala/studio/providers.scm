;; Protocol adapters for Studio Model Profiles.
;;
;; This module constructs requests for the three explicitly supported LLM
;; protocols and the OpenAI-compatible embeddings protocol. It does not own
;; model selection: task routing and profile persistence live in the Studio
;; model. The fake protocol delegates to the existing Khala fake engine so all
;; automated tests exercise the same on-token contract as Writing.
(define-module (khala studio providers)
  #:use-module (curl)
  #:use-module (ice-9 format)
  #:use-module (ice-9 optargs)
  #:use-module (ice-9 textual-ports)
  #:use-module (json)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala engine llm-fake)
  #:use-module (khala json)
  #:export (studio-provider-presets
            studio-protocol-options
            studio-task-keys
            studio-json-object
            studio-json-object-ref
            studio-build-chat-request
            studio-build-embedding-request
            studio-chat-with-profile
            studio-embedding-with-profile
            studio-discover-profile-models
            studio-validate-embedding-vector))

(define (provider-fail code message . details)
  (throw 'studio-provider-error code message details))

(define (with-provider-errors thunk)
  (catch 'studio-provider-error
    thunk
    (lambda (key . args)
      (if (eq? key 'studio-provider-error)
          (apply provider-fail args)
          (apply throw key args)))))

(define (object? value) (and (list? value) (every pair? value)))
(define (object-ref object key)
  (and (object? object)
       (let* ((string-key (if (symbol? key) (symbol->string key) key))
              (entry (or (assoc key object) (assoc string-key object))))
         (and entry (cdr entry)))))

(define (json-object text)
  (if (and (string? text) (not (string-null? text)))
      (catch #t
        (lambda ()
          (let ((value (json-string->scm text)))
            (if (object? value) value '())))
        (lambda _ '()))
      '()))

(define (profile-object profile key)
  (let ((value (assoc-ref profile key)))
    (cond ((string? value) (json-object value))
          ((object? value) value)
          (else '()))))

(define (profile-string profile key default)
  (let ((value (assoc-ref profile key)))
    (if (and (string? value) (not (string-null? value))) value default)))

(define (json-scalar value)
  (cond ((or (string? value) (number? value) (boolean? value)) value)
        ((eq? value 'null) #f)
        (else value)))

(define (object-set object key value)
  (cons (cons key (json-scalar value))
        (filter (lambda (entry) (not (equal? (car entry) key))) object)))

(define (header-pair name value)
  (format #f "~a: ~a" name value))

(define (safe-header? name value)
  (and (string? name) (string? value)
       (not (string-index name #\newline))
       (not (string-index name #\return))
       (not (string-index value #\newline))
       (not (string-index value #\return))))

(define (profile-headers profile)
  (let ((headers (profile-object profile 'custom_headers)))
    (filter (lambda (entry) (safe-header? (car entry) (cdr entry)))
            headers)))

(define (request-headers profile base)
  (append
   base
   (map (lambda (entry) (header-pair (car entry) (cdr entry)))
        (profile-headers profile))))

(define (join-url base suffix)
  (let loop ((end (string-length base)))
    (if (and (> end 0) (char=? (string-ref base (- end 1)) #\/))
        (loop (- end 1))
        (string-append (substring base 0 end) suffix))))

(define (parameter-value parameters options keys)
  (let loop ((keys keys))
    (if (null? keys)
        #f
        (let* ((key (car keys))
               (option-entry (and (list? options) (assoc key options)))
               (parameter-entry (and (object? parameters) (assoc key parameters))))
          (cond ((and option-entry (not (eq? (cdr option-entry) 'null)))
                 (cdr option-entry))
                ((and parameter-entry (not (eq? (cdr parameter-entry) 'null)))
                 (cdr parameter-entry))
                (else (loop (cdr keys))))))))

(define (capability? capabilities key)
  (eq? (object-ref capabilities key) #t))

(define (send-parameter? capabilities parameters options key aliases)
  (and (capability? capabilities key)
       (parameter-value parameters options aliases)))

(define (strip-null-fields object)
  (filter (lambda (entry) (not (eq? (cdr entry) 'null))) object))

(define (capability-limit profile key)
  (let ((value (object-ref (profile-object profile 'capabilities) key)))
    (and (integer? value) (> value 0) value)))

(define (bounded-max-tokens profile value)
  (let ((limit (capability-limit profile "max_output_tokens")))
    (cond ((not value) limit)
          ((and limit (> value limit)) limit)
          (else value))))

(define studio-task-keys
  '("writing" "character_development" "scene_extraction" "storyboard_planning"))

(define studio-protocol-options
  '(("openai-compatible"
     (label . "OpenAI Chat Completions Compatible")
     (supports_model_list . #t)
     (supports_streaming . #t)
     (supports_json . #t))
    ("gemini-native"
     (label . "Google Gemini Native")
     (supports_model_list . #t)
     (supports_streaming . #t)
     (supports_json . #t))
    ("anthropic-messages"
     (label . "Anthropic Messages")
     (supports_model_list . #f)
     (supports_streaming . #t)
     (supports_json . #f))
    ("fake"
     (label . "Fake Engine (testing)")
     (supports_model_list . #t)
     (supports_streaming . #t)
     (supports_json . #t))))

(define studio-provider-presets
  `(("openai" (name . "OpenAI") (protocol . "openai-compatible")
     (base_url . "https://api.openai.com/v1") (model_id . ""))
    ("deepseek" (name . "DeepSeek") (protocol . "openai-compatible")
     (base_url . "https://api.deepseek.com/v1") (model_id . "deepseek-chat"))
    ("siliconflow" (name . "SiliconFlow") (protocol . "openai-compatible")
     (base_url . "https://api.siliconflow.cn/v1") (model_id . ""))
    ("bigmodel" (name . "BigModel / Zhipu") (protocol . "openai-compatible")
     (base_url . "https://open.bigmodel.cn/api/paas/v4") (model_id . "glm-4-flash"))
    ("xai" (name . "xAI") (protocol . "openai-compatible")
     (base_url . "https://api.x.ai/v1") (model_id . ""))
    ("openrouter" (name . "OpenRouter") (protocol . "openai-compatible")
     (base_url . "https://openrouter.ai/api/v1") (model_id . ""))
    ("ollama" (name . "Ollama (local)") (protocol . "openai-compatible")
     (base_url . "http://127.0.0.1:11434/v1") (model_id . ""))
    ("lmstudio" (name . "LM Studio (local)") (protocol . "openai-compatible")
     (base_url . "http://127.0.0.1:1234/v1") (model_id . ""))
    ("gemini" (name . "Google Gemini") (protocol . "gemini-native")
     (base_url . "https://generativelanguage.googleapis.com/v1beta")
     (model_id . ""))
    ("anthropic" (name . "Anthropic") (protocol . "anthropic-messages")
     (base_url . "https://api.anthropic.com/v1") (model_id . ""))
    ("custom-openai" (name . "Custom OpenAI-compatible")
     (protocol . "openai-compatible") (base_url . "") (model_id . ""))
    ("custom-gemini" (name . "Custom Gemini-compatible")
     (protocol . "gemini-native") (base_url . "") (model_id . ""))
    ("custom-anthropic" (name . "Custom Anthropic-compatible")
     (protocol . "anthropic-messages") (base_url . "") (model_id . ""))
    ("fake" (name . "Fake Engine") (protocol . "fake")
     (base_url . "fake://local") (model_id . "fake"))))

(define (system-message? message)
  (equal? (object-ref message "role") "system"))

(define (message-content message)
  (let ((content (object-ref message "content")))
    (if (string? content) content "")))

(define (openai-chat-body profile messages options stream?)
  (let* ((parameters (profile-object profile 'parameters))
         (capabilities (profile-object profile 'capabilities))
         (body (list (cons "model" (profile-string profile 'model_id ""))
                     (cons "messages" (map (lambda (message)
                                             `(("role" . ,(object-ref message "role"))
                                               ("content" . ,(message-content message))))
                                           messages))
                     (cons "stream" stream?)))
         (max-tokens (bounded-max-tokens
                      profile
                      (parameter-value parameters options
                                       '("max_tokens" "num_predict" "max_output_tokens"))))
         (temperature (parameter-value parameters options '("temperature")))
         (top-p (parameter-value parameters options '("top_p")))
         (json? (and (profile-object profile 'capabilities)
                     (capability? capabilities 'json)
                     (equal? (parameter-value parameters options '("format")) "json"))))
    (when (and max-tokens (> max-tokens 0))
      (set! body (object-set body "max_tokens" max-tokens)))
    (when (and temperature (capability? capabilities 'temperature))
      (set! body (object-set body "temperature" temperature)))
    (when (and top-p (capability? capabilities 'top_p))
      (set! body (object-set body "top_p" top-p)))
    (when json?
      (set! body (object-set body "response_format" `(("type" . "json_object")))))
    (let ((reasoning (parameter-value parameters options '("reasoning_effort"))))
      (when (and reasoning (capability? capabilities 'reasoning))
        (set! body (object-set body "reasoning_effort" reasoning))))
    body))

(define (gemini-chat-body profile messages options)
  (let* ((parameters (profile-object profile 'parameters))
         (capabilities (profile-object profile 'capabilities))
         (contents
          (map (lambda (message)
                 `(("role" . ,(if (system-message? message) "user"
                                  (if (equal? (object-ref message "role") "assistant")
                                      "model" "user")))
                   ("parts" . ,(list `(("text" . ,(message-content message)))))))
               messages))
         (generation (list))
         (temperature (parameter-value parameters options '("temperature")))
         (top-p (parameter-value parameters options '("top_p")))
         (max-tokens (bounded-max-tokens
                      profile
                      (parameter-value parameters options
                                       '("max_tokens" "num_predict" "max_output_tokens"))))
         (json? (and (capability? capabilities 'json)
                     (equal? (parameter-value parameters options '("format")) "json"))))
    (when (and temperature (capability? capabilities 'temperature))
      (set! generation (object-set generation "temperature" temperature)))
    (when (and top-p (capability? capabilities 'top_p))
      (set! generation (object-set generation "topP" top-p)))
    (when (and max-tokens (> max-tokens 0))
      (set! generation (object-set generation "maxOutputTokens" max-tokens)))
    (when json?
      (set! generation (object-set generation "responseMimeType" "application/json")))
    (let ((system (string-join (filter-map
                                (lambda (message)
                                  (and (system-message? message)
                                       (message-content message)))
                                messages)
                               "\n\n")))
      (append
       (list (cons "contents"
                   (filter (lambda (message) (not (system-message? message)))
                           contents)))
       (if (string-null? system)
           '()
           (list (cons "systemInstruction"
                       `(("parts" . ,(list `(("text" . ,system))))))))
       (if (null? generation)
           '()
           (list (cons "generationConfig" generation)))))))

(define (anthropic-chat-body profile messages options stream?)
  (let* ((parameters (profile-object profile 'parameters))
         (capabilities (profile-object profile 'capabilities))
         (max-tokens (or (bounded-max-tokens
                          profile
                          (parameter-value parameters options
                                           '("max_tokens" "num_predict" "max_output_tokens")))
                         1024))
         (temperature (parameter-value parameters options '("temperature")))
         (top-p (parameter-value parameters options '("top_p")))
         (body (list (cons "model" (profile-string profile 'model_id ""))
                     (cons "max_tokens" max-tokens)
                     (cons "stream" stream?)
                     (cons "messages"
                           (map (lambda (message)
                                  `(("role" . ,(object-ref message "role"))
                                    ("content" . ,(message-content message))))
                                (filter (lambda (message)
                                          (not (system-message? message)))
                                        messages)))))
         (system (string-join (filter-map
                               (lambda (message)
                                 (and (system-message? message)
                                      (message-content message)))
                               messages)
                              "\n\n")))
    (unless (string-null? system)
      (set! body (object-set body "system" system)))
    (when (and temperature (capability? capabilities 'temperature))
      (set! body (object-set body "temperature" temperature)))
    (when (and top-p (capability? capabilities 'top_p))
      (set! body (object-set body "top_p" top-p)))
    body))

(define* (studio-build-chat-request profile messages options)
  (let* ((protocol (profile-string profile 'protocol "openai-compatible"))
         (base (profile-string profile 'base_url ""))
         (model (profile-string profile 'model_id ""))
         (api-key (profile-string profile 'api_key ""))
         (capabilities (profile-object profile 'capabilities))
         (stream? (and (capability? capabilities 'streaming)
                       (equal? (parameter-value (profile-object profile 'parameters)
                                                options '("stream"))
                               #t)))
         (common '("content-type: application/json" "accept: application/json")))
    (cond
     ((equal? protocol "fake")
      `((protocol . "fake") (model . ,model) (stream . #f)
        (messages . ,messages) (options . ,options)))
     ((equal? protocol "openai-compatible")
      (let ((headers (request-headers
                      profile
                      (append common
                              (if (string-null? api-key) '()
                                  (list (header-pair "authorization"
                                                     (string-append "Bearer " api-key))))))))
        `((protocol . "openai-compatible")
          (method . "POST")
          (url . ,(join-url base "/chat/completions"))
          (headers . ,headers)
          (body . ,(json-encode
                    (json-normalize
                     (openai-chat-body profile messages options stream?))))
          (stream . ,stream?)
          (model . ,model))))
     ((equal? protocol "gemini-native")
      (let ((headers (request-headers
                      profile
                      (append common
                              (if (string-null? api-key) '()
                                  (list (header-pair "x-goog-api-key" api-key)))))))
        `((protocol . "gemini-native")
          (method . "POST")
          (url . ,(string-append
                   (join-url base (string-append "/models/" model
                                                 (if stream?
                                                     ":streamGenerateContent?alt=sse"
                                                     ":generateContent")))))
          (headers . ,headers)
          (body . ,(json-encode
                    (json-normalize
                     (gemini-chat-body profile messages options))))
          (stream . ,stream?)
          (model . ,model))))
     ((equal? protocol "anthropic-messages")
      (let ((headers (request-headers
                      profile
                      (append common
                              (list "anthropic-version: 2023-06-01")
                              (if (string-null? api-key) '()
                                  (list (header-pair "x-api-key" api-key)))))))
        `((protocol . "anthropic-messages")
          (method . "POST")
          (url . ,(join-url base "/messages"))
          (headers . ,headers)
          (body . ,(json-encode
                    (json-normalize
                     (anthropic-chat-body profile messages options stream?))))
          (stream . ,stream?)
          (model . ,model))))
     (else
      (provider-fail "PROTOCOL_ERROR"
                     (format #f "Unsupported model protocol: ~a" protocol))))))

(define* (studio-build-embedding-request profile text #:key (dimensions #f))
  (let* ((base (profile-string profile 'base_url ""))
         (model (profile-string profile 'model_id ""))
         (api-key (profile-string profile 'api_key ""))
         (headers (request-headers
                   profile
                   (append '("content-type: application/json")
                           (if (string-null? api-key) '()
                               (list (header-pair "authorization"
                                                  (string-append "Bearer " api-key)))))))
         (body (list (cons "model" model) (cons "input" (if (list? text) text (list text)))))
         (dimensions (or dimensions (assoc-ref profile 'dimensions))))
    (when (and dimensions (> dimensions 0))
      (set! body (object-set body "dimensions" dimensions)))
    `((method . "POST")
      (url . ,(join-url base "/embeddings"))
      (headers . ,headers)
      (body . ,(json-encode (json-normalize body)))
      (model . ,model))))

(define (response-text value)
  (cond ((string? value) value)
        ((bytevector? value) (utf8->string value))
        (else "")))

(define (http-error-message text)
  (catch #t
    (lambda ()
      (let* ((value (json-string->scm text))
             (error (or (object-ref value "error") value))
             (message (or (object-ref error "message")
                          (object-ref value "message"))))
        (and (string? message) (substring message 0 (min 300 (string-length message))))))
    (lambda _ #f)))

(define* (studio-http-json request #:key (accept 200))
  (let ((handle (curl-easy-init)))
    (dynamic-wind
      (lambda ()
        (curl-easy-setopt handle 'url (assoc-ref request 'url))
        (curl-easy-setopt handle 'followlocation #t)
        (curl-easy-setopt handle 'connecttimeout
                          (or (assoc-ref request 'connect_timeout) 15))
        (curl-easy-setopt handle 'timeout
                          (or (assoc-ref request 'timeout) 60))
        (curl-easy-setopt handle 'httpheader (or (assoc-ref request 'headers) '()))
        (curl-easy-setopt handle 'useragent "Khala-Studio/1")
        (when (assoc-ref request 'body)
          (curl-easy-setopt handle 'post #t)
          (curl-easy-setopt handle 'postfields (assoc-ref request 'body))))
      (lambda ()
        (let ((body (curl-easy-perform handle #t))
              (code (curl-easy-getinfo handle 'response-code)))
          (let ((text (response-text body)))
            (cond
             ((not (and (integer? code) (> code 0)))
              (provider-fail "NETWORK_ERROR"
                             (or (curl-error-string) "Provider network request failed")))
             ((= code 401) (provider-fail "AUTHENTICATION_FAILED" "Provider rejected the API key"))
             ((= code 403) (provider-fail "AUTHENTICATION_FAILED" "Provider denied access"))
             ((= code 404) (provider-fail "MODEL_NOT_FOUND" "Provider model or endpoint was not found"))
             ((= code 429) (provider-fail "RATE_LIMITED" "Provider rate limit reached"))
             ((>= code 500) (provider-fail "PROVIDER_ERROR"
                                            (or (http-error-message text)
                                                "Provider server error")))
             ((not (member code accept))
              (provider-fail "PROTOCOL_ERROR"
                             (or (http-error-message text)
                                 (format #f "Provider returned HTTP ~a" code))))
             (else (cons code text))))))
      (lambda () (catch #t (lambda () (curl-easy-cleanup handle)) (lambda _ #f))))))

(define (parse-sse text on-token)
  (let ((tokens '()))
    (for-each
     (lambda (block)
       (let ((data (string-join
                    (filter-map
                     (lambda (line)
                       (and (string-prefix? "data:" line)
                            (string-trim-both (substring line 5))))
                     (string-split block #\newline))
                    "\n")))
         (unless (or (string-null? data) (equal? data "[DONE]"))
           (let ((value (json-string->scm data)))
             (on-token value)))))
     (string-split (string-trim text) #\newline))
    (reverse tokens)))

(define (openai-stream-text value)
  (let* ((choices (object-ref value "choices"))
         (choice (and (list? choices) (pair? choices) (car choices)))
         (delta (and choice (object-ref choice "delta"))))
    (or (and delta (object-ref delta "content"))
        (let ((message (and choice (object-ref choice "message"))))
          (and message (object-ref message "content")))
        "")))

(define (gemini-stream-text value)
  (let* ((candidates (object-ref value "candidates"))
         (candidate (and (list? candidates) (pair? candidates) (car candidates)))
         (content (and candidate (object-ref candidate "content")))
         (parts (and content (object-ref content "parts"))))
    (if (list? parts)
        (string-append
         (string-join (filter-map (lambda (part) (object-ref part "text")) parts) ""))
        "")))

(define (anthropic-stream-text value)
  (let ((delta (object-ref value "delta")))
    (or (and delta (object-ref delta "text")) "")))

(define (openai-message-text value)
  (let* ((choices (object-ref value "choices"))
         (choice (and (list? choices) (pair? choices) (car choices)))
         (message (and choice (object-ref choice "message"))))
    (or (and message (object-ref message "content")) "")))

(define (anthropic-message-text value)
  (let ((content (object-ref value "content")))
    (if (list? content)
        (string-join
         (filter-map (lambda (block) (and (equal? (object-ref block "type") "text")
                                          (object-ref block "text")))
                     content)
         "")
        "")))

(define (usage-number value keys)
  (let loop ((keys keys))
    (if (null? keys) 0
        (let ((number (object-ref value (car keys))))
          (if (number? number) number (loop (cdr keys)))))))

(define (fake-chat profile messages options on-token cancelled?)
  (let ((result (engine-chat (profile-string profile 'model_id "fake")
                             messages options
                             #:on-token on-token
                             #:cancelled? cancelled?)))
    `((text . ,(or (assoc-ref result 'text) ""))
      (prompt_tokens . ,(or (assoc-ref result 'prompt_eval_count) 0))
      (completion_tokens . ,(or (assoc-ref result 'eval_count) 0))
      (done . ,(assoc-ref result 'done)))))

(define* (studio-chat-with-profile profile messages options
                                   #:key (on-token (lambda (_) #t))
                                   (cancelled? (lambda () #f)))
  (let* ((request (studio-build-chat-request profile messages options))
         (protocol (assoc-ref request 'protocol)))
    (if (equal? protocol "fake")
        (fake-chat profile messages options on-token cancelled?)
        (let* ((request (append request
                                `((timeout . ,(or (assoc-ref profile 'timeout_seconds) 60))
                                  (connect_timeout . 15))))
               (response (studio-http-json request))
               (text (cdr response)))
          (with-provider-errors
            (lambda ()
              (if (assoc-ref request 'stream)
                  (let ((collected '()))
                    (parse-sse
                     text
                     (lambda (value)
                       (unless (cancelled?)
                         (let ((token
                                (case (string->symbol protocol)
                                  ((openai-compatible) (openai-stream-text value))
                                  ((gemini-native) (gemini-stream-text value))
                                  ((anthropic-messages) (anthropic-stream-text value))
                                  (else ""))))
                           (unless (string-null? token)
                             (set! collected (cons token collected))
                             (on-token token))))))
                    `((text . ,(string-concatenate (reverse collected)))
                      (prompt_tokens . 0) (completion_tokens . ,(length collected))
                      (done . ,(not (cancelled?))))))
                  (let* ((value (json-string->scm text))
                         (content
                          (case (string->symbol protocol)
                            ((openai-compatible) (openai-message-text value))
                            ((gemini-native) (gemini-stream-text value))
                            ((anthropic-messages) (anthropic-message-text value))
                            (else ""))))
                    (unless (string-null? content) (on-token content))
                    `((text . ,content)
                      (prompt_tokens . ,(usage-number value
                                                       '("prompt_tokens" "promptTokenCount"
                                                         "input_tokens")))
                      (completion_tokens . ,(usage-number value
                                                           '("completion_tokens"
                                                             "candidatesTokenCount"
                                                             "output_tokens")))
                      (done . ,(not (cancelled?)))))))))))

(define (validate-vector value dimensions)
  (unless (and (list? value) (pair? value))
    (provider-fail "EMBEDDING_INVALID"
                   "Embedding response did not contain a vector"))
  (unless (every number? value)
    (provider-fail "EMBEDDING_INVALID"
                   "Embedding vector contains non-numeric values"))
  (when (and dimensions (> dimensions 0) (not (= (length value) dimensions)))
    (provider-fail "EMBEDDING_DIMENSION_MISMATCH"
                   (format #f "Expected embedding dimension ~a, received ~a"
                           dimensions (length value))))
  value)

(define (studio-validate-embedding-vector value dimensions)
  (validate-vector value dimensions))

(define* (studio-embedding-with-profile profile text
                                        #:key (dimensions #f) (on-token #f))
  (let* ((request (studio-build-embedding-request profile text
                                                   #:dimensions dimensions))
         (response (studio-http-json
                    (append request
                            `((timeout . ,(or (assoc-ref profile 'timeout_seconds) 60))
                              (connect_timeout . 15)))))
         (value (json-string->scm (cdr response)))
         (data (object-ref value "data"))
         (first (and (list? data) (pair? data) (car data)))
         (vector (and first (object-ref first "embedding")))
         (actual-model (or (object-ref value "model")
                           (assoc-ref profile 'model_id) "")))
    `((model . ,actual-model)
      (dimensions . ,(length (validate-vector vector (or dimensions 0))))
      (vector . ,vector))))

(define* (studio-discover-profile-models profile #:key (timeout 20))
  (let ((protocol (profile-string profile 'protocol "openai-compatible"))
        (base (profile-string profile 'base_url ""))
        (api-key (profile-string profile 'api_key "")))
    (cond
     ((equal? protocol "fake")
      (list '(("id" . "fake") ("name" . "fake"))))
     ((equal? protocol "anthropic-messages")
      (provider-fail "MODEL_DISCOVERY_UNSUPPORTED"
                     "Anthropic model discovery is not supported; enter the model ID manually"))
     (else
      (let* ((url (if (equal? protocol "gemini-native")
                      (join-url base "/models")
                      (join-url base "/models")))
             (headers (request-headers
                       profile
                       (append '("accept: application/json")
                               (cond
                                ((string-null? api-key) '())
                                ((equal? protocol "gemini-native")
                                 (list (header-pair "x-goog-api-key" api-key)))
                                (else
                                 (list (header-pair "authorization"
                                                    (string-append "Bearer " api-key))))))))
             (response (studio-http-json `((url . ,url) (headers . ,headers)
                                           (timeout . ,timeout))))
             (value (json-string->scm (cdr response)))
             (entries (or (object-ref value "data") (object-ref value "models") '())))
        (map (lambda (entry)
               (let ((id (or (object-ref entry "id")
                             (object-ref entry "name") "")))
                 (when (and (equal? protocol "gemini-native")
                            (string-prefix? "models/" id))
                   (set! id (substring id 7)))
                 `(("id" . ,id)
                   ("name" . ,(or (object-ref entry "displayName") id)))))
             (if (list? entries) entries '())))))))
