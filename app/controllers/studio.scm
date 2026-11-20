;; Khala Studio writing API and prototype page.

(define-artanis-controller studio) ; DO NOT REMOVE THIS LINE!!!

(use-modules (artanis artanis)
             (artanis route)
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
