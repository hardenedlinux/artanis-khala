(define-module (khala comfy files)
  #:use-module (khala config)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-13)
  #:export (file-root view-path))

(define (file-root config type)
  (cond ((equal? type "input") (config-ref config 'input_dir))
        ((equal? type "temp") (config-ref config 'temp_dir))
        (else (config-ref config 'output_dir))))

(define (view-path config filename subfolder type)
  (let* ((root (catch #t (lambda () (canonicalize-path (file-root config type)))
                 (lambda _ #f)))
         (relative (and filename
                        (string-join (filter (lambda (part) (not (string-null? part)))
                                             (list (or subfolder "") filename)) "/")))
         (candidate (and root relative
                         (catch #t
                           (lambda () (canonicalize-path (string-append root "/" relative)))
                           (lambda _ #f))))
         (prefix (and root (string-append root "/"))))
    (and candidate (file-exists? candidate)
         (or (string=? candidate root)
             (string-prefix? prefix candidate))
         candidate)))
