(define-module (khala comfy persistence-api)
  #:use-module (khala config)
  #:export (persistence-call persistence-active?))

(define (persistence-active? config)
  (or (config-ref config 'persist_history)
      (config-ref config 'persist_queue)))

(define (persistence-call config procedure . args)
  (if (persistence-active? config)
      (let ((target (module-ref (resolve-interface '(khala comfy persistence)) procedure)))
        (apply target config args))
      #f))
