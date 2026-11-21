(use-modules (khala config)
             ((khala studio persistence) #:prefix db:)
             ((khala studio providers) #:prefix provider:)
             ((khala studio secrets) #:prefix secret:)
             (app models studio)
             (ice-9 format)
             (json)
             (khala json)
             (srfi srfi-1)
             (srfi srfi-13))

(define db-path "/tmp/khala-studio-model-settings.sqlite3")
(define secrets-path "/tmp/khala-studio-model-settings-secrets.json")
(define assets-dir "/tmp/khala-studio-model-settings-assets")

(define (cleanup)
  (for-each (lambda (path)
              (when (file-exists? path) (delete-file path)))
            (list db-path secrets-path
                  (string-append db-path "-journal")
                  (string-append db-path "-wal")
                  (string-append db-path "-shm"))))

(define (check name condition)
  (unless condition (error "Studio model settings test failed" name))
  (format #t "ok ~a~%" name))

(define (api-error thunk)
  (catch 'studio-api-error
    (lambda () (thunk) #f)
    (lambda (key status code message details)
      (list status code message))))

(define (provider-error thunk)
  (catch 'studio-provider-error
    (lambda () (thunk) #f)
    (lambda (key code message details)
      (cons code message))))

(define (json-body request)
  (json-string->scm (assoc-ref request 'body)))

(define (object-ref object key)
  (and (list? object) (assoc-ref object key)))

(define (no-setting? value)
  (or (not value) (eq? value 'null) (equal? value "")))

(cleanup)
(define config
  (map (lambda (entry)
         (case (car entry)
           ((studio_db) (cons 'studio_db db-path))
           ((studio_secrets_file) (cons 'studio_secrets_file secrets-path))
           ((studio_assets_dir) (cons 'studio_assets_dir assets-dir))
           ((engine) (cons 'engine "fake"))
           ((studio_model) (cons 'studio_model "fake"))
           (else entry)))
       (load-config)))

(check 'fresh-schema (= 8 (db:studio-schema-version config)))

(define initial-settings (studio-model-settings config))
(define legacy-id (assoc-ref initial-settings "default_llm_profile_id"))
(check 'legacy-model-migrated
       (and legacy-id
            (= 1 (length (assoc-ref initial-settings "llm_profiles")))
            (equal? (assoc-ref (assoc-ref initial-settings "task_assignments")
                               "writing")
                    legacy-id)))

(define openai-profile
  (studio-create-model-profile!
   config
   (list (cons "name" "DeepSeek Author")
         (cons "provider" "deepseek")
         (cons "protocol" "openai-compatible")
         (cons "base_url" "https://api.deepseek.com/v1")
         (cons "model_id" "deepseek-chat")
         (cons "api_key" "sk-test-secret-1234")
         (cons "custom_headers" (list (cons "X-Trace" "studio")))
         (cons "timeout_seconds" 45)
         (cons "parameters" (list (cons "temperature" 0.4)
                                  (cons "max_output_tokens" 777)
                                  (cons "stream" #t)))
         (cons "capabilities" (list (cons "temperature" #t)
                                    (cons "top_p" #t)
                                    (cons "streaming" #t)
                                    (cons "json" #t)
                                    (cons "reasoning" #f))))))
(define openai-id (assoc-ref openai-profile "id"))
(check 'profile-key-not-returned
       (and (assoc-ref openai-profile "api_key_configured")
            (not (assoc-ref openai-profile "api_key"))
            (assoc-ref openai-profile "api_key_masked")))
(check 'secret-stored-outside-database
       (equal? (secret:studio-secret-get config (format #f "llm:~a" openai-id))
               "sk-test-secret-1234"))

(define updated-name
  (studio-update-model-profile! config openai-id
                                (list (cons "name" "DeepSeek Rewrite"))))
(check 'blank-key-update-preserves-secret
       (begin
         (studio-update-model-profile! config openai-id
                                       (list (cons "api_key" "")))
         (equal? (secret:studio-secret-get config
                                           (format #f "llm:~a" openai-id))
                 "sk-test-secret-1234")))

(define changed-model
  (studio-update-model-profile! config openai-id
                                (list (cons "model_id" "deepseek-reasoner")
                                      (cons "parameters"
                                            (list (cons "temperature" 1.4)
                                                  (cons "reasoning_effort" "high")))
                                      (cons "capabilities"
                                            (list (cons "reasoning" #t))))))
(check 'model-change-resets-special-parameters
       (and (= 0.7 (assoc-ref (assoc-ref changed-model "parameters")
                              "temperature"))
            (= 2048 (assoc-ref (assoc-ref changed-model "parameters")
                               "max_output_tokens"))
            (not (assoc-ref (assoc-ref changed-model "capabilities")
                            "reasoning"))))

(studio-update-model-profile!
 config openai-id
 (list (cons "parameters" (list (cons "temperature" 1.3)))))
(define changed-provider
  (studio-update-model-profile! config openai-id
                                (list (cons "provider" "siliconflow")
                                      (cons "parameters"
                                            (list (cons "temperature" 1.3))))))
(check 'provider-change-resets-special-parameters
       (= 0.7 (assoc-ref (assoc-ref changed-provider "parameters")
                         "temperature")))

(define settings-with-secret (studio-model-settings config))
(check 'settings-never-expose-secret
       (not (string-contains
             (json-encode (json-normalize settings-with-secret))
             "sk-test-secret-1234")))

(define fake-profile
  (studio-create-model-profile!
   config
   (list (cons "name" "Fake Story Engine")
         (cons "provider" "fake")
         (cons "protocol" "fake")
         (cons "base_url" "fake://local")
         (cons "model_id" "fake"))))
(define fake-id (assoc-ref fake-profile "id"))

(studio-update-model-routing!
 config
 (list (cons "default_profile_id" fake-id)
       (cons "tasks" (list (cons "writing" fake-id)
                           (cons "character_development" fake-id)
                           (cons "scene_extraction" fake-id)
                           (cons "storyboard_planning" fake-id)))))

(define workplace
  (db:studio-create-workplace! config (db:studio-new-id) "Model Test"
                               "Profile routing" "#713D3B" #f))
(define wid (assoc-ref workplace 'id))
(define other-workplace
  (db:studio-create-workplace! config (db:studio-new-id) "Other Model Test"
                               "Isolation" "#354B40" #f))
(define other-wid (assoc-ref other-workplace 'id))
(define document
  (db:studio-create-document! config (db:studio-new-id) wid #f
                              "chapter" "The Locked Workshop"
                              "Sera opened the door. The visitor waited in the rain."
                              "markdown" 0))
(define did (assoc-ref document 'id))

(define prepared
  (studio-prepare-ai config wid did
                     (list (cons "instruction" "Continue the scene."))
                     "continue"))
(check 'writing-task-routes-to-assigned-profile
       (equal? (assoc-ref prepared 'profile_id) fake-id))

(define character
  (db:studio-create-character!
   config (db:studio-new-id) wid "Sera Voss" "Mechanic"
   "A mechanic guarding her workshop." "{}"
   (json-encode (json-normalize
                 (list (cons "face" "Angular face with a burn scar.")
                       (cons "hair" "Dark hair tied back."))))
   "{}" "{}"))
(define cid (assoc-ref character 'id))

(define extracted
  (studio-extract-scene-draft
   config wid did
   (list (cons "expected_revision" 1)
         (cons "scope" "selection")
         (cons "selected_text" "Sera opened the door.")
         (cons "selection_start" 0)
         (cons "selection_end" 21))))
(check 'extraction-uses-fake-structured-output
       (and (equal? (assoc-ref extracted "title") "The Locked Workshop")
            (equal? (assoc-ref extracted "protocol") "fake")))
(check 'extraction-matches-existing-character
       (let* ((cast (assoc-ref extracted "cast"))
              (first (and (pair? cast) (car cast))))
         (and first (equal? (assoc-ref first "character_id") cid))))
(check 'extraction-records-source
       (let ((source (assoc-ref extracted "source")))
         (and (equal? (assoc-ref source "document_id") did)
              (= (assoc-ref source "document_revision") 1)
              (equal? (assoc-ref source "text") "Sera opened the door."))))

(define invalid-output
  (api-error
   (lambda ()
     (studio-validate-scene-extraction-json
      "{\"title\":\"Bad\",\"cast\":[],\"given_circumstances\":{}}" (list character)))))
(check 'invalid-extraction-schema-rejected
       (and invalid-output
            (= 502 (car invalid-output))
            (equal? (cadr invalid-output) "INVALID_AI_OUTPUT")))

(define unknown-field-output
  (api-error
   (lambda ()
     (studio-validate-scene-extraction-json
      (string-append
       "{\"title\":\"Bad\",\"summary\":\"\","
       "\"given_circumstances\":{\"time\":\"\",\"place\":\"\",\"environment\":\"\",\"background\":\"\",\"prior_events\":\"\"},"
       "\"dramatic_situation\":{\"central_question\":\"\",\"primary_conflict\":\"\",\"turn\":\"\"},"
       "\"dialogue\":\"\","
       "\"direction\":{\"blocking\":\"\",\"spatial\":\"\",\"performance_direction\":\"\",\"camera\":\"\"},"
       "\"cast\":[],\"unresolved_characters\":[],\"surprise\":true}")
      (list character)))))
(check 'unknown-extraction-field-rejected
       (and unknown-field-output
            (= 502 (car unknown-field-output))
            (equal? (cadr unknown-field-output) "INVALID_AI_OUTPUT")))

(define cast-body
  (map (lambda (entry)
         (list (cons "character_id" (assoc-ref entry "character_id"))
               (cons "objective" (assoc-ref entry "objective"))
               (cons "action" (assoc-ref entry "action"))
               (cons "conflict" (assoc-ref entry "conflict"))
               (cons "emotional_state" (assoc-ref entry "emotional_state"))
               (cons "performance_direction"
                     (assoc-ref entry "performance_direction"))
               (cons "subtext" (assoc-ref entry "subtext"))))
       (assoc-ref extracted "cast")))
(define source (assoc-ref extracted "source"))
(define confirmed
  (studio-confirm-scene-extraction!
   config wid did
   (list (cons "title" (assoc-ref extracted "title"))
         (cons "summary" (assoc-ref extracted "summary"))
         (cons "given_circumstances" (assoc-ref extracted "given_circumstances"))
         (cons "dramatic_situation" (assoc-ref extracted "dramatic_situation"))
         (cons "dialogue" (assoc-ref extracted "dialogue"))
         (cons "direction" (assoc-ref extracted "direction"))
         (cons "cast" cast-body)
         (cons "expected_revision" 1)
         (cons "source_text_snapshot" (assoc-ref source "text"))
         (cons "source_selection_start" (assoc-ref source "selection_start"))
         (cons "source_selection_end" (assoc-ref source "selection_end")))))
(define confirmed-scene (assoc-ref confirmed "scene"))
(define scene-id (assoc-ref confirmed-scene "id"))
(check 'confirmation-creates-scene-and-cast
       (and scene-id
            (= 1 (length (assoc-ref confirmed "cast")))))
(check 'confirmation-preserves-source-trace
       (and (equal? (assoc-ref confirmed-scene "source_document_id") did)
            (= (assoc-ref confirmed-scene "source_document_revision") 1)
            (equal? (assoc-ref confirmed-scene "source_text_snapshot")
                    "Sera opened the door.")))
(check 'document-scene-index
       (equal? (map (lambda (scene) (assoc-ref scene "id"))
                    (studio-list-document-scenes config wid did))
               (list scene-id)))

(define tampered-confirmation
  (api-error
   (lambda ()
     (studio-confirm-scene-extraction!
      config wid did
      (list (cons "title" "Tampered Source")
            (cons "expected_revision" 1)
            (cons "source_text_snapshot" "Not the saved source passage."))))))
(check 'confirmation-rejects-tampered-source
       (and tampered-confirmation
            (= 422 (car tampered-confirmation))
            (equal? (cadr tampered-confirmation) "INVALID_SELECTION")))

(define stale-confirmation
  (api-error
   (lambda ()
     (studio-confirm-scene-extraction!
      config wid did
      (list (cons "title" "Stale Source")
            (cons "expected_revision" 2)
            (cons "source_text_snapshot" "Sera opened the door."))))))
(check 'confirmation-rejects-stale-revision
       (and stale-confirmation
            (= 409 (car stale-confirmation))
            (equal? (cadr stale-confirmation) "REVISION_CONFLICT")))

(define other-character
  (db:studio-create-character!
   config (db:studio-new-id) other-wid "Ilyan Ro" "Visitor"
   "A visitor from another Workplace." "{}" "{}" "{}" "{}"))
(define cross-workplace
  (api-error
   (lambda ()
     (studio-confirm-scene-extraction!
      config wid did
      (list (cons "title" "Cross Workplace")
            (cons "expected_revision" 1)
            (cons "source_text_snapshot" "Sera opened the door.")
            (cons "cast" (list (list (cons "character_id"
                                            (assoc-ref other-character 'id))))))))))
(check 'scene-cast-cannot-cross-workplaces
       (and cross-workplace
            (= 422 (car cross-workplace))
            (equal? (cadr cross-workplace) "INVALID_CAST_CHARACTER")))

(define original-document (db:studio-get-document config wid did))
(check 'extraction-does-not-modify-source
       (and (= 1 (assoc-ref original-document 'revision))
            (equal? (assoc-ref original-document 'content)
                    "Sera opened the door. The visitor waited in the rain.")))

(define openai-profile-options
  (json-encode (json-normalize
                (list (cons "temperature" 0.4)
                      (cons "top_p" 0.8)
                      (cons "max_output_tokens" 321)
                      (cons "stream" #t)
                      (cons "format" "json")))))
(define openai-request
  (provider:studio-build-chat-request
   (list (cons 'protocol "openai-compatible")
         (cons 'base_url "https://example.test/v1")
         (cons 'model_id "custom/model-1")
         (cons 'api_key "secret-key")
         (cons 'custom_headers
               (json-encode (json-normalize
                             (list (cons "X-Trace" "yes")))))
         (cons 'parameters openai-profile-options)
         (cons 'capabilities
               (json-encode (json-normalize
                             (list (cons "temperature" #t)
                                   (cons "top_p" #t)
                                   (cons "streaming" #t)
                                   (cons "json" #t)
                                   (cons "reasoning" #f))))))
   (list (list (cons "role" "system") (cons "content" "System rule"))
         (list (cons "role" "user") (cons "content" "Write")))
   '(("temperature" . 0.9) ("max_output_tokens" . 99) ("stream" . #t)
     ("format" . "json"))))
(define openai-body (json-body openai-request))
(check 'openai-request-shape
       (and (equal? (assoc-ref openai-request 'url)
                    "https://example.test/v1/chat/completions")
            (equal? (assoc-ref openai-body "model") "custom/model-1")
            (= (assoc-ref openai-body "max_tokens") 99)
            (= (assoc-ref openai-body "temperature") 0.9)
            (equal? (assoc-ref openai-body "response_format")
                    '(("type" . "json_object")))))
(check 'openai-request-uses-secret-in-header
       (any (lambda (header) (string-contains header "Bearer secret-key"))
            (assoc-ref openai-request 'headers)))
(check 'openai-custom-header-kept
       (any (lambda (header) (string-contains header "X-Trace: yes"))
            (assoc-ref openai-request 'headers)))

(define unknown-capability-request
  (provider:studio-build-chat-request
   (list (cons 'protocol "openai-compatible")
         (cons 'base_url "https://example.test/v1")
         (cons 'model_id "unknown-model")
         (cons 'custom_headers "{}")
         (cons 'parameters "{}")
         (cons 'capabilities "{}"))
   (list (list (cons "role" "user") (cons "content" "Hello")))
   '(("temperature" . 0.9) ("top_p" . 0.4) ("stream" . #t))))
(define unknown-body (json-body unknown-capability-request))
(check 'unknown-capabilities-do-not-block-core-request
       (and (equal? (assoc-ref unknown-body "model") "unknown-model")
            (not (assoc-ref unknown-body "temperature"))
            (not (assoc-ref unknown-body "top_p"))
            (eq? (assoc-ref unknown-body "stream") #f)))

(define bounded-request
  (provider:studio-build-chat-request
   (list (cons 'protocol "openai-compatible")
         (cons 'base_url "https://example.test/v1")
         (cons 'model_id "bounded-model")
         (cons 'custom_headers "{}")
         (cons 'parameters "{}")
         (cons 'capabilities
               (json-encode (json-normalize
                             (list (cons "max_output_tokens" 50))))))
   (list (list (cons "role" "user") (cons "content" "Hello")))
   '(("max_output_tokens" . 99))))
(check 'known-max-output-capability-clamps-request
       (= 50 (assoc-ref (json-body bounded-request) "max_tokens")))

(define gemini-request
  (provider:studio-build-chat-request
   (list (cons 'protocol "gemini-native")
         (cons 'base_url "https://generativelanguage.googleapis.com/v1beta")
         (cons 'model_id "gemini-test")
         (cons 'api_key "gemini-key")
         (cons 'custom_headers "{}")
         (cons 'parameters "{}")
         (cons 'capabilities
               (json-encode (json-normalize
                             (list (cons "temperature" #t)
                                   (cons "json" #t))))))
   (list (list (cons "role" "system") (cons "content" "System rule"))
         (list (cons "role" "user") (cons "content" "Write")))
   '(("temperature" . 0.3) ("format" . "json"))))
(define gemini-body (json-body gemini-request))
(check 'gemini-request-shape
       (and (string-contains (assoc-ref gemini-request 'url)
                             "/models/gemini-test:generateContent")
            (equal? (assoc-ref (assoc-ref gemini-body "systemInstruction")
                               "parts")
                    (vector (list (cons "text" "System rule"))))
            (equal? (assoc-ref (assoc-ref gemini-body "generationConfig")
                               "responseMimeType")
                    "application/json")))

(define anthropic-request
  (provider:studio-build-chat-request
   (list (cons 'protocol "anthropic-messages")
         (cons 'base_url "https://api.anthropic.test/v1")
         (cons 'model_id "claude-test")
         (cons 'api_key "anthropic-key")
         (cons 'custom_headers "{}")
         (cons 'parameters "{}")
         (cons 'capabilities
               (json-encode (json-normalize
                             (list (cons "temperature" #t)
                                   (cons "json" #f))))))
   (list (list (cons "role" "system") (cons "content" "System rule"))
         (list (cons "role" "user") (cons "content" "Write")))
   '(("max_output_tokens" . 77) ("temperature" . 0.2))))
(define anthropic-body (json-body anthropic-request))
(check 'anthropic-request-shape
       (and (equal? (assoc-ref anthropic-request 'url)
                    "https://api.anthropic.test/v1/messages")
            (equal? (assoc-ref anthropic-body "system") "System rule")
            (= (assoc-ref anthropic-body "max_tokens") 77)))

(define embedding-request
  (provider:studio-build-embedding-request
   (list (cons 'protocol "openai-embeddings")
         (cons 'base_url "https://embedding.test/v1")
         (cons 'model_id "embedding-test")
         (cons 'api_key "embedding-key")
         (cons 'dimensions 3)
         (cons 'custom_headers "{}"))
   "hello"))
(define embedding-body (json-body embedding-request))
(check 'embedding-request-shape
       (and (equal? (assoc-ref embedding-request 'url)
                    "https://embedding.test/v1/embeddings")
            (= (assoc-ref embedding-body "dimensions") 3)
            (equal? (assoc-ref embedding-body "input") (vector "hello"))))
(check 'embedding-vector-validation
       (and (equal? (provider:studio-validate-embedding-vector
                     (list 0.1 0.2 0.3) 3)
                    (list 0.1 0.2 0.3))
            (let ((error (provider-error
                          (lambda ()
                            (provider:studio-validate-embedding-vector
                             (list 0.1 0.2 0.3) 4)))))
              (and error
                   (equal? (car error) "EMBEDDING_DIMENSION_MISMATCH")))))

(define embedding-profile
  (studio-create-embedding-profile!
   config
   (list (cons "name" "Embedding Test")
         (cons "provider" "custom")
         (cons "protocol" "openai-embeddings")
         (cons "base_url" "https://embedding.test/v1")
         (cons "model_id" "embedding-test")
         (cons "dimensions" 3)
         (cons "batch_size" 8)
         (cons "timeout_seconds" 30)
         (cons "api_key" "embedding-secret-9876"))))
(check 'embedding-profile-secret-masked
       (and (assoc-ref embedding-profile "api_key_configured")
            (not (assoc-ref embedding-profile "api_key"))))
(define embedding-id (assoc-ref embedding-profile "id"))
(define routed-settings
  (studio-update-model-routing!
   config
   (list (cons "default_embedding_profile_id" embedding-id))))
(check 'embedding-default-routing
       (equal? (assoc-ref routed-settings "default_embedding_profile_id")
               embedding-id))

(studio-update-embedding-profile! config embedding-id
                                  (list (cons "enabled" #f)))
(check 'disabled-embedding-clears-default
       (no-setting? (assoc-ref (studio-model-settings config)
                               "default_embedding_profile_id")))

(define disposable-profile
  (studio-create-model-profile!
   config
   (list (cons "name" "Disposable Routing")
         (cons "provider" "fake")
         (cons "protocol" "fake")
         (cons "base_url" "fake://local")
         (cons "model_id" "fake"))))
(define disposable-id (assoc-ref disposable-profile "id"))
(studio-update-model-routing!
 config
 (list (cons "default_profile_id" disposable-id)
       (cons "tasks" (list (cons "writing" disposable-id)))))
(studio-update-model-profile! config disposable-id
                              (list (cons "enabled" #f)))
(define disabled-routing (studio-model-settings config))
(check 'disabled-profile-clears-routing
       (and (no-setting? (assoc-ref disabled-routing "default_llm_profile_id"))
            (not (assoc-ref (assoc-ref disabled-routing "task_assignments")
                            "writing"))))

(check 'authorization-header-rejected-in-custom-headers
       (let ((error (api-error
                     (lambda ()
                       (studio-create-model-profile!
                        config
                        (list (cons "name" "Unsafe Header")
                              (cons "protocol" "openai-compatible")
                              (cons "base_url" "https://example.test/v1")
                              (cons "model_id" "model")
                              (cons "custom_headers"
                                    (list (cons "Authorization" "Bearer steal")))))))))
         (and error (= 400 (car error)))))

(studio-delete-model-profile! config openai-id)
(check 'deleted-profile-disappears
       (not (db:studio-get-model-profile config openai-id)))

(format #t "Studio model settings tests passed~%")
