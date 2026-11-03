;; UI-facing Khala controller.

(define-artanis-controller khala) ; DO NOT REMOVE THIS LINE!!!

(use-modules (artanis artanis)
             (artanis route)
             (ice-9 optargs)
             (json)
             (srfi srfi-1)
             (app models khala)
             (khala config)
             (khala json))

(define* (reply-json value #:optional (status 200))
  (response-emit (json-encode value) #:status status
                 #:headers '((content-type . (application/json)))))

(define (body-json rc)
  (let ((body (rc-body rc)))
    (if body (json-string->scm (utf8->string body))
        (make-json-object '()))))

(define (terminal? status)
  (member (assoc-ref (json-object-fields status) "state")
          '("done" "failed" "cancelled")))

(define config (load-config))

(get "/khala/api/downloads"
     (lambda _ (reply-json (khala-downloads))))
(post "/khala/api/downloads"
      (lambda (rc)
        (let ((catalog (assoc-ref (body-json rc) "catalog")))
          (if catalog
              (reply-json (khala-start-download! config catalog))
              (reply-json (make-json-object
                           (list (cons "error" "catalog is required"))) 400)))))
(post "/khala/api/downloads/:id/cancel"
      (lambda (rc)
        (reply-json (khala-cancel-download! (params rc "id")))))
(get "/khala/api/downloads/:id/events"
     (lambda (rc)
       (let ((id (params rc "id")))
         (response-emit-stream
          (lambda (send)
            (let loop ()
              (let ((status (khala-download-status id)))
                (when status
                  (send (string-append "data: " (json-encode status) "\n\n")))
                (unless (and status (terminal? status))
                  (usleep 500000)
                  (loop)))))
          #:headers '((content-type . (text/event-stream)))))))
(get "/khala/api/catalog"
     (lambda _ (reply-json (khala-catalog config))))
(get "/khala/api/system"
     (lambda _ (reply-json (khala-system config))))
(get "/khala/api/settings"
     (lambda _ (reply-json (khala-settings (load-config)))))
(put "/khala/api/settings"
     (lambda (rc)
       (reply-json (khala-save-settings! (load-config) (body-json rc)))))
