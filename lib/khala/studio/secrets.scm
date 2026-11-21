;; Server-local API credential storage for Khala Studio model profiles.
;;
;; Credentials are deliberately kept out of SQLite and out of every public
;; model response. The file is written atomically with mode 0600. This is local
;; secret storage, not a substitute for an OS keyring or hardware-backed vault.
(define-module (khala studio secrets)
  #:use-module (ice-9 format)
  #:use-module (ice-9 textual-ports)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala config)
  #:use-module (khala json)
  #:export (studio-secret-get
            studio-secret-set!
            studio-secret-delete!
            studio-secret-mask))

(define (secret-file-path config)
  (let ((configured (config-ref config 'studio_secrets_file)))
    (if (and (string? configured) (not (string-null? configured)))
        configured
        "var/studio-secrets.json")))

(define (ensure-parent path)
  (let loop ((dir (dirname path)))
    (unless (or (string=? dir ".") (string=? dir "/") (file-exists? dir))
      (loop (dirname dir))
      (catch 'system-error
        (lambda () (mkdir dir #o700))
        (lambda (key . args)
          (unless (file-exists? dir) (apply throw key args)))))))

(define (restrict-permissions path)
  (catch #t
    (lambda () (chmod path #o600))
    (lambda _ #f)))

(define (read-secrets path)
  (if (not (file-exists? path))
      '()
      (begin
        (restrict-permissions path)
        (catch #t
          (lambda ()
            (let ((value (json-string->scm
                          (call-with-input-file path get-string-all))))
              (if (and (list? value) (every pair? value)) value '())))
          (lambda _ '())))))

(define (write-secrets! path secrets)
  (ensure-parent path)
  (let* ((temp (format #f "~a.tmp.~a" path (getpid)))
         (payload (json-encode
                   (json-normalize
                    (filter (lambda (entry)
                              (and (string? (cdr entry))
                                   (not (string-null? (cdr entry)))))
                            secrets)))))
    (dynamic-wind
      (lambda () #t)
      (lambda ()
        (call-with-output-file temp
          (lambda (port) (put-string port payload))
          #:encoding "UTF-8")
        (chmod temp #o600)
        (rename-file temp path)
        (restrict-permissions path))
      (lambda ()
        (when (file-exists? temp)
          (catch #t (lambda () (delete-file temp)) (lambda _ #f)))))))

(define (studio-secret-get config key)
  (let ((entry (assoc key (read-secrets (secret-file-path config)))))
    (and entry (cdr entry))))

(define (studio-secret-set! config key value)
  (let* ((path (secret-file-path config))
         (secrets (read-secrets path))
         (cleaned (filter (lambda (entry) (not (equal? (car entry) key)))
                          secrets)))
    (write-secrets!
     path
     (if (and (string? value) (not (string-null? (string-trim-both value))))
         (acons key (string-trim-both value) cleaned)
         cleaned))
    (and (string? value) (not (string-null? value)))))

(define (studio-secret-delete! config key)
  (let* ((path (secret-file-path config))
         (secrets (read-secrets path)))
    (write-secrets! path
                    (filter (lambda (entry) (not (equal? (car entry) key)))
                            secrets))
    #t))

(define (studio-secret-mask value)
  (if (and (string? value) (not (string-null? value)))
      (let ((length (string-length value)))
        (if (>= length 4)
            (string-append "••••" (substring value (- length 4)))
            "••••"))
      #f))
