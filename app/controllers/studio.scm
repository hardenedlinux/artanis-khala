;; Khala Studio writing API and prototype page.

(define-artanis-controller studio) ; DO NOT REMOVE THIS LINE!!!

(use-modules (artanis artanis)
             (artanis route)
             (artanis upload)
             (ice-9 format)
             (ice-9 optargs)
             (rnrs bytevectors)
             (rnrs io ports)
             (json)
             (srfi srfi-1)
             (app models studio)
             (khala config)
             (khala json)
             ((khala studio persistence) #:select (studio-new-id)))

(define config (load-config))
(define max-request-size 4194304)

(define (obj . fields) (make-json-object fields))

(define (json-ready value)
  (cond
   ((json-object? value)
    (make-json-object
     (map (lambda (entry) (cons (car entry) (json-ready (cdr entry))))
          (json-object-fields value))))
   ((and (pair? value) (every pair? value) (every string? (map car value)))
    (make-json-object
     (map (lambda (entry) (cons (car entry) (json-ready (cdr entry)))) value)))
   ((list? value) (map json-ready value))
   ((vector? value) (list->vector (map json-ready (vector->list value))))
   (else value)))

(define* (reply-json value #:optional (status 200))
  (response-emit (json-encode (json-ready value)) #:status status
                 #:headers '((content-type . (application/json)))))

(define* (reply-success value #:optional (status 200))
  (reply-json (obj (cons "data" value)) status))

(define (reply-error status code message . details)
  (reply-json
   (obj (cons "error"
              (make-json-object
               (append (list (cons "code" code) (cons "message" message))
                       (filter pair? details)))))
   status))

(define (log-failure context key args)
  (format (current-error-port) "Studio API failure (~a): ~s ~s~%"
          context key args))

(define (api-handler thunk)
  (catch #t
    (lambda ()
      (catch 'studio-api-error
        thunk
        (lambda (key status code message details)
          (apply reply-error status code message details))))
    (lambda (key . args)
      (log-failure "unhandled" key args)
      (reply-error 500 "INTERNAL_ERROR" "Internal server error"))))

(define (body-size rc)
  (let ((header (get-header rc 'content-length)))
    (cond ((number? header) header)
          ((string? header) (or (string->number header) 0))
          (else 0))))

(define (json-input value)
  (cond
   ((eq? value 'null) #f)
   ((and (list? value) (every pair? value))
    (map (lambda (entry) (cons (car entry) (json-input (cdr entry)))) value))
   ((list? value) (map json-input value))
   ((vector? value) (list->vector (map json-input (vector->list value))))
   (else value)))

(define (body-json rc)
  (when (> (body-size rc) max-request-size)
    (throw 'studio-api-error 413 "PAYLOAD_TOO_LARGE"
           "Request body is too large" '()))
  (let ((body (rc-body rc)))
    (when (and body (> (bytevector-length body) max-request-size))
      (throw 'studio-api-error 413 "PAYLOAD_TOO_LARGE"
             "Request body is too large" '()))
    (if (or (not body) (= (bytevector-length body) 0))
        '()
        (catch #t
          (lambda ()
            (let ((value (json-input (json-string->scm (utf8->string body)))))
              (if (or (null? value)
                      (and (list? value) (every pair? value)))
                  value
                  (throw 'studio-api-error 400 "INVALID_JSON"
                         "Request body must be a JSON object" '()))))
          (lambda (key . args)
            (if (eq? key 'studio-api-error)
                (apply throw key args)
                (throw 'studio-api-error 400 "INVALID_JSON"
                       "Request body is not valid JSON" '())))))))

(define (sse-event event data)
  (string-append "event: " event "\n"
                 "data: " (json-encode (json-ready data)) "\n\n"))

(define (studio-page)
  (response-emit
   (call-with-input-file "app/views/studio/studio.html.tpl" get-bytevector-all)
   #:headers '((content-type . (text/html (charset . "utf-8")))
               (cache-control . (no-cache)))))

(define (studio-static-file path content-type)
  (if (file-exists? path)
      (response-emit
       (call-with-input-file path get-bytevector-all)
       #:headers `((content-type . ,content-type)
                   (cache-control . (no-cache))))
      (response-emit "Not found" #:status 404)))

(define (multipart-part operator name)
  (find (lambda (part) (equal? (mfd-name part) name))
        (mfds-operator-mfds operator)))

(define (multipart-field rc operator name)
  (let ((part (multipart-part operator name)))
    (and part (mfds-op-ref rc operator name))))

(define (upload-handler rc)
  (let* ((workplace-id (params rc "workplace_id"))
         (operator (get-mfds-op-from-post rc))
         (file-part (find (lambda (part)
                            (and (equal? (mfd-name part) "file")
                                 (mfd-filename part)))
                          (mfds-operator-mfds operator)))
         (raw-filename (and file-part (mfd-filename file-part)))
         (filename (and raw-filename (basename raw-filename)))
         (bytes (and file-part
                     (mfds-op-ref rc operator "file" #:bv? #t)))
         (mime (and file-part (mfd-type file-part)))
         (field-names '("name" "description" "asset_type" "source" "width"
                        "height" "duration_ms" "author" "notes" "tags"
                        "generation_metadata"))
         (fields (filter-map
                  (lambda (name)
                    (let ((value (multipart-field rc operator name)))
                      (and value (cons name value))))
                  field-names)))
    (unless (and file-part filename bytes (> (bytevector-length bytes) 0))
      (throw 'studio-api-error 400 "INVALID_UPLOAD"
             "A non-empty multipart file field named 'file' is required" '()))
    (reply-success
     (studio-create-uploaded-asset! config workplace-id (studio-new-id)
                                    filename mime bytes fields)
     201)))

(define (header-safe-filename value)
  (let ((chars (string->list (or value ""))))
    (if (null? chars)
        "asset"
        (list->string
         (map (lambda (char)
                (if (or (char=? char #\") (char=? char #\\) (char<? char #\space))
                    #\_
                    char))
              chars)))))

(define (asset-file-handler rc)
  (let* ((info (studio-asset-file-info config (params rc "workplace_id")
                                       (params rc "asset_id")))
         (asset (assoc-ref info 'asset))
         (path (assoc-ref info 'path))
         (mime (assoc-ref asset 'mime_type))
         (filename (header-safe-filename
                    (or (assoc-ref asset 'original_filename)
                        (assoc-ref asset 'storage_key)
                        "asset"))))
    (response-emit
     (call-with-input-file path get-bytevector-all)
     #:headers
     `((content-type . ,(list (string->symbol mime)))
       (content-disposition . (inline (filename . ,filename)))
       (x-content-type-options . "nosniff")
       (cache-control . (private (max-age . 300)))))))

(define (inspire-handler rc)
  (let* ((workplace-id (params rc "workplace_id"))
         (document-id (params rc "document_id"))
         (body (body-json rc))
         (prepared (studio-prepare-ai config workplace-id document-id body
                                      "inspire")))
    (catch #t
      (lambda ()
        (let ((result (studio-run-ai prepared)))
          (reply-success
           `(("content" . ,(or (assoc-ref result 'text) ""))
             ("model" . ,(assoc-ref prepared 'model))))))
      (lambda (key . args)
        (log-failure "inspire" key args)
        (reply-error 502 "GENERATION_FAILED" "Generation failed")))))

(define (continue-handler rc)
  (let* ((workplace-id (params rc "workplace_id"))
         (document-id (params rc "document_id"))
         (body (body-json rc))
         (prepared (studio-prepare-ai config workplace-id document-id body
                                      "continue"))
         (run-id (studio-new-id))
         (cancelled? #f)
         (model (assoc-ref prepared 'model)))
    (response-emit-stream
     (lambda (send)
       (catch #t
         (lambda ()
           (send (sse-event "meta"
                            `(("run_id" . ,run-id) ("model" . ,model))))
           (studio-run-ai
            prepared
            #:on-token
            (lambda (token)
              (unless cancelled?
                (send (sse-event "token" `(("text" . ,token))))))
            #:cancelled? (lambda () cancelled?))
           (unless cancelled?
             (send (sse-event "done"
                              `(("run_id" . ,run-id)
                                ("finish_reason" . "stop"))))))
         (lambda (key . args)
           (log-failure "continue" key args)
           (unless cancelled?
             (catch #t
               (lambda ()
                 (send (sse-event
                        "error"
                        `(("code" . "GENERATION_FAILED")
                          ("message" . "Generation failed")))))
               (lambda _ #f))))))
     #:headers '((content-type . (text/event-stream))
                 (cache-control . (no-cache))
                 (connection . (keep-alive))
                 (x-accel-buffering . "no"))
     #:on-close (lambda () (set! cancelled? #t)))))

(get "/studio" (lambda _ (studio-page)))
(get "/studio/index.html" (lambda _ (studio-page)))

(get "/studio/assets/studio-ui"
     (lambda _
       (studio-static-file "studio-ui/dist/studio-ui.js" '(text/javascript))))

(get "/studio/assets/studio-ui-theme"
     (lambda _
       (studio-static-file "studio-ui/dist/studio-ui.css" '(text/css))))

(get "/studio/assets/react"
     (lambda _
       (studio-static-file
        "studio-ui/dist/vendor/react.production.min.js" '(text/javascript))))

(get "/studio/assets/react-dom"
     (lambda _
       (studio-static-file
        "studio-ui/dist/vendor/react-dom.production.min.js" '(text/javascript))))

(get "/studio/api/v1/capabilities"
     (lambda _ (api-handler (lambda () (reply-success (studio-capabilities config))))))

(get "/studio/api/v1/workplaces"
     (lambda _ (api-handler (lambda () (reply-success (studio-list-workplaces config))))))

(post "/studio/api/v1/workplaces"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success (studio-create-workplace! config (body-json rc)) 201)))))

(get "/studio/api/v1/workplaces/:workplace_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success (studio-get-workplace config (params rc "workplace_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-workplace! config (params rc "workplace_id")
                                     (body-json rc)))))))

(get "/studio/api/v1/workplaces/:workplace_id/characters"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-characters config (params rc "workplace_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-character! config (params rc "workplace_id")
                                      (body-json rc))
            201)))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-character config (params rc "workplace_id")
                                 (params rc "character_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/characters/:character_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-character! config (params rc "workplace_id")
                                     (params rc "character_id")
                                     (body-json rc)))))))

(page-delete "/studio/api/v1/workplaces/:workplace_id/characters/:character_id"
        (lambda (rc)
          (api-handler
           (lambda ()
             (reply-success
              (studio-archive-character! config (params rc "workplace_id")
                                         (params rc "character_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/ai/drafts"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-character-drafts config (params rc "workplace_id")
                                         (params rc "character_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/ai/develop"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-develop-character! config (params rc "workplace_id")
                                       (params rc "character_id")
                                       (body-json rc) #f))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/ai/develop/:section"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-develop-character! config (params rc "workplace_id")
                                       (params rc "character_id")
                                       (body-json rc)
                                       (params rc "section")))))))

(put "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/ai/drafts/:section"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-character-draft! config (params rc "workplace_id")
                                           (params rc "character_id")
                                           (params rc "section")
                                           (body-json rc)))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/ai/drafts/:section/apply"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-apply-character-draft! config (params rc "workplace_id")
                                           (params rc "character_id")
                                           (params rc "section")))))))

(page-delete "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/ai/drafts/:section"
             (lambda (rc)
               (api-handler
                (lambda ()
                  (reply-success
                   (studio-discard-character-draft!
                    config (params rc "workplace_id")
                    (params rc "character_id") (params rc "section")))))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-character-outfits config (params rc "workplace_id")
                                          (params rc "character_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-character-outfit! config (params rc "workplace_id")
                                             (params rc "character_id")
                                             (body-json rc))
            201)))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits/:outfit_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-character-outfit config (params rc "workplace_id")
                                        (params rc "character_id")
                                        (params rc "outfit_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits/:outfit_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-character-outfit! config (params rc "workplace_id")
                                            (params rc "character_id")
                                            (params rc "outfit_id")
                                            (body-json rc)))))))

(page-delete "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits/:outfit_id"
             (lambda (rc)
               (api-handler
                (lambda ()
                  (reply-success
                   (studio-archive-character-outfit!
                    config (params rc "workplace_id")
                    (params rc "character_id") (params rc "outfit_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits/:outfit_id/default"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-set-default-character-outfit!
             config (params rc "workplace_id") (params rc "character_id")
             (params rc "outfit_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/outfits/:outfit_id/reference"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-set-character-outfit-reference!
            config (params rc "workplace_id") (params rc "character_id")
            (params rc "outfit_id") (body-json rc)))))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/artworks"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-character-artworks config (params rc "workplace_id")
                                           (params rc "character_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/artworks/prompt"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-character-artwork-prompt
             config (params rc "workplace_id") (params rc "character_id")
             (body-json rc)))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/artworks/generate"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-generate-character-artwork!
             config (params rc "workplace_id") (params rc "character_id")
             (body-json rc)) 201)))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/avatar"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-set-character-avatar!
             config (params rc "workplace_id") (params rc "character_id")
             (body-json rc)))))))

(post "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/full-body"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-set-character-full-body!
             config (params rc "workplace_id") (params rc "character_id")
             (body-json rc)))))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/canon"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-character-canon config (params rc "workplace_id")
                                   (params rc "character_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/scenes"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-scenes config (params rc "workplace_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/scenes"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-scene! config (params rc "workplace_id")
                                  (body-json rc))
            201)))))

(get "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-scene config (params rc "workplace_id")
                             (params rc "scene_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-scene! config (params rc "workplace_id")
                                 (params rc "scene_id")
                                 (body-json rc)))))))

(page-delete "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id"
             (lambda (rc)
               (api-handler
                (lambda ()
                  (reply-success
                   (studio-delete-scene! config (params rc "workplace_id")
                                         (params rc "scene_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/references"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-set-scene-references!
            config (params rc "workplace_id") (params rc "scene_id")
            (body-json rc)))))))

(get "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/cast"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-scene-cast config (params rc "workplace_id")
                                   (params rc "scene_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/cast"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-scene-cast! config (params rc "workplace_id")
                                      (params rc "scene_id")
                                      (body-json rc)))))))

(get "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/storyboard"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-storyboard config (params rc "workplace_id")
                                  (params rc "scene_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/storyboard"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-storyboard! config (params rc "workplace_id")
                                       (params rc "scene_id")
                                       (body-json rc)))))))

(put "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/storyboard"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-storyboard! config (params rc "workplace_id")
                                      (params rc "scene_id")
                                      (body-json rc)))))))

(post "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/storyboard/shots/:shot_id/image"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-generate-storyboard-image! config (params rc "workplace_id")
                                               (params rc "scene_id")
                                               (params rc "shot_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/assets"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-assets config (params rc "workplace_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/assets"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-asset! config (params rc "workplace_id")
                                  (body-json rc))
            201)))))

(post "/studio/api/v1/workplaces/:workplace_id/assets/upload"
      (lambda (rc) (api-handler (lambda () (upload-handler rc)))))

(get "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-asset config (params rc "workplace_id")
                             (params rc "asset_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id/file"
     (lambda (rc) (api-handler (lambda () (asset-file-handler rc)))))

(put "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-asset! config (params rc "workplace_id")
                                 (params rc "asset_id")
                                 (body-json rc)))))))

(page-delete "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id"
             (lambda (rc)
               (api-handler
                (lambda ()
                  (reply-success
                   (studio-delete-asset! config (params rc "workplace_id")
                                         (params rc "asset_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id/links"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-asset-links config (params rc "workplace_id")
                                    (params rc "asset_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id/links"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-add-asset-link! config (params rc "workplace_id")
                                    (params rc "asset_id")
                                    (body-json rc))
            201)))))

(page-delete "/studio/api/v1/workplaces/:workplace_id/assets/:asset_id/links/:resource_type/:resource_id"
             (lambda (rc)
               (api-handler
                (lambda ()
                  (reply-success
                   (studio-remove-asset-link!
                    config (params rc "workplace_id") (params rc "asset_id")
                    (params rc "resource_type") (params rc "resource_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/characters/:character_id/assets"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-resource-assets config (params rc "workplace_id")
                                        "character"
                                        (params rc "character_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/scenes/:scene_id/assets"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-resource-assets config (params rc "workplace_id")
                                        "scene"
                                        (params rc "scene_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/assets"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-resource-assets config (params rc "workplace_id")
                                        "document"
                                        (params rc "document_id")))))))

(get "/studio/api/v1/workplaces/:workplace_id/documents"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-documents config (params rc "workplace_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/documents"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-document! config (params rc "workplace_id")
                                     (body-json rc))
            201)))))

(get "/studio/api/v1/workplaces/:workplace_id/documents/:document_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-document config (params rc "workplace_id")
                                (params rc "document_id")))))))

(put "/studio/api/v1/workplaces/:workplace_id/documents/:document_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-update-document! config (params rc "workplace_id")
                                    (params rc "document_id")
                                    (body-json rc)))))))

(get "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/versions"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-list-versions config (params rc "workplace_id")
                                 (params rc "document_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/versions"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-create-version! config (params rc "workplace_id")
                                    (params rc "document_id")
                                    (body-json rc))
            201)))))

(get "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/versions/:version_id"
     (lambda (rc)
       (api-handler
        (lambda ()
          (reply-success
           (studio-get-version config (params rc "workplace_id")
                               (params rc "document_id")
                               (params rc "version_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/versions/:version_id/restore"
      (lambda (rc)
        (api-handler
         (lambda ()
           (reply-success
            (studio-restore-version! config (params rc "workplace_id")
                                     (params rc "document_id")
                                     (params rc "version_id")))))))

(post "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/ai/inspire"
      (lambda (rc) (api-handler (lambda () (inspire-handler rc)))))

(post "/studio/api/v1/workplaces/:workplace_id/documents/:document_id/ai/continue"
      (lambda (rc) (api-handler (lambda () (continue-handler rc)))))
