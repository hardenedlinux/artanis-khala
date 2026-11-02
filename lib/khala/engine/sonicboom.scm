(define-module (khala engine sonicboom)
  #:use-module (rnrs bytevectors)
  #:use-module (khala png)
  #:use-module (ice-9 format)
  #:export (engine-run-t2i))

(define (sb name)
  (module-ref (resolve-interface '(sonicboom image)) name))

(define* (engine-run-t2i params #:key (on-progress (lambda args #t))
                         (cancelled? (lambda () #f)))
  ;; Resolve the optional binding only when SonicBoom is selected for a job.
  (let* ((model ((sb 'load-image-model) (assq-ref params 'model_path)))
         (images
          (dynamic-wind
            (lambda () #t)
            (lambda ()
              ((sb 'generate-images) model
               #:prompt (or (assq-ref params 'positive) "")
               #:negative (or (assq-ref params 'negative) "")
               #:width (or (assq-ref params 'width) 512)
               #:height (or (assq-ref params 'height) 512)
               #:steps (or (assq-ref params 'steps) 20)
               #:guidance (or (assq-ref params 'cfg) 3.0)
               #:seed (or (assq-ref params 'seed) 0)
               #:batch (or (assq-ref params 'batch_size) 1)
               #:progress (lambda (image step total)
                            (if (cancelled?) #f (begin (on-progress step total) #t)))))
            (lambda () ((sb 'free-image-model!) model)))))
    (map (lambda (image)
           (let ((width (list-ref image 0)) (height (list-ref image 1))
                 (rgb (list-ref image 2)))
             (rgb->png width height rgb)))
         images)))
