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
  #:use-module (app models comfy)
  #:use-module (app models ollama)
  #:use-module (khala config)
  #:use-module (khala engine)
  #:use-module (khala json)
  #:use-module ((khala studio assets) #:prefix fs:)
  #:use-module ((khala studio persistence) #:prefix db:)
  #:export (studio-capabilities
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
            studio-run-ai))

(define max-content-length 2000000)
(define max-title-length 512)
(define max-description-length 4000)
(define max-context-length 20000)
(define max-instruction-length 4000)
(define max-label-length 500)
(define max-character-role-length 256)
(define max-identity-field-length 20000)
(define max-scene-text-length 500000)

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
    ("archived_at" . ,(mark (assoc-ref workplace 'archived_at)))))

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

(define (public-scene scene)
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
    ("created_at" . ,(assoc-ref scene 'created_at))
    ("updated_at" . ,(assoc-ref scene 'updated_at))
    ("deleted_at" . ,(mark (assoc-ref scene 'deleted_at)))))

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
      ("image_generation" . ,(studio-image-generation-capabilities config)))))

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
  (let* ((model (resolve-model config body))
         (prepared
          `((model . ,model)
            (engine . ,(resolve-engine config))
            (messages
             . ,(list
                 `(("role" . "system")
                   ("content" . ,(read-prompt
                                  (if section
                                      "character-section.md"
                                      "character-develop.md"))))
                 `(("role" . "user")
                   ("content" . ,(character-development-prompt
                                  character body section)))))
            (options . (("temperature" . 0.7)
                        ("num_predict" . 4096))))))
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
   ((object? value)
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
        (public-scene scene)
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
  (let* ((model (resolve-model config (or body '())))
         (engine (resolve-engine config))
         (system (read-prompt "storyboard.md"))
         (max-tokens (optional-integer-field body "max_tokens" 256
                                             max-storyboard-ai-tokens 2048))
         (context (storyboard-clip
                   (storyboard-scene-context scene cast characters references)
                   max-storyboard-context-length)))
    `((model . ,model)
      (engine . ,engine)
      (messages
       . ,(list `(("role" . "system") ("content" . ,system))
                `(("role" . "user") ("content" . ,context))))
      (options . (("temperature" . 0.55)
                  ("num_predict" . ,max-tokens)
                  ("format" . "json"))))))

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
                 (if (equal? (configured-engine config) "fake")
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
         (model (resolve-model config body))
         (engine (resolve-engine config))
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
         (options `(("temperature" . 0.85) ("num_predict" . ,max-tokens))))
    `((model . ,model)
      (engine . ,engine)
      (messages . ,messages)
      (options . ,options))))

(define* (studio-run-ai prepared #:key (on-token (lambda (token) #t))
                        (cancelled? (lambda () #f)))
  (let* ((engine (assoc-ref prepared 'engine))
         (chat (module-ref (resolve-interface engine) 'engine-chat)))
    (chat (assoc-ref prepared 'model)
          (assoc-ref prepared 'messages)
          (assoc-ref prepared 'options)
          #:on-token on-token
          #:cancelled? cancelled?)))

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
      ("model" . ,(assoc-ref prepared 'model)))))
