;; UI-facing Khala controller.

(define-artanis-controller khala) ; DO NOT REMOVE THIS LINE!!!

(use-modules (artanis artanis)
             (artanis route)
             (ice-9 optargs)
             (json)
             (rnrs io ports)
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

(define (asset-type path)
  (cond ((string-suffix? ".js" path) '(text/javascript))
        ((string-suffix? ".css" path) '(text/css))
        ((string-suffix? ".svg" path) '(image/svg+xml))
        ((string-suffix? ".png" path) '(image/png))
        ((string-suffix? ".woff2" path) '(font/woff2))
        ((string-suffix? ".json" path) '(application/json))
        ((string-suffix? ".html" path) '(text/html (charset . "utf-8")))
        (else '(application/octet-stream))))

(define (serve-file path)
  (response-emit (call-with-input-file path get-bytevector-all)
                 #:headers `((content-type . ,(asset-type path)))))

(define (ui-static-path request-path)
  (let* ((prefix "/khala/")
         (relative (and (string-prefix? prefix request-path)
                        (substring request-path (string-length prefix))))
         (root (canonicalize-path "ui/dist"))
         (candidate (and relative
                         (not (member ".." (string-split relative #\/)))
                         (string-append root "/" relative)))
         (resolved (and candidate
                        (file-exists? candidate)
                        (canonicalize-path candidate)))
         (root-prefix (string-append root "/")))
    (and resolved
         (string-prefix? root-prefix resolved)
         (not (file-is-directory? resolved))
         resolved)))

(define (missing-ui-page rc)
  (let ((accept (or (get-header rc 'accept-language) "en")))
    (cond
     ((string-prefix? "zh" accept)
      "<h1>Khala UI 尚未构建</h1><p>请在 ui/ 运行 <code>npm ci &amp;&amp; npm run build</code>，或执行 tools/build-ui.sh。</p>")
     ((string-prefix? "ja" accept)
      "<h1>Khala UI は未ビルドです</h1><p>ui/ で <code>npm ci &amp;&amp; npm run build</code> を実行するか、tools/build-ui.sh を使用してください。</p>")
     (else
      "<h1>Khala UI is not built</h1><p>Run <code>npm ci &amp;&amp; npm run build</code> in ui/, or run tools/build-ui.sh.</p>"))))

(define (serve-ui rc)
  (let ((index "ui/dist/index.html"))
    (if (file-exists? index)
        (response-emit (call-with-input-file index get-bytevector-all)
                       #:headers '((content-type . (text/html))))
        (response-emit (missing-ui-page rc)
                       #:headers '((content-type . (text/html)))))))

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
(get "/khala" (lambda (rc) (serve-ui rc)))
(get "/khala/(models|history|chat|settings)"
     (lambda (rc) (serve-ui rc)))
(get "/khala/(assets/[^/]+|favicon.svg|icons.svg)"
     (lambda (rc)
       (let ((path (ui-static-path (rc-path rc))))
         (if path
             (serve-file path)
             (response-emit "Not found" #:status 404)))))
