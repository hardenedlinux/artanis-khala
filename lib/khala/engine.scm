(define-module (khala engine)
  #:export (engine-run-t2i engine-sampler-options))

(define* (engine-run-t2i params #:key (engine 'fake)
                         (on-progress (lambda args #t))
                         (cancelled? (lambda () #f)))
  (let* ((module (case engine
                   ((fake) '(khala engine fake))
                   ((sonicboom) '(khala engine sonicboom))
                   (else (error "unknown Khala engine" engine))))
         (run (module-ref (resolve-interface module) 'engine-run-t2i)))
    (run params #:on-progress on-progress #:cancelled? cancelled?)))

;; KSampler COMBO choices per engine: (samplers . schedulers). An engine only
;; offers what it really uses, so a chosen value is never silently ignored.
;; SonicBoom's generate-images has a single fixed sampler (MOSS-Image
;; flow-matching Euler); confirm the names against the SonicBoom docs.
(define (engine-sampler-options engine)
  (case engine
    ((sonicboom) '(("euler") . ("simple")))
    (else '(("euler" "euler_ancestral" "dpmpp_2m") . ("normal" "karras" "simple")))))
