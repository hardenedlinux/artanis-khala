;; Studio writing API model: validation, document transformation, and the
;; existing Khala LLM adapter dispatch.

(define-module (app models studio)
  #:use-module (ice-9 format)
  #:use-module (ice-9 optargs)
  #:use-module (ice-9 textual-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (web uri)
  #:use-module (app models comfy)
  #:use-module (app models ollama)
  #:use-module (khala config)
  #:use-module (khala engine)
  #:use-module (khala json)
  #:use-module (khala png)
  #:use-module ((khala studio assets) #:prefix fs:)
  #:use-module ((khala studio persistence) #:prefix db:)
  #:use-module ((khala studio providers) #:prefix provider:)
  #:use-module ((khala studio secrets) #:prefix secret:)
  #:export (studio-capabilities
            studio-create-demo!
            studio-acceptance-overview
            studio-run-acceptance!
            studio-list-workplaces
            studio-create-workplace!
            studio-get-workplace
            studio-update-workplace!
            studio-list-characters
            studio-create-character!
            studio-get-character
            studio-update-character!
            studio-archive-character!
            studio-list-character-drafts
            studio-develop-character!
            studio-update-character-draft!
            studio-apply-character-draft!
            studio-discard-character-draft!
            studio-list-character-outfits
            studio-create-character-outfit!
            studio-get-character-outfit
            studio-update-character-outfit!
            studio-archive-character-outfit!
            studio-set-default-character-outfit!
            studio-set-character-outfit-reference!
            studio-character-artwork-prompt
            studio-list-character-artworks
            studio-generate-character-artwork!
            studio-set-character-avatar!
            studio-set-character-full-body!
            studio-character-canon
            studio-list-scenes
            studio-create-scene!
            studio-get-scene
            studio-update-scene!
            studio-delete-scene!
            studio-set-scene-references!
            studio-list-scene-cast
            studio-update-scene-cast!
            studio-get-storyboard
            studio-create-storyboard!
            studio-update-storyboard!
            studio-validate-storyboard-json
            studio-generate-storyboard-image!
            studio-list-assets
            studio-create-asset!
            studio-get-asset
            studio-update-asset!
            studio-delete-asset!
            studio-create-uploaded-asset!
            studio-list-asset-links
            studio-add-asset-link!
            studio-remove-asset-link!
            studio-list-resource-assets
            studio-asset-file-info
            studio-list-documents
            studio-create-document!
            studio-get-document
            studio-update-document!
            studio-list-versions
            studio-create-version!
            studio-get-version
            studio-restore-version!
            studio-inspire
            studio-prepare-ai
            studio-run-ai
            studio-model-settings
            studio-create-model-profile!
            studio-update-model-profile!
            studio-delete-model-profile!
            studio-test-model-profile!
            studio-discover-model-profile-models
            studio-update-model-routing!
            studio-create-embedding-profile!
            studio-update-embedding-profile!
            studio-delete-embedding-profile!
            studio-test-embedding-profile!
            studio-extract-scene-draft
            studio-validate-scene-extraction-json
            studio-confirm-scene-extraction!
            studio-list-document-scenes))

(define max-content-length 2000000)
(define max-title-length 512)
(define max-description-length 4000)
(define max-context-length 20000)
(define max-instruction-length 4000)
(define max-label-length 500)
(define max-character-role-length 256)
(define max-identity-field-length 20000)
(define max-scene-text-length 500000)
(define max-profile-name-length 256)
(define max-model-id-length 512)
(define max-base-url-length 2048)
(define max-api-key-length 4096)
(define max-profile-json-length 32000)
(define max-extraction-source-length 2000000)
(define max-extraction-characters 60)

(define model-protocols
  '("openai-compatible" "gemini-native" "anthropic-messages" "fake"))
(define embedding-protocols '("openai-embeddings"))
(define model-task-keys
  '("writing" "character_development" "scene_extraction" "storyboard_planning"))

(define scene-statuses '("draft" "ready" "final"))
(define scene-detail-fields
  '("summary" "sort_order" "status"
    "time" "place" "environment" "background" "prior_events"
    "central_question" "primary_conflict" "turn"
    "dialogue" "blocking" "spatial" "performance_direction" "camera"))
(define scene-given-fields
  '("time" "place" "environment" "background" "prior_events"))
(define scene-dramatic-fields
  '("central_question" "primary_conflict" "turn"))
(define scene-direction-fields
  '("blocking" "spatial" "performance_direction" "camera"))
(define scene-cast-fields
  '("objective" "action" "conflict" "emotional_state"
    "performance_direction" "subtext" "sort_order"))

(define character-identity-specs
  '(("literary_identity"
     "background" "personality" "values" "motivations"
     "fears" "goals" "relationships" "arc")
    ("visual_identity"
     "standard_appearance" "face" "body" "hair"
     "eyes" "skin" "distinctive_features" "clothing"
     "palette" "expressions" "posture")
    ("vocal_identity"
     "voice_character" "timbre" "range" "pitch" "accent"
     "pronunciation" "pace" "speech_habits")
    ("performance_identity"
     "habits" "movement" "gestures" "emotional_responses"
     "behavioral_traits" "typical_reactions" "situations")))

(define missing (list 'missing))

(define (api-fail status code message . details)
  (throw 'studio-api-error status code message details))

(define (object? value) (and (list? value) (every pair? value)))
(define (object-ref object key) (and (object? object) (assoc-ref object key)))
(define (object-has? object key) (and (object? object) (assoc key object) #t))

(define (hex-digit? char)
  (or (char-numeric? char)
      (char<=? #\a char #\f)
      (char<=? #\A char #\F)))

(define (valid-uuid? value)
  (and (string? value)
       (= (string-length value) 36)
       (every (lambda (index)
                (if (member index '(8 13 18 23))
                    (char=? (string-ref value index) #\-)
                    (hex-digit? (string-ref value index))))
              (iota 36))))

(define (valid-safe-id? value)
  (and (string? value)
       (not (string-null? value))
       (<= (string-length value) 256)
       (not (string-contains value "/"))
       (not (string-contains value "\\"))
       (not (string-contains value ".."))
       (not (string-index value #\nul))))

(define* (string-field object key #:key (required #f) (allow-empty #f)
                       (max max-content-length) (default ""))
  (let ((value (object-ref object key)))
    (cond
     ((not (object-has? object key))
      (if required
          (api-fail 400 "VALIDATION_ERROR" (format #f "~a is required" key))
          default))
     ((not (string? value))
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a must be a string" key)))
     ((and (not allow-empty) (string-null? value))
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a must not be empty" key)))
     ((> (string-length value) max)
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a is too large" key)))
     (else value))))

(define* (optional-string-field object key #:key (max max-context-length))
  (let ((value (object-ref object key)))
    (cond
     ((not (object-has? object key)) "")
     ((not (string? value))
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a must be a string" key)))
     ((> (string-length value) max)
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a is too large" key)))
     (else value))))

(define (required-integer-field object key min max)
  (let ((value (object-ref object key)))
    (cond
     ((not (object-has? object key))
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a is required" key)))
     ((not (integer? value))
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a must be an integer" key)))
     ((or (< value min) (> value max))
      (api-fail 400 "VALIDATION_ERROR" (format #f "~a is out of range" key)))
     (else value))))

(define (optional-integer-field object key min max default)
  (if (object-has? object key)
      (required-integer-field object key min max)
      default))

(define (valid-cover-color? value)
  (and (string? value)
       (= (string-length value) 7)
       (char=? (string-ref value 0) #\#)
       (every hex-digit? (string->list (substring value 1)))))

(define (require-uuid-in-path value label)
  (if (and (string? value) (valid-uuid? value))
      (string-downcase value)
      (api-fail 404 "NOT_FOUND" (format #f "~a not found" label))))

(define (require-workplace config id)
  (let* ((workplace-id (require-uuid-in-path id "Workplace"))
         (workplace (db:studio-get-workplace config workplace-id)))
    (or workplace
        (api-fail 404 "NOT_FOUND" "Workplace not found"))))

(define (require-document config workplace-id document-id)
  (let* ((id (require-uuid-in-path document-id "Document"))
         (document (db:studio-get-document config workplace-id id)))
    (or document
        (api-fail 404 "NOT_FOUND" "Document not found"))))

(define (require-character config workplace-id character-id)
  (let* ((id (require-uuid-in-path character-id "Character"))
         (character (db:studio-get-character config workplace-id id)))
    (or character
        (api-fail 404 "NOT_FOUND" "Character not found"))))

(define (require-scene config workplace-id scene-id)
  (let* ((id (require-uuid-in-path scene-id "Scene"))
         (scene (db:studio-get-scene config workplace-id id)))
    (or scene
        (api-fail 404 "NOT_FOUND" "Scene not found"))))

(define (identity-fields key)
  (let ((entry (assoc key character-identity-specs)))
    (and entry (cdr entry))))

(define (identity-from-json text)
  (if (or (not (string? text)) (string-null? text))
      '()
      (catch #t
        (lambda ()
          (let ((value (json-string->scm text)))
            (if (or (null? value) (object? value)) value '())))
        (lambda _ '()))))

(define (identity-to-json value)
  (if (null? value) "{}" (json-encode (json-normalize value))))

(define (storyboard-shots text)
  (if (or (not (string? text)) (string-null? text))
      '()
      (catch #t
        (lambda ()
          (let ((value (json-string->scm text)))
            (cond
             ((vector? value) (vector->list value))
             ((list? value) (if (every pair? value) '() value))
             (else '()))))
        (lambda _ '()))))

(define (merge-identity key current incoming)
  (unless (or (null? incoming) (object? incoming))
    (api-fail 400 "VALIDATION_ERROR"
              (format #f "~a must be an object" key)))
  (let ((allowed (identity-fields key)))
    (for-each
     (lambda (entry)
       (let ((field (car entry)))
         (unless (member field allowed)
           (api-fail 400 "VALIDATION_ERROR"
                     (format #f "~a.~a is not supported" key field)))
         (string-field incoming field #:allow-empty #t
                       #:max max-identity-field-length)))
     incoming)
    (fold
     (lambda (entry result)
       (acons (car entry) (cdr entry)
              (alist-delete (car entry) result equal?)))
     current incoming)))

(define (mark null-value)
  (if null-value null-value 'null))

(define (between? value low high)
  (and (>= value low) (<= value high)))

(define (cjk-char? char)
  (let ((code (char->integer char)))
    (or (between? code #x2e80 #x9fff)
        (between? code #xf900 #xfaff)
        (between? code #x3040 #x30ff)
        (between? code #xac00 #xd7af))))

;; Latin words count as words; CJK text counts as one word per character.
;; Whitespace and punctuation are ignored. This matches how the writing
;; prototype displays a mixed-language manuscript count.
(define (word-count text)
  (let loop ((index 0) (count 0) (in-word? #f))
    (if (= index (string-length text))
        count
        (let ((char (string-ref text index)))
          (cond
           ((char-whitespace? char) (loop (+ index 1) count #f))
           ((cjk-char? char) (loop (+ index 1) (+ count 1) #f))
           ((or (char-alphabetic? char) (char-numeric? char)
                (char=? char #\-) (char=? char #\'))
            (loop (+ index 1)
                  (if in-word? count (+ count 1))
                  #t))
           (else (loop (+ index 1) count #f)))))))

(define (sample-workplace-title? title)
  (and (string? title) (string-prefix? "[SAMPLE]" title)))

(define (public-workplace workplace)
  `(("id" . ,(assoc-ref workplace 'id))
    ("title" . ,(assoc-ref workplace 'title))
    ("description" . ,(assoc-ref workplace 'description))
    ("cover_color" . ,(assoc-ref workplace 'cover_color))
    ("cover_asset_id" . ,(mark (assoc-ref workplace 'cover_asset_id)))
    ("document_count" . ,(assoc-ref workplace 'document_count))
    ("created_at" . ,(assoc-ref workplace 'created_at))
    ("updated_at" . ,(assoc-ref workplace 'updated_at))
    ("last_opened_at" . ,(mark (assoc-ref workplace 'last_opened_at)))
    ("archived_at" . ,(mark (assoc-ref workplace 'archived_at)))
    ("sample" . ,(and (sample-workplace-title?
                       (assoc-ref workplace 'title))
                      #t))))

(define* (public-document document #:key (include-content #f))
  (append
   `(("id" . ,(assoc-ref document 'id))
     ("workplace_id" . ,(assoc-ref document 'workplace_id))
     ("parent_id" . ,(mark (assoc-ref document 'parent_id)))
     ("kind" . ,(assoc-ref document 'kind))
     ("title" . ,(assoc-ref document 'title))
     ("content_format" . ,(assoc-ref document 'content_format))
     ("revision" . ,(assoc-ref document 'revision))
     ("sort_order" . ,(assoc-ref document 'sort_order))
     ("word_count" . ,(word-count (assoc-ref document 'content)))
     ("created_at" . ,(assoc-ref document 'created_at))
     ("updated_at" . ,(assoc-ref document 'updated_at))
     ("deleted_at" . ,(mark (assoc-ref document 'deleted_at))))
   (if include-content
       `(("content" . ,(assoc-ref document 'content)))
       '())))

(define* (public-version version #:key (include-content #f))
  (append
   `(("id" . ,(assoc-ref version 'id))
     ("document_id" . ,(assoc-ref version 'document_id))
     ("revision" . ,(assoc-ref version 'revision))
     ("title" . ,(assoc-ref version 'title))
     ("label" . ,(mark (assoc-ref version 'label)))
     ("source" . ,(assoc-ref version 'source))
     ("created_at" . ,(assoc-ref version 'created_at)))
   (if include-content
       `(("content" . ,(assoc-ref version 'content)))
       '())))

(define (public-character character)
  `(("id" . ,(assoc-ref character 'id))
    ("workplace_id" . ,(assoc-ref character 'workplace_id))
    ("name" . ,(assoc-ref character 'name))
    ("role" . ,(assoc-ref character 'role))
    ("summary" . ,(assoc-ref character 'summary))
    ("concept" . ,(or (assoc-ref character 'concept) ""))
    ("literary_identity"
     . ,(identity-from-json (assoc-ref character 'literary_identity)))
    ("visual_identity"
     . ,(identity-from-json (assoc-ref character 'visual_identity)))
    ("vocal_identity"
     . ,(identity-from-json (assoc-ref character 'vocal_identity)))
    ("performance_identity"
     . ,(identity-from-json (assoc-ref character 'performance_identity)))
    ("avatar_asset_id" . ,(mark (assoc-ref character 'avatar_asset_id)))
    ("full_body_asset_id" . ,(mark (assoc-ref character 'full_body_asset_id)))
    ("created_at" . ,(assoc-ref character 'created_at))
    ("updated_at" . ,(assoc-ref character 'updated_at))
    ("archived_at" . ,(mark (assoc-ref character 'archived_at)))))

(define (public-character-with-avatar config character)
  (let* ((avatar-id (assoc-ref character 'avatar_asset_id))
         (full-body-id (assoc-ref character 'full_body_asset_id))
         (workplace-id (assoc-ref character 'workplace_id))
         (asset (and avatar-id
                     (db:studio-get-asset config workplace-id avatar-id)))
         (full-body (and full-body-id
                         (db:studio-get-asset config workplace-id
                                              full-body-id))))
    (append (public-character character)
            `(("avatar" . ,(mark (and asset
                                      (public-asset asset #:config config))))
              ("full_body" . ,(mark (and full-body
                                         (public-asset full-body #:config config))))))))

(define* (public-scene scene #:key (include-source-text #f))
  (append
   `(("id" . ,(assoc-ref scene 'id))
    ("workplace_id" . ,(assoc-ref scene 'workplace_id))
    ("title" . ,(assoc-ref scene 'title))
    ("summary" . ,(assoc-ref scene 'summary))
    ("sort_order" . ,(assoc-ref scene 'sort_order))
    ("status" . ,(assoc-ref scene 'status))
    ("given_circumstances"
     . ,(map (lambda (field)
               (cons field
                     (or (assoc-ref scene (string->symbol field)) "")))
             scene-given-fields))
    ("dramatic_situation"
     . ,(map (lambda (field)
               (cons field
                     (or (assoc-ref scene (string->symbol field)) "")))
             scene-dramatic-fields))
    ("dialogue" . ,(assoc-ref scene 'dialogue))
    ("direction"
     . ,(map (lambda (field)
               (cons field
                     (or (assoc-ref scene (string->symbol field)) "")))
             scene-direction-fields))
    ("cast_count" . ,(or (assoc-ref scene 'cast_count) 0))
    ("storyboard_count" . ,(length (storyboard-shots
                                    (assoc-ref scene 'storyboard))))
    ("reference_asset_ids"
     . ,(json-string-list (assoc-ref scene 'reference_asset_ids)))
    ("reference_count"
     . ,(length (json-string-list (assoc-ref scene 'reference_asset_ids))))
    ("source_document_id"
     . ,(mark (assoc-ref scene 'source_document_id)))
    ("source_document_version_id"
     . ,(mark (assoc-ref scene 'source_document_version_id)))
    ("source_document_revision"
     . ,(mark (assoc-ref scene 'source_document_revision)))
    ("source_selection_start"
     . ,(mark (assoc-ref scene 'source_selection_start)))
    ("source_selection_end"
     . ,(mark (assoc-ref scene 'source_selection_end)))
    ("created_at" . ,(assoc-ref scene 'created_at))
    ("updated_at" . ,(assoc-ref scene 'updated_at))
    ("deleted_at" . ,(mark (assoc-ref scene 'deleted_at))))
   (if include-source-text
       `(("source_text_snapshot"
          . ,(mark (assoc-ref scene 'source_text_snapshot))))
       '())))

(define (public-scene-cast entry)
  `(("id" . ,(assoc-ref entry 'id))
    ("scene_id" . ,(assoc-ref entry 'scene_id))
    ("character_id" . ,(assoc-ref entry 'character_id))
    ("character_name" . ,(or (assoc-ref entry 'character_name) ""))
    ("character_role" . ,(or (assoc-ref entry 'character_role) ""))
    ("objective" . ,(assoc-ref entry 'objective))
    ("action" . ,(assoc-ref entry 'action))
    ("conflict" . ,(assoc-ref entry 'conflict))
    ("emotional_state" . ,(assoc-ref entry 'emotional_state))
    ("performance_direction" . ,(assoc-ref entry 'performance_direction))
    ("subtext" . ,(assoc-ref entry 'subtext))
    ("sort_order" . ,(assoc-ref entry 'sort_order))
    ("created_at" . ,(assoc-ref entry 'created_at))
    ("updated_at" . ,(assoc-ref entry 'updated_at))))

(define (model-size path)
  (catch #t
    (lambda () (stat:size (stat path)))
    (lambda _ 0)))

(define (installed-models config)
  (map (lambda (file)
         (let ((name (ollama-model-name file)))
           `(("id" . ,name)
             ("name" . ,name)
             ("size" . ,(model-size
                         (string-append (ollama-llm-dir config) "/" file))))))
       (ollama-gguf-files config)))

(define (fake-model)
  '(("id" . "fake") ("name" . "fake") ("size" . 0)))

(define (configured-model config)
  (let ((value (or (config-ref config 'studio_model)
                   (config-ref config 'default_model)
                   "")))
    (and (string? value) (not (string-null? value)) value)))

(define (sonicboom-available?)
  (catch #t
    (lambda () (resolve-interface '(khala engine llm-sonicboom)) #t)
    (lambda _ #f)))

(define (configured-engine config)
  (let ((engine (config-ref config 'engine)))
    (if (equal? engine "sonicboom") "sonicboom" "fake")))

(define (studio-image-generation-capabilities config)
  (let* ((engine-name (configured-engine config))
         (engine (if (equal? engine-name "sonicboom") 'sonicboom 'fake))
         (capabilities (engine-image-capabilities engine)))
    `(("engine" . ,engine-name)
      ("available" . ,(and (or (equal? engine-name "fake")
                               (sonicboom-available?))
                           #t))
      ("reference_images" . ,(and (assq-ref capabilities 'reference_images)
                                  #t))
      ("reference_mode" . ,(or (assq-ref capabilities 'reference_mode)
                               "text-only"))
      ("max_references" . ,(or (assq-ref capabilities 'max_references) 0)))))

(define (available-models config)
  (define installed (installed-models config))
  (define configured (configured-model config))
  (if (equal? (configured-engine config) "sonicboom")
      installed
      (let* ((base (cons (fake-model) installed))
             (has-configured?
              (and configured
                   (find (lambda (entry)
                           (equal? (assoc-ref entry "id") configured))
                         base))))
        (if (and configured (not has-configured?))
            (cons `(("id" . ,configured) ("name" . ,configured) ("size" . 0))
                  base)
            base))))

(define (default-model config)
  (define models (available-models config))
  (define configured (configured-model config))
  (cond
   ((and configured
         (or (equal? (configured-engine config) "fake")
             (find (lambda (entry)
                     (equal? (assoc-ref entry "id") configured))
                   models)))
    configured)
   ((pair? models) (assoc-ref (car models) "id"))
   (else #f)))

(define (studio-capabilities config)
  (let* ((engine (configured-engine config))
         (models (available-models config))
         (default (default-model config))
         (available? (and default
                          (or (equal? engine "fake")
                              (sonicboom-available?)))))
    `(("api_version" . 1)
      ("storage" . "local")
      ("engine" . ,engine)
      ("default_model" . ,(mark default))
      ("models" . ,models)
      ("ai_available" . ,(and available? #t))
      ("model_profiles" . ,(map (lambda (profile)
                                  `(("id" . ,(assoc-ref profile 'id))
                                    ("name" . ,(assoc-ref profile 'name))
                                    ("model" . ,(assoc-ref profile 'model_id))
                                    ("protocol" . ,(assoc-ref profile 'protocol))))
                                (db:studio-list-model-profiles config)))
      ("image_generation" . ,(studio-image-generation-capabilities config)))))

;; --- Unified LLM / embedding model settings --------------------------------

(define (profile-secret-key kind id)
  (format #f "~a:~a" kind id))

(define (default-model-capabilities protocol)
  (case (string->symbol protocol)
    ((openai-compatible)
     '(("temperature" . #t) ("top_p" . #t) ("streaming" . #t)
       ("json" . #t) ("reasoning" . #f)))
    ((gemini-native)
     '(("temperature" . #t) ("top_p" . #t) ("streaming" . #t)
       ("json" . #t) ("reasoning" . #f)))
    ((anthropic-messages)
     '(("temperature" . #t) ("top_p" . #t) ("streaming" . #t)
       ("json" . #f) ("reasoning" . #f)))
    ((fake)
     '(("temperature" . #t) ("top_p" . #t) ("streaming" . #t)
       ("json" . #t) ("reasoning" . #f)))
    (else '())))

(define model-capability-booleans
  '("temperature" "top_p" "streaming" "json" "reasoning"))
(define model-capability-limits
  '("context_window" "max_output_tokens"))

(define (validate-model-capabilities text)
  (let ((object (json-string->scm text)))
    (unless (object? object)
      (api-fail 400 "VALIDATION_ERROR" "capabilities must be an object"))
    (for-each
     (lambda (entry)
       (let ((key (car entry)) (value (cdr entry)))
         (cond
          ((member key model-capability-booleans string=?)
           (unless (boolean? value)
             (api-fail 400 "VALIDATION_ERROR"
                       (format #f "capability ~a must be boolean" key))))
          ((member key model-capability-limits string=?)
           (unless (and (integer? value) (> value 0) (<= value 10000000))
             (api-fail 400 "VALIDATION_ERROR"
                       (format #f "capability ~a must be a positive integer" key))))
          (else
           (api-fail 400 "VALIDATION_ERROR"
                     (format #f "Unknown capability: ~a" key))))))
     object)
    text))

(define (model-profile-capabilities body existing protocol reset-defaults?)
  (validate-model-capabilities
   (if reset-defaults?
       (json-encode (json-normalize (default-model-capabilities protocol)))
       (profile-json-object
        body "capabilities"
        (or (and existing (assoc-ref existing 'capabilities))
            (json-encode
             (json-normalize (default-model-capabilities protocol))))))))

(define (default-model-parameters protocol)
  (case (string->symbol protocol)
    ((openai-compatible gemini-native anthropic-messages fake)
     '(("max_output_tokens" . 2048) ("temperature" . 0.7)
       ("top_p" . 1.0) ("stream" . #t)))
    (else '())))

(define (profile-json-object body key default)
  (if (object-has? body key)
      (let ((value (object-ref body key)))
        (cond
         ((not (object? value))
          (api-fail 400 "VALIDATION_ERROR"
                    (format #f "~a must be an object" key)))
         ((> (string-length (json-encode (json-normalize value)))
             max-profile-json-length)
          (api-fail 400 "VALIDATION_ERROR"
                    (format #f "~a is too large" key)))
         (else (json-encode (json-normalize value)))))
      default))

(define (profile-custom-headers body default)
  (if (not (object-has? body "custom_headers"))
      default
      (let ((headers (object-ref body "custom_headers")))
        (unless (object? headers)
          (api-fail 400 "VALIDATION_ERROR" "custom_headers must be an object"))
        (for-each
         (lambda (entry)
           (let ((name (car entry)) (value (cdr entry)))
             (unless (and (string? name) (string? value))
               (api-fail 400 "VALIDATION_ERROR"
                         "custom_headers must map strings to strings"))
             (unless (and (not (string-null? (string-trim-both name)))
                          (not (string-index name #\newline))
                          (not (string-index name #\return))
                          (not (string-index value #\newline))
                          (not (string-index value #\return)))
               (api-fail 400 "VALIDATION_ERROR"
                         "custom_headers contains an invalid header"))
             (let ((lower (string-downcase (string-trim-both name))))
               (when (member lower
                             '("authorization" "x-api-key" "api-key"
                               "x-goog-api-key" "cookie" "proxy-authorization"))
                 (api-fail 400 "VALIDATION_ERROR"
                           "Authentication headers belong in api_key, not custom_headers")))))
         headers)
        (json-encode (json-normalize headers)))))

(define (valid-provider-url? value)
  (and (string? value)
       (not (string-null? value))
       (<= (string-length value) max-base-url-length)
       (not (string-index value #\newline))
       (catch #t
         (lambda ()
           (let ((uri (string->uri value)))
             (and uri
                  (memq (uri-scheme uri) '(http https))
                  (string? (uri-host uri))
                  (not (string-null? (uri-host uri)))
                  (not (uri-userinfo uri)))))
         (lambda _ #f))))

(define (validate-model-id value required?)
  (when (and value (not (string? value)))
    (api-fail 400 "VALIDATION_ERROR" "model_id must be a string"))
  (let ((text (if (string? value) (string-trim-both value) "")))
    (when (and required? (string-null? text))
      (api-fail 400 "VALIDATION_ERROR" "model_id is required"))
    (unless (<= (string-length text) max-model-id-length)
      (api-fail 400 "VALIDATION_ERROR" "model_id is too large"))
    (when (string-index text #\newline)
      (api-fail 400 "VALIDATION_ERROR" "model_id contains invalid characters"))
    text))

(define (profile-enabled-value body default)
  (if (object-has? body "enabled")
      (let ((value (object-ref body "enabled")))
        (unless (boolean? value)
          (api-fail 400 "VALIDATION_ERROR" "enabled must be a boolean"))
        value)
      default))

(define (api-key-input body)
  (if (object-has? body "api_key")
      (let ((value (object-ref body "api_key")))
        (cond ((not (string? value))
               (api-fail 400 "VALIDATION_ERROR" "api_key must be a string"))
              ((> (string-length value) max-api-key-length)
               (api-fail 400 "VALIDATION_ERROR" "api_key is too large"))
              ((string-null? (string-trim-both value)) #f)
              (else (string-trim-both value))))
      'preserve))

(define (profile-api-key config kind id)
  (secret:studio-secret-get config (profile-secret-key kind id)))

(define (public-model-profile config profile)
  (let ((key (profile-api-key config "llm" (assoc-ref profile 'id))))
    `(("id" . ,(assoc-ref profile 'id))
      ("name" . ,(assoc-ref profile 'name))
      ("provider" . ,(assoc-ref profile 'provider))
      ("protocol" . ,(assoc-ref profile 'protocol))
      ("base_url" . ,(assoc-ref profile 'base_url))
      ("model_id" . ,(assoc-ref profile 'model_id))
      ("custom_headers" . ,(identity-from-json
                            (assoc-ref profile 'custom_headers)))
      ("timeout_seconds" . ,(assoc-ref profile 'timeout_seconds))
      ("parameters" . ,(identity-from-json (assoc-ref profile 'parameters)))
      ("capabilities" . ,(identity-from-json (assoc-ref profile 'capabilities)))
      ("enabled" . ,(assoc-ref profile 'enabled))
      ("api_key_configured" . ,(and key #t))
      ("api_key_masked" . ,(mark (secret:studio-secret-mask key)))
      ("created_at" . ,(assoc-ref profile 'created_at))
      ("updated_at" . ,(assoc-ref profile 'updated_at)))))

(define (public-embedding-profile config profile)
  (let ((key (profile-api-key config "embedding" (assoc-ref profile 'id))))
    `(("id" . ,(assoc-ref profile 'id))
      ("name" . ,(assoc-ref profile 'name))
      ("provider" . ,(assoc-ref profile 'provider))
      ("protocol" . ,(assoc-ref profile 'protocol))
      ("base_url" . ,(assoc-ref profile 'base_url))
      ("model_id" . ,(assoc-ref profile 'model_id))
      ("dimensions" . ,(mark (assoc-ref profile 'dimensions)))
      ("batch_size" . ,(assoc-ref profile 'batch_size))
      ("timeout_seconds" . ,(assoc-ref profile 'timeout_seconds))
      ("custom_headers" . ,(identity-from-json
                            (assoc-ref profile 'custom_headers)))
      ("enabled" . ,(assoc-ref profile 'enabled))
      ("api_key_configured" . ,(and key #t))
      ("api_key_masked" . ,(mark (secret:studio-secret-mask key)))
      ("created_at" . ,(assoc-ref profile 'created_at))
      ("updated_at" . ,(assoc-ref profile 'updated_at)))))

(define (private-profile config kind profile)
  (and profile
       (acons 'api_key
              (or (profile-api-key config kind (assoc-ref profile 'id)) "")
              profile)))

(define (assignment-map rows)
  (map (lambda (task)
         (let ((entry (find (lambda (row)
                              (equal? (assoc-ref row 'task) task))
                            rows)))
           (cons task (and entry (assoc-ref entry 'profile_id)))))
       model-task-keys))

(define (json-object-alist? value)
  (and (list? value)
       (every (lambda (entry)
                (and (pair? entry)
                     (or (string? (car entry)) (symbol? (car entry)))))
              value)))

(define (public-json-tree value)
  (cond
   ((json-object-alist? value)
    (map (lambda (entry)
           (cons (if (symbol? (car entry))
                     (symbol->string (car entry))
                     (car entry))
                 (public-json-tree (cdr entry))))
         value))
   ((list? value) (map public-json-tree value))
   ((vector? value) (list->vector (map public-json-tree (vector->list value))))
   (else value)))

(define (ensure-legacy-model-profile! config)
  (when (and (null? (db:studio-list-model-profiles config))
             (equal? (configured-engine config) "fake")
             (configured-model config))
    (let* ((id (db:studio-new-id))
           (model (configured-model config)))
      (db:studio-create-model-profile!
       config id
       `((name . ,(format #f "Legacy Writing Model (~a)" model))
         (provider . "legacy")
         (protocol . "fake")
         (base_url . "fake://local")
         (model_id . ,model)
         (custom_headers . "{}")
         (timeout_seconds . 60)
         (parameters . ,(json-encode
                         (json-normalize (default-model-parameters "fake"))))
         (capabilities . ,(json-encode
                           (json-normalize
                            (default-model-capabilities "fake"))))
         (enabled . #t)))
      (db:studio-set-setting! config "default_model_profile_id" id)
      (db:studio-set-task-assignments!
       config (map (lambda (task) `((task . ,task) (profile_id . ,id)))
                   model-task-keys)))))

(define (studio-model-settings config)
  (ensure-legacy-model-profile! config)
  (let* ((profiles (db:studio-list-model-profiles config))
         (embedding (db:studio-list-embedding-profiles config))
         (default-llm (db:studio-get-setting config "default_model_profile_id"))
         (default-embedding (db:studio-get-setting
                             config "default_embedding_profile_id"))
         (setting-value (lambda (value)
                          (and value
                               (not (string-null? value))
                               value))))
    `(("llm_profiles" . ,(map (lambda (profile)
                                (public-model-profile config profile))
                              profiles))
      ("embedding_profiles" . ,(map (lambda (profile)
                                      (public-embedding-profile config profile))
                                    embedding))
      ("default_llm_profile_id" . ,(mark (setting-value default-llm)))
      ("default_embedding_profile_id"
       . ,(mark (setting-value default-embedding)))
      ("task_assignments" . ,(assignment-map
                              (db:studio-list-task-assignments config)))
      ("provider_presets" . ,(public-json-tree provider:studio-provider-presets))
      ("protocols" . ,(public-json-tree provider:studio-protocol-options))
      ("tasks" . ,model-task-keys)
      ("legacy" .
       (("engine" . ,(configured-engine config))
        ("model" . ,(mark (configured-model config)))
        ("fallback_available" . ,(and (configured-model config) #t)))))))

(define (model-profile-values body existing)
  (let* ((protocol (if (object-has? body "protocol")
                       (string-field body "protocol" #:required #t)
                       (and existing (assoc-ref existing 'protocol))))
         (protocol (or protocol "openai-compatible"))
         (protocol-changed? (and existing
                                 (not (equal? protocol
                                              (assoc-ref existing 'protocol)))))
         (provider-changed?
          (and existing
               (object-has? body "provider")
               (not (equal? (string-trim-both
                             (string-field body "provider" #:allow-empty #t
                                           #:max 128))
                            (or (assoc-ref existing 'provider) "custom")))))
         (model-changed?
          (and existing
               (object-has? body "model_id")
               (not (equal? (validate-model-id (object-ref body "model_id")
                                               (not (equal? protocol "fake")))
                            (or (assoc-ref existing 'model_id) "")))))
         (reset-profile-defaults? (or protocol-changed? provider-changed?
                                      model-changed?)))
    (unless (member protocol model-protocols)
      (api-fail 400 "VALIDATION_ERROR" "protocol is not supported"))
    (let* ((base-default (or (and existing (assoc-ref existing 'base_url)) ""))
           (base (if (object-has? body "base_url")
                     (string-field body "base_url" #:allow-empty #t
                                   #:max max-base-url-length)
                     base-default))
           (model-default (or (and existing (assoc-ref existing 'model_id)) ""))
           (model (validate-model-id
                   (if (object-has? body "model_id")
                       (object-ref body "model_id")
                       model-default)
                   (not (equal? protocol "fake")))))
      (unless (or (equal? protocol "fake") (valid-provider-url? base))
        (api-fail 400 "VALIDATION_ERROR"
                  "base_url must be an explicit http(s) URL without credentials"))
      `((name . ,(if (object-has? body "name")
                     (string-field body "name" #:required #t
                                   #:max max-profile-name-length)
                     (and existing (assoc-ref existing 'name))))
        (provider . ,(if (object-has? body "provider")
                         (string-field body "provider" #:allow-empty #t
                                       #:max 128)
                         (or (and existing (assoc-ref existing 'provider))
                             "custom")))
        (protocol . ,protocol)
        (base_url . ,base)
        (model_id . ,model)
        (custom_headers
         . ,(profile-custom-headers body
                                    (or (and existing
                                             (assoc-ref existing 'custom_headers))
                                        "{}")))
        (timeout_seconds
         . ,(if (object-has? body "timeout_seconds")
                (required-integer-field body "timeout_seconds" 1 300)
                (or (and existing (assoc-ref existing 'timeout_seconds)) 60)))
        (parameters
         . ,(if reset-profile-defaults?
                (json-encode
                 (json-normalize (default-model-parameters protocol)))
                (profile-json-object
                 body "parameters"
                 (or (and existing (assoc-ref existing 'parameters))
                     (json-encode
                      (json-normalize
                       (default-model-parameters protocol)))))))
        (capabilities
         . ,(model-profile-capabilities body existing protocol
                                        reset-profile-defaults?))
        (enabled . ,(profile-enabled-value
                     body (or (and existing (assoc-ref existing 'enabled)) #t)))))))

(define (require-model-profile config id)
  (let ((profile (db:studio-get-model-profile
                  config (require-uuid-in-path id "Model profile"))))
    (or profile (api-fail 404 "NOT_FOUND" "Model profile not found"))))

(define (store-profile-key! config kind id input existing-id)
  (cond
   ((eq? input 'preserve) #t)
   ((not input)
    (when (or (not existing-id) (not (equal? id existing-id)))
      (secret:studio-secret-delete! config (profile-secret-key kind id))))
   (else (secret:studio-secret-set! config (profile-secret-key kind id) input))))

(define (studio-create-model-profile! config body)
  (unless (object-has? body "name")
    (api-fail 400 "VALIDATION_ERROR" "name is required"))
  (let* ((id (db:studio-new-id))
         (values (model-profile-values body #f))
         (key (api-key-input body))
         (created (db:studio-create-model-profile! config id values)))
    (store-profile-key! config "llm" id key #f)
    (public-model-profile config created)))

(define (studio-update-model-profile! config id body)
  (let* ((profile (require-model-profile config id))
         (profile-id (assoc-ref profile 'id))
         (values (model-profile-values body profile))
         (key (api-key-input body))
         (updated (db:studio-update-model-profile! config profile-id values)))
    (store-profile-key! config "llm" profile-id key profile-id)
    (public-model-profile config updated)))

(define (studio-delete-model-profile! config id)
  (let* ((profile (require-model-profile config id))
         (profile-id (assoc-ref profile 'id))
         (archived (db:studio-archive-model-profile! config profile-id)))
    (or archived (api-fail 404 "NOT_FOUND" "Model profile not found"))
    (secret:studio-secret-delete! config (profile-secret-key "llm" profile-id))
    `(("id" . ,profile-id) ("archived_at" . ,archived))))

(define (provider-error-response key code message details)
  (if (eq? key 'studio-provider-error)
      (api-fail (if (equal? code "NETWORK_ERROR") 503 502) code message)
      (begin
        (format (current-error-port) "Studio model request failed: ~s~%" key)
        (api-fail 502 "GENERATION_FAILED" "Model request failed"))))

(define (studio-test-model-profile! config id body)
  (let* ((profile (private-profile config "llm"
                                  (require-model-profile config id)))
         (prompt (optional-string-field (or body '()) "prompt"
                                         #:max max-instruction-length))
         (prompt (if (string-null? prompt)
                     "Reply with the single word OK."
                     prompt))
         (messages (list `(("role" . "user") ("content" . ,prompt))))
         (began (get-internal-real-time)))
    (catch #t
      (lambda ()
        (let ((result (provider:studio-chat-with-profile
                       profile messages '(("max_output_tokens" . 32)
                                          ("stream" . #f)))))
          `(("ok" . #t)
            ("profile_id" . ,(assoc-ref profile 'id))
            ("model" . ,(or (assoc-ref profile 'model_id) ""))
            ("protocol" . ,(assoc-ref profile 'protocol))
            ("base_url" . ,(or (assoc-ref profile 'base_url) ""))
            ("preview" . ,(let ((text (or (assoc-ref result 'text) "")))
                            (substring text 0 (min 160 (string-length text)))))
            ("elapsed_ms" . ,(quotient
                              (* (- (get-internal-real-time) began) 1000)
                              internal-time-units-per-second)))))
      (lambda (key . args)
        (if (eq? key 'studio-provider-error)
            (provider-error-response key (car args) (cadr args) (caddr args))
            (apply throw key args))))))

(define (studio-discover-model-profile-models config id)
  (let ((profile (private-profile config "llm"
                                  (require-model-profile config id))))
    (catch #t
      (lambda ()
        (let ((models (provider:studio-discover-profile-models profile)))
          `(("models" . ,(list->vector (map json-normalize models))))))
      (lambda (key . args)
        (if (eq? key 'studio-provider-error)
            (provider-error-response key (car args) (cadr args) (caddr args))
            (apply throw key args))))))

(define (validate-assigned-profile config value task)
  (cond
   ((not value) #f)
   ((not (and (string? value) (valid-uuid? value)))
    (api-fail 400 "VALIDATION_ERROR"
              (format #f "~a must be a Model Profile UUID or null" task)))
   (else
    (let ((profile (db:studio-get-model-profile config (string-downcase value))))
      (unless (and profile (assoc-ref profile 'enabled))
        (api-fail 422 "INVALID_MODEL_PROFILE"
                  (format #f "~a must reference an enabled Model Profile" task)))
      (assoc-ref profile 'id)))))

(define (validate-assigned-embedding-profile config value)
  (cond
   ((not value) #f)
   ((not (and (string? value) (valid-uuid? value)))
    (api-fail 400 "VALIDATION_ERROR"
              "default_embedding_profile_id must be an Embedding Profile UUID or null"))
   (else
    (let ((profile (db:studio-get-embedding-profile
                    config (string-downcase value))))
      (unless (and profile (assoc-ref profile 'enabled))
        (api-fail 422 "INVALID_MODEL_PROFILE"
                  "default_embedding_profile_id must reference an enabled Embedding Profile"))
      (assoc-ref profile 'id)))))

(define (studio-update-model-routing! config body)
  (let* ((body (or body '()))
         (default-input (and (object-has? body "default_profile_id")
                             (object-ref body "default_profile_id")))
         (default (validate-assigned-profile config default-input "default_profile_id"))
         (embedding-default-input
          (and (object-has? body "default_embedding_profile_id")
               (object-ref body "default_embedding_profile_id")))
         (embedding-default
          (validate-assigned-embedding-profile config embedding-default-input))
         (tasks (object-ref body "tasks"))
         (assignments '()))
    (when (object-has? body "tasks")
      (unless (object? tasks)
        (api-fail 400 "VALIDATION_ERROR" "tasks must be an object"))
      (for-each
       (lambda (entry)
         (unless (member (car entry) model-task-keys)
           (api-fail 400 "VALIDATION_ERROR"
                     (format #f "Unknown model task: ~a" (car entry))))
         (unless (or (not (cdr entry)) (string? (cdr entry)))
           (api-fail 400 "VALIDATION_ERROR"
                     (format #f "~a must be a profile UUID or null" (car entry))))
         (set! assignments
               (cons `((task . ,(car entry))
                       (profile_id . ,(validate-assigned-profile
                                       config (cdr entry) (car entry))))
                     assignments)))
       tasks))
    (when (object-has? body "default_profile_id")
      (db:studio-set-setting! config "default_model_profile_id" (or default "")))
    (when (object-has? body "default_embedding_profile_id")
      (db:studio-set-setting! config "default_embedding_profile_id"
                              (or embedding-default "")))
    (unless (null? assignments)
      (db:studio-set-task-assignments! config (reverse assignments)))
    (studio-model-settings config)))

(define (embedding-profile-values body existing)
  (let* ((protocol (if (object-has? body "protocol")
                       (string-field body "protocol" #:required #t)
                       (or (and existing (assoc-ref existing 'protocol))
                           "openai-embeddings")))
         (base-default (or (and existing (assoc-ref existing 'base_url)) ""))
         (base (if (object-has? body "base_url")
                   (string-field body "base_url" #:allow-empty #t
                                 #:max max-base-url-length)
                   base-default))
         (model-default (or (and existing (assoc-ref existing 'model_id)) ""))
         (model (validate-model-id
                 (if (object-has? body "model_id") (object-ref body "model_id")
                     model-default)
                 #t))
         (dimensions
          (if (object-has? body "dimensions")
              (let ((value (object-ref body "dimensions")))
                (cond ((not value) #f)
                      ((not (integer? value)) (api-fail 400 "VALIDATION_ERROR" "dimensions must be an integer or null"))
                      ((or (< value 1) (> value 65536)) (api-fail 400 "VALIDATION_ERROR" "dimensions is out of range"))
                      (else value)))
              (and existing (assoc-ref existing 'dimensions)))))
    (unless (member protocol embedding-protocols)
      (api-fail 400 "VALIDATION_ERROR" "Embedding protocol is not supported"))
    (unless (valid-provider-url? base)
      (api-fail 400 "VALIDATION_ERROR"
                "base_url must be an explicit http(s) URL without credentials"))
    `((name . ,(if (object-has? body "name")
                   (string-field body "name" #:required #t
                                 #:max max-profile-name-length)
                   (and existing (assoc-ref existing 'name))))
      (provider . ,(if (object-has? body "provider")
                       (string-field body "provider" #:allow-empty #t #:max 128)
                       (or (and existing (assoc-ref existing 'provider)) "custom")))
      (protocol . ,protocol)
      (base_url . ,base)
      (model_id . ,model)
      (dimensions . ,dimensions)
      (batch_size . ,(if (object-has? body "batch_size")
                         (required-integer-field body "batch_size" 1 256)
                         (or (and existing (assoc-ref existing 'batch_size)) 16)))
      (timeout_seconds . ,(if (object-has? body "timeout_seconds")
                              (required-integer-field body "timeout_seconds" 1 300)
                              (or (and existing (assoc-ref existing 'timeout_seconds)) 60)))
      (custom_headers . ,(profile-custom-headers
                          body (or (and existing (assoc-ref existing 'custom_headers))
                                   "{}")))
      (enabled . ,(profile-enabled-value
                   body (or (and existing (assoc-ref existing 'enabled)) #t))))))

(define (require-embedding-profile config id)
  (let ((profile (db:studio-get-embedding-profile
                  config (require-uuid-in-path id "Embedding profile"))))
    (or profile (api-fail 404 "NOT_FOUND" "Embedding profile not found"))))

(define (studio-create-embedding-profile! config body)
  (unless (object-has? body "name")
    (api-fail 400 "VALIDATION_ERROR" "name is required"))
  (let* ((id (db:studio-new-id))
         (values (embedding-profile-values body #f))
         (key (api-key-input body))
         (created (db:studio-create-embedding-profile! config id values)))
    (store-profile-key! config "embedding" id key #f)
    (public-embedding-profile config created)))

(define (studio-update-embedding-profile! config id body)
  (let* ((profile (require-embedding-profile config id))
         (profile-id (assoc-ref profile 'id))
         (values (embedding-profile-values body profile))
         (key (api-key-input body))
         (updated (db:studio-update-embedding-profile! config profile-id values)))
    (store-profile-key! config "embedding" profile-id key profile-id)
    (public-embedding-profile config updated)))

(define (studio-delete-embedding-profile! config id)
  (let* ((profile (require-embedding-profile config id))
         (profile-id (assoc-ref profile 'id))
         (archived (db:studio-archive-embedding-profile! config profile-id)))
    (or archived (api-fail 404 "NOT_FOUND" "Embedding profile not found"))
    (secret:studio-secret-delete! config (profile-secret-key "embedding" profile-id))
    `(("id" . ,profile-id) ("archived_at" . ,archived))))

(define (studio-test-embedding-profile! config id body)
  (let* ((profile (private-profile config "embedding"
                                  (require-embedding-profile config id)))
         (text (optional-string-field (or body '()) "text"
                                       #:max max-context-length))
         (text (if (string-null? text)
                   "Khala Studio embedding connection test."
                   text)))
    (catch #t
      (lambda ()
        (let ((result (provider:studio-embedding-with-profile profile text)))
          `(("ok" . #t)
            ("profile_id" . ,(assoc-ref profile 'id))
            ("model" . ,(assoc-ref result 'model))
            ("dimensions" . ,(assoc-ref result 'dimensions))
            ("sample" . ,(list-head (assoc-ref result 'vector)
                                    (min 3 (length (assoc-ref result 'vector)))))
            ("protocol" . ,(assoc-ref profile 'protocol)))))
      (lambda (key . args)
        (if (eq? key 'studio-provider-error)
            (provider-error-response key (car args) (cadr args) (caddr args))
            (apply throw key args))))))

(define (studio-list-workplaces config)
  (map public-workplace (db:studio-list-workplaces config)))

(define (studio-create-workplace! config body)
  (let* ((title (string-field body "title" #:required #t
                              #:max max-title-length))
         (description (string-field body "description" #:allow-empty #t
                                    #:max max-description-length))
         (cover-color (string-field body "cover_color" #:allow-empty #t
                                    #:default "#713D3B"))
         (cover-asset (object-ref body "cover_asset_id")))
    (unless (valid-cover-color? cover-color)
      (api-fail 400 "VALIDATION_ERROR" "cover_color must be a #RRGGBB color"))
    (when (and (object-has? body "cover_asset_id")
               cover-asset
               (not (valid-uuid? cover-asset)))
      (api-fail 400 "VALIDATION_ERROR" "cover_asset_id must be a UUID or null"))
    (public-workplace
     (db:studio-create-workplace! config (db:studio-new-id) title description
                                  cover-color cover-asset))))

(define (studio-get-workplace config id)
  (let* ((workplace (require-workplace config id))
         (id (assoc-ref workplace 'id))
         (opened (or (db:studio-touch-workplace! config id) workplace)))
    (public-workplace opened)))

(define (studio-update-workplace! config id body)
  (let* ((workplace (require-workplace config id))
         (workplace-id (assoc-ref workplace 'id))
         (updates '()))
    (when (object-has? body "title")
      (set! updates
            (acons 'title (string-field body "title" #:required #t
                                        #:max max-title-length)
                   updates)))
    (when (object-has? body "description")
      (set! updates
            (acons 'description
                   (string-field body "description" #:allow-empty #t
                                 #:max max-description-length)
                   updates)))
    (when (object-has? body "cover_color")
      (let ((color (string-field body "cover_color" #:allow-empty #t)))
        (unless (valid-cover-color? color)
          (api-fail 400 "VALIDATION_ERROR" "cover_color must be a #RRGGBB color"))
        (set! updates (acons 'cover_color color updates))))
    (when (object-has? body "cover_asset_id")
      (let ((asset (object-ref body "cover_asset_id")))
        (when (and asset (not (valid-uuid? asset)))
          (api-fail 400 "VALIDATION_ERROR" "cover_asset_id must be a UUID or null"))
        (set! updates (acons 'cover_asset_id asset updates))))
    (if (null? updates)
        (public-workplace workplace)
        (public-workplace
         (db:studio-update-workplace! config workplace-id updates)))))

;; --- Prototype sample and manual model acceptance -------------------------

(define demo-workplace-title "[SAMPLE] The Last Lamp")

(define (demo-fill! pixels width height x0 y0 x1 y1 red green blue)
  (do ((y (max 0 y0) (+ y 1))) ((>= y (min height y1)))
    (do ((x (max 0 x0) (+ x 1))) ((>= x (min width x1)))
      (let ((offset (+ (* y width 3) (* x 3))))
        (bytevector-u8-set! pixels offset red)
        (bytevector-u8-set! pixels (+ offset 1) green)
        (bytevector-u8-set! pixels (+ offset 2) blue)))))

(define (demo-illustrative-png)
  (let* ((width 768)
         (height 432)
         (pixels (make-bytevector (* width height 3) 0)))
    (demo-fill! pixels width height 0 0 width height 232 220 196)
    (demo-fill! pixels width height 0 310 width height 157 126 94)
    (demo-fill! pixels width height 58 62 292 292 38 48 55)
    (demo-fill! pixels width height 76 80 274 274 65 82 91)
    (demo-fill! pixels width height 104 108 246 246 202 173 120)
    (demo-fill! pixels width height 498 168 618 308 105 69 50)
    (demo-fill! pixels width height 514 184 602 292 218 177 105)
    (demo-fill! pixels width height 540 206 576 288 244 221 160)
    (demo-fill! pixels width height 166 180 214 310 61 56 49)
    (demo-fill! pixels width height 182 144 198 180 211 183 148)
    (demo-fill! pixels width height 318 172 372 310 57 71 81)
    (demo-fill! pixels width height 334 138 354 174 207 181 157)
    (demo-fill! pixels width height 452 192 492 306 50 88 71)
    (demo-fill! pixels width height 462 162 482 194 195 157 120)
    (demo-fill! pixels width height 0 386 width 432 51 40 34)
    (png-add-text
     (rgb->png width height pixels)
     "Comment"
     "Khala Studio illustrative sample; not generated by an image model.")))

(define (demo-character! config workplace-id name role summary concept
                         literary visual vocal performance outfit)
  (let* ((character-id (db:studio-new-id))
         (character (db:studio-create-character!
                     config character-id workplace-id name role summary
                     (identity-to-json literary)
                     (identity-to-json visual)
                     (identity-to-json vocal)
                     (identity-to-json performance)
                     #:concept concept)))
    (let ((outfit (db:studio-create-character-outfit!
                   config (db:studio-new-id) workplace-id character-id
                   (append
                    `((name . ,(assoc-ref outfit 'name))
                      (kind . ,(assoc-ref outfit 'kind))
                      (description . ,(assoc-ref outfit 'description))
                      (image_prompt . ,(assoc-ref outfit 'image_prompt))
                      (is_default . #t))
                    (map (lambda (key)
                           (cons key
                                 (string-list-json (assoc-ref outfit key))))
                         '(components materials colors accessories
                           special_features))))))
      (cons character outfit))))

(define (demo-storyboard-shots nira-id orin-id tam-id)
  (let ((ids (list nira-id orin-id tam-id)))
    (map
     (lambda (index)
       (let* ((beat
               (list-ref
                '(("The lamp keeper refuses the surveyor's warning as the tide reaches the gate."
                   "Nira keeps one hand on the lamp mechanism and stands between Orin and the stair."
                   nira
                   ("Nira Vale")
                   "Controlled anger; gaze fixed on the oil trail."
                   "Still posture, then a sharp turn toward the door as water crosses the threshold."
                   "Wide establishing frame from the tide gate; figures small against black water."
                   "A wide cinematic 16:9 frame of a stone tide gate at night, a woman in a charcoal oilskin coat guarding a brass lamp mechanism while a blue-coated surveyor waits below.")
                  ("The apprentice exposes a broken seal and forces the lie into the open."
                   "Tam holds up the seal; Orin looks away, caught between relief and guilt."
                   all
                   ("Nira Vale" "Orin Sable" "Tam Rhee")
                   "Tam is frightened but determined; Orin's jaw tightens."
                   "Tam steps forward, then retreats half a pace when Nira turns."
                   "Tight three-shot across a scarred workbench, warm lamp light on brass."
                   "A tight cinematic 16:9 three-shot around a wooden workbench, an apprentice presenting a broken brass seal while two adults avoid each other's eyes.")
                  ("Nira relights the lamp before she answers Orin."
                   "The flame reveals the flooded floor and the truth Orin tried to hide."
                   nira-orin
                   ("Nira Vale" "Orin Sable")
                   "Nira's fear settles into resolve; Orin squints against the light."
                   "Nira kneels to shield the flame, then rises without looking at him."
                   "Low angle on the lamp flare, long silhouettes crossing the tide gate."
                   "A low-angle cinematic 16:9 frame as a brass lamp flares with warm light in a flooded stone chamber, silhouettes stretching across the wet floor.")
                  ("At the threshold, Nira chooses what the lamp will remember."
                   "Nira closes the lamp shutter and names the price of Orin's help."
                   nira
                   ("Nira Vale")
                   "Quiet exhaustion with a new resolve."
                   "She stands alone, palms flat on the lamp housing, breathing measured."
                   "Close profile with the dark tide gate soft behind her."
                   "A close cinematic 16:9 profile of a lamp keeper in a charcoal coat, palms flat on a brass lamp, warm light fading across her face."))
                index))
             (selection (list-ref beat 2))
             (ids (case selection
                    ((all) (list nira-id orin-id tam-id))
                    ((nira-orin) (list nira-id orin-id))
                    (else (list nira-id))))
             (names (case selection
                      ((all) (list "Nira Vale" "Orin Sable" "Tam Rhee"))
                      ((nira-orin) (list "Nira Vale" "Orin Sable"))
                      (else (list "Nira Vale")))))
         `(("id" . ,(db:studio-new-id))
           ("number" . ,(+ index 1))
           ("dramatic_beat" . ,(list-ref beat 0))
           ("action" . ,(list-ref beat 1))
           ("content" . ,(list-ref beat 1))
           ("character_ids" . ,ids)
           ("characters" . ,names)
           ("camera" . ,(list-ref beat 6))
           ("expression" . ,(list-ref beat 4))
           ("performance" . ,(list-ref beat 5))
           ("expression_action" . ,(string-join (list (list-ref beat 4)
                                                     (list-ref beat 5))
                                                "\n\n"))
           ("visual_description" . ,(list-ref beat 7))
           ("image_prompt" . ,(list-ref beat 7))
           ("asset_id" . null)
           ("file_url" . null)
           ("status" . "pending")
           ("source" . "sample")
           ("model" . "sample")
           ("character_outfits" . ())
           ("reference_usage" . null)
           ("author_edited" . #f))))
     (iota 4))))

(define (demo-payload config created)
  (let* ((workplace (find (lambda (item)
                            (equal? (assoc-ref item 'title)
                                    demo-workplace-title))
                          (db:studio-list-workplaces config)))
         (wid (and workplace (assoc-ref workplace 'id)))
         (characters (and wid (db:studio-list-characters config wid)))
         (documents (and wid (db:studio-list-documents config wid)))
         (scenes (and wid (db:studio-list-scenes config wid)))
         (document (and documents (car documents)))
         (scene (and scenes (car scenes)))
         (assets (and wid (db:studio-list-assets config wid)))
         (asset (find (lambda (item)
                        (equal? (assoc-ref item 'source) "imported"))
                      assets)))
    `(("created" . ,(and created #t))
      ("workplace" . ,(public-workplace workplace))
      ("characters" . ,(map (lambda (character)
                              (public-character-with-avatar config character))
                            (or characters '())))
      ("document" . ,(and document (public-document document
                                                     #:include-content #t)))
      ("scene" . ,(and scene (public-scene scene #:include-source-text #t)))
      ("cast" . ,(if scene
                     (map public-scene-cast
                          (db:studio-list-scene-cast config wid
                                                   (assoc-ref scene 'id)))
                     '()))
      ("storyboard" . ,(and scene (storyboard-payload config scene)))
      ("asset" . ,(and asset (public-asset asset #:include-links #t
                                           #:config config)))
      ("note" . "示例资料独立存放于 [SAMPLE] Workplace；图片是明确标注的示意占位，不是图像模型生成结果。"))))

(define (studio-create-demo! config)
  (let ((existing (find (lambda (item)
                          (equal? (assoc-ref item 'title)
                                  demo-workplace-title))
                        (db:studio-list-workplaces config))))
    (if existing
        (demo-payload config #f)
        (let* ((workplace
                (db:studio-create-workplace!
                 config (db:studio-new-id) demo-workplace-title
                 "一个可完整演示的示例故事：从人物、正文、Scene 到 Storyboard 与图片资源。"
                 "#713D3B" #f))
               (wid (assoc-ref workplace 'id))
               (nira
                (demo-character!
                 config wid "Nira Vale" "Lamp Keeper"
                 "守着潮门最后一盏灯的机械师；不肯承认自己需要别人。"
                 "Nira inherited the tide-gate lamp from her mother and has kept it burning for eleven years. She believes the harbor survives because someone stays awake, not because anyone is rescued."
                 `((background . "Raised in the tide-gate workshop after the harbor surveys were abandoned.")
                   (personality . "Watchful, exacting, privately generous; she tests people by what they do when no one thanks them.")
                   (values . "Steadiness, craft, and keeping a light for people who cannot repay it.")
                   (motivations . "To keep the lamp and the harbor from becoming another official ruin.")
                   (fears . "That accepting help will prove she cannot hold the gate alone.")
                   (goals . "Find who opened the lamp valve before the next high tide.")
                   (relationships . "Orin was once her closest ally; Tam is the apprentice she pretends not to protect.")
                   (arc . "From guarding the light alone to deciding who is allowed to share the watch."))
                 `((standard_appearance . "A compact lamp keeper in a long charcoal oilskin coat, soot-dark cuffs and a brass lamp key at her throat.")
                   (face . "Angular face, a thin scar through the left eyebrow, amber eyes set in a habitual squint against lamplight.")
                   (body . "Lean and strong-shouldered, with the slight asymmetry of years spent carrying lamp housings.")
                   (hair . "Dark auburn hair braided low and tied with a faded oxblood ribbon.")
                   (eyes . "Amber; direct and unblinking when challenged.")
                   (skin . "Warm weathered skin, freckled across the nose, soot on the knuckles.")
                   (distinctive_features . "Thin scar through the left eyebrow and a brass lamp key worn outside the coat.")
                   (clothing . "Charcoal oilskin work coat, dark trousers, leather boots and a repaired oxblood scarf.")
                   (palette . "Charcoal, oxblood, aged brass and sea-grey.")
                   (expressions . "Anger reads as stillness; tenderness appears only in the way she lowers her voice.")
                   (posture . "Grounded stance, one shoulder slightly forward, hands never far from a tool."))
                 `((voice_character . "Low and dry, with the cadence of someone used to giving instructions across weather.")
                   (timbre . "Warm-grained, slightly rough from lamp smoke.")
                   (range . "Narrow middle register; drops lower when frightened.")
                   (pitch . "Low for her build.")
                   (accent . "Tide-gate harbor accent, clipped and practical.")
                   (pronunciation . "Precise consonants; shortens official names with visible impatience.")
                   (pace . "Measured, with long pauses before personal answers.")
                   (speech_habits . "Names lamp parts by number and avoids saying 'help' aloud."))
                 `((habits . "Checks the lamp shutter twice before leaving a room.")
                   (movement . "Economical, deliberate; crosses a room by the shortest safe line.")
                   (gestures . "Taps the brass key against her thumb while thinking.")
                   (emotional_responses . "Withdraws into precision when threatened; becomes blunt and honest when exhausted.")
                   (behavioral_traits . "Fixes a small visible problem before addressing the larger danger.")
                   (typical_reactions . "Positions herself between an exit and whoever she is protecting.")
                   (situations . "Defiant under authority, patient with Tam, unguarded only in the lamp room after midnight."))
                 '((name . "Harbor Workwear")
                   (kind . "standard")
                   (description . "The practical silhouette Nira wears for every night watch.")
                   (components . ("charcoal oilskin coat" "dark work trousers"
                                  "reinforced leather boots" "oxblood scarf"))
                   (materials . ("waxed canvas" "wool" "leather" "brass"))
                   (colors . ("charcoal" "oxblood" "aged brass" "sea-grey"))
                   (accessories . ("brass lamp key" "small tool case" "lamp gloves"))
                   (special_features . ("ribbon-repaired cuff" "soot-dark left shoulder"))
                   (image_prompt . "Full-length character design of Nira Vale in a charcoal oilskin work coat, oxblood scarf, brass lamp key and weathered leather boots, warm editorial backdrop."))))
               (orin
                (demo-character!
                 config wid "Orin Sable" "Harbor Surveyor"
                 "回来复核潮门的测量员；带着一个迟到十一年的答案。"
                 "Orin left the harbor to work for the regional survey office. He returns with a repair order that would close the tide gate and a confession he cannot deliver cleanly."
                 `((background . "Former harbor apprentice who left after a failed survey and built a career in the capital.")
                   (personality . "Careful, apologetic in words, evasive in action; he believes documentation can repair what people cannot.")
                   (values . "Accuracy, public safety and the possibility of earning forgiveness through procedure.")
                   (motivations . "To close the gate safely and be believed when he says the old lamp cannot be trusted.")
                   (fears . "That Nira will see the order as another abandonment and that he will deserve it.")
                   (goals . "Get Nira to sign the survey and evacuate the lower harbor before the tide.")
                   (relationships . "Once Nira's closest ally; now the bearer of an official order that may destroy her life's work.")
                   (arc . "From hiding behind the survey to admitting he helped create the danger."))
                 `((eyes . "Pale grey eyes that avoid direct contact when he lies.")
                   (skin . "Pale windburned skin, ink stains on the right hand.")
                   (distinctive_features . "Brass compass on a long chain and a repaired split in the map case.")
                   (clothing . "Midnight-blue survey coat, grey waistcoat, leather map satchel, brass compass.")
                   (palette . "Midnight blue, slate grey, worn leather and brass.")
                   (expressions . "Relief looks almost like grief; guilt makes him over-explain.")
                   (posture . "Tall and slightly stooped, as if always folding into a doorway."))
                 `((voice_character . "Polished and careful, with a habit of softening bad news into procedure.")
                   (timbre . "Clear, light and slightly nasal.")
                   (range . "Wide enough for formal reports; thins when he is caught lying.")
                   (pitch . "Mid-range.")
                   (accent . "Capital diction laid over a trace of harbor vowels.")
                   (pronunciation . "Over-precise technical terms; the harbor accent surfaces on names.")
                   (pace . "Even, then too fast when he is defending himself.")
                   (speech_habits . "Begins sentences with 'the survey says' when he is afraid."))
                 `((habits . "Rechecks the compass even when he knows the bearing.")
                   (movement . "Long strides that stop abruptly at thresholds.")
                   (gestures . "Turns the compass chain around one finger while listening.")
                   (emotional_responses . "Retreats into paperwork when ashamed; becomes unexpectedly direct when the danger is physical.")
                   (behavioral_traits . "Documents everything, including things he would rather forget.")
                   (typical_reactions . "Apologises first, then tries to solve the practical problem.")
                   (situations . "Formal with officials, faltering with Nira, gentle and clumsy with Tam."))
                 '((name . "Surveyor's Field Dress")
                   (kind . "standard")
                   (description . "Orin's official field silhouette, built for wind, rain and paperwork.")
                   (components . ("midnight-blue survey coat" "grey waistcoat"
                                  "leather map satchel" "brass compass"))
                   (materials . ("wool" "leather" "brass" "paper"))
                   (colors . ("midnight blue" "slate grey" "worn leather" "brass"))
                   (accessories . ("brass compass" "folded survey" "ink pen"))
                   (special_features . ("repaired map-case split" "red survey seal"))
                   (image_prompt . "Full-length character design of Orin Sable in a midnight-blue survey coat, grey waistcoat, leather map satchel and brass compass, warm editorial backdrop."))))
               (tam
                (demo-character!
                 config wid "Tam Rhee" "Lamp Apprentice"
                 "在潮门长大的年轻学徒；比两个成年人都更早看见真相。"
                 "Tam keeps the lamp wicks and the workshop ledgers. They are quicker with details than with confrontation, but they will not let a dangerous lie pass unchallenged."
                 `((background . "Grew up in the lower harbor and came to the lamp workshop after the last flood took their family's shop.")
                   (personality . "Curious, observant and braver than they believe; jokes when nervous.")
                   (values . "Fairness, practical care and not letting the same mistake happen twice.")
                   (motivations . "To be trusted with real responsibility rather than protected from it.")
                   (fears . "Being sent away when the adults decide the danger is too large.")
                   (goals . "Prove that the lamp was opened from inside and keep Nira from facing the truth alone.")
                   (relationships . "Looks to Nira as a teacher and to Orin as proof that clever people can still be wrong.")
                   (arc . "From carrying messages to speaking the truth in front of both adults."))
                 `((standard_appearance . "A young apprentice in patched canvas layers and a green wool scarf, always carrying a ledger.")
                   (face . "Open face with a small chin scar and quick dark eyes.")
                   (body . "Small, wiry build; moves faster than expected in cramped spaces.")
                   (hair . "Short-cropped black hair with a stubborn cowlick.")
                   (eyes . "Dark brown, alert and constantly measuring the room.")
                   (skin . "Warm copper skin, ink-stained fingertips.")
                   (distinctive_features . "Small chin scar and a green scarf knitted too long.")
                   (clothing . "Patched canvas jacket, rolled sleeves, green wool scarf and a canvas ledger satchel.")
                   (palette . "Moss green, canvas tan, ink black and brass.")
                   (expressions . "Fear shows as a rush of words; resolve shows as sudden quiet.")
                   (posture . "Perched forward, ready to move or hand something over."))
                 `((voice_character . "Bright and quick, with a habit of finishing a thought before it is welcome.")
                   (timbre . "Clear and slightly breathless.")
                   (range . "Light middle register with an easy upward break.")
                   (pitch . "Higher than the adults without sounding childish.")
                   (accent . "Lower-harbor accent, softened by reading.")
                   (pronunciation . "Trips over long official words, then repeats them perfectly.")
                   (pace . "Fast, with sudden stops when Nira looks at them.")
                   (speech_habits . "Says 'the ledger says' when nervous."))
                 `((habits . "Writes the time on every new page before using it.")
                   (movement . "Quick, light steps; slips sideways through narrow gaps.")
                   (gestures . "Holds the ledger against their chest when uncertain.")
                   (emotional_responses . "Talks faster when afraid; goes very still when deciding to disobey.")
                   (behavioral_traits . "Notices mismatched numbers before mismatched moods.")
                   (typical_reactions . "Checks whether they are believed before saying anything else.")
                   (situations . "Eager with Orin, defensive with Nira, steady when the lamp is actually failing."))
                 '((name . "Apprentice Layers")
                   (kind . "standard")
                   (description . "Tam's patched working clothes, chosen for lamp rooms and cold stairs.")
                   (components . ("patched canvas jacket" "rolled work shirt"
                                  "green wool scarf" "ledger satchel"))
                   (materials . ("canvas" "wool" "leather" "paper"))
                   (colors . ("moss green" "canvas tan" "ink black" "brass"))
                   (accessories . ("lamp wick knife" "ink pencil" "ledger satchel"))
                   (special_features . ("overlong hand-knitted scarf" "ink-stained cuffs"))
                   (image_prompt . "Full-length character design of Tam Rhee, a young lamp apprentice in patched canvas layers, moss-green scarf and a ledger satchel, warm editorial backdrop."))))
               (story
                (string-join
                 '("# The Last Lamp"
                   ""
                   "The tide gate had been dark for eleven years when Nira heard the surveyor's boots on the stair."
                   ""
                   "She did not turn from the lamp. Its brass housing was warm under her palm, the shutter breathing a thin gold line across the flooded stone. Behind her, Tam stopped writing. The ledger pages rustled once and went still."
                   ""
                   "\"The office has signed the closure,\" Orin said. \"The lower gate comes down before midnight. You need to leave the lamp.\""
                   ""
                   "Nira looked at the oil trail on the floor. It began at the lamp valve, crossed the threshold and ended under Orin's boot. \"You came a long way to tell me something I already know.\""
                   ""
                   "Tam stepped out from the workbench with a broken brass seal in their palm. \"It was opened from inside,\" they said. \"The ledger says the valve was shut at dusk. This seal was cut after.\""
                   ""
                   "Orin's hand went to the compass at his chest. He did not open it. \"The survey was wrong eleven years ago,\" he said. \"I signed a report that said this gate could hold. I have been trying to correct it ever since.\""
                   ""
                   "The water crossed the first step. Nira struck a match. The flame caught, and the tide gate filled with a light that made every lie visible."
                   ""
                   "\"Then correct it here,\" she said. \"Before the tide decides what your signature is worth.\"")
                 "\n"))
               (document
                (db:studio-create-document!
                 config (db:studio-new-id) wid #f "manuscript"
                 "The Last Lamp" story "markdown" 0))
               (version-id (db:studio-new-id))
               (_version
                (db:studio-create-version! config wid (assoc-ref document 'id)
                                           version-id "Opening Conflict"
                                           "checkpoint"))
               (excerpt "The tide gate had been dark for eleven years when Nira heard the surveyor's boots on the stair.")
               (excerpt-start (string-contains story excerpt))
               (excerpt-end (+ excerpt-start (string-length excerpt)))
               (scene-id (db:studio-new-id))
               (scene
                (db:studio-create-extracted-scene!
                 config scene-id wid
                 `((title . "The Lamp at the Tide Gate")
                   (summary . "Nira, Orin and Tam confront the broken seal while the tide rises and an old betrayal becomes actionable.")
                   (sort_order . 1)
                   (status . "ready")
                   (time . "Eleven years after the lower harbor flood; shortly before midnight")
                   (place . "The tide-gate lamp room")
                   (environment . "Black water crossing the stone floor, one warm lamp, cold air from the open stair.")
                   (background . "The harbor survey office has ordered the lower gate closed and the lamp abandoned.")
                   (prior_events . "Tam discovered that the lamp valve had been opened from inside after dusk.")
                   (central_question . "Will Nira accept Orin's help before the tide makes the choice for them?")
                   (primary_conflict . "Nira needs the truth and the lamp; Orin needs absolution through procedure; neither can move without admitting dependence.")
                   (turn . "Tam reveals the broken seal, proving the danger was set in motion inside the lamp room.")
                   (dialogue . "ORIN\nThe office has signed the closure. You need to leave the lamp.\n\nNIRA\nYou came a long way to tell me something I already know.\n\nTAM\nIt was opened from inside. This seal was cut after dusk.\n\nNIRA\nThen correct it here, before the tide decides what your signature is worth.")
                   (blocking . "Nira stays beside the lamp; Orin remains below the threshold; Tam moves between the workbench and the oil trail.")
                   (spatial . "The lamp housing dominates the room. The stair and the rising water create a narrow corridor between the three figures.")
                   (performance_direction . "Keep the adults still and let Tam's movement carry the turn. The lamp flare should feel like an answer, not a spectacle.")
                   (camera . "Begin wide from the tide gate, move to a three-shot at the workbench, then hold a low close-up on the relit lamp.")
                   (source_document_id . ,(assoc-ref document 'id))
                   (source_document_version_id . ,version-id)
                   (source_document_revision . ,(assoc-ref document 'revision))
                   (source_text_snapshot . ,excerpt)
                   (source_selection_start . ,excerpt-start)
                   (source_selection_end . ,excerpt-end))
                 (list
                  `((character_id . ,(assoc-ref (car nira) 'id))
                    (objective . "Keep the lamp burning and force Orin to tell the truth without asking for help.")
                    (action . "She holds the lamp mechanism and refuses to step away from it.")
                    (conflict . "Orin's official order and the rising water make independence impossible.")
                    (emotional_state . "Controlled anger over fear.")
                    (performance_direction . "Still hands; one sharp turn when the seal appears.")
                    (subtext . "She has already decided to relight the lamp; she is waiting to see who will stay.")
                    (sort_order . 0))
                  `((character_id . ,(assoc-ref (car orin) 'id))
                    (objective . "Get Nira to sign the closure and leave before the gate fails.")
                    (action . "He presents the order, avoids the oil trail and finally admits his old report was wrong.")
                    (conflict . "Nira's refusal and Tam's evidence make procedure useless.")
                    (emotional_state . "Guilt disguised as calm.")
                    (performance_direction . "He touches the compass but never opens it.")
                    (subtext . "He wants forgiveness more than compliance.")
                    (sort_order . 1))
                  `((character_id . ,(assoc-ref (car tam) 'id))
                    (objective . "Make the adults see the broken seal before it is too late.")
                    (action . "They step forward with the seal, then retreat half a pace.")
                    (conflict . "They are afraid of being dismissed as a child.")
                    (emotional_state . "Fear held together by determination.")
                    (performance_direction . "Quick words, then sudden stillness after presenting the seal.")
                    (subtext . "They need to be trusted with what they already know.")
                    (sort_order . 2)))))
               (asset-id (db:studio-new-id))
               (storage-key (fs:studio-asset-storage-key asset-id ".png"))
               (png-bytes (demo-illustrative-png))
               (checksum
                (catch #t
                  (lambda ()
                    (fs:studio-asset-store-file! config storage-key png-bytes))
                  (lambda (key . args)
                    (apply throw key args))))
               (asset
                (catch #t
                  (lambda ()
                    (db:studio-create-asset!
                     config asset-id wid
                     `((name . "Tide Gate — Illustrative Storyboard Plate")
                       (description . "示例用途的示意画面，用于演示 Scene 与 Asset 关联；不是图像模型生成结果。")
                       (asset_type . "image")
                       (storage_key . ,storage-key)
                       (original_filename . "sample-tide-gate.png")
                       (mime_type . "image/png")
                       (file_size . ,(bytevector-length png-bytes))
                       (checksum . ,checksum)
                       (source . "imported")
                       (width . 768)
                       (height . 432)
                       (duration_ms . #f)
                       (author . "Khala Studio sample")
                       (notes . "Illustrative placeholder only. generated_by_model=false; engine=fake.")
                       (generation_metadata
                        . ,(json-encode
                            (json-normalize
                             '(("sample" . #t)
                               ("illustrative" . #t)
                               ("provenance" . "illustrative placeholder")
                               ("generated_by_model" . #f)
                               ("engine" . "fake")
                               ("workplace_title" . "[SAMPLE] The Last Lamp")))))
                       (tags . ("sample" "illustrative" "storyboard")))))
                  (lambda (key . args)
                    (fs:studio-asset-delete-file! config storage-key)
                    (apply throw key args)))))
      (db:studio-add-asset-link! config wid (assoc-ref asset 'id)
                                 "scene" scene-id)
      (db:studio-set-scene-references!
       config wid scene-id (string-list-json (list (assoc-ref asset 'id))))
      (db:studio-update-scene!
       config wid scene-id
       `((storyboard . ,(storyboard-json
                         (demo-storyboard-shots
                          (assoc-ref (car nira) 'id)
                          (assoc-ref (car orin) 'id)
                          (assoc-ref (car tam) 'id))))))
      (db:studio-touch-workplace! config wid)
      (demo-payload config #t)))))

(define acceptance-task-specs
  '(("character_development" . "Character Development")
    ("scene_extraction" . "Scene Extraction")
    ("storyboard_planning" . "Storyboard Planning")))

(define (acceptance-task-spec task)
  (or (assoc task acceptance-task-specs)
      (api-fail 404 "NOT_FOUND" "Acceptance task not found")))

(define (acceptance-resolved-task config task)
  (let* ((profile (profile-for-task config task))
         (engine (and (not profile) (configured-engine config)))
         (model (if profile
                    (assoc-ref profile 'model_id)
                    (and (configured-model config) (configured-model config))))
         (protocol (if profile
                       (assoc-ref profile 'protocol)
                       engine)))
    `(("task" . ,task)
      ("label" . ,(cdr (acceptance-task-spec task)))
      ("configured" . ,(and (or profile model) #t))
      ("profile_id" . ,(mark (and profile (assoc-ref profile 'id))))
      ("profile_name" . ,(mark (and profile (assoc-ref profile 'name))))
      ("model" . ,(mark model))
      ("protocol" . ,(mark protocol))
      ("base_url" . ,(mark (and profile (assoc-ref profile 'base_url))))
      ("external_provider" . ,(and profile
                                    (not (equal? protocol "fake"))
                                    #t))
      ("may_incur_charges" . ,(and protocol
                                   (not (equal? protocol "fake"))
                                   #t)))))

(define (studio-acceptance-overview config)
  (ensure-legacy-model-profile! config)
  (let* ((embedding-setting (db:studio-get-setting
                             config "default_embedding_profile_id"))
         (embedding (and embedding-setting
                         (db:studio-get-embedding-profile
                          config embedding-setting))))
    `(("tasks" . ,(map (lambda (entry)
                         (acceptance-resolved-task config (car entry)))
                       acceptance-task-specs))
      ("embedding" .
       (("configured" . ,(and embedding #t))
        ("profile_id" . ,(mark (and embedding (assoc-ref embedding 'id))))
        ("profile_name" . ,(mark (and embedding (assoc-ref embedding 'name))))
        ("model" . ,(mark (and embedding (assoc-ref embedding 'model_id))))
        ("protocol" . ,(mark (and embedding (assoc-ref embedding 'protocol))))
        ("dimensions" . ,(mark (and embedding
                                    (assoc-ref embedding 'dimensions))))
        ("may_incur_charges" . ,(and embedding #t))))
      ("warning" . "Manual acceptance only. Each run is explicitly triggered, makes exactly one provider request and is never retried automatically.")
      ("embedding_note" . "Embedding is tested separately from LLM tasks and does not participate in task fallback."))))

(define acceptance-character-id "11111111-1111-4111-8111-111111111111")
(define acceptance-second-character-id "22222222-2222-4222-8222-222222222222")

(define (acceptance-character)
  `((id . ,acceptance-character-id)
    (workplace_id . ,acceptance-character-id)
    (name . "Acceptance Mechanic")
    (role . "Protagonist")
    (summary . "A mechanic who refuses to depend on anyone.")
    (concept . "A young mechanic in a rain-soaked harbor workshop who refuses to depend on anyone.")
    (literary_identity . "{}")
    (visual_identity . "{}")
    (vocal_identity . "{}")
    (performance_identity . "{}")
    (avatar_asset_id . #f)
    (full_body_asset_id . #f)
    (created_at . "") (updated_at . "") (archived_at . #f)))

(define (acceptance-scene)
  `((id . ,acceptance-character-id)
    (workplace_id . ,acceptance-character-id)
    (title . "The Locked Workshop")
    (summary . "A visitor brings evidence while the mechanic refuses help.")
    (time . "Late evening")
    (place . "A repair workshop beside the rail yard")
    (environment . "Oil lamps, cold rain and a half-dismantled engine")
    (background . "The workshop survives on independent commissions.")
    (prior_events . "An important machine was deliberately damaged.")
    (central_question . "Will the mechanic accept help before the workshop is lost?")
    (primary_conflict . "She needs information; accepting it would make her dependent.")
    (turn . "The visitor names a detail only a witness could know.")
    (dialogue . "MECHANIC\nYou came a long way to tell me something I already know.")
    (blocking . "The mechanic remains between the visitor and the engine.")
    (spatial . "A narrow workbench divides the figures.")
    (performance_direction . "Neither moves toward the other.")
    (camera . "Medium two-shot.")))

(define (acceptance-characters)
  (list (acceptance-character)))

(define (acceptance-reference-line)
  "Reference image metadata: one illustrative scene plate; pixels were not inspected by the model.")

(define (acceptance-elapsed-ms began)
  (quotient (* (- (get-internal-real-time) began) 1000)
            internal-time-units-per-second))

(define (acceptance-preview text)
  (substring (or text "") 0 (min 600 (string-length (or text "")))))

(define (acceptance-response config task prepared text elapsed validation)
  `(("task" . ,task)
    ("profile_id" . ,(mark (assoc-ref prepared 'profile_id)))
    ("profile_name" . ,(mark (assoc-ref prepared 'profile_name)))
    ("model" . ,(mark (assoc-ref prepared 'model)))
    ("protocol" . ,(mark (or (assoc-ref prepared 'protocol)
                             (configured-engine config))))
    ("valid" . #t)
    ("validation" . ,validation)
    ("elapsed_ms" . ,elapsed)
    ("preview" . ,(acceptance-preview text))))

(define (studio-run-acceptance! config task body)
  (let* ((body (or body '()))
         (spec (acceptance-task-spec task))
         (_ (unless (eq? (object-ref body "confirm_charge") #t)
              (api-fail 400 "CONFIRMATION_REQUIRED"
                        "Set confirm_charge to true after reviewing the profile and possible charges")))
         (began (get-internal-real-time)))
    (case (string->symbol task)
      ((character_development)
       (let* ((character (acceptance-character))
              (model/text (character-run-development-ai
                           config character body #f))
              (text (cadr model/text))
              (identities (character-ai-full-identities text))
              (prepared (prepare-task-chat
                         config "character_development" '()
                         '(("temperature" . 0.7) ("format" . "json")) body)))
         (acceptance-response
          config task prepared text (acceptance-elapsed-ms began)
          `(("sections" . ,(map (lambda (entry)
                                  (cons (car entry)
                                        (length (cdr entry))))
                                identities))
            ("draft_persisted" . #f)))))
      ((scene_extraction)
       (let* ((document `((id . ,acceptance-character-id)
                          (title . "Acceptance Scene Passage")
                          (content . "Nira kept one hand on the lamp and refused to step aside. Orin held up the signed order. Tam placed the broken seal on the workbench and waited for one of them to admit the danger was already inside.")))
              (characters (acceptance-characters))
              (prepared (scene-extraction-prepared
                         config body document 1 "document" #f #f
                         (assoc-ref document 'content) characters))
              (result (studio-run-ai prepared))
              (text (or (assoc-ref result 'text) ""))
              (draft (studio-validate-scene-extraction-json text characters)))
         (acceptance-response
          config task prepared text (acceptance-elapsed-ms began)
          `(("title" . ,(assoc-ref draft 'title))
            ("cast_count" . ,(length (assoc-ref draft 'cast)))
            ("unresolved_count" . ,(length (assoc-ref draft 'unresolved_characters)))
            ("persisted" . #f)))))
      ((storyboard_planning)
       (let* ((characters (acceptance-characters))
              (cast
               (list
                `((character_id . ,acceptance-character-id)
                  (character_name . "Acceptance Mechanic")
                  (objective . "Keep control of the workshop.")
                  (action . "Block the doorway.")
                  (conflict . "She needs the visitor's evidence.")
                  (emotional_state . "Controlled anger.")
                  (performance_direction . "Still hands.")
                  (subtext . "She already knows the visitor is right."))))
              (scene (acceptance-scene))
              (prepared (storyboard-ai-prepared
                         config scene cast characters
                         (list (acceptance-reference-line)) body))
              (result (studio-run-ai prepared))
              (text (or (assoc-ref result 'text) ""))
              (shots (studio-validate-storyboard-json
                      text (list acceptance-character-id))))
         (acceptance-response
          config task prepared text (acceptance-elapsed-ms began)
          `(("shot_count" . ,(length shots))
            ("character_ids_preserved" . #t)
            ("persisted" . #f)))))
      (else (api-fail 404 "NOT_FOUND" "Acceptance task not found")))))

(define (identity-from-body body key)
  (if (not (object-has? body key))
      "{}"
      (let ((incoming (object-ref body key)))
        (unless (or (null? incoming) (object? incoming))
          (api-fail 400 "VALIDATION_ERROR"
                    (format #f "~a must be an object" key)))
        (identity-to-json (merge-identity key '() incoming)))))

(define (studio-list-characters config workplace-id)
  (let ((workplace (require-workplace config workplace-id)))
    (map (lambda (character)
           (public-character-with-avatar config character))
         (db:studio-list-characters config (assoc-ref workplace 'id)))))

(define (studio-create-character! config workplace-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (name (string-field body "name" #:required #t
                             #:max max-title-length))
         (role (string-field body "role" #:allow-empty #t
                             #:default "" #:max max-character-role-length))
         (summary (string-field body "summary" #:allow-empty #t
                                #:default "" #:max max-description-length))
         (concept (string-field body "concept" #:allow-empty #t
                                #:default "" #:max max-description-length))
         (literary (identity-from-body body "literary_identity"))
         (visual (identity-from-body body "visual_identity"))
         (vocal (identity-from-body body "vocal_identity"))
         (performance (identity-from-body body "performance_identity")))
    (public-character
     (db:studio-create-character! config (db:studio-new-id) wid name role
                                  summary literary visual vocal performance
                                  #:concept concept))))

(define (studio-get-character config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (public-character-with-avatar
     config (require-character config wid character-id))))

(define (studio-update-character! config workplace-id character-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (updates '()))
    (when (object-has? body "name")
      (set! updates
            (acons 'name (string-field body "name" #:required #t
                                       #:max max-title-length)
                   updates)))
    (when (object-has? body "role")
      (set! updates
            (acons 'role (string-field body "role" #:allow-empty #t
                                       #:default "" #:max max-character-role-length)
                   updates)))
    (when (object-has? body "summary")
      (set! updates
            (acons 'summary (string-field body "summary" #:allow-empty #t
                                          #:default "" #:max max-description-length)
                   updates)))
    (when (object-has? body "concept")
      (set! updates
            (acons 'concept (string-field body "concept" #:allow-empty #t
                                          #:default ""
                                          #:max max-description-length)
                   updates)))
    (for-each
     (lambda (key)
       (when (object-has? body key)
         (let* ((column (string->symbol key))
                (current (identity-from-json (assoc-ref character column)))
                (incoming (object-ref body key))
                (merged (merge-identity key current incoming)))
           (set! updates
                 (acons column (identity-to-json merged) updates)))))
     '("literary_identity" "visual_identity"
       "vocal_identity" "performance_identity"))
    (if (null? updates)
        (public-character-with-avatar config character)
        (public-character-with-avatar
         config
         (or (db:studio-update-character! config wid cid updates)
             (api-fail 404 "NOT_FOUND" "Character not found"))))))

(define (studio-archive-character! config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (archived (db:studio-archive-character! config wid cid)))
    (or archived
        (api-fail 404 "NOT_FOUND" "Character not found"))
    `(("id" . ,cid)
      ("workplace_id" . ,wid)
      ("archived_at" . ,archived))))

;; Character Studio: AI proposals are drafts. Only the explicit apply step
;; writes an identity section onto studio_characters. Outfits and artwork keep
;; their own author-controlled approval pointers.
(define character-section-order
  '("literary_identity" "visual_identity"
    "vocal_identity" "performance_identity"))

(define character-artwork-specs
  '(("avatar" "portrait" 768 768
     "Head-and-shoulders portrait. The face is the focal point, with a calm editorial background and enough negative space for a character index card.")
    ("full_body" "full body" 768 1024
     "Full-body standing character study. Show the complete silhouette, posture, hands and footwear without cropping the figure.")
    ("character_sheet" "character sheet" 1024 1024
     "Production character sheet on a restrained paper background: one clear full-body turn, a smaller three-quarter view, face details, colour swatches and concise visual-canon notes.")
    ("expression_sheet" "expression sheet" 1024 768
     "Expression reference sheet arranged as a clean grid of six subtle facial expressions, keeping the same face, hair, age and identity in every panel.")
    ("outfit" "outfit artwork" 768 1024
     "Full-length outfit design plate. Emphasise the garments, materials, construction, accessories and how the outfit sits on this specific body. Keep the character's face and hair canonical.")))

(define (character-section-key value)
  (let* ((raw (string-downcase (or value "")))
         (key (cond ((member raw character-section-order string=?) raw)
                    ((equal? raw "literary") "literary_identity")
                    ((equal? raw "visual") "visual_identity")
                    ((equal? raw "vocal") "vocal_identity")
                    ((equal? raw "performance") "performance_identity")
                    (else #f))))
    (or key
        (api-fail 404 "NOT_FOUND" "Character identity section not found"))))

(define (character-boolean-field body key)
  (cond ((not (object-has? body key)) #f)
        ((boolean? (object-ref body key)) (object-ref body key))
        (else (api-fail 400 "VALIDATION_ERROR"
                        (format #f "~a must be a boolean" key)))))

(define (character-draft-json value)
  (if (or (not value) (null? value))
      "{}"
      (identity-to-json value)))

(define (public-character-draft draft)
  `(("section" . ,(assoc-ref draft 'section))
    ("content" . ,(identity-from-json (assoc-ref draft 'content)))
    ("source" . ,(assoc-ref draft 'source))
    ("model" . ,(assoc-ref draft 'model))
    ("author_edited" . ,(and (assoc-ref draft 'author_edited) #t))
    ("created_at" . ,(assoc-ref draft 'created_at))
    ("updated_at" . ,(assoc-ref draft 'updated_at))))

(define (public-character-drafts drafts)
  (map public-character-draft drafts))

(define (character-draft-map drafts)
  (map (lambda (draft)
         (cons (assoc-ref draft 'section) draft))
       drafts))

(define (strip-json-fence text)
  (let* ((trimmed (string-trim-both text))
         (without-open
          (if (string-prefix? "```" trimmed)
              (let ((newline (string-index trimmed #\newline)))
                (if newline (substring trimmed (+ newline 1))
                    (substring trimmed 3)))
              trimmed))
         (without-close
          (if (string-suffix? "```" without-open)
              (substring without-open 0 (- (string-length without-open) 3))
              without-open)))
    (string-trim-both without-close)))

(define (character-ai-fail message)
  (api-fail 502 "INVALID_CHARACTER_OUTPUT" message))

(define (character-ai-object text label)
  (unless (string? text)
    (character-ai-fail (format #f "~a returned no JSON" label)))
  (catch #t
    (lambda ()
      (let ((value (json-string->scm (strip-json-fence text))))
        (unless (object? value)
          (character-ai-fail (format #f "~a must be a JSON object" label)))
        value))
    (lambda (key . args)
      (if (eq? key 'studio-api-error)
          (apply throw key args)
          (character-ai-fail (format #f "~a returned invalid JSON" label))))))

(define (character-ai-object-fields object label allowed)
  (unless (object? object)
    (character-ai-fail (format #f "~a must be a JSON object" label)))
  (for-each
   (lambda (entry)
     (unless (member (car entry) allowed)
       (character-ai-fail
        (format #f "~a.~a is not supported" label (car entry)))))
   object))

(define (character-ai-field-value section key value)
  (unless (string? value)
    (character-ai-fail
     (format #f "~a.~a must be a string" section key)))
  (when (> (string-length value) max-identity-field-length)
    (character-ai-fail
     (format #f "~a.~a is too large" section key)))
  (string-trim-both value))

(define (character-ai-section section value)
  (let ((fields (identity-fields section)))
    (character-ai-object-fields value section fields)
    (let ((result
           (map (lambda (entry)
                  (cons (car entry)
                        (character-ai-field-value section (car entry) (cdr entry))))
                value)))
      (unless (any (lambda (entry)
                     (not (string-null? (cdr entry))))
                   result)
        (character-ai-fail
         (format #f "~a must contain at least one identity field" section)))
      result)))

(define (character-input-section section value)
  (unless (or (null? value) (object? value))
    (api-fail 400 "VALIDATION_ERROR"
              (format #f "~a content must be an object" section)))
  (let ((fields (identity-fields section)))
    (for-each
     (lambda (entry)
       (unless (member (car entry) fields)
         (api-fail 400 "VALIDATION_ERROR"
                   (format #f "~a.~a is not supported" section (car entry))))
       (unless (string? (cdr entry))
         (api-fail 400 "VALIDATION_ERROR"
                   (format #f "~a.~a must be a string" section (car entry))))
       (when (> (string-length (cdr entry)) max-identity-field-length)
         (api-fail 400 "VALIDATION_ERROR"
                   (format #f "~a.~a is too large" section (car entry)))))
     value)
    value))

(define (character-ai-full-identities text)
  (let ((root (character-ai-object text "The Character Development response")))
    (character-ai-object-fields root "character" character-section-order)
    (for-each
     (lambda (section)
       (unless (object-has? root section)
         (character-ai-fail
          (format #f "The Character Development response is missing ~a" section))))
     character-section-order)
    (map (lambda (section)
           (cons section (character-ai-section section (object-ref root section))))
         character-section-order)))

(define (character-ai-section-identity section text)
  (let ((root (character-ai-object
               text (format #f "The ~a response" section))))
    (cons section (character-ai-section section root))))

(define (character-canon-identity character section)
  (identity-from-json
   (assoc-ref character (string->symbol section))))

(define (character-drop-locked-fields section incoming current)
  (filter (lambda (entry)
            (let ((locked (assoc-ref current (car entry))))
              (or (not (string? locked))
                  (string-null? (string-trim-both locked)))))
          incoming))

(define (character-ai-identity-lines character section)
  (let* ((identity (character-canon-identity character section))
         (fields (identity-fields section))
         (lines
          (filter-map
           (lambda (field)
             (let ((value (assoc-ref identity field)))
               (and (string? value)
                    (not (string-null? (string-trim-both value)))
                    (format #f "- ~a: ~a" field (string-trim-both value)))))
           fields)))
    (if (null? lines) "- not yet specified" (string-join lines "\n"))))

(define (character-ai-context character)
  (format #f
          "NAME: ~a\nROLE: ~a\nSUMMARY: ~a\nCONCEPT: ~a\n\nAPPROVED CANON — LOCKED\n[literary_identity]\n~a\n[visual_identity]\n~a\n[vocal_identity]\n~a\n[performance_identity]\n~a"
          (assoc-ref character 'name)
          (or (assoc-ref character 'role) "")
          (or (assoc-ref character 'summary) "")
          (or (assoc-ref character 'concept) "")
          (character-ai-identity-lines character "literary_identity")
          (character-ai-identity-lines character "visual_identity")
          (character-ai-identity-lines character "vocal_identity")
          (character-ai-identity-lines character "performance_identity")))

(define (character-development-prompt character body section)
  (let* ((concept (optional-string-field body "concept"
                                          #:max max-description-length))
         (instruction (optional-string-field body "instruction"
                                             #:max max-instruction-length))
         (field-lines
          (string-join
           (map (lambda (entry)
                  (format #f "- ~a: ~a"
                          (car entry) (string-join (cdr entry) ", ")))
                character-identity-specs)
           "\n"))
         (concept-text (if (string-null? concept)
                           (or (assoc-ref character 'concept) "")
                           concept)))
    (if section
        (format #f
                "KHALA_CHARACTER_SECTION: ~a\n\nDevelop only the ~a section for this existing Character Studio character.\n\nAUTHOR CONCEPT\n~a\n\nAUTHOR NOTES\n~a\n\n~a\n\nREQUIRED FIELDS FOR THIS SECTION\n~a\n\nReturn exactly one JSON object whose keys are the requested field names and whose values are concise, concrete strings. Do not wrap the JSON in Markdown. Never contradict locked canon. Leave details not implied by the concept open to interpretation rather than inventing plot events."
                section section
                (if (string-null? concept-text) "(not supplied)" concept-text)
                (if (string-null? instruction) "(none)" instruction)
                (character-ai-context character)
                (string-join (identity-fields section) ", "))
        (format #f
                "KHALA_CHARACTER_DEVELOP\n\nBuild a complete, production-ready Character Studio profile from the author's concept and the already approved canon.\n\nAUTHOR CONCEPT\n~a\n\nAUTHOR NOTES\n~a\n\n~a\n\nALLOWED FIELDS PER SECTION\n~a\n\nReturn exactly one JSON object with the keys literary_identity, visual_identity, vocal_identity and performance_identity. Each value must be an object containing only the allowed field names for that section. Every value must be a concise string. Do not wrap the JSON in Markdown. Locked canon values are immutable; do not repeat or alter them. AI may fill missing details, but must never claim a suggested event already happened."
                (if (string-null? concept-text) "(not supplied)" concept-text)
                (if (string-null? instruction) "(none)" instruction)
                (character-ai-context character)
                field-lines))))

(define (character-run-development-ai config character body section)
  (let* ((messages
          (list
           `(("role" . "system")
             ("content" . ,(read-prompt
                            (if section
                                "character-section.md"
                                "character-develop.md"))))
           `(("role" . "user")
             ("content" . ,(character-development-prompt
                            character body section)))))
         (prepared
          (prepare-task-chat config "character_development" messages
                             '(("temperature" . 0.7)
                               ("num_predict" . 4096)
                               ("max_output_tokens" . 4096)
                               ("stream" . #f)
                               ("format" . "json"))
                             body))
         (model (assoc-ref prepared 'model)))
    (catch #t
      (lambda ()
        (let* ((result (studio-run-ai prepared))
               (text (or (assoc-ref result 'text)
                         (assoc-ref result "text")
                         "")))
          (list model text)))
      (lambda (key . args)
        (if (eq? key 'studio-api-error)
            (apply throw key args)
            (begin
              (format (current-error-port)
                      "Character development generation failed: ~s ~s~%"
                      key args)
              (api-fail 502 "GENERATION_FAILED"
                        "Character development generation failed")))))))

(define (studio-list-character-drafts config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id)))
    (public-character-drafts
     (db:studio-list-character-drafts config wid (assoc-ref character 'id)))))

(define (studio-develop-character! config workplace-id character-id body section)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (section (and section (character-section-key section)))
         (requested (if section (list section) character-section-order))
         (force (character-boolean-field body "force"))
         (existing (db:studio-list-character-drafts config wid cid))
         (edited
          (filter (lambda (draft)
                    (and (member (assoc-ref draft 'section) requested string=?)
                         (assoc-ref draft 'author_edited)))
                  existing)))
    (when (and (pair? edited) (not force))
      (api-fail 409 "DRAFT_PROTECTED"
                "AI regeneration would overwrite an author-edited draft"
                (cons "sections"
                      (map (lambda (draft) (assoc-ref draft 'section)) edited))))
    (let* ((model/text (character-run-development-ai
                        config character body section))
           (model (car model/text))
           (text (cadr model/text))
           (identities
            (if section
                (list (character-ai-section-identity section text))
                (character-ai-full-identities text))))
      (for-each
       (lambda (entry)
         (let* ((key (car entry))
                (incoming (cdr entry))
                (current (character-canon-identity character key))
                (filtered (character-drop-locked-fields key incoming current)))
           (db:studio-save-character-draft!
            config wid cid key (character-draft-json filtered)
            "ai" model #f)))
       identities)
      (let ((saved (db:studio-list-character-drafts config wid cid)))
        (public-character-drafts
         (if section
             (filter (lambda (draft)
                       (equal? (assoc-ref draft 'section) section))
                     saved)
             saved))))))

(define (studio-update-character-draft! config workplace-id character-id
                                        section body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (key (character-section-key section)))
    (unless (object-has? body "content")
      (api-fail 400 "VALIDATION_ERROR" "content is required"))
    (let* ((incoming (object-ref body "content"))
           (validated (character-input-section key incoming)))
      (public-character-draft
       (db:studio-save-character-draft!
        config wid cid key (character-draft-json validated)
        "author" "" #t)))))

(define (studio-apply-character-draft! config workplace-id character-id section)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (key (character-section-key section))
         (draft (db:studio-get-character-draft config wid cid key)))
    (unless draft
      (api-fail 404 "NOT_FOUND" "Character draft not found"))
    (let* ((incoming (identity-from-json (assoc-ref draft 'content)))
           (current (character-canon-identity character key))
           (merged (merge-identity key current incoming)))
      (public-character-with-avatar
       config
       (db:studio-apply-character-draft!
        config wid cid key (identity-to-json merged))))))

(define (studio-discard-character-draft! config workplace-id character-id section)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (key (character-section-key section))
         (removed (db:studio-delete-character-draft! config wid cid key)))
    (unless removed
      (api-fail 404 "NOT_FOUND" "Character draft not found"))
    `(("character_id" . ,cid)
      ("section" . ,key)
      ("removed" . #t))))

(define (json-string-list text)
  (cond
   ((vector? text) (vector->list text))
   ((list? text) text)
   ((or (not (string? text)) (string-null? text)) '())
   (else
    (catch #t
      (lambda ()
        (let ((value (json-string->scm text)))
          (cond ((vector? value) (vector->list value))
                ((list? value) value)
                (else '()))))
      (lambda _ '())))))

(define (string-list-json values)
  (json-encode (json-normalize (if (list? values) values '()))))

(define (character-string-list-field body key label default)
  (if (not (object-has? body key))
      (string-list-json default)
      (let ((values (json-array-values (object-ref body key) label)))
        (when (> (length values) 64)
          (api-fail 400 "VALIDATION_ERROR"
                    (format #f "~a has too many entries" label)))
        (let loop ((rest values) (result '()))
          (if (null? rest)
              (string-list-json (reverse result))
              (let ((value (car rest)))
                (unless (string? value)
                  (api-fail 400 "VALIDATION_ERROR"
                            (format #f "~a entries must be strings" label)))
                (when (> (string-length value) 1000)
                  (api-fail 400 "VALIDATION_ERROR"
                            (format #f "~a entry is too large" label)))
                (let ((value (string-trim-both value)))
                  (loop (cdr rest)
                        (if (string-null? value)
                            result
                            (cons value result))))))))))

(define character-outfit-kinds
  '("standard" "casual" "battle" "formal" "custom"))

(define (character-outfit-kind-field body default)
  (let ((kind (string-field body "kind" #:allow-empty #t
                            #:default default #:max 32)))
    (unless (member kind character-outfit-kinds)
      (api-fail 400 "VALIDATION_ERROR" "kind is not supported"))
    kind))

(define (character-outfit-values body create?)
  (let ((values '()))
    (when (or create? (object-has? body "name"))
      (set! values
            (acons 'name (string-field body "name" #:required #t
                                       #:max max-title-length)
                   values)))
    (when (or create? (object-has? body "kind"))
      (set! values
            (acons 'kind (character-outfit-kind-field body "custom") values)))
    (when (or create? (object-has? body "description"))
      (set! values
            (acons 'description
                   (string-field body "description" #:allow-empty #t
                                 #:default ""
                                 #:max max-description-length)
                   values)))
    (for-each
     (lambda (entry)
       (when (or create? (object-has? body (car entry)))
         (set! values
               (acons (string->symbol (car entry))
                      (character-string-list-field body (car entry)
                                                   (cadr entry) '())
                      values))))
     '(("components" "components") ("materials" "materials")
       ("colors" "colors") ("accessories" "accessories")
       ("special_features" "special_features")))
    (when (or create? (object-has? body "image_prompt"))
      (set! values
            (acons 'image_prompt
                   (string-field body "image_prompt" #:allow-empty #t
                                 #:default "" #:max 14000)
                   values)))
    (when (object-has? body "is_default")
      (set! values
            (acons 'is_default (character-boolean-field body "is_default")
                   values)))
    (when (object-has? body "reference_asset_id")
      (let ((asset-id (object-ref body "reference_asset_id")))
        (unless (or (not asset-id) (valid-uuid? asset-id))
          (api-fail 400 "VALIDATION_ERROR"
                    "reference_asset_id must be a UUID or null"))
        (set! values
              (acons 'reference_asset_id
                     (and asset-id (string-downcase asset-id)) values))))
    values))

(define (public-character-outfit outfit)
  `(("id" . ,(assoc-ref outfit 'id))
    ("character_id" . ,(assoc-ref outfit 'character_id))
    ("name" . ,(assoc-ref outfit 'name))
    ("kind" . ,(assoc-ref outfit 'kind))
    ("description" . ,(assoc-ref outfit 'description))
    ("components" . ,(json-string-list (assoc-ref outfit 'components)))
    ("materials" . ,(json-string-list (assoc-ref outfit 'materials)))
    ("colors" . ,(json-string-list (assoc-ref outfit 'colors)))
    ("accessories" . ,(json-string-list (assoc-ref outfit 'accessories)))
    ("special_features"
     . ,(json-string-list (assoc-ref outfit 'special_features)))
    ("image_prompt" . ,(assoc-ref outfit 'image_prompt))
    ("reference_asset_id" . ,(mark (assoc-ref outfit 'reference_asset_id)))
    ("is_default" . ,(and (assoc-ref outfit 'is_default) #t))
    ("created_at" . ,(assoc-ref outfit 'created_at))
    ("updated_at" . ,(assoc-ref outfit 'updated_at))
    ("archived_at" . ,(mark (assoc-ref outfit 'archived_at)))))

(define (studio-list-character-outfits config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id)))
    (map public-character-outfit
         (db:studio-list-character-outfits config wid
                                          (assoc-ref character 'id)))))

(define (studio-get-character-outfit config workplace-id character-id outfit-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (id (require-uuid-in-path outfit-id "Outfit"))
         (outfit (db:studio-get-character-outfit
                  config wid (assoc-ref character 'id) id)))
    (or (and outfit (public-character-outfit outfit))
        (api-fail 404 "NOT_FOUND" "Outfit not found"))))

(define (studio-create-character-outfit! config workplace-id character-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (values (character-outfit-values body #t)))
    (when (assoc 'reference_asset_id values)
      (require-character-image-asset config wid cid
                                     (assoc-ref values 'reference_asset_id)))
    (public-character-outfit
     (db:studio-create-character-outfit!
      config (db:studio-new-id) wid cid values))))

(define (studio-update-character-outfit! config workplace-id character-id
                                         outfit-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (id (require-uuid-in-path outfit-id "Outfit"))
         (outfit (db:studio-get-character-outfit config wid cid id)))
    (unless outfit (api-fail 404 "NOT_FOUND" "Outfit not found"))
    (let ((values (character-outfit-values body #f)))
      (when (assoc 'reference_asset_id values)
        (when (assoc-ref values 'reference_asset_id)
          (require-character-image-asset config wid cid
                                         (assoc-ref values 'reference_asset_id))))
      (public-character-outfit
       (db:studio-update-character-outfit! config wid cid id values)))))

(define (studio-archive-character-outfit! config workplace-id character-id outfit-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (id (require-uuid-in-path outfit-id "Outfit")))
    (or (db:studio-archive-character-outfit! config wid cid id)
        (api-fail 404 "NOT_FOUND" "Outfit not found"))))

(define (studio-set-default-character-outfit! config workplace-id character-id
                                              outfit-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (id (require-uuid-in-path outfit-id "Outfit"))
         (outfit (db:studio-set-default-character-outfit! config wid cid id)))
    (if outfit
        (public-character-outfit outfit)
        (api-fail 404 "NOT_FOUND" "Outfit not found"))))

(define (character-linked-image-asset config wid cid asset-id)
  (let ((asset (db:studio-get-asset config wid asset-id)))
    (unless asset
      (api-fail 404 "NOT_FOUND" "Asset not found"))
    (unless (equal? (assoc-ref asset 'asset_type) "image")
      (api-fail 422 "INVALID_ASSET" "The selected Asset is not an image"))
    (unless (find (lambda (entry) (equal? (assoc-ref entry 'id) asset-id))
                  (db:studio-list-linked-assets config wid "character" cid))
      (api-fail 422 "ASSET_NOT_LINKED"
                "The selected image is not linked to this Character"))
    asset))

(define (require-character-image-asset config wid cid asset-id)
  (and asset-id
       (character-linked-image-asset config wid cid
                                     (require-uuid-in-path asset-id "Asset"))))

(define (character-artwork-spec type)
  (or (assoc type character-artwork-specs)
      (api-fail 400 "VALIDATION_ERROR" "artwork_type is not supported")))

(define (character-artwork-type body)
  (let ((value (string-field body "artwork_type" #:required #t #:max 32)))
    (or (assoc value character-artwork-specs)
        (api-fail 400 "VALIDATION_ERROR" "artwork_type is not supported"))))

(define (character-default-outfit config wid cid)
  (let ((outfits (db:studio-list-character-outfits config wid cid)))
    (or (find (lambda (outfit) (assoc-ref outfit 'is_default)) outfits)
        (and (pair? outfits) (car outfits)))))

(define (character-selected-outfit config wid cid body require?)
  (let ((requested (object-ref body "outfit_id")))
    (cond
     ((and (object-has? body "outfit_id") requested)
      (let* ((id (require-uuid-in-path requested "Outfit"))
             (outfit (db:studio-get-character-outfit config wid cid id)))
        (or outfit (api-fail 404 "NOT_FOUND" "Outfit not found"))))
     (require?
      (or (character-default-outfit config wid cid)
          (api-fail 422 "OUTFIT_REQUIRED"
                    "Choose or create an Outfit before generating this artwork")))
     (else (character-default-outfit config wid cid)))))

(define (character-identity-lines identity fields)
  (let ((lines
         (filter-map
          (lambda (field)
            (let ((value (assoc-ref identity field)))
              (and (string? value)
                   (not (string-null? (string-trim-both value)))
                   (format #f "- ~a: ~a" field (string-trim-both value)))))
          fields)))
    (if (null? lines) "- not yet specified" (string-join lines "\n"))))

(define (character-outfit-prompt-lines outfit)
  (format #f
          "NAME: ~a\nKIND: ~a\nDESCRIPTION: ~a\n- components: ~a\n- materials: ~a\n- colors: ~a\n- accessories: ~a\n- special features: ~a\n- design note: ~a"
          (assoc-ref outfit 'name) (assoc-ref outfit 'kind)
          (or (assoc-ref outfit 'description) "")
          (string-join (json-string-list (assoc-ref outfit 'components)) ", ")
          (string-join (json-string-list (assoc-ref outfit 'materials)) ", ")
          (string-join (json-string-list (assoc-ref outfit 'colors)) ", ")
          (string-join (json-string-list (assoc-ref outfit 'accessories)) ", ")
          (string-join (json-string-list (assoc-ref outfit 'special_features)) ", ")
          (or (assoc-ref outfit 'image_prompt) "")))

(define (character-artwork-prompt-text character spec outfit extra)
  (let* ((type (car spec))
         (visual (character-canon-identity character "visual_identity"))
         (literary (character-canon-identity character "literary_identity"))
         (visual-fields (identity-fields "visual_identity"))
         (literary-fields (identity-fields "literary_identity")))
    (format #f
            "~a\n\nEditorial character artwork for Khala Studio. Type: ~a.\n\nCHARACTER\nName: ~a\nRole: ~a\nSummary: ~a\n\nVISUAL CANON — authoritative; preserve face, body, hair, eyes, skin, distinguishing features and colour relationships exactly.\n~a\n\nCHARACTER PRESENCE\n~a\n\nOUTFIT\n~a\n\nCOMPOSITION\n~a\n\nADDITIONAL AUTHOR DIRECTION\n~a\n\nCONSISTENCY RULES\nKeep the same Character identity across all images. Change only pose, expression, framing, lighting and the selected outfit. Do not invent permanent scars, prosthetics, tattoos, clothing changes or other canon alterations. No text artifacts. No neon, glow, gradients or cyberpunk styling. Warm paper, leather and editorial studio atmosphere."
            (read-prompt "character-artwork.md")
            (cadr spec)
            (assoc-ref character 'name)
            (or (assoc-ref character 'role) "")
            (or (assoc-ref character 'summary) "")
            (character-identity-lines visual visual-fields)
            (character-identity-lines literary literary-fields)
            (if outfit (character-outfit-prompt-lines outfit)
                "- no Outfit selected; use only the approved visual canon")
            (cadddr (cdr spec))
            (if (string-null? extra) "(none)" extra))))

(define (studio-character-artwork-prompt config workplace-id character-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (spec (character-artwork-type body))
         (type (car spec))
         (outfit (character-selected-outfit config wid cid body
                                             (equal? type "outfit")))
         (extra (optional-string-field body "extra_description" #:max 8000))
         (prompt (character-artwork-prompt-text character spec outfit extra)))
    `(("character_id" . ,cid)
      ("artwork_type" . ,type)
      ("outfit_id" . ,(mark (and outfit (assoc-ref outfit 'id))))
      ("prompt" . ,prompt)
      ("width" . ,(caddr spec))
      ("height" . ,(cadddr spec)))))

(define (studio-list-character-artworks config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id)))
    (map (lambda (asset) (public-asset asset #:config config))
         (filter (lambda (asset)
                   (equal? (assoc-ref asset 'asset_type) "image"))
                 (db:studio-list-linked-assets config wid "character" cid)))))

(define (character-artwork-seed)
  (+ (current-time) (random 1000000)))

(define (studio-generate-character-artwork! config workplace-id character-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (spec (character-artwork-type body))
         (type (car spec))
         (outfit (character-selected-outfit config wid cid body
                                             (equal? type "outfit")))
         (extra (optional-string-field body "extra_description" #:max 8000))
         (prompt (if (object-has? body "prompt")
                     (string-field body "prompt" #:required #t #:max 20000)
                     (character-artwork-prompt-text character spec outfit extra)))
         (width (caddr spec))
         (height (cadddr spec)))
    (unless (image-generation-available? config)
      (api-fail 503 "IMAGE_SERVICE_UNAVAILABLE"
                "Image generation is not available in this environment"))
    (let* ((pngs
            (catch #t
              (lambda ()
                (comfy-render-image! config prompt width height
                                     (character-artwork-seed)))
              (lambda (key . args)
                (format (current-error-port)
                        "Character artwork generation failed: ~s ~s~%" key args)
                (api-fail 502 "GENERATION_FAILED"
                          "Image generation failed; Character Canon was not changed"))))
           (_ (unless (and (pair? pngs)
                           (bytevector? (car pngs))
                           (> (bytevector-length (car pngs)) 0))
                (api-fail 502 "GENERATION_FAILED"
                          "Image generation returned no image")))
           (png (car pngs))
           (asset-id (db:studio-new-id))
           (filename (format #f "character-~a-~a.png" type asset-id))
           (storage-key #f))
      (catch #t
        (lambda ()
          (let* ((validated
                  (fs:studio-asset-validate-upload
                   config filename "image/png" png "image"))
                 (extension (assoc-ref validated 'extension))
                 (key (fs:studio-asset-storage-key asset-id extension))
                 (checksum (fs:studio-asset-store-file! config key png))
                 (metadata
                  (json-encode
                   (json-normalize
                    `(("artwork_type" . ,type)
                      ("character_id" . ,cid)
                      ("outfit_id" . ,(mark (and outfit (assoc-ref outfit 'id))))
                      ("engine" . ,(configured-engine config))
                      ("model" . ,(or (configured-model config)
                                      (configured-engine config)))
                      ("provider" . "moss-image")
                      ("adapter" . "engine-run-t2i")
                      ("prompt" . ,prompt)
                      ("width" . ,width)
                      ("height" . ,height)))))
                 (name (format #f "~a — ~a"
                               (assoc-ref character 'name)
                               (cadr spec)))
                 (values
                  `((name . ,name)
                    (description
                     . ,(format #f "Generated ~a artwork for ~a."
                                (cadr spec) (assoc-ref character 'name)))
                    (asset_type . "image")
                    (storage_key . ,key)
                    (original_filename . ,filename)
                    (mime_type . "image/png")
                    (file_size . ,(bytevector-length png))
                    (checksum . ,checksum)
                    (source . "generated")
                    (width . ,width)
                    (height . ,height)
                    (duration_ms . #f)
                    (author . "Khala Studio")
                    (notes . ,(or (and outfit (assoc-ref outfit 'name)) ""))
                    (generation_metadata . ,metadata)
                    (tags . ("character" "artwork" ,type)))))
            (set! storage-key key)
            (let* ((asset (db:studio-create-asset! config asset-id wid values))
                   (_ (db:studio-add-asset-link! config wid asset-id
                                                 "character" cid))
                   (public (public-asset asset #:config config)))
              `(("character_id" . ,cid)
                ("artwork_type" . ,type)
                ("outfit_id" . ,(mark (and outfit (assoc-ref outfit 'id))))
                ("prompt" . ,prompt)
                ("asset" . ,public)))))
        (lambda (key . args)
          (when storage-key
            (catch #t
              (lambda () (fs:studio-asset-delete-file! config storage-key))
              (lambda _ #f)))
          (if (eq? key 'studio-api-error)
              (apply throw key args)
              (begin
                (format (current-error-port)
                        "Character artwork persistence failed: ~s ~s~%" key args)
                (api-fail 502 "GENERATION_FAILED"
                          "The generated artwork could not be saved"))))))))

(define (studio-set-character-avatar! config workplace-id character-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (asset-id (string-field body "asset_id" #:required #t #:max 36)))
    (require-character-image-asset config wid cid asset-id)
    (public-character-with-avatar
     config
     (db:studio-set-character-avatar! config wid cid
                                      (string-downcase asset-id)))))

(define (studio-set-character-full-body! config workplace-id character-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (asset-id (string-field body "asset_id" #:required #t #:max 36)))
    (require-character-image-asset config wid cid asset-id)
    (public-character-with-avatar
     config
     (db:studio-set-character-full-body! config wid cid
                                          (string-downcase asset-id)))))

(define (studio-set-character-outfit-reference! config workplace-id character-id
                                                outfit-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (id (require-uuid-in-path outfit-id "Outfit"))
         (outfit (db:studio-get-character-outfit config wid cid id))
         (asset-id (string-field body "asset_id" #:required #t #:max 36)))
    (unless outfit (api-fail 404 "NOT_FOUND" "Outfit not found"))
    (require-character-image-asset config wid cid asset-id)
    (or (and (db:studio-set-character-outfit-reference!
              config wid cid id (string-downcase asset-id))
             (public-character-outfit
              (db:studio-get-character-outfit config wid cid id)))
        (api-fail 404 "NOT_FOUND" "Outfit not found"))))

(define (studio-character-canon config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (character (require-character config wid character-id))
         (cid (assoc-ref character 'id))
         (avatar-id (assoc-ref character 'avatar_asset_id))
         (full-body-id (assoc-ref character 'full_body_asset_id))
         (avatar (and avatar-id (db:studio-get-asset config wid avatar-id))))
    `(("character" . ,(public-character character))
      ("avatar" . ,(mark (and avatar (public-asset avatar #:config config))))
      ("full_body"
       . ,(mark (and full-body-id
                     (db:studio-get-asset config wid full-body-id)
                     (public-asset (db:studio-get-asset config wid full-body-id)
                                   #:config config))))
      ("outfits" . ,(map public-character-outfit
                         (db:studio-list-character-outfits config wid cid)))
      ("drafts" . ,(public-character-drafts
                    (db:studio-list-character-drafts config wid cid))))))

(define (require-object-fields object key allowed)
  (unless (or (null? object) (object? object))
    (api-fail 400 "VALIDATION_ERROR" (format #f "~a must be an object" key)))
  (for-each
   (lambda (entry)
     (unless (member (car entry) allowed)
       (api-fail 400 "VALIDATION_ERROR"
                 (format #f "~a.~a is not supported" key (car entry)))))
   object))

(define* (scene-text-field object key #:key (default ""))
  (string-field object key #:allow-empty #t #:default default
                #:max max-scene-text-length))

(define (scene-status-field body default)
  (let ((status (string-field body "status" #:allow-empty #t
                              #:default default #:max 16)))
    (unless (member status scene-statuses)
      (api-fail 400 "VALIDATION_ERROR" "status is not supported"))
    status))

(define (scene-create-values body)
  (let* ((given (if (object-has? body "given_circumstances")
                    (or (object-ref body "given_circumstances") '())
                    '()))
         (dramatic (if (object-has? body "dramatic_situation")
                       (or (object-ref body "dramatic_situation") '())
                       '()))
         (direction (if (object-has? body "direction")
                        (or (object-ref body "direction") '())
                        '())))
    (require-object-fields given "given_circumstances" scene-given-fields)
    (require-object-fields dramatic "dramatic_situation" scene-dramatic-fields)
    (require-object-fields direction "direction" scene-direction-fields)
    `((title . ,(string-field body "title" #:required #t
                              #:max max-title-length))
      (summary . ,(scene-text-field body "summary"))
      (sort_order . ,(optional-integer-field body "sort_order"
                                             -1000000000 1000000000 0))
      (status . ,(scene-status-field body "draft"))
      (time . ,(scene-text-field given "time"))
      (place . ,(scene-text-field given "place"))
      (environment . ,(scene-text-field given "environment"))
      (background . ,(scene-text-field given "background"))
      (prior_events . ,(scene-text-field given "prior_events"))
      (central_question . ,(scene-text-field dramatic "central_question"))
      (primary_conflict . ,(scene-text-field dramatic "primary_conflict"))
      (turn . ,(scene-text-field dramatic "turn"))
      (dialogue . ,(scene-text-field body "dialogue"))
      (blocking . ,(scene-text-field direction "blocking"))
      (spatial . ,(scene-text-field direction "spatial"))
      (performance_direction
       . ,(scene-text-field direction "performance_direction"))
      (camera . ,(scene-text-field direction "camera")))))

(define (scene-update-values body)
  (let ((updates '()))
    (when (object-has? body "title")
      (set! updates
            (acons 'title (string-field body "title" #:required #t
                                        #:max max-title-length)
                   updates)))
    (when (object-has? body "summary")
      (set! updates (acons 'summary (scene-text-field body "summary") updates)))
    (when (object-has? body "sort_order")
      (set! updates
            (acons 'sort_order
                   (required-integer-field body "sort_order"
                                           -1000000000 1000000000)
                   updates)))
    (when (object-has? body "status")
      (set! updates (acons 'status (scene-status-field body "draft") updates)))
    (for-each
     (lambda (group)
       (let ((key (car group))
             (fields (cdr group)))
         (when (object-has? body key)
           (let ((object (object-ref body key)))
             (require-object-fields object key fields)
             (for-each
              (lambda (field)
                (when (object-has? object field)
                  (set! updates
                        (acons (string->symbol field)
                               (scene-text-field object field)
                               updates))))
              fields)))))
     `(("given_circumstances" . ,scene-given-fields)
       ("dramatic_situation" . ,scene-dramatic-fields)
       ("direction" . ,scene-direction-fields)))
    updates))

(define (scene-cast-array value)
  (cond
   ((vector? value) (vector->list value))
   ((null? value) '())
   ;; A list of cast objects is also a list of pairs, so distinguish it from a
   ;; single object by requiring object keys to be strings rather than entries.
   ((and (list? value)
         (every pair? value)
         (every (lambda (entry) (string? (car entry))) value))
    (api-fail 400 "VALIDATION_ERROR" "cast must be an array"))
   ((list? value) value)
   (else (api-fail 400 "VALIDATION_ERROR" "cast must be an array"))))

(define (scene-cast-entry value index)
  (unless (object? value)
    (api-fail 400 "VALIDATION_ERROR"
              (format #f "cast[~a] must be an object" index)))
  (require-object-fields value (format #f "cast[~a]" index)
                         (cons "character_id" scene-cast-fields))
  (let ((character-id (string-field value "character_id" #:required #t
                                    #:max 36)))
    (unless (valid-uuid? character-id)
      (api-fail 400 "VALIDATION_ERROR"
                (format #f "cast[~a].character_id must be a UUID" index)))
    `((character_id . ,(string-downcase character-id))
      (objective . ,(scene-text-field value "objective"))
      (action . ,(scene-text-field value "action"))
      (conflict . ,(scene-text-field value "conflict"))
      (emotional_state . ,(scene-text-field value "emotional_state"))
      (performance_direction
       . ,(scene-text-field value "performance_direction"))
      (subtext . ,(scene-text-field value "subtext"))
      (sort_order . ,(optional-integer-field value "sort_order"
                                             -1000000000 1000000000 index)))))

(define (scene-cast-values value)
  (let* ((values (scene-cast-array value))
         (entries (map scene-cast-entry values (iota (length values)))))
    (let loop ((rest entries) (seen '()))
      (when (pair? rest)
        (let ((id (assoc-ref (car rest) 'character_id)))
          (when (member id seen string=?)
            (api-fail 400 "VALIDATION_ERROR"
                      "A Character can only appear once in a Scene cast"))
          (loop (cdr rest) (cons id seen)))))
    entries))

;; --- Writing -> Scene extraction -------------------------------------------

(define (extraction-fail message)
  (api-fail 502 "INVALID_AI_OUTPUT" message))

(define (extraction-object value label)
  (unless (object? value)
    (extraction-fail (format #f "~a must be a JSON object" label)))
  value)

(define* (extraction-string object key label max #:key (required #f))
  (let ((value (object-ref object key)))
    (cond
     ((not (object-has? object key))
      (if required
          (extraction-fail (format #f "~a.~a is required" label key))
          ""))
     ((eq? value 'null)
      (if required
          (extraction-fail (format #f "~a.~a must be a string" label key))
          ""))
     ((not (string? value))
      (extraction-fail (format #f "~a.~a must be a string" label key)))
     ((> (string-length value) max)
      (extraction-fail (format #f "~a.~a is too large" label key)))
     (else value))))

(define (extraction-array value label)
  (cond ((vector? value) (vector->list value))
        ((list? value) value)
        ((eq? value 'null) '())
        (else (extraction-fail (format #f "~a must be an array" label)))))

(define (extraction-known-fields object label allowed)
  (for-each
   (lambda (entry)
     (unless (member (car entry) allowed string=?)
       (extraction-fail
        (format #f "~a contains unknown field ~a" label (car entry)))))
   object)
  object)

(define (extraction-groups value label fields)
  (let ((object (extraction-known-fields
                 (if (eq? value 'null) '() (extraction-object value label))
                 label fields)))
    (map (lambda (field)
           (cons field (extraction-string object field label
                                          max-scene-text-length)))
         fields)))

(define (extraction-cast-entry value index characters)
  (let* ((label (format #f "cast[~a]" index))
         (entry (extraction-known-fields
                 (extraction-object value label) label
                 '("character_id" "character_name" "objective" "action"
                   "conflict" "emotional_state" "performance_direction"
                   "subtext")))
         (raw-id (object-ref entry "character_id"))
         (name (extraction-string entry "character_name" label
                                  max-title-length #:required #t))
         (character-id
          (cond
           ((or (not (object-has? entry "character_id")) (eq? raw-id 'null)) #f)
           ((and (string? raw-id) (valid-uuid? raw-id))
            (string-downcase raw-id))
           (else (extraction-fail (format #f "~a.character_id is invalid" label)))))
         (matched (and character-id
                       (find (lambda (character)
                               (equal? (assoc-ref character 'id) character-id))
                             characters))))
    (cond
     ((and character-id matched)
      (cons
       `((character_id . ,character-id)
         (character_name . ,(assoc-ref matched 'name))
         (objective . ,(extraction-string entry "objective" label
                                          max-scene-text-length))
         (action . ,(extraction-string entry "action" label
                                       max-scene-text-length))
         (conflict . ,(extraction-string entry "conflict" label
                                         max-scene-text-length))
         (emotional_state . ,(extraction-string entry "emotional_state" label
                                                max-scene-text-length))
         (performance_direction
          . ,(extraction-string entry "performance_direction" label
                                max-scene-text-length))
         (subtext . ,(extraction-string entry "subtext" label
                                        max-scene-text-length))
         (sort_order . ,index))
       #f))
     (else
      (cons
       #f
       `((name . ,name)
         (reason . ,(if character-id
                        "The proposed Character ID is not in this Workplace pool."
                        "The model could not match this person to an existing Character."))))))))

(define (studio-validate-scene-extraction-json text characters)
  (catch #t
    (lambda ()
      (let* ((root (extraction-known-fields
                    (extraction-object (json-string->scm (string-trim-both text))
                                       "scene")
                    "scene"
                    '("title" "summary" "given_circumstances"
                      "dramatic_situation" "dialogue" "direction" "cast"
                      "unresolved_characters")))
             (raw-cast (object-ref root "cast"))
             (cast-values (extraction-array raw-cast "cast")))
        (when (> (length cast-values) max-extraction-characters)
          (extraction-fail "The extracted Scene has too many cast entries"))
        (let* ((pairs (map (lambda (entry index)
                             (extraction-cast-entry entry index characters))
                           cast-values (iota (length cast-values))))
               (cast (filter identity (map car pairs)))
               (unresolved
                (append
                 (filter identity (map cdr pairs))
                 (if (object-has? root "unresolved_characters")
                     (map (lambda (entry index)
                            (let* ((label (format #f "unresolved_characters[~a]" index))
                                   (object (extraction-known-fields
                                            (extraction-object entry label) label
                                            '("name" "reason"))))
                              `((name . ,(extraction-string object "name" label
                                                            max-title-length
                                                            #:required #t))
                                (reason . ,(extraction-string object "reason" label
                                                              max-description-length)))))
                          (extraction-array (object-ref root "unresolved_characters")
                                            "unresolved_characters")
                          (iota (length (extraction-array
                                         (object-ref root "unresolved_characters")
                                         "unresolved_characters"))))
                     '()))))
          (let loop ((rest cast) (seen '()))
            (when (pair? rest)
              (let ((id (assoc-ref (car rest) 'character_id)))
                (when (member id seen string=?)
                  (extraction-fail "The extracted Scene repeats a Character"))
                (loop (cdr rest) (cons id seen)))))
          `((title . ,(extraction-string root "title" "scene"
                                         max-title-length #:required #t))
            (summary . ,(extraction-string root "summary" "scene"
                                           max-scene-text-length))
            (given_circumstances
             . ,(extraction-groups (extraction-object
                                    (object-ref root "given_circumstances")
                                    "given_circumstances")
                                   "given_circumstances" scene-given-fields))
            (dramatic_situation
             . ,(extraction-groups (extraction-object
                                    (object-ref root "dramatic_situation")
                                    "dramatic_situation")
                                   "dramatic_situation" scene-dramatic-fields))
            (dialogue . ,(extraction-string root "dialogue" "scene"
                                            max-scene-text-length))
            (direction
             . ,(extraction-groups (extraction-object
                                    (object-ref root "direction")
                                    "direction")
                                   "direction" scene-direction-fields))
            (cast . ,cast)
            (unresolved_characters . ,unresolved)))))
    (lambda (key . args)
      (if (eq? key 'studio-api-error)
          (apply throw key args)
          (extraction-fail "The Scene Extraction model did not return valid JSON")))))

(define (character-pool-prompt character index)
  (format #f
          "CHARACTER ID: ~a\nNAME: ~a\nROLE: ~a\nSUMMARY: ~a\nLITERARY IDENTITY: ~a\nVISUAL IDENTITY: ~a\nVOCAL IDENTITY: ~a\nPERFORMANCE IDENTITY: ~a"
          (assoc-ref character 'id)
          (assoc-ref character 'name)
          (or (assoc-ref character 'role) "")
          (clip-head (or (assoc-ref character 'summary) "") 4000)
          (clip-head (character-ai-identity-lines character "literary_identity") 6000)
          (clip-head (character-ai-identity-lines character "visual_identity") 6000)
          (clip-head (character-ai-identity-lines character "vocal_identity") 4000)
          (clip-head (character-ai-identity-lines character "performance_identity") 5000)))

(define (extraction-source-range content body scope)
  (if (equal? scope "document")
      (values content #f #f)
      (let* ((selected (optional-string-field body "selected_text"
                                              #:max max-extraction-source-length))
             (start-input (object-ref body "selection_start"))
             (end-input (object-ref body "selection_end")))
        (when (string-null? selected)
          (api-fail 400 "VALIDATION_ERROR"
                    "selected_text is required for a selection extraction"))
        (cond
         ((and (object-has? body "selection_start")
               (not (or (not start-input) (integer? start-input))))
          (api-fail 400 "VALIDATION_ERROR"
                    "selection_start must be an integer or null"))
         ((and (object-has? body "selection_end")
               (not (or (not end-input) (integer? end-input))))
          (api-fail 400 "VALIDATION_ERROR"
                    "selection_end must be an integer or null")))
        (if (and start-input end-input)
            (let ((start start-input) (end end-input))
              (unless (and (>= start 0) (<= start end)
                           (<= end (string-length content)))
                (api-fail 422 "INVALID_SELECTION"
                          "The selection range is outside the current document"))
              (unless (equal? (substring content start end) selected)
                (api-fail 409 "STALE_SELECTION"
                          "The selected text no longer matches the saved document"))
              (values selected start end))
            (let* ((first (string-contains content selected)))
              (unless first
                (api-fail 422 "INVALID_SELECTION"
                          "The selected text is not present in the saved document"))
              (let ((second (string-contains content selected (+ first 1))))
                (if second
                    (values selected #f #f)
                    (values selected first (+ first (string-length selected))))))))))

(define (scene-extraction-prompt document revision scope selection-start
                                 selection-end snapshot characters)
  (format #f
          "KHALA_SCENE_EXTRACTION\n\nDocument: ~a\nRevision: ~a\nScope: ~a\nSelection start: ~a\nSelection end: ~a\n\nSOURCE PASSAGE\n~a\n\nCHARACTER POOL — MATCH ONLY BY EXISTING ID\n~a"
          (assoc-ref document 'title)
          revision scope
          (or selection-start "not reliably available")
          (or selection-end "not reliably available")
          (clip-head snapshot 80000)
          (if (null? characters)
              "No existing Characters. Every person must be unresolved."
              (string-join
               (map character-pool-prompt characters
                    (iota (length characters)))
               "\n\n"))))

(define (scene-extraction-prepared config body document revision scope
                                   selection-start selection-end snapshot
                                   characters)
  (let* ((prompt (scene-extraction-prompt
                  document revision scope selection-start selection-end
                  snapshot characters))
         (messages (list `(("role" . "system")
                           ("content" . ,(read-prompt "scene-extraction.md")))
                         `(("role" . "user") ("content" . ,prompt))))
         (options '(("temperature" . 0.25)
                    ("num_predict" . 4096)
                    ("max_output_tokens" . 4096)
                    ("stream" . #f)
                    ("format" . "json"))))
    (prepare-task-chat config "scene_extraction" messages options body)))

(define (studio-extract-scene-draft config workplace-id document-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (did (assoc-ref document 'id))
         (revision (required-integer-field body "expected_revision"
                                           1 2147483647))
         (current-revision (assoc-ref document 'revision)))
    (unless (= revision current-revision)
      (api-fail 409 "REVISION_CONFLICT" "Document revision changed"
                (cons "current_revision" current-revision)))
    (let* ((scope (if (object-has? body "scope")
                      (string-field body "scope" #:required #t #:max 32)
                      (let ((selected (object-ref body "selected_text")))
                        (if (and (string? selected) (not (string-null? selected)))
                            "selection" "document"))))
           (_ (unless (member scope '("selection" "document"))
                (api-fail 400 "VALIDATION_ERROR"
                          "scope must be selection or document")))
           (characters (filter-map
                        (lambda (id)
                          (db:studio-get-character config wid id))
                        (map (lambda (entry) (assoc-ref entry 'id))
                             (db:studio-list-characters config wid))))
           (range-values (call-with-values
                              (lambda ()
                                (extraction-source-range
                                 (assoc-ref document 'content) body scope))
                            list))
           (snapshot (list-ref range-values 0))
           (selection-start (list-ref range-values 1))
           (selection-end (list-ref range-values 2))
           (prepared (scene-extraction-prepared
                      config body document revision scope
                      selection-start selection-end snapshot characters))
           (result (studio-run-ai prepared))
           (text (or (assoc-ref result 'text) (assoc-ref result "text") ""))
           (draft (studio-validate-scene-extraction-json text characters))
           (version (db:studio-latest-version-for-revision
                     config wid did revision)))
      (public-json-tree
       (append
        draft
        `((source .
                 (("document_id" . ,did)
                  ("document_revision" . ,revision)
                  ("document_version_id" . ,(mark
                                             (and version (assoc-ref version 'id))))
                  ("scope" . ,scope)
                  ("selection_start" . ,(mark selection-start))
                  ("selection_end" . ,(mark selection-end))
                  ("text" . ,snapshot)))
         (model . ,(assoc-ref prepared 'model))
         (profile_id . ,(mark (assoc-ref prepared 'profile_id)))
         (protocol . ,(or (assoc-ref prepared 'protocol)
                           (configured-engine config)))))))))

(define (studio-confirm-scene-extraction! config workplace-id document-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (did (assoc-ref document 'id))
         (revision (required-integer-field body "expected_revision"
                                           1 2147483647))
         (current-revision (assoc-ref document 'revision))
         (_revision-check
          (unless (= revision current-revision)
            (api-fail 409 "REVISION_CONFLICT" "Document revision changed"
                      (cons "current_revision" current-revision))))
         (snapshot (string-field body "source_text_snapshot"
                                 #:required #t
                                 #:max max-extraction-source-length))
         (start (if (object-has? body "source_selection_start")
                    (let ((value (object-ref body "source_selection_start")))
                      (cond ((not value) #f)
                            ((integer? value) value)
                            (else (api-fail 400 "VALIDATION_ERROR"
                                            "source_selection_start must be an integer or null"))))
                    #f))
         (end (if (object-has? body "source_selection_end")
                  (let ((value (object-ref body "source_selection_end")))
                    (cond ((not value) #f)
                          ((integer? value) value)
                          (else (api-fail 400 "VALIDATION_ERROR"
                                          "source_selection_end must be an integer or null"))))
                  #f))
         (_range-check
          (when (and start end)
            (unless (and (>= start 0) (<= start end)
                         (<= end (string-length (assoc-ref document 'content))))
              (api-fail 422 "INVALID_SELECTION"
                        "Source selection range is outside the document"))))
         (_source-check
          (let ((content (assoc-ref document 'content)))
            (cond
             ((and start end)
              (unless (equal? (substring content start end) snapshot)
                (api-fail 409 "STALE_SELECTION"
                          "The source selection no longer matches the document")))
             ((equal? snapshot content) #t)
             ((string-contains content snapshot) #t)
             (else
              (api-fail 422 "INVALID_SELECTION"
                        "The source snapshot is not present in the document")))))
         (values (scene-create-values body))
         (cast (if (object-has? body "cast")
                   (scene-cast-values (object-ref body "cast"))
                   '()))
         (version (db:studio-latest-version-for-revision config wid did revision))
         (scene-id (db:studio-new-id))
         (source-values
          `((source_document_id . ,did)
            (source_document_version_id . ,(and version (assoc-ref version 'id)))
            (source_document_revision . ,revision)
            (source_text_snapshot . ,snapshot)
            (source_selection_start . ,start)
            (source_selection_end . ,end))))
    (for-each
     (lambda (entry)
       (unless (db:studio-get-character config wid
                                        (assoc-ref entry 'character_id))
         (api-fail 422 "INVALID_CAST_CHARACTER"
                   "Every cast Character must belong to this Workplace")))
     cast)
    (catch 'studio-cast-error
      (lambda ()
        (let ((scene (db:studio-create-extracted-scene!
                      config scene-id wid (append values source-values) cast)))
          `(("scene" . ,(public-scene scene #:include-source-text #t))
            ("cast" . ,(map public-scene-cast
                            (db:studio-list-scene-cast config wid scene-id))))))
      (lambda (key reason)
        (api-fail 422 "INVALID_CAST_CHARACTER"
                  "Every cast Character must belong to this Workplace")))))

(define (studio-list-document-scenes config workplace-id document-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id)))
    (map public-scene
         (db:studio-list-document-scenes config wid (assoc-ref document 'id)))))

(define (studio-list-scenes config workplace-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (map public-scene (db:studio-list-scenes config wid))))

(define (studio-create-scene! config workplace-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (public-scene
     (db:studio-create-scene! config (db:studio-new-id) wid
                              (scene-create-values body)))))

(define (studio-get-scene config workplace-id scene-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (id (require-uuid-in-path scene-id "Scene"))
         (scene (db:studio-get-scene config wid id)))
    (if scene
        (public-scene scene #:include-source-text #t)
        (api-fail 404 "NOT_FOUND" "Scene not found"))))

(define (studio-update-scene! config workplace-id scene-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (id (require-uuid-in-path scene-id "Scene"))
         (scene (db:studio-get-scene config wid id)))
    (unless scene
      (api-fail 404 "NOT_FOUND" "Scene not found"))
    (let ((updates (scene-update-values body)))
      (public-scene
       (if (null? updates)
           scene
           (or (db:studio-update-scene! config wid id updates)
               (api-fail 404 "NOT_FOUND" "Scene not found")))))))

(define (studio-delete-scene! config workplace-id scene-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (id (require-uuid-in-path scene-id "Scene"))
         (deleted (db:studio-delete-scene! config wid id)))
    (or deleted
        (api-fail 404 "NOT_FOUND" "Scene not found"))
    `(("id" . ,id)
      ("workplace_id" . ,wid)
      ("deleted_at" . ,deleted))))

(define max-scene-reference-images 12)

(define (scene-linked-image-asset config wid sid asset-id)
  (let ((asset (db:studio-get-asset config wid asset-id)))
    (unless asset
      (api-fail 404 "NOT_FOUND" "Asset not found"))
    (unless (equal? (assoc-ref asset 'asset_type) "image")
      (api-fail 422 "INVALID_ASSET" "Scene references must be image Assets"))
    (unless (find (lambda (entry) (equal? (assoc-ref entry 'id) asset-id))
                  (db:studio-list-linked-assets config wid "scene" sid))
      (api-fail 422 "ASSET_NOT_LINKED"
                "Every Scene reference must be linked to this Scene"))
    asset))

(define (studio-set-scene-references! config workplace-id scene-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (scene (require-scene config wid scene-id))
         (sid (assoc-ref scene 'id)))
    (unless (object-has? body "asset_ids")
      (api-fail 400 "VALIDATION_ERROR" "asset_ids is required"))
    (let* ((raw (object-ref body "asset_ids"))
           (values (json-array-list raw "asset_ids")))
      (when (> (length values) max-scene-reference-images)
        (api-fail 400 "VALIDATION_ERROR"
                  (format #f "asset_ids supports at most ~a Scene references"
                          max-scene-reference-images)))
      (let ((ids
             (map (lambda (value)
                    (unless (and (string? value) (valid-uuid? value))
                      (api-fail 400 "VALIDATION_ERROR"
                                "asset_ids must contain UUID strings"))
                    (string-downcase value))
                  values)))
        (let loop ((rest ids) (seen '()))
          (when (pair? rest)
            (when (member (car rest) seen string=?)
              (api-fail 400 "VALIDATION_ERROR"
                        "asset_ids must not contain duplicates"))
            (loop (cdr rest) (cons (car rest) seen))))
        (for-each (lambda (asset-id)
                    (scene-linked-image-asset config wid sid asset-id))
                  ids)
        (public-scene
         (or (db:studio-set-scene-references!
              config wid sid (string-list-json ids))
             (api-fail 404 "NOT_FOUND" "Scene not found")))))))

(define (studio-list-scene-cast config workplace-id scene-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (id (require-uuid-in-path scene-id "Scene"))
         (cast (db:studio-list-scene-cast config wid id)))
    (if cast
        (map public-scene-cast cast)
        (api-fail 404 "NOT_FOUND" "Scene not found"))))

(define (studio-update-scene-cast! config workplace-id scene-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (id (require-uuid-in-path scene-id "Scene"))
         (scene (db:studio-get-scene config wid id)))
    (unless scene
      (api-fail 404 "NOT_FOUND" "Scene not found"))
    (unless (object-has? body "cast")
      (api-fail 400 "VALIDATION_ERROR" "cast is required"))
    (let ((entries (scene-cast-values (object-ref body "cast"))))
      (for-each
       (lambda (entry)
         (unless (db:studio-get-character config wid
                                          (assoc-ref entry 'character_id))
           (api-fail 422 "INVALID_CAST_CHARACTER"
                     "Every cast Character must belong to this Workplace")))
       entries)
      (catch 'studio-cast-error
        (lambda ()
          (map public-scene-cast
               (db:studio-replace-scene-cast! config wid id entries)))
        (lambda (key reason)
          (case reason
            ((scene-not-found) (api-fail 404 "NOT_FOUND" "Scene not found"))
            ((character-not-found)
             (api-fail 422 "INVALID_CAST_CHARACTER"
                       "Every cast Character must belong to this Workplace"))
            (else (api-fail 422 "INVALID_CAST"
                          "The cast could not be updated"))))))))

;; Storyboards are saved with the Scene, not as another document or workflow.
;; The UI only needs a compact, editable shot list; image binaries stay in the
;; existing Asset store and every shot keeps the stable Asset ID it points at.
(define max-storyboard-shots 8)
(define max-shot-text-length 20000)
(define max-shot-prompt-length 14000)
(define max-storyboard-context-length 60000)
(define max-storyboard-ai-tokens 4096)
(define storyboard-image-width 768)
(define storyboard-image-height 432)

(define storyboard-ai-shot-fields
  '("dramatic_beat" "action" "character_ids" "expression"
    "performance" "camera" "visual_description" "image_prompt"))

(define (storyboard-clip text limit)
  (let ((value (or text "")))
    (if (<= (string-length value) limit)
        value
        (string-append (substring value 0 limit) "…"))))

(define (storyboard-text-or text fallback)
  (if (and (string? text) (not (string-null? (string-trim-both text))))
      (string-trim-both text)
      fallback))

(define (storyboard-nonempty-text text)
  (and (string? text)
       (not (string-null? (string-trim-both text)))
       (string-trim-both text)))

(define (storyboard-join-text . values)
  (string-join (filter storyboard-nonempty-text values) "\n\n"))

(define (storyboard-json shots)
  (json-encode (json-normalize (if (list? shots) shots '()))))

(define (storyboard-json-list value)
  (cond ((vector? value) (vector->list value))
        ((list? value) value)
        (else '())))

(define (json-array-list value label)
  (cond
   ((null? value) '())
   ((vector? value) (vector->list value))
   ((object? value)
    (api-fail 400 "VALIDATION_ERROR" (format #f "~a must be an array" label)))
   ((list? value) value)
   (else (api-fail 400 "VALIDATION_ERROR"
                   (format #f "~a must be an array" label)))))

(define (image-generation-available? config)
  (or (equal? (configured-engine config) "fake")
      (sonicboom-available?)))

(define (storyboard-normalize-shot shot)
  (let* ((legacy-content (or (assoc-ref shot "content") ""))
         (legacy-expression (or (assoc-ref shot "expression_action") ""))
         (action (or (storyboard-nonempty-text (assoc-ref shot "action"))
                     legacy-content))
         (expression (or (storyboard-nonempty-text (assoc-ref shot "expression"))
                         legacy-expression))
         (performance (or (assoc-ref shot "performance") ""))
         (expression-action (or (storyboard-join-text expression performance)
                                legacy-expression))
         (result shot))
    (set! result (storyboard-shot-set result "action" action))
    (set! result (storyboard-shot-set result "content" action))
    (set! result (storyboard-shot-set result "dramatic_beat"
                                      (or (assoc-ref shot "dramatic_beat") "")))
    (set! result (storyboard-shot-set result "expression" expression))
    (set! result (storyboard-shot-set result "performance" performance))
    (set! result (storyboard-shot-set result "expression_action"
                                      expression-action))
    (set! result (storyboard-shot-set result "source"
                                      (or (assoc-ref shot "source") "deterministic")))
    (set! result (storyboard-shot-set result "model"
                                      (or (assoc-ref shot "model") "")))
    (set! result (storyboard-shot-set result "author_edited"
                                      (and (eq? (assoc-ref shot "author_edited") #t)
                                           #t)))
    (set! result (storyboard-shot-set result "character_ids"
                                      (storyboard-json-list
                                       (assoc-ref shot "character_ids"))))
    (set! result (storyboard-shot-set result "characters"
                                      (storyboard-json-list
                                       (assoc-ref shot "characters"))))
    (set! result (storyboard-shot-set result "character_outfits"
                                      (storyboard-json-list
                                       (assoc-ref shot "character_outfits"))))
    (let ((usage (assoc-ref shot "reference_usage")))
      (storyboard-shot-set result "reference_usage"
                           (if (or (not usage) (eq? usage 'null)) 'null usage)))))

(define (storyboard-payload config scene)
  `(("scene_id" . ,(assoc-ref scene 'id))
    ("shots" . ,(map storyboard-normalize-shot
                     (storyboard-shots (assoc-ref scene 'storyboard))))
    ("generation_available" . ,(and (image-generation-available? config) #t))
    ("image_generation" . ,(studio-image-generation-capabilities config))
    ("updated_at" . ,(assoc-ref scene 'updated_at))))

(define storyboard-visual-fields
  '(("standard_appearance" . "standard appearance")
    ("face" . "face") ("body" . "body") ("hair" . "hair")
    ("clothing" . "clothing") ("palette" . "colour palette")
    ("expressions" . "expressions") ("posture" . "posture")))

(define (storyboard-visual-canon character)
  (let* ((name (assoc-ref character 'name))
         (visual (identity-from-json (assoc-ref character 'visual_identity)))
         (parts (filter-map
                 (lambda (entry)
                   (let ((value (assoc-ref visual (car entry))))
                     (and (string? value)
                          (not (string-null? (string-trim-both value)))
                          (format #f "~a: ~a" (cdr entry)
                                  (storyboard-clip value 600)))))
                 storyboard-visual-fields)))
    (if (null? parts)
        (format #f "~a: Visual Canon is not defined; do not invent permanent physical features."
                name)
        (format #f "~a — ~a" name (string-join parts "; ")))))

(define (storyboard-setting scene)
  (let ((given (map (lambda (field)
                      (assoc-ref scene (string->symbol field)))
                    scene-given-fields)))
    (string-join
     (filter (lambda (value)
               (and value (not (string-null? (string-trim-both value)))))
             given)
     " · ")))

(define (storyboard-cast-line entry)
  (format #f "~a [Character ID: ~a] — objective: ~a; action: ~a; emotional state: ~a; conflict: ~a; performance direction: ~a; subtext: ~a"
          (assoc-ref entry 'character_name)
          (assoc-ref entry 'character_id)
          (storyboard-text-or (assoc-ref entry 'objective) "not stated")
          (storyboard-text-or (assoc-ref entry 'action) "not stated")
          (storyboard-text-or (assoc-ref entry 'emotional_state) "not stated")
          (storyboard-text-or (assoc-ref entry 'conflict) "not stated")
          (storyboard-text-or (assoc-ref entry 'performance_direction) "not stated")
          (storyboard-text-or (assoc-ref entry 'subtext) "not stated")))

(define (storyboard-identity-lines identity)
  (filter
   (lambda (line) line)
   (map (lambda (entry)
          (let ((value (assoc-ref identity (car entry))))
            (and (string? value)
                 (not (string-null? (string-trim-both value)))
                 (format #f "- ~a: ~a" (cdr entry)
                         (storyboard-clip (string-trim-both value) 3000)))))
        '(("background" . "background") ("personality" . "personality")
          ("values" . "values") ("motivations" . "motivations")
          ("fears" . "fears") ("goals" . "goals") ("arc" . "arc")
          ("standard_appearance" . "standard appearance")
          ("face" . "face") ("body" . "body") ("hair" . "hair")
          ("clothing" . "clothing") ("palette" . "palette")
          ("expressions" . "expressions") ("posture" . "posture")
          ("habits" . "habits") ("movement" . "movement")
          ("gestures" . "gestures")
          ("emotional_responses" . "emotional responses")
          ("situations" . "situations")))))

(define (storyboard-character-context character entry)
  (let* ((literary (identity-from-json (assoc-ref character 'literary_identity)))
         (visual (identity-from-json (assoc-ref character 'visual_identity)))
         (performance
          (identity-from-json (assoc-ref character 'performance_identity)))
         (section (lambda (title identity)
                    (let ((lines (storyboard-identity-lines identity)))
                      (format #f "~a\n~a" title
                              (if (null? lines)
                                  "- not defined"
                                  (string-join lines "\n")))))))
    (string-join
     (list
      (storyboard-cast-line entry)
      (format #f "Name: ~a\nCharacter ID: ~a\nRole: ~a\nSummary: ~a"
              (assoc-ref character 'name)
              (assoc-ref character 'id)
              (storyboard-text-or (assoc-ref character 'role) "not stated")
              (storyboard-text-or (assoc-ref character 'summary) "not stated"))
      (section "LITERARY IDENTITY" literary)
      (section "VISUAL IDENTITY (CANON — AUTHORITATIVE)" visual)
      (section "PERFORMANCE IDENTITY" performance))
     "\n")))

(define (storyboard-character-lines cast characters)
  (map (lambda (entry)
         (let ((character (find (lambda (item)
                                  (equal? (assoc-ref item 'id)
                                          (assoc-ref entry 'character_id)))
                                characters)))
           (if character
               (storyboard-character-context character entry)
               (format #f "~a\nVisual Canon unavailable; do not invent permanent features."
                       (storyboard-cast-line entry)))))
       cast))

(define (storyboard-asset-reference-line asset)
  (let* ((tags (assoc-ref asset 'tags))
         (metadata
          (filter-map
           (lambda (entry)
             (let ((value (assoc-ref asset (car entry))))
               (and value (not (eq? value 'null))
                    (format #f "~a: ~a" (cdr entry) value))))
           '(("asset_type" . "type") ("mime_type" . "mime")
             ("width" . "width") ("height" . "height")
             ("duration_ms" . "duration ms")))))
    (format #f "~a — ~a~a"
            (assoc-ref asset 'name)
            (storyboard-text-or (assoc-ref asset 'description) "no description")
            (string-append
             (if (null? metadata)
                 ""
                 (format #f " [~a]" (string-join metadata ", ")))
             (if (or (not (list? tags)) (null? tags))
                 ""
                 (format #f " [tags: ~a]" (string-join tags ", ")))))))

(define (storyboard-asset-references config workplace-id scene-id cast)
  (let ((seen '()) (lines '()))
    (define (add-assets assets)
      (for-each
       (lambda (asset)
         (let ((id (assoc-ref asset 'id)))
           (unless (member id seen string=?)
             (set! seen (cons id seen))
             (set! lines
                   (cons (storyboard-asset-reference-line asset) lines)))))
       assets))
    (add-assets (db:studio-list-linked-assets config workplace-id "scene" scene-id))
    (for-each
     (lambda (entry)
       (add-assets (db:studio-list-linked-assets
                    config workplace-id "character"
                    (assoc-ref entry 'character_id))))
     cast)
    (take (reverse lines) (min 12 (length lines)))))

(define (storyboard-shot-set shot key value)
  (acons key value (alist-delete key shot equal?)))

(define* (storyboard-shot number content camera expression visual ids names
                          scene cast characters references
                          #:key (dramatic-beat "") (performance "")
                          (model ""))
  (let* ((setting (storyboard-setting scene))
         (cast-lines (storyboard-character-lines cast characters))
         (prompt-lines
          (append
           (list (format #f "STORYBOARD SHOT ~a — ~a" number content)
                 (format #f "SCENE: ~a" (assoc-ref scene 'title))
                 (format #f "SETTING: ~a" (storyboard-text-or setting "not specified"))
                 (format #f "SHOT ACTION: ~a" content)
                 (format #f "CAMERA / COMPOSITION: ~a" camera)
                 (format #f "EXPRESSION & ACTION: ~a" expression)
                 (format #f "VISUAL DESCRIPTION: ~a" visual)
                 "CAST AND SCENE OBJECTIVES:")
           cast-lines
           (list (format #f "REFERENCE ASSETS: ~a"
                         (if (null? references)
                             "none linked"
                             (string-join references "; ")))
                 "CONTINUITY: Preserve each named character's Visual Canon exactly: face, body, hair, clothing, palette, expressions and posture. Keep costume, age, injuries and distinguishing features consistent between shots. Do not add permanent physical changes."
                 "STYLE: Cinematic storyboard frame, 16:9, warm naturalistic production design, restrained film lighting, readable staging, no text, no captions, no UI, no borders."))))
    `(("id" . ,(db:studio-new-id))
      ("number" . ,number)
      ("dramatic_beat" . ,dramatic-beat)
      ("action" . ,content)
      ("content" . ,content)
      ("character_ids" . ,ids)
      ("characters" . ,names)
      ("camera" . ,camera)
      ("expression" . ,expression)
      ("performance" . ,performance)
      ("expression_action" . ,expression)
      ("visual_description" . ,visual)
      ("image_prompt" . ,(storyboard-clip (string-join prompt-lines "\n")
                                         max-shot-prompt-length))
      ("asset_id" . null)
      ("file_url" . null)
      ("status" . "pending")
      ("source" . "deterministic")
      ("model" . ,model)
      ("character_outfits" . ())
      ("reference_usage" . null)
      ("author_edited" . #f))))

(define (storyboard-generated-shots scene cast characters references model)
  (let* ((ids (map (lambda (entry) (assoc-ref entry 'character_id)) cast))
         (names (map (lambda (entry) (assoc-ref entry 'character_name)) cast))
         (setting (storyboard-text-or (storyboard-setting scene)
                                      "the scene's physical world"))
         (visuals (if (null? characters)
                      "No Character Visual Canon is available; do not invent permanent character features."
                      (string-join (map storyboard-visual-canon characters) "\n")))
         (emotions (if (null? cast)
                       "No cast is present yet; keep the frame environmental."
                       (string-join
                        (map (lambda (entry)
                               (format #f "~a: ~a"
                                       (assoc-ref entry 'character_name)
                                       (storyboard-text-or
                                        (assoc-ref entry 'emotional_state)
                                        "emotion not stated")))
                             cast)
                        "; ")))
         (actions (if (null? cast)
                      "No character action is established yet."
                      (string-join
                       (map (lambda (entry)
                              (format #f "~a wants ~a through ~a"
                                      (assoc-ref entry 'character_name)
                                      (storyboard-text-or
                                       (assoc-ref entry 'objective)
                                       "an unstated objective")
                                      (storyboard-text-or
                                       (assoc-ref entry 'action)
                                       "an unstated action")))
                            cast)
                       "; ")))
         (question (storyboard-text-or
                    (assoc-ref scene 'central_question)
                    "the unanswered dramatic question"))
         (conflict (storyboard-text-or
                    (assoc-ref scene 'primary_conflict)
                    "the pressure in the room"))
         (turn (storyboard-text-or
                (assoc-ref scene 'turn)
                "the moment when the situation can no longer return to its opening state"))
         (summary (storyboard-text-or
                   (assoc-ref scene 'summary)
                   "the room and the people in it")))
    (list
     (storyboard-shot
      1
      (storyboard-clip (format #f "Establish the world: ~a. ~a" setting summary) 1500)
      "Wide establishing shot, 24mm lens, eye level, deep staging; the geography and social distance of the room are readable."
      (format #f "The room holds its opening tension. ~a" emotions)
      (format #f "~a\n~a" setting visuals)
      ids names scene cast characters references
      #:dramatic-beat "Establish the world, the social distance, and the pressure already in the room."
      #:performance "Hold the Cast in their opening postures; let small reactions register before anyone speaks."
      #:model model)
     (storyboard-shot
      2
      (storyboard-clip (format #f "Pressure gathers around one question: ~a. The conflict is ~a." question conflict) 1600)
      "Medium two-shot, 35mm lens, slightly off-axis, foreground obstruction framing the distance between the characters."
      (format #f "Small reactions reveal what each person refuses to say. ~a" emotions)
      (format #f "~a\n~a" setting visuals)
      ids names scene cast characters references
      #:dramatic-beat "Bring the central question into the room and make avoidance visible."
      #:performance "Create a change of distance between the characters without resolving the conflict."
      #:model model)
     (storyboard-shot
      3
      (storyboard-clip (format #f "Action: ~a. The scene's pressure becomes physical." actions) 1700)
      "Medium close-up, 50mm lens, controlled handheld drift, focus shifts with the active character's objective."
      (format #f "~a. Keep gestures specific to the Visual Canon and the scene's performance direction." actions)
      (format #f "~a\n~a" setting visuals)
      ids names scene cast characters references
      #:dramatic-beat "Turn intention into action; the scene's pressure becomes physical."
      #:performance "Each gesture should pursue a scene objective and meet a concrete resistance."
      #:model model)
     (storyboard-shot
      4
      (storyboard-clip (format #f "The turn: ~a. Hold on the irreversible reaction." turn) 1600)
      "Close-up, 85mm lens, shallow focus, stillness after movement; the turn lands on a face and a changed spatial relation."
      (format #f "The reaction carries the cost of the turn without declaring it in dialogue. ~a" emotions)
      (format #f "~a\n~a" setting visuals)
      ids names scene cast characters references
      #:dramatic-beat "Land the turn and show its cost in a changed relationship or spatial balance."
      #:performance "End on a reaction that carries the consequence without announcing it in dialogue."
      #:model model))))

(define (storyboard-fill-default-outfits config wid shots)
  (map (lambda (shot)
         (let* ((ids (or (assoc-ref shot "character_ids") '()))
                (existing (or (assoc-ref shot "character_outfits") '()))
                (mapping
                 (fold
                  (lambda (character-id result)
                    (if (find (lambda (entry)
                                (equal? (assoc-ref entry "character_id")
                                        character-id))
                              result)
                        result
                        (let ((outfit (character-default-outfit
                                       config wid character-id)))
                          (if outfit
                              (append
                               result
                               (list
                                (list (cons "character_id" character-id)
                                      (cons "outfit_id"
                                            (assoc-ref outfit 'id)))))
                              result))))
                  (filter (lambda (entry)
                            (member (or (assoc-ref entry "character_id") "")
                                    ids string=?))
                          existing)
                  ids)))
           (storyboard-shot-set shot "character_outfits" mapping)))
       shots))

(define (storyboard-current-shots scene)
  (storyboard-shots (assoc-ref scene 'storyboard)))

(define (storyboard-cast-ids cast)
  (map (lambda (entry) (assoc-ref entry 'character_id)) cast))

(define (storyboard-shot-input-string value key default max)
  (if (object-has? value key)
      (string-field value key #:allow-empty #t #:default default #:max max)
      default))

(define (storyboard-shot-signature shot)
  `(,(assoc-ref shot "number")
    ,(assoc-ref shot "dramatic_beat")
    ,(assoc-ref shot "action")
    ,(sort (list-copy (assoc-ref shot "character_ids")) string<?)
    ,(assoc-ref shot "expression")
    ,(assoc-ref shot "performance")
    ,(assoc-ref shot "camera")
    ,(assoc-ref shot "visual_description")
    ,(assoc-ref shot "image_prompt")
    ,(sort
      (map (lambda (entry)
             (format #f "~a:~a"
                     (or (assoc-ref entry "character_id") "")
                     (or (assoc-ref entry "outfit_id") "")))
           (or (assoc-ref shot "character_outfits") '()))
      string<?)))

(define (storyboard-character-outfits-field value index ids previous
                                            config wid)
  (define (validate entry entry-index)
    (unless (object? entry)
      (api-fail 400 "VALIDATION_ERROR"
                (format #f "shots[~a].character_outfits[~a] must be an object"
                        index entry-index)))
    (require-object-fields
     entry (format #f "shots[~a].character_outfits[~a]" index entry-index)
     '("character_id" "outfit_id"))
    (let* ((character-id (object-ref entry "character_id"))
           (outfit-id (object-ref entry "outfit_id")))
      (unless (and (string? character-id) (valid-uuid? character-id))
        (api-fail 400 "VALIDATION_ERROR"
                  "character_outfits.character_id must be a UUID"))
      (unless (and (string? outfit-id) (valid-uuid? outfit-id))
        (api-fail 400 "VALIDATION_ERROR"
                  "character_outfits.outfit_id must be a UUID"))
      (let ((character-id (string-downcase character-id))
            (outfit-id (string-downcase outfit-id)))
        (unless (member character-id ids string=?)
          (api-fail 422 "INVALID_SHOT_OUTFIT"
                    "Every Shot Outfit must belong to a Character in that Shot"))
        (unless (db:studio-get-character-outfit config wid character-id outfit-id)
          (api-fail 422 "INVALID_SHOT_OUTFIT"
                    "Every Shot Outfit must belong to its Character and Workplace"))
        `(("character_id" . ,character-id) ("outfit_id" . ,outfit-id)))))
  (if (not (object-has? value "character_outfits"))
      (filter (lambda (entry)
                (member (or (assoc-ref entry "character_id") "") ids string=?))
              previous)
      (let ((entries (json-array-list (object-ref value "character_outfits")
                                      (format #f "shots[~a].character_outfits"
                                              index))))
        (let loop ((rest entries) (result '()) (seen '()) (position 0))
          (if (null? rest)
              (reverse result)
              (let ((entry (validate (car rest) position)))
                (let ((character-id (assoc-ref entry "character_id")))
                  (when (member character-id seen string=?)
                    (api-fail 400 "VALIDATION_ERROR"
                              "A Shot can select only one Outfit per Character"))
                  (loop (cdr rest) (cons entry result)
                        (cons character-id seen) (+ position 1)))))))))

(define (storyboard-shot-value value index current cast config wid)
  (unless (object? value)
    (api-fail 400 "VALIDATION_ERROR"
              (format #f "shots[~a] must be an object" index)))
  (require-object-fields
   value (format #f "shots[~a]" index)
   '("id" "number" "dramatic_beat" "action" "content" "character_ids"
     "camera" "expression" "performance" "expression_action"
     "visual_description" "image_prompt" "character_outfits"
     ;; Derived fields are accepted for round-tripping from the UI, but the
     ;; server preserves their authoritative values below.
     "characters" "asset_id" "file_url" "status" "source" "model"
     "author_edited" "reference_usage"))
  (let* ((raw-id (object-ref value "id"))
         (id (cond ((not raw-id) (db:studio-new-id))
                   ((valid-uuid? raw-id) (string-downcase raw-id))
                   (else (api-fail 400 "VALIDATION_ERROR"
                                   (format #f "shots[~a].id must be a UUID" index)))))
         (previous-raw (find (lambda (shot)
                               (equal? (assoc-ref shot "id") id))
                             current))
         (previous (and previous-raw (storyboard-normalize-shot previous-raw)))
         (ids (json-array-list (or (object-ref value "character_ids") '())
                               (format #f "shots[~a].character_ids" index)))
         (cast-ids (storyboard-cast-ids cast)))
    (for-each
     (lambda (character-id)
       (unless (and (valid-uuid? character-id)
                    (member (string-downcase character-id) cast-ids string=?))
         (api-fail 422 "INVALID_SHOT_CHARACTER"
                   "Every shot Character must be cast in this Scene")))
     ids)
    (let loop ((rest ids) (seen '()))
      (when (pair? rest)
        (let ((character-id (string-downcase (car rest))))
          (when (member character-id seen string=?)
            (api-fail 400 "VALIDATION_ERROR"
                      "A Character can only appear once in a Shot"))
          (loop (cdr rest) (cons character-id seen)))))
    (let* ((ids (map string-downcase ids))
           (names (map (lambda (character-id)
                         (let ((entry (find (lambda (item)
                                              (equal? (assoc-ref item 'character_id)
                                                      character-id))
                                            cast)))
                           (and entry (assoc-ref entry 'character_name))))
                       ids))
           (number (optional-integer-field value "number" 1 99
                                           (if previous
                                               (or (assoc-ref previous "number")
                                                   (+ index 1))
                                               (+ index 1))))
           (previous-action (if previous (assoc-ref previous "action") ""))
           (previous-content (if previous (assoc-ref previous "content") ""))
           (incoming-action (and (object-has? value "action")
                                 (storyboard-shot-input-string
                                  value "action" "" max-shot-text-length)))
           (incoming-content (and (object-has? value "content")
                                  (storyboard-shot-input-string
                                   value "content" "" max-shot-text-length)))
           (action (cond
                    ((and incoming-action incoming-content)
                     (cond
                      ((and (equal? incoming-action previous-action)
                            (not (equal? incoming-content previous-content)))
                       incoming-content)
                      (else incoming-action)))
                    (incoming-action incoming-action)
                    (incoming-content incoming-content)
                    (else previous-action)))
           (dramatic-beat
            (storyboard-shot-input-string
             value "dramatic_beat"
             (if previous (or (assoc-ref previous "dramatic_beat") "") "")
             max-shot-text-length))
           (incoming-expression
            (and (object-has? value "expression")
                 (storyboard-shot-input-string
                  value "expression" "" max-shot-text-length)))
           (incoming-expression-action
            (and (object-has? value "expression_action")
                 (storyboard-shot-input-string
                  value "expression_action" "" max-shot-text-length)))
           (expression
            (cond (incoming-expression incoming-expression)
                  (incoming-expression-action incoming-expression-action)
                  (previous (or (assoc-ref previous "expression") ""))
                  (else "")))
           (performance
            (storyboard-shot-input-string
             value "performance"
             (if previous (or (assoc-ref previous "performance") "") "")
             max-shot-text-length))
           (expression-action
            (or (storyboard-join-text expression performance)
                incoming-expression-action ""))
           (camera (storyboard-shot-input-string
                    value "camera"
                    (if previous (or (assoc-ref previous "camera") "") "")
                    max-shot-text-length))
           (visual (storyboard-shot-input-string
                    value "visual_description"
                    (if previous
                        (or (assoc-ref previous "visual_description") "")
                        "")
                    max-shot-text-length))
           (image-prompt (storyboard-shot-input-string
                          value "image_prompt"
                          (if previous
                              (or (assoc-ref previous "image_prompt") "")
                              "")
                          max-shot-prompt-length))
           (character-outfits
            (storyboard-character-outfits-field
             value index ids
             (if previous
                 (or (assoc-ref previous "character_outfits") '())
                 '())
             config wid))
           (asset-id (if previous
                         (let ((asset (assoc-ref previous "asset_id")))
                           (if (and asset (not (eq? asset 'null))) asset 'null))
                         'null))
           (file-url (if previous
                         (let ((url (assoc-ref previous "file_url")))
                           (if (and url (not (eq? url 'null))) url 'null))
                         'null))
           (status (if previous
                       (or (assoc-ref previous "status") "pending")
                       "pending"))
           (source (if previous
                       (or (assoc-ref previous "source") "manual")
                       "manual"))
           (model (if previous (or (assoc-ref previous "model") "") ""))
           (reference-usage (if previous
                                (or (assoc-ref previous "reference_usage") 'null)
                                'null))
           (candidate
            `(("id" . ,id)
              ("number" . ,number)
              ("dramatic_beat" . ,dramatic-beat)
              ("action" . ,action)
              ("content" . ,action)
              ("character_ids" . ,ids)
              ("characters" . ,(filter-map (lambda (name) name) names))
              ("camera" . ,camera)
              ("expression" . ,expression)
              ("performance" . ,performance)
              ("expression_action" . ,expression-action)
              ("visual_description" . ,visual)
              ("image_prompt" . ,image-prompt)
              ("asset_id" . ,asset-id)
              ("file_url" . ,file-url)
              ("status" . ,status)
              ("source" . ,source)
              ("model" . ,model)
              ("character_outfits" . ,character-outfits)
              ("reference_usage" . ,reference-usage)
              ("author_edited" . #f)))
           (author-edited
            (if previous
                (or (eq? (assoc-ref previous "author_edited") #t)
                    (not (equal? (storyboard-shot-signature previous)
                                 (storyboard-shot-signature candidate))))
                #t)))
      (storyboard-shot-set candidate "author_edited"
                           (and author-edited #t)))))

(define (storyboard-shots-from-body body current cast config wid)
  (unless (object-has? body "shots")
    (api-fail 400 "VALIDATION_ERROR" "shots is required"))
  (let* ((values (json-array-list (object-ref body "shots") "shots"))
         (count (length values)))
    (unless (and (>= count 1) (<= count max-storyboard-shots))
      (api-fail 400 "VALIDATION_ERROR"
                (format #f "shots must contain between 1 and ~a shots"
                        max-storyboard-shots)))
    (let ((shots (map (lambda (value index)
                        (storyboard-shot-value value index current cast config wid))
                      values (iota count))))
      (let loop ((rest shots) (seen '()))
        (when (pair? rest)
          (let ((id (assoc-ref (car rest) "id")))
            (when (member id seen string=?)
              (api-fail 400 "VALIDATION_ERROR" "Shot ids must be unique"))
            (loop (cdr rest) (cons id seen)))))
      shots)))

(define (storyboard-ai-fail message)
  (api-fail 502 "INVALID_STORYBOARD_OUTPUT" message))

(define (storyboard-ai-object-fields object label allowed)
  (unless (object? object)
    (storyboard-ai-fail (format #f "~a must be a JSON object" label)))
  (for-each
   (lambda (entry)
     (unless (member (car entry) allowed)
       (storyboard-ai-fail
        (format #f "~a.~a is not part of the storyboard schema"
                label (car entry)))))
   object))

(define (storyboard-ai-array value label)
  (cond
   ((vector? value) (vector->list value))
   ((or (null? value) (list? value))
    (storyboard-ai-fail (format #f "~a must be a JSON array" label)))
   (else (storyboard-ai-fail (format #f "~a must be a JSON array" label)))))

(define (storyboard-ai-string shot label key max allow-empty)
  (unless (object-has? shot key)
    (storyboard-ai-fail (format #f "~a.~a is required" label key)))
  (let ((value (object-ref shot key)))
    (unless (string? value)
      (storyboard-ai-fail (format #f "~a.~a must be a string" label key)))
    (when (and (not allow-empty) (string-null? (string-trim-both value)))
      (storyboard-ai-fail (format #f "~a.~a must not be empty" label key)))
    (when (> (string-length value) max)
      (storyboard-ai-fail (format #f "~a.~a is too large" label key)))
    value))

(define (storyboard-ai-shot shot index cast-ids)
  (let ((label (format #f "shots[~a]" index)))
    (storyboard-ai-object-fields shot label storyboard-ai-shot-fields)
    (let* ((raw-ids (and (object-has? shot "character_ids")
                         (object-ref shot "character_ids")))
           (_ (unless (object-has? shot "character_ids")
                (storyboard-ai-fail
                 (format #f "~a.character_ids is required" label))))
           (ids (storyboard-ai-array raw-ids
                                     (format #f "~a.character_ids" label)))
           (ids (map (lambda (character-id)
                       (unless (and (string? character-id)
                                    (valid-uuid? character-id))
                         (storyboard-ai-fail
                          (format #f "~a.character_ids must contain UUIDs" label)))
                       (string-downcase character-id))
                     ids)))
      (let loop ((rest ids) (seen '()))
        (when (pair? rest)
          (when (member (car rest) seen string=?)
            (storyboard-ai-fail
             (format #f "~a.character_ids contains a duplicate" label)))
          (loop (cdr rest) (cons (car rest) seen))))
      (for-each
       (lambda (character-id)
         (unless (member character-id cast-ids string=?)
           (storyboard-ai-fail
            (format #f "~a references a Character outside this Scene cast"
                    label))))
       ids)
      `(("dramatic_beat"
         . ,(storyboard-ai-string shot label "dramatic_beat"
                                  max-shot-text-length #f))
        ("action" . ,(storyboard-ai-string shot label "action"
                                         max-shot-text-length #f))
        ("character_ids" . ,ids)
        ("expression" . ,(storyboard-ai-string shot label "expression"
                                             max-shot-text-length #t))
        ("performance" . ,(storyboard-ai-string shot label "performance"
                                               max-shot-text-length #t))
        ("camera" . ,(storyboard-ai-string shot label "camera"
                                         max-shot-text-length #f))
        ("visual_description"
         . ,(storyboard-ai-string shot label "visual_description"
                                  max-shot-text-length #f))
        ("image_prompt" . ,(storyboard-ai-string shot label "image_prompt"
                                               max-shot-prompt-length #f))))))

(define (studio-validate-storyboard-json text cast-ids)
  (unless (string? text)
    (storyboard-ai-fail "The storyboard model returned no JSON"))
  (catch #t
    (lambda ()
      (let* ((trimmed (string-trim-both text))
             (root (json-string->scm trimmed)))
        (storyboard-ai-object-fields root "storyboard" '("shots"))
        (unless (object-has? root "shots")
          (storyboard-ai-fail "storyboard.shots is required"))
        (let* ((shot-values (storyboard-ai-array
                             (object-ref root "shots") "storyboard.shots"))
               (count (length shot-values)))
          (unless (and (>= count 1) (<= count max-storyboard-shots))
            (storyboard-ai-fail
             (format #f "storyboard.shots must contain between 1 and ~a shots"
                     max-storyboard-shots)))
          (map (lambda (shot index)
                 (storyboard-ai-shot shot index cast-ids))
               shot-values (iota count)))))
    (lambda (key . args)
      (if (eq? key 'studio-api-error)
          (apply throw key args)
          (storyboard-ai-fail
           "The storyboard model did not return valid JSON")))))

(define (storyboard-context-line label value)
  (let ((text (storyboard-nonempty-text value)))
    (and text (format #f "~a: ~a" label (storyboard-clip text 5000)))))

(define (storyboard-scene-context scene cast characters references)
  (let* ((given
          (filter-map
           (lambda (entry)
             (storyboard-context-line
              (cdr entry)
              (assoc-ref scene (string->symbol (car entry)))))
           '(("time" . "Time") ("place" . "Place")
             ("environment" . "Environment")
             ("background" . "Background")
             ("prior_events" . "Prior events"))))
         (dramatic
          (filter-map
           (lambda (entry)
             (storyboard-context-line
              (cdr entry)
              (assoc-ref scene (string->symbol (car entry)))))
           '(("central_question" . "Central question")
             ("primary_conflict" . "Primary conflict")
             ("turn" . "Turn"))))
         (direction
          (filter-map
           (lambda (entry)
             (storyboard-context-line
              (cdr entry)
              (assoc-ref scene (string->symbol (car entry)))))
           '(("blocking" . "Blocking") ("spatial" . "Spatial")
             ("performance_direction" . "Performance direction")
             ("camera" . "Camera")))))
    (string-join
     (filter
      storyboard-nonempty-text
      (list
       (format #f "SCENE TITLE: ~a" (assoc-ref scene 'title))
       (storyboard-context-line "Summary" (assoc-ref scene 'summary))
       (format #f "GIVEN CIRCUMSTANCES\n~a"
               (if (null? given)
                   "- not specified"
                   (string-join given "\n")))
       (format #f "DRAMATIC SITUATION\n~a"
               (if (null? dramatic)
                   "- not specified"
                   (string-join dramatic "\n")))
       (format #f "DIALOGUE\n~a"
               (storyboard-text-or (assoc-ref scene 'dialogue) "not supplied"))
       (format #f "DIRECTION\n~a"
               (if (null? direction)
                   "- not specified"
                   (string-join direction "\n")))
       (format #f "CAST — SCENE-SPECIFIC CONTEXT\n~a"
               (if (null? cast)
                   "No Character is cast in this Scene."
                   (string-join
                    (storyboard-character-lines cast characters) "\n\n")))
       (format #f "REFERENCE ASSETS — TEXT METADATA ONLY\n~a"
               (if (null? references)
                   "No Assets are linked to this Scene or its Cast."
                   (string-join references "\n")))
       "The Asset metadata above is text. You have not seen image pixels. Do not claim otherwise."))
     "\n\n")))

(define (storyboard-ai-prepared config scene cast characters references body)
  (let* ((system (read-prompt "storyboard.md"))
         (max-tokens (optional-integer-field body "max_tokens" 256
                                             max-storyboard-ai-tokens 2048))
         (context (storyboard-clip
                   (storyboard-scene-context scene cast characters references)
                   max-storyboard-context-length))
         (messages
          (list `(("role" . "system") ("content" . ,system))
                `(("role" . "user") ("content" . ,context))))
         (options `(("temperature" . 0.55)
                    ("num_predict" . ,max-tokens)
                    ("max_output_tokens" . ,max-tokens)
                    ("stream" . #f)
                    ("format" . "json"))))
    (prepare-task-chat config "storyboard_planning" messages options body)))

(define (storyboard-deterministic? config)
  (let ((profile (profile-for-task config "storyboard_planning")))
    (if profile
        (equal? (assoc-ref profile 'protocol) "fake")
        (equal? (configured-engine config) "fake"))))

(define (storyboard-shot-character-names ids cast)
  (map (lambda (character-id)
         (let ((entry (find (lambda (item)
                              (equal? (assoc-ref item 'character_id)
                                      character-id))
                            cast)))
           (or (and entry (assoc-ref entry 'character_name)) "Unknown Character")))
       ids))

(define (storyboard-ai-image-prompt prompt ids characters references)
  (let* ((canon
          (if (null? ids)
              "No Character appears in this shot. Do not invent a recurring character."
              (string-join
               (map (lambda (character-id)
                      (let ((character
                             (find (lambda (item)
                                     (equal? (assoc-ref item 'id) character-id))
                                   characters)))
                        (if character
                            (storyboard-visual-canon character)
                            (format #f "~a: Visual Canon unavailable; do not invent permanent features."
                                    character-id))))
                    ids)
               "\n")))
         (reference-line
          (if (null? references)
              "Reference Assets: none linked."
              (format #f "Reference Assets (metadata only): ~a"
                      (string-join references "; ")))))
    (storyboard-clip
     (string-join
      (list "VISUAL CANON — AUTHORITATIVE; DO NOT ALTER PERMANENT FEATURES"
            canon
            "Keep face, body, hair, clothing, palette and distinguishing features identical. Expressions, poses, action and lighting may change."
            reference-line
            "SHOT"
            prompt
            "STYLE: Cinematic 16:9 storyboard frame, warm naturalistic production design, restrained film lighting, readable staging, no text, captions, UI or borders.")
      "\n\n")
     max-shot-prompt-length)))

(define (storyboard-ai-shots parsed cast characters model references)
  (map (lambda (shot index)
         (let* ((ids (assoc-ref shot "character_ids"))
                (names (storyboard-shot-character-names ids cast))
                (action (assoc-ref shot "action"))
                (expression (assoc-ref shot "expression"))
                (performance (assoc-ref shot "performance")))
           `(("id" . ,(db:studio-new-id))
             ("number" . ,(+ index 1))
             ("dramatic_beat" . ,(assoc-ref shot "dramatic_beat"))
             ("action" . ,action)
             ("content" . ,action)
             ("character_ids" . ,ids)
             ("characters" . ,names)
             ("camera" . ,(assoc-ref shot "camera"))
             ("expression" . ,expression)
             ("performance" . ,performance)
             ("expression_action"
              . ,(or (storyboard-join-text expression performance) ""))
             ("visual_description" . ,(assoc-ref shot "visual_description"))
             ("image_prompt"
              . ,(storyboard-ai-image-prompt
                  (assoc-ref shot "image_prompt") ids characters references))
             ("asset_id" . null)
             ("file_url" . null)
             ("status" . "pending")
             ("source" . "ai")
             ("model" . ,model)
             ("character_outfits" . ())
             ("reference_usage" . null)
             ("author_edited" . #f))))
       parsed (iota (length parsed))))

(define (studio-get-storyboard config workplace-id scene-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (scene (require-scene config wid scene-id)))
    (storyboard-payload config scene)))

(define (storyboard-boolean-field body key)
  (let ((value (object-ref body key)))
    (cond ((not (object-has? body key)) #f)
          ((boolean? value) value)
          (else (api-fail 400 "VALIDATION_ERROR"
                          (format #f "~a must be a boolean" key))))))

(define (storyboard-protected-shot? shot)
  (let ((asset-id (assoc-ref shot "asset_id"))
        (file-url (assoc-ref shot "file_url"))
        (status (assoc-ref shot "status")))
    (or ;; Boards saved before authorship tracking cannot be proven untouched.
        (not (or (assoc "source" shot) (assoc "author_edited" shot)))
        (eq? (assoc-ref shot "author_edited") #t)
        (equal? status "generated")
        (and asset-id (not (eq? asset-id 'null)))
        (and file-url (not (eq? file-url 'null))))))

(define (storyboard-protected-count shots)
  (length (filter storyboard-protected-shot? shots)))

(define (storyboard-run-ai-generation config scene cast characters references body)
  (catch #t
    (lambda ()
      (let* ((prepared
              (storyboard-ai-prepared config scene cast characters
                                      references body))
             (cast-ids (storyboard-cast-ids cast))
             (result (studio-run-ai prepared))
             (text (or (assoc-ref result 'text)
                       (assoc-ref result "text")
                       ""))
             (parsed (studio-validate-storyboard-json text cast-ids))
             (model (assoc-ref prepared 'model)))
        (storyboard-ai-shots parsed cast characters model references)))
    (lambda (key . args)
      (if (eq? key 'studio-api-error)
          (apply throw key args)
          (begin
            (format (current-error-port) "Storyboard model generation failed: ~s ~s~%"
                    key args)
            (api-fail 502 "GENERATION_FAILED"
                      "The storyboard model failed to generate a valid board"))))))

(define (studio-create-storyboard! config workplace-id scene-id body)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (scene (require-scene config wid scene-id))
         (sid (assoc-ref scene 'id))
         (current-raw (storyboard-current-shots scene))
         (current (map storyboard-normalize-shot current-raw))
         (force (storyboard-boolean-field body "force"))
         (acknowledge (storyboard-boolean-field body "acknowledge_protected"))
         (protected-count (storyboard-protected-count current-raw)))
    (when (and force (not acknowledge) (> protected-count 0))
      (api-fail 422 "STORYBOARD_PROTECTED"
                "Regeneration would replace author-edited or image-generated shots"
                (cons "protected_shots" protected-count)))
    (if (and (pair? current) (not force))
        (storyboard-payload config scene)
        (let* ((cast (db:studio-list-scene-cast config wid sid))
               (characters (filter-map
                            (lambda (entry)
                              (db:studio-get-character
                               config wid (assoc-ref entry 'character_id)))
                            cast))
               (references (storyboard-asset-references config wid sid cast))
               (shots
                (storyboard-fill-default-outfits
                 config wid
                 (if (storyboard-deterministic? config)
                     (storyboard-generated-shots scene cast characters references
                                                 (default-model config))
                     (storyboard-run-ai-generation
                      config scene cast characters references body))))
               (saved (db:studio-update-scene!
                       config wid sid
                       `((storyboard . ,(storyboard-json shots))))))
          (storyboard-payload config saved)))))

(define (studio-update-storyboard! config workplace-id scene-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (scene (require-scene config wid scene-id))
         (sid (assoc-ref scene 'id))
         (cast (db:studio-list-scene-cast config wid sid))
         (shots (storyboard-shots-from-body body
                                            (storyboard-current-shots scene)
                                            cast config wid))
         (saved (db:studio-update-scene!
                 config wid sid
                 `((storyboard . ,(storyboard-json shots))))))
    (storyboard-payload config saved)))

(define (storyboard-public-asset config asset)
  (public-asset asset #:include-links #t #:config config))

(define max-storyboard-reference-images 24)

(define (storyboard-reference-bytes config asset)
  (let* ((storage-key (and asset (assoc-ref asset 'storage_key)))
         (path (and storage-key
                    (fs:studio-asset-resolve-path config storage-key))))
    (unless path
      (api-fail 422 "REFERENCE_FILE_MISSING"
                "An approved reference image is unavailable"))
    (let ((bytes (call-with-input-file path get-bytevector-all)))
      (unless (and bytes (> (bytevector-length bytes) 0))
        (api-fail 422 "REFERENCE_FILE_MISSING"
                  "An approved reference image is empty"))
      bytes)))

(define (storyboard-reference-descriptor config wid role kind asset
                                          character-id outfit-id)
  (let ((asset-id (assoc-ref asset 'id)))
    `((role . ,role)
      (reference_kind . ,kind)
      (asset_id . ,asset-id)
      (character_id . ,character-id)
      (outfit_id . ,outfit-id)
      (workplace_id . ,wid)
      (name . ,(assoc-ref asset 'name))
      (mime_type . ,(assoc-ref asset 'mime_type))
      (checksum . ,(assoc-ref asset 'checksum))
      (width . ,(assoc-ref asset 'width))
      (height . ,(assoc-ref asset 'height))
      (data . ,(storyboard-reference-bytes config asset)))))

(define (storyboard-approved-reference-asset config wid asset-id label)
  (or (and asset-id (db:studio-get-asset config wid asset-id))
      (api-fail 422 "REFERENCE_ASSET_MISSING"
                (format #f "~a points to an unavailable Asset" label))))

(define (storyboard-shot-outfit-id shot character-id)
  (let ((entry (find (lambda (item)
                       (equal? (assoc-ref item "character_id") character-id))
                     (or (assoc-ref shot "character_outfits") '()))))
    (and entry (assoc-ref entry "outfit_id"))))

(define (storyboard-approved-references config wid scene shot)
  (let* ((shot-ids (or (assoc-ref shot "character_ids") '()))
         (character-references
          (append-map
           (lambda (character-id)
             (let* ((character (db:studio-get-character config wid character-id))
                    (_ (unless character
                         (api-fail 422 "INVALID_SHOT_CHARACTER"
                                   "A Shot Character is no longer available")))
                    (full-body-id (assoc-ref character 'full_body_asset_id))
                    (avatar-id (assoc-ref character 'avatar_asset_id))
                    (approved-id (or full-body-id avatar-id))
                    (kind (if full-body-id "full_body" "avatar"))
                    (character-reference
                     (if approved-id
                         (let ((asset
                                (storyboard-approved-reference-asset
                                 config wid approved-id
                                 (format #f "~a's approved ~a"
                                         (assoc-ref character 'name) kind))))
                           (list (storyboard-reference-descriptor
                                  config wid "character" kind asset
                                  character-id #f)))
                         '()))
                    (outfit-id (or (storyboard-shot-outfit-id shot character-id)
                                   (let ((outfit (character-default-outfit
                                                  config wid character-id)))
                                     (and outfit (assoc-ref outfit 'id)))))
                    (outfit (and outfit-id
                                 (db:studio-get-character-outfit
                                  config wid character-id outfit-id)))
                    (_ (when (and outfit-id (not outfit))
                         (api-fail 422 "INVALID_SHOT_OUTFIT"
                                   "A selected Shot Outfit is no longer available")))
                    (outfit-reference-id (and outfit
                                              (assoc-ref outfit
                                                         'reference_asset_id)))
                    (outfit-reference
                     (if outfit-reference-id
                         (let ((asset
                                (storyboard-approved-reference-asset
                                 config wid outfit-reference-id
                                 (format #f "Outfit ~a"
                                         (assoc-ref outfit 'name)))))
                           (list (storyboard-reference-descriptor
                                  config wid "outfit" "outfit_reference" asset
                                  character-id outfit-id)))
                         '())))
               (append character-reference outfit-reference)))
           shot-ids))
         (scene-references
          (let ((scene-reference-ids
                 (json-string-list (assoc-ref scene 'reference_asset_ids))))
            (map (lambda (asset-id)
                   (let ((asset
                          (storyboard-approved-reference-asset
                           config wid asset-id "A Scene reference")))
                     (storyboard-reference-descriptor
                      config wid "scene" "scene_reference" asset #f #f)))
                 scene-reference-ids)))
         (references (append character-references scene-references)))
    (when (> (length references) max-storyboard-reference-images)
      (api-fail 422 "TOO_MANY_REFERENCES"
                (format #f "A Shot supports at most ~a approved reference images"
                        max-storyboard-reference-images)))
    references))

(define (storyboard-reference-trace config wid reference applied)
  (let ((asset-id (assoc-ref reference 'asset_id))
        (character-id (assoc-ref reference 'character_id))
        (outfit-id (assoc-ref reference 'outfit_id)))
    `(("role" . ,(assoc-ref reference 'role))
      ("reference_kind" . ,(assoc-ref reference 'reference_kind))
      ("asset_id" . ,asset-id)
      ("character_id" . ,(mark character-id))
      ("outfit_id" . ,(mark outfit-id))
      ("name" . ,(assoc-ref reference 'name))
      ("mime_type" . ,(assoc-ref reference 'mime_type))
      ("checksum" . ,(assoc-ref reference 'checksum))
      ("width" . ,(mark (assoc-ref reference 'width)))
      ("height" . ,(mark (assoc-ref reference 'height)))
      ("file_url"
       . ,(format #f "/studio/api/v1/workplaces/~a/assets/~a/file"
                  wid asset-id))
      ("applied" . ,(and applied #t)))))

(define (storyboard-reference-usage config wid references)
  (let* ((capabilities (studio-image-generation-capabilities config))
         (supports (assoc-ref capabilities "reference_images"))
         (applied (and supports (pair? references) #t))
         (mode (cond (applied "reference-conditioned")
                     (supports "text-only")
                     (else "text-only")))
         (message
          (cond
           (applied "Approved reference image bytes were passed to the image adapter.")
           ((pair? references)
            "Approved references were collected, but the current image adapter is text-to-image only; they were not applied.")
           (else "No approved reference images were selected."))))
    `(("engine" . ,(assoc-ref capabilities "engine"))
      ("mode" . ,mode)
      ("applied" . ,(and applied #t))
      ("reference_mode" . ,(assoc-ref capabilities "reference_mode"))
      ("message" . ,message)
      ("references"
       . ,(map (lambda (reference)
                 (storyboard-reference-trace config wid reference applied))
               references)))))

(define (studio-generate-storyboard-image! config workplace-id scene-id shot-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (scene (require-scene config wid scene-id))
         (sid (assoc-ref scene 'id))
         (shots (map storyboard-normalize-shot
                     (storyboard-current-shots scene)))
         (shot (find (lambda (item)
                       (equal? (assoc-ref item "id")
                               (require-uuid-in-path shot-id "Shot")))
                     shots)))
    (unless shot
      (api-fail 404 "NOT_FOUND" "Storyboard shot not found"))
    (unless (image-generation-available? config)
      (api-fail 503 "IMAGE_SERVICE_UNAVAILABLE"
                "Image generation is not available in this environment"))
    (let* ((prompt (assoc-ref shot "image_prompt"))
           (_ (unless (and (string? prompt)
                           (not (string-null? (string-trim-both prompt))))
                (api-fail 422 "SHOT_PROMPT_REQUIRED"
                          "The Storyboard shot needs an image prompt")))
           (references
            (storyboard-approved-references config wid scene shot))
           (reference-usage
            (storyboard-reference-usage config wid references))
           (apply-references?
            (eq? (assoc-ref reference-usage "applied") #t))
           (pngs
            (catch #t
              (lambda ()
                (comfy-render-image! config prompt storyboard-image-width
                                     storyboard-image-height
                                     (+ (current-time) (random 1000000))
                                     #:references
                                     (if apply-references? references '())))
              (lambda (key . args)
                (format (current-error-port) "Storyboard image generation failed: ~s ~s~%"
                        key args)
                (api-fail 502 "GENERATION_FAILED"
                          "Image generation failed; the Scene was not changed"))))
           (_ (unless (and (pair? pngs)
                           (bytevector? (car pngs))
                           (> (bytevector-length (car pngs)) 0))
                (api-fail 502 "GENERATION_FAILED"
                          "Image generation returned no image")))
           (png (car pngs))
           (asset-id (db:studio-new-id))
           (shot-number (assoc-ref shot "number"))
           (filename (format #f "storyboard-shot-~a.png" shot-number))
           (storage-key #f))
      (catch #t
        (lambda ()
          (let* ((validated
                  (fs:studio-asset-validate-upload
                   config filename "image/png" png "image"))
                 (extension (assoc-ref validated 'extension))
                 (key (fs:studio-asset-storage-key asset-id extension))
                 (checksum (fs:studio-asset-store-file! config key png))
                 (metadata
                  (json-encode
                   (json-normalize
                    `(("engine" . ,(configured-engine config))
                      ("prompt" . ,prompt)
                      ("scene_id" . ,sid)
                      ("shot_id" . ,(assoc-ref shot "id"))
                      ("shot_number" . ,shot-number)
                      ("width" . ,storyboard-image-width)
                      ("height" . ,storyboard-image-height)
                      ("reference_mode" . ,(assoc-ref reference-usage "mode"))
                      ("references_applied"
                       . ,(assoc-ref reference-usage "applied"))
                      ("references"
                       . ,(assoc-ref reference-usage "references"))))))
                 (values
                  `((name . ,(format #f "Storyboard ~a — ~a"
                                     shot-number (assoc-ref scene 'title)))
                    (description . ,(format #f "Generated image for shot ~a of ~a."
                                            shot-number (assoc-ref scene 'title)))
                    (asset_type . "image")
                    (storage_key . ,key)
                    (original_filename . ,filename)
                    (mime_type . "image/png")
                    (file_size . ,(bytevector-length png))
                    (checksum . ,checksum)
                    (source . "generated")
                    (width . ,storyboard-image-width)
                    (height . ,storyboard-image-height)
                    (duration_ms . #f)
                    (author . "Khala Studio")
                    (notes . ,(assoc-ref scene 'title))
                    (generation_metadata . ,metadata)
                    (tags . ("storyboard" "generated")))))
            (set! storage-key key)
            (let* ((asset (db:studio-create-asset! config asset-id wid values))
                   (file-url (format #f "/studio/api/v1/workplaces/~a/assets/~a/file"
                                     wid asset-id))
                   (updated-shots
                    (map (lambda (item)
                           (if (equal? (assoc-ref item "id")
                                       (assoc-ref shot "id"))
                               (storyboard-shot-set
                                (storyboard-shot-set
                                 (storyboard-shot-set
                                  (storyboard-shot-set item "asset_id" asset-id)
                                  "file_url" file-url)
                                 "status" "generated")
                                "reference_usage" reference-usage)
                               item))
                         shots))
                   (_ (db:studio-add-asset-link! config wid asset-id "scene" sid))
                   (saved (db:studio-update-scene!
                           config wid sid
                           `((storyboard . ,(storyboard-json updated-shots)))))
                   (updated-shot (find (lambda (item)
                                         (equal? (assoc-ref item "id")
                                                 (assoc-ref shot "id")))
                                       (storyboard-current-shots saved))))
              `(("shot" . ,updated-shot)
                ("asset" . ,(storyboard-public-asset config asset))
                ("reference_usage" . ,reference-usage)))))
        (lambda (key . args)
          (when storage-key
            (fs:studio-asset-delete-file! config storage-key))
          (catch #t
            (lambda () (db:studio-archive-asset! config wid asset-id))
            (lambda _ #f))
          (format (current-error-port) "Storyboard image save failed: ~s ~s~%"
                  key args)
          (api-fail 502 "GENERATION_FAILED"
                    "The generated image could not be stored"))))))

(define asset-types '("image" "audio" "video" "document" "other"))
(define asset-sources '("generated" "imported"))
(define asset-resource-types '("character" "scene" "document"))
(define max-asset-name-length 512)
(define max-asset-description-length 4000)
(define max-asset-author-length 512)
(define max-asset-notes-length 20000)
(define max-asset-tag-length 64)
(define max-asset-tags 32)

(define (asset-type-field body default)
  (let ((value (string-field body "asset_type" #:allow-empty #t
                             #:default default #:max 32)))
    (unless (member value asset-types)
      (api-fail 400 "VALIDATION_ERROR" "asset_type is not supported"))
    value))

(define (asset-source-field body default)
  (let ((value (string-field body "source" #:allow-empty #t
                             #:default default #:max 32)))
    (unless (member value asset-sources)
      (api-fail 400 "VALIDATION_ERROR"
                "source must be generated or imported"))
    value))

(define (json-array-values value label)
  (cond
   ((vector? value) (vector->list value))
   ((null? value) '())
   ((object? value) (api-fail 400 "VALIDATION_ERROR"
                              (format #f "~a must be an array" label)))
   ((list? value) value)
   (else (api-fail 400 "VALIDATION_ERROR"
                   (format #f "~a must be an array" label)))))

(define (normalize-tags values)
  (when (> (length values) max-asset-tags)
    (api-fail 400 "VALIDATION_ERROR" "Too many Asset tags"))
  (let loop ((rest values) (result '()))
    (if (null? rest)
        (reverse result)
        (let ((tag (car rest)))
          (unless (string? tag)
            (api-fail 400 "VALIDATION_ERROR" "Every tag must be a string"))
          (let ((tag (string-trim-both tag)))
            (when (> (string-length tag) max-asset-tag-length)
              (api-fail 400 "VALIDATION_ERROR" "Asset tag is too large"))
            (if (or (string-null? tag) (member tag result string=?))
                (loop (cdr rest) result)
                (loop (cdr rest) (cons tag result))))))))

(define* (asset-tags-value body #:key (default '()))
  (if (object-has? body "tags")
      (normalize-tags (json-array-values (object-ref body "tags") "tags"))
      default))

(define (asset-tags-from-form body)
  (if (not (object-has? body "tags"))
      '()
      (let ((value (object-ref body "tags")))
        (cond
         ((string? value)
          (let ((trimmed (string-trim-both value)))
            (if (string-prefix? "[" trimmed)
                (catch #t
                  (lambda ()
                    (normalize-tags
                     (json-array-values (json-string->scm trimmed) "tags")))
                  (lambda _
                    (api-fail 400 "VALIDATION_ERROR" "tags must be valid JSON")))
                (normalize-tags
                 (filter (lambda (tag) (not (string-null? tag)))
                         (map string-trim-both (string-split value #\,)))))))
         (else (normalize-tags (json-array-values value "tags")))))))

(define (generation-metadata-from-body body)
  (if (not (object-has? body "generation_metadata"))
      "{}"
      (let* ((raw (object-ref body "generation_metadata"))
             (value (if (string? raw)
                        (catch #t
                          (lambda () (json-string->scm raw))
                          (lambda _
                            (api-fail 400 "VALIDATION_ERROR"
                                      "generation_metadata must be valid JSON")))
                        raw)))
        (unless (or (not value) (object? value))
          (api-fail 400 "VALIDATION_ERROR"
                    "generation_metadata must be an object"))
        (if (not value)
            "{}"
            (let ((encoded (json-encode (json-normalize value))))
              (when (> (string-length encoded) 20000)
                (api-fail 400 "VALIDATION_ERROR"
                          "generation_metadata is too large"))
              encoded)))))

(define (nullable-integer-field body key min max)
  (if (not (object-has? body key))
      #f
      (let ((value (object-ref body key)))
        (cond
         ((not value) #f)
         ((not (integer? value))
          (api-fail 400 "VALIDATION_ERROR"
                    (format #f "~a must be an integer or null" key)))
         ((or (< value min) (> value max))
          (api-fail 400 "VALIDATION_ERROR"
                    (format #f "~a is out of range" key)))
         (else value)))))

(define (form-integer-field body key min max)
  (if (not (object-has? body key))
      #f
      (let ((value (object-ref body key)))
        (cond
         ((not value) #f)
         ((integer? value)
          (if (and (>= value min) (<= value max))
              value
              (api-fail 400 "VALIDATION_ERROR"
                        (format #f "~a is out of range" key))))
         ((string? value)
          (let ((number (string->number (string-trim-both value))))
            (if (and number (integer? number) (>= number min) (<= number max))
                number
                (api-fail 400 "VALIDATION_ERROR"
                          (format #f "~a must be an integer" key)))))
         (else (api-fail 400 "VALIDATION_ERROR"
                         (format #f "~a must be an integer" key)))))))

(define (asset-safe-mime? value)
  (and (string? value)
       (not (string-null? value))
       (<= (string-length value) 255)
       (every (lambda (char)
                (or (char-alphabetic? char)
                    (char-numeric? char)
                    (member char '(#\/ #\+ #\- #\. #\; #\space))))
              (string->list value))))

(define (require-asset config workplace-id asset-id)
  (let* ((id (require-uuid-in-path asset-id "Asset"))
         (asset (db:studio-get-asset config workplace-id id)))
    (or asset
        (api-fail 404 "NOT_FOUND" "Asset not found"))))

(define (public-asset-link config workplace-id link)
  (let* ((type (assoc-ref link 'resource_type))
         (id (assoc-ref link 'resource_id))
         (target (case (string->symbol type)
                   ((character) (db:studio-get-character config workplace-id id))
                   ((scene) (db:studio-get-scene config workplace-id id))
                   ((document) (db:studio-get-document config workplace-id id))
                   (else #f)))
         (name (and target
                    (or (assoc-ref target 'name)
                        (assoc-ref target 'title)
                        ""))))
    `(("resource_type" . ,type)
      ("resource_id" . ,id)
      ("name" . ,(or name ""))
      ("available" . ,(and target #t))
      ("created_at" . ,(assoc-ref link 'created_at)))))

(define (asset-links-for config workplace-id asset-id)
  (map (lambda (link) (public-asset-link config workplace-id link))
       (db:studio-list-asset-links config workplace-id asset-id)))

(define (asset-generation-metadata value)
  (if (or (not (string? value)) (string-null? value))
      (make-json-object '())
      (catch #t
        (lambda ()
          (let ((parsed (json-string->scm value)))
            (cond
             ((null? parsed) (make-json-object '()))
             ((object? parsed) parsed)
             (else (make-json-object '())))))
        (lambda _ (make-json-object '())))))

(define* (public-asset asset #:key (include-links #f) config)
  (let* ((storage-key (assoc-ref asset 'storage_key))
         (workplace-id (assoc-ref asset 'workplace_id))
         (asset-id (assoc-ref asset 'id))
         (has-file (and storage-key (not (string-null? storage-key)) #t)))
    `(("id" . ,asset-id)
      ("workplace_id" . ,workplace-id)
      ("name" . ,(assoc-ref asset 'name))
      ("description" . ,(assoc-ref asset 'description))
      ("asset_type" . ,(assoc-ref asset 'asset_type))
      ("storage_key" . ,storage-key)
      ("has_file" . ,(and has-file #t))
      ("file_url" . ,(mark (and has-file
                                (format #f "/studio/api/v1/workplaces/~a/assets/~a/file"
                                        workplace-id asset-id))))
      ("original_filename" . ,(assoc-ref asset 'original_filename))
      ("mime_type" . ,(assoc-ref asset 'mime_type))
      ("file_size" . ,(assoc-ref asset 'file_size))
      ("checksum" . ,(assoc-ref asset 'checksum))
      ("source" . ,(assoc-ref asset 'source))
      ("width" . ,(mark (assoc-ref asset 'width)))
      ("height" . ,(mark (assoc-ref asset 'height)))
      ("duration_ms" . ,(mark (assoc-ref asset 'duration_ms)))
      ("author" . ,(assoc-ref asset 'author))
      ("notes" . ,(assoc-ref asset 'notes))
      ("tags" . ,(assoc-ref asset 'tags))
      ("generation_metadata"
       . ,(asset-generation-metadata (assoc-ref asset 'generation_metadata)))
      ("created_at" . ,(assoc-ref asset 'created_at))
      ("updated_at" . ,(assoc-ref asset 'updated_at))
      ("archived_at" . ,(mark (assoc-ref asset 'archived_at)))
      ("links" . ,(if include-links
                       (asset-links-for config workplace-id asset-id)
                       '())))))

(define (asset-common-values body source default-name)
  (let ((name (string-field body "name" #:required (not default-name)
                            #:max max-asset-name-length
                            #:default (or default-name "")))
        (original (string-field body "original_filename" #:allow-empty #t
                                #:default "" #:max 512))
        (mime (string-field body "mime_type" #:allow-empty #t
                            #:default "application/octet-stream" #:max 255)))
    (unless (asset-safe-mime? mime)
      (api-fail 400 "VALIDATION_ERROR" "mime_type is invalid"))
    (when (and (not (string-null? original))
               (or (string-contains original "/")
                   (string-contains original "\\")
                   (string-contains original "..")))
      (api-fail 400 "VALIDATION_ERROR" "original_filename is invalid"))
    `((name . ,name)
      (description . ,(string-field body "description" #:allow-empty #t
                                    #:default ""
                                    #:max max-asset-description-length))
      (asset_type . ,(asset-type-field body "other"))
      (original_filename . ,original)
      (mime_type . ,mime)
      (source . ,source)
      (width . ,(nullable-integer-field body "width" 1 100000))
      (height . ,(nullable-integer-field body "height" 1 100000))
      (duration_ms . ,(nullable-integer-field body "duration_ms" 0 1000000000))
      (author . ,(string-field body "author" #:allow-empty #t
                               #:default "" #:max max-asset-author-length))
      (notes . ,(string-field body "notes" #:allow-empty #t
                              #:default "" #:max max-asset-notes-length))
      (generation_metadata . ,(generation-metadata-from-body body))
      (tags . ,(asset-tags-from-form body)))))

(define (studio-list-assets config workplace-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (map (lambda (asset) (public-asset asset #:config config))
         (db:studio-list-assets config wid))))

(define (studio-create-asset! config workplace-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (when (or (object-has? body "storage_key")
              (object-has? body "checksum")
              (object-has? body "file_size"))
      (api-fail 400 "VALIDATION_ERROR"
                "File fields are managed by the server"))
    (let* ((values (asset-common-values body (asset-source-field body "imported")
                                        #f))
           (values (append `((storage_key . "")
                             (file_size . 0)
                             (checksum . ""))
                           values)))
      (public-asset
       (db:studio-create-asset! config (db:studio-new-id) wid values)
       #:config config))))

(define (studio-get-asset config workplace-id asset-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id)))
    (public-asset asset #:include-links #t #:config config)))

(define (studio-update-asset! config workplace-id asset-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id))
         (id (assoc-ref asset 'id))
         (updates '()))
    (when (object-has? body "name")
      (set! updates
            (acons 'name (string-field body "name" #:required #t
                                       #:max max-asset-name-length)
                   updates)))
    (when (object-has? body "description")
      (set! updates
            (acons 'description
                   (string-field body "description" #:allow-empty #t
                                 #:default ""
                                 #:max max-asset-description-length)
                   updates)))
    (when (object-has? body "author")
      (set! updates
            (acons 'author (string-field body "author" #:allow-empty #t
                                         #:default ""
                                         #:max max-asset-author-length)
                   updates)))
    (when (object-has? body "notes")
      (set! updates
            (acons 'notes (string-field body "notes" #:allow-empty #t
                                        #:default ""
                                        #:max max-asset-notes-length)
                   updates)))
    (for-each
     (lambda (entry)
       (when (object-has? body (car entry))
         (set! updates
               (acons (string->symbol (car entry))
                      (nullable-integer-field body (car entry)
                                              (cadr entry) (caddr entry))
                      updates))))
     '(("width" 1 100000) ("height" 1 100000)
       ("duration_ms" 0 1000000000)))
    (when (object-has? body "generation_metadata")
      (set! updates
            (acons 'generation_metadata
                   (generation-metadata-from-body body)
                   updates)))
    (let ((tags (if (object-has? body "tags")
                    (asset-tags-value body)
                    #f)))
      (public-asset
       (db:studio-update-asset! config wid id updates #:tags tags)
       #:include-links #t #:config config))))

(define (studio-delete-asset! config workplace-id asset-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id))
         (archived (db:studio-archive-asset! config wid
                                              (assoc-ref asset 'id))))
    (unless archived
      (api-fail 404 "NOT_FOUND" "Asset not found"))
    (fs:studio-asset-delete-file! config (or (assoc-ref archived 'storage_key) ""))
    `(("id" . ,(assoc-ref archived 'id))
      ("workplace_id" . ,(assoc-ref archived 'workplace_id))
      ("archived_at" . ,(assoc-ref archived 'archived_at)))))

(define (studio-create-uploaded-asset! config workplace-id id filename mime bytes fields)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (type (string-field fields "asset_type" #:allow-empty #t
                             #:default "" #:max 32))
         (fields (fold
                  (lambda (key result)
                    (let ((value (object-ref result key)))
                      (if (string? value)
                          (let ((number (string->number (string-trim-both value))))
                            (if (integer? number)
                                (acons key number
                                       (alist-delete key result equal?))
                                result))
                          result)))
                  fields
                  '("width" "height" "duration_ms")))
         (validated
          (catch 'studio-asset-error
            (lambda ()
              (fs:studio-asset-validate-upload config filename mime bytes type))
            (lambda (key code message)
              (api-fail (if (eq? code 'file-too-large) 413 400)
                        (string-upcase
                         (string-map (lambda (char)
                                       (if (char=? char #\-) #\_ char))
                                     (symbol->string code)))
                        message))))
         (extension (assoc-ref validated 'extension))
         (storage-key (fs:studio-asset-storage-key id extension))
         (basename (basename filename))
         (dot (string-rindex basename #\.))
         (default-name (if (and dot (> dot 0)) (substring basename 0 dot) basename))
         (values (asset-common-values
                  (acons "name" (or (object-ref fields "name") default-name)
                         (alist-delete "name" fields equal?))
                  "upload" default-name))
         (values (append validated
                         `((storage_key . ,storage-key)
                           (source . "upload"))
                         (filter (lambda (entry) (not (assoc (car entry) validated)))
                                 values)))
         (checksum (fs:studio-asset-store-file! config storage-key bytes)))
    (catch #t
      (lambda ()
        (public-asset
         (db:studio-create-asset! config id wid
                                  (acons 'checksum checksum values))
         #:config config))
      (lambda (key . args)
        (fs:studio-asset-delete-file! config storage-key)
        (apply throw key args)))))

(define (resource-type-field body)
  (let ((value (string-field body "resource_type" #:required #t #:max 32)))
    (unless (member value asset-resource-types)
      (api-fail 400 "VALIDATION_ERROR" "resource_type is not supported"))
    value))

(define (require-link-target config workplace-id resource-type resource-id)
  (let ((id (require-uuid-in-path resource-id "Resource")))
    (unless (member resource-type asset-resource-types)
      (api-fail 400 "VALIDATION_ERROR" "resource_type is not supported"))
    (let ((target (case (string->symbol resource-type)
                    ((character) (db:studio-get-character config workplace-id id))
                    ((scene) (db:studio-get-scene config workplace-id id))
                    ((document) (db:studio-get-document config workplace-id id))
                    (else #f))))
      (unless target
        (api-fail 422 "INVALID_RESOURCE"
                  "The target resource does not belong to this Workplace"))
      id)))

(define (studio-list-asset-links config workplace-id asset-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id)))
    (asset-links-for config wid (assoc-ref asset 'id))))

(define (studio-add-asset-link! config workplace-id asset-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id))
         (resource-type (resource-type-field body))
         (resource-id (require-link-target
                       config wid resource-type
                       (string-field body "resource_id" #:required #t #:max 36))))
    (public-asset-link
     config wid
     (catch 'studio-asset-link-error
       (lambda ()
         (db:studio-add-asset-link! config wid (assoc-ref asset 'id)
                                    resource-type resource-id))
       (lambda (key reason)
         (if (eq? reason 'asset-not-found)
             (api-fail 404 "NOT_FOUND" "Asset not found")
             (api-fail 422 "INVALID_RESOURCE" "Asset link could not be created")))))))

(define (studio-remove-asset-link! config workplace-id asset-id resource-type resource-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id))
         (resource-id (require-link-target config wid resource-type resource-id))
         (removed (db:studio-remove-asset-link! config wid (assoc-ref asset 'id)
                                                resource-type resource-id)))
    `(("asset_id" . ,(assoc-ref asset 'id))
      ("resource_type" . ,resource-type)
      ("resource_id" . ,resource-id)
      ("removed" . ,(and removed #t)))))

(define (studio-list-resource-assets config workplace-id resource-type resource-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (id (require-link-target config wid resource-type resource-id)))
    (map (lambda (asset) (public-asset asset #:config config))
         (db:studio-list-linked-assets config wid resource-type id))))

(define (studio-asset-file-info config workplace-id asset-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (asset (require-asset config wid asset-id))
         (path (fs:studio-asset-resolve-path config
                                             (assoc-ref asset 'storage_key))))
    (unless path
      (api-fail 404 "ASSET_FILE_MISSING" "Asset file is unavailable"))
    `((asset . ,asset) (path . ,path))))

(define (studio-list-documents config workplace-id)
  (let ((workplace (require-workplace config workplace-id)))
    (map public-document
         (db:studio-list-documents config (assoc-ref workplace 'id)))))

(define (studio-create-document! config workplace-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (kind (string-field body "kind" #:required #t #:max 32
                             #:default "chapter"))
         (title (string-field body "title" #:required #t
                              #:max max-title-length))
         (format-name (string-field body "content_format" #:allow-empty #t
                                    #:default "markdown"))
         (content (string-field body "content" #:allow-empty #t
                                #:default ""
                                #:max max-content-length))
         (sort-order (optional-integer-field body "sort_order" -1000000000
                                             1000000000 0))
         (parent (object-ref body "parent_id")))
    (unless (member kind '("manuscript" "chapter" "outline" "note"))
      (api-fail 400 "VALIDATION_ERROR" "kind is not supported"))
    (unless (equal? format-name "markdown")
      (api-fail 400 "VALIDATION_ERROR" "content_format must be markdown"))
    (when (object-has? body "parent_id")
      (unless (or (not parent) (valid-uuid? parent))
        (api-fail 400 "VALIDATION_ERROR" "parent_id must be a UUID or null"))
      (when parent
        (let ((parent-document
               (db:studio-get-document config wid (string-downcase parent))))
          (unless parent-document
            (api-fail 422 "INVALID_PARENT"
                      "parent_id does not belong to this Workplace")))))
    (public-document
     (db:studio-create-document! config (db:studio-new-id) wid
                                 (and parent (string-downcase parent))
                                 kind title content format-name sort-order)
     #:include-content #t)))

(define (studio-get-document config workplace-id document-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (public-document (require-document config wid document-id)
                     #:include-content #t)))

(define (studio-update-document! config workplace-id document-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (did (assoc-ref document 'id))
         (expected (required-integer-field body "expected_revision" 1 2147483647))
         (title (if (object-has? body "title")
                    (string-field body "title" #:required #t
                                  #:max max-title-length)
                    (assoc-ref document 'title)))
         (content (if (object-has? body "content")
                      (string-field body "content" #:allow-empty #t
                                    #:max max-content-length)
                      (assoc-ref document 'content)))
         (format-name (if (object-has? body "content_format")
                          (string-field body "content_format" #:allow-empty #t)
                          (assoc-ref document 'content_format))))
    (unless (equal? format-name "markdown")
      (api-fail 400 "VALIDATION_ERROR" "content_format must be markdown"))
    (let ((result (db:studio-update-document! config wid did title content
                                              format-name expected)))
      (cond
       ((not result)
        (api-fail 404 "NOT_FOUND" "Document not found"))
       ((eq? (car result) 'conflict)
        (api-fail 409 "REVISION_CONFLICT" "Document revision changed"
                  (cons "current_revision"
                        (assoc-ref (cdr result) 'revision))))
       (else
        (public-document (cdr result) #:include-content #t))))))

(define (studio-list-versions config workplace-id document-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id)))
    (map public-version
         (db:studio-list-versions config wid (assoc-ref document 'id)))))

(define (studio-create-version! config workplace-id document-id body)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (label (and (object-has? body "label")
                     (object-ref body "label")
                     (string-field body "label" #:allow-empty #t
                                   #:max max-label-length)))
         (source (if (object-has? body "source")
                     (string-field body "source" #:allow-empty #t)
                     "checkpoint")))
    (unless (member source '("manual" "ai" "restore" "checkpoint"))
      (api-fail 400 "VALIDATION_ERROR" "source is not supported"))
    (public-version
     (db:studio-create-version! config wid (assoc-ref document 'id)
                                (db:studio-new-id) label source)
     #:include-content #t)))

(define (studio-get-version config workplace-id document-id version-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (version (require-uuid-in-path version-id "Version"))
         (found (db:studio-get-version config wid (assoc-ref document 'id) version)))
    (if found
        (public-version found #:include-content #t)
        (api-fail 404 "NOT_FOUND" "Version not found"))))

(define (studio-restore-version! config workplace-id document-id version-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (version (require-uuid-in-path version-id "Version"))
         (restored (db:studio-restore-version! config wid
                                               (assoc-ref document 'id) version)))
    (if restored
        (public-document restored #:include-content #t)
        (api-fail 404 "NOT_FOUND" "Version not found"))))

(define (read-prompt name)
  (let ((path (string-append "conf/studio-prompts/" name)))
    (if (file-exists? path)
        (call-with-input-file path get-string-all)
        (api-fail 503 "INFERENCE_UNAVAILABLE"
                  "Writing prompt configuration is unavailable"))))

(define (safe-model-id value)
  (and (string? value)
       (valid-safe-id? value)
       (string-downcase value)))

(define (resolve-model config body)
  (let* ((requested (object-ref body "model"))
         (default (default-model config))
         (model (cond
                 ((and (object-has? body "model") requested)
                  (unless (string? requested)
                    (api-fail 400 "VALIDATION_ERROR" "model must be a string"))
                  (or (safe-model-id requested)
                      (api-fail 400 "VALIDATION_ERROR" "model is invalid")))
                 ((and (object-has? body "model") (not requested)) default)
                 (else default))))
    (unless model
      (api-fail 503 "MODEL_UNAVAILABLE"
                "No studio writing model is configured or available"))
    (when (and (equal? (configured-engine config) "sonicboom")
               (not (find (lambda (entry)
                            (equal? (assoc-ref entry "id") model))
                          (available-models config))))
      (api-fail 503 "MODEL_UNAVAILABLE"
                "The requested studio writing model is not available"))
    model))

(define (enabled-model-profile config id)
  (and id
       (not (string-null? id))
       (let ((profile (db:studio-get-model-profile config id)))
         (and profile (assoc-ref profile 'enabled) profile))))

(define (profile-for-task config task)
  (let* ((assignments (db:studio-list-task-assignments config))
         (assignment (find (lambda (entry)
                             (equal? (assoc-ref entry 'task) task))
                           assignments))
         (assigned (and assignment (assoc-ref assignment 'profile_id)))
         (default-setting (db:studio-get-setting
                           config "default_model_profile_id"))
         (default-id (and default-setting
                          (not (string-null? default-setting))
                          default-setting))
         (profile (or (enabled-model-profile config assigned)
                      (enabled-model-profile config default-id))))
    (private-profile config "llm" profile)))

(define (resolve-task-model config task body)
  (let ((profile (profile-for-task config task)))
    (if profile
        (let ((model (assoc-ref profile 'model_id)))
          (unless (and model (not (string-null? model)))
            (api-fail 503 "MODEL_UNAVAILABLE"
                      "The assigned Model Profile has no model ID"))
          model)
        (resolve-model config body))))

(define* (prepare-task-chat config task messages options body)
  (let ((profile (profile-for-task config task)))
    (if profile
        `((profile . ,profile)
          (profile_id . ,(assoc-ref profile 'id))
          (profile_name . ,(assoc-ref profile 'name))
          (protocol . ,(assoc-ref profile 'protocol))
          (model . ,(assoc-ref profile 'model_id))
          (messages . ,messages)
          (options . ,options))
        `((engine . ,(resolve-engine config))
          (model . ,(resolve-model config (or body '())))
          (messages . ,messages)
          (options . ,options)))))

(define (clip-tail text limit)
  (if (<= (string-length text) limit)
      text
      (substring text (- (string-length text) limit))))

(define (clip-head text limit)
  (if (<= (string-length text) limit)
      text
      (substring text 0 limit)))

(define (context-field body key)
  (optional-string-field body key #:max max-context-length))

(define (build-ai-prompt mode document body)
  (let* ((selected (context-field body "selected_text"))
         (before (context-field body "context_before"))
         (after (context-field body "context_after"))
         (instruction (optional-string-field body "instruction"
                                             #:max max-instruction-length))
         (content (assoc-ref document 'content))
         (document-text (if (equal? mode "continue")
                            (clip-tail content 32000)
                            (clip-head content 32000)))
         (fallback-before (if (string-null? before)
                              (clip-tail document-text 16000)
                              before)))
    (format #f
            "WORKPLACE DOCUMENT\nTitle: ~a\nKind: ~a\nFormat: markdown\n\nCURRENT DOCUMENT\n~a\n\nSELECTED TEXT\n~a\n\nCONTEXT BEFORE THE CURSOR OR SELECTION\n~a\n\nCONTEXT AFTER THE CURSOR OR SELECTION\n~a\n\nAUTHOR INSTRUCTION\n~a\n"
            (assoc-ref document 'title)
            (assoc-ref document 'kind)
            document-text
            selected
            fallback-before
            after
            (if (string-null? instruction) "(none)" instruction))))

(define (resolve-engine config)
  (if (equal? (configured-engine config) "sonicboom")
      (if (sonicboom-available?)
          '(khala engine llm-sonicboom)
          (api-fail 503 "INFERENCE_UNAVAILABLE"
                    "SonicBoom inference is unavailable"))
      '(khala engine llm-fake)))

(define (studio-prepare-ai config workplace-id document-id body mode)
  (let* ((body (or body '()))
         (workplace (require-workplace config workplace-id))
         (_ (unless (equal? (assoc-ref workplace 'archived_at) #f)
              (api-fail 404 "NOT_FOUND" "Workplace not found")))
         (wid (assoc-ref workplace 'id))
         (document (require-document config wid document-id))
         (prompt-name (if (equal? mode "continue")
                          "continue.md"
                          "inspire.md"))
         (system (read-prompt prompt-name))
         (max-tokens (if (equal? mode "continue")
                         (optional-integer-field body "max_tokens" 1 4096 1024)
                         1024))
         (messages
          (list `(("role" . "system") ("content" . ,system))
                `(("role" . "user")
                  ("content" . ,(build-ai-prompt mode document body)))))
         (options `(("temperature" . 0.85)
                    ("num_predict" . ,max-tokens)
                    ("max_output_tokens" . ,max-tokens)
                    ("stream" . ,(equal? mode "continue")))))
    (prepare-task-chat config "writing" messages options body)))

(define* (studio-run-ai prepared #:key (on-token (lambda (token) #t))
                        (cancelled? (lambda () #f)))
  (if (assoc-ref prepared 'profile)
      (catch #t
        (lambda ()
          (provider:studio-chat-with-profile
           (assoc-ref prepared 'profile)
           (assoc-ref prepared 'messages)
           (assoc-ref prepared 'options)
           #:on-token on-token
           #:cancelled? cancelled?))
        (lambda (key . args)
          (if (eq? key 'studio-provider-error)
              (api-fail (if (equal? (car args) "NETWORK_ERROR") 503 502)
                        (car args) (cadr args))
              (apply throw key args))))
      (let* ((engine (assoc-ref prepared 'engine))
             (chat (module-ref (resolve-interface engine) 'engine-chat)))
        (chat (assoc-ref prepared 'model)
              (assoc-ref prepared 'messages)
              (assoc-ref prepared 'options)
              #:on-token on-token
              #:cancelled? cancelled?))))

(define* (studio-inspire config workplace-id document-id body
                         #:key (on-token (lambda (token) #t))
                         (cancelled? (lambda () #f)))
  (let* ((prepared (studio-prepare-ai config workplace-id document-id body
                                      "inspire"))
         (result (studio-run-ai prepared #:on-token on-token
                                #:cancelled? cancelled?))
         (text (or (assoc-ref result 'text)
                   (assoc-ref result "text")
                   "")))
    `(("content" . ,text)
      ("model" . ,(assoc-ref prepared 'model))
      ("profile_id" . ,(mark (assoc-ref prepared 'profile_id)))
      ("protocol" . ,(or (assoc-ref prepared 'protocol)
                          (configured-engine config))))))
