(define-module (khala models)
  #:use-module (khala config)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (model-folders model-files model-path))

(define model-folders (config-model-folders))

(define (model-path config folder)
  (string-append (config-ref config 'models_root) "/" folder))

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
