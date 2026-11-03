(define-module (khala models)
  #:use-module (khala config)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (model-folders model-files model-path model-file-path contained-path))

(define model-folders (config-model-folders))

(define (model-path config folder)
  (string-append (config-ref config 'models_root) "/" folder))

(define (directory? path)
  (catch #t (lambda () (eq? 'directory (stat:type (stat path)))) (lambda _ #f)))

;; A directory model (MOSS-Image layout: transformer/ and vae/ next to each
;; other) is one entry, not the files inside it.
(define (directory-model? path)
  (and (directory? (string-append path "/transformer"))
       (directory? (string-append path "/vae"))))

;; PATH joined to NAME, canonicalized, and only if it stays inside BASE.
(define (contained-path base name)
  (and (string? name) (not (string-null? name))
       (not (string-prefix? "/" name))
       (let ((full (string-append base "/" name)))
         (and (file-exists? full) (file-exists? base)
              (let ((root (canonicalize-path base))
                    (target (canonicalize-path full)))
                (and (string-prefix? (string-append root "/") target)
                     target))))))

(define (model-file-path config folder name)
  (and (member folder model-folders)
       (contained-path (model-path config folder) name)))

(define (walk-files path root)
  (if (not (file-exists? path))
      '()
      (append-map
       (lambda (name)
         (if (member name '("." ".."))
             '()
             (let* ((full (string-append path "/" name))
                    (relative (substring full (+ (string-length root) 1)))
                    (kind (catch #t (lambda () (stat:type (stat full)))
                            (lambda _ #f))))
               (cond
                ((and (eq? kind 'directory) (directory-model? full))
                 (list relative))
                ((eq? kind 'directory) (walk-files full root))
                ((eq? kind 'regular) (list relative))
                (else '())))))
       (scandir path
                (lambda (name)
                  (not (member name '("." ".."))))))))

(define (model-files config folder)
  (if (not (member folder model-folders))
      #f
      (sort (walk-files (model-path config folder) (model-path config folder))
            string<?)))
