(define-module (khala engine)
  #:export (engine-run-t2i))

(define* (engine-run-t2i params #:key (engine 'fake)
                         (on-progress (lambda args #t))
                         (cancelled? (lambda () #f)))
  (let* ((module (case engine
                   ((fake) '(khala engine fake))
                   ((sonicboom) '(khala engine sonicboom))
                   (else (error "unknown Khala engine" engine))))
         (run (module-ref (resolve-interface module) 'engine-run-t2i)))
    (run params #:on-progress on-progress #:cancelled? cancelled?)))
