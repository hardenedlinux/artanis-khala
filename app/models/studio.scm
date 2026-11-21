;; Studio writing API model: validation, document transformation, and the
;; existing Khala LLM adapter dispatch.

(define-module (app models studio)
  #:use-module (ice-9 format)
  #:use-module (ice-9 optargs)
  #:use-module (ice-9 textual-ports)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (app models ollama)
  #:use-module (khala config)
  #:use-module (khala json)
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
            studio-list-scenes
            studio-create-scene!
            studio-get-scene
            studio-update-scene!
            studio-delete-scene!
            studio-list-scene-cast
            studio-update-scene-cast!
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
     "fears" "goals" "arc")
    ("visual_identity"
     "standard_appearance" "face" "body" "hair"
     "clothing" "palette" "expressions" "posture")
    ("vocal_identity"
     "timbre" "range" "pitch" "accent" "pronunciation" "pace")
    ("performance_identity"
     "habits" "movement" "gestures" "emotional_responses" "situations")))

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
    ("literary_identity"
     . ,(identity-from-json (assoc-ref character 'literary_identity)))
    ("visual_identity"
     . ,(identity-from-json (assoc-ref character 'visual_identity)))
    ("vocal_identity"
     . ,(identity-from-json (assoc-ref character 'vocal_identity)))
    ("performance_identity"
     . ,(identity-from-json (assoc-ref character 'performance_identity)))
    ("created_at" . ,(assoc-ref character 'created_at))
    ("updated_at" . ,(assoc-ref character 'updated_at))
    ("archived_at" . ,(mark (assoc-ref character 'archived_at)))))

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
      ("ai_available" . ,(and available? #t)))))

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
    (map public-character
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
         (literary (identity-from-body body "literary_identity"))
         (visual (identity-from-body body "visual_identity"))
         (vocal (identity-from-body body "vocal_identity"))
         (performance (identity-from-body body "performance_identity")))
    (public-character
     (db:studio-create-character! config (db:studio-new-id) wid name role
                                  summary literary visual vocal performance))))

(define (studio-get-character config workplace-id character-id)
  (let* ((workplace (require-workplace config workplace-id))
         (wid (assoc-ref workplace 'id)))
    (public-character (require-character config wid character-id))))

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
        (public-character character)
        (public-character
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
