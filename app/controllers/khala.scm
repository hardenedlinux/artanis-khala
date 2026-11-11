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
             (khala comfy files)
             (khala json)
             (khala png))

(define* (reply-json value #:optional (status 200))
  (response-emit (json-encode value) #:status status
                 #:headers '((content-type . (application/json)))))

(define (obj . fields) (make-json-object fields))

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
(get "/khala/api/provenance"
     (lambda (rc)
       (let ((path (view-path config (params rc "filename")
                              (or (params rc "subfolder") "")
                              (or (params rc "type") "output"))))
         (if path
             (let ((text (png-read-text
                          (call-with-input-file path get-bytevector-all) "khala")))
               (if text
                   ;; A decoded object is an alist, which json-encode
                   ;; would write as an array: normalize it first.
                   (reply-json (json-normalize (json-string->scm text)))
                   (reply-json (obj (cons "error" "provenance not found")) 404)))
             (reply-json (obj (cons "error" "image not found")) 404)))))
(get "/khala/api/settings"
     (lambda _ (reply-json (khala-settings (load-config)))))
(put "/khala/api/settings"
     (lambda (rc)
       (reply-json (khala-save-settings! (load-config) (body-json rc)))))
(post "/khala/api/enhance"
      (lambda (rc)
        (let* ((body (body-json rc))
               (text (assoc-ref body "text"))
               (model (or (assoc-ref body "model")
                          (config-ref config 'enhance_model)))
               (system (call-with-input-file "conf/prompt-enhance.txt"
                         get-string-all)))
          (catch #t
            (lambda ()
              (let* ((engine (if (equal? (config-ref config 'engine) "sonicboom")
                                 '(khala engine llm-sonicboom)
                                 '(khala engine llm-fake)))
                     (chat (module-ref (resolve-interface engine) 'engine-chat))
                     (result (chat model
                                   (list
                                    `(("role" . "system") ("content" . ,system))
                                    `(("role" . "user") ("content" . ,text)))
                                   (list (cons "format" "json"))))
                     (payload (json-string->scm (assoc-ref result 'text)))
                     (prompt (assoc-ref payload "prompt"))
                     (negative (assoc-ref payload "negative")))
                (if (and (string? prompt) (string? negative))
                    (reply-json (obj (cons "prompt" prompt)
                                     (cons "negative" negative)
                                     (cons "model" model)))
                    (reply-json (obj (cons "error" "invalid enhancement JSON")) 502))))
            (lambda (key . args)
              (reply-json
               (obj (cons "error"
                          (format #f "prompt enhancement failed: ~a ~s" key args)))
               502))))))
(get "/khala" (lambda (rc) (serve-ui rc)))
(get "/khala/(models|history|chat|settings)"
     (lambda (rc) (serve-ui rc)))
(get "/khala/(assets/[^/]+|favicon.svg|icons.svg)"
     (lambda (rc)
       (let ((path (ui-static-path (rc-path rc))))
         (if path
             (serve-file path)
             (response-emit "Not found" #:status 404)))))
