;; ComfyUI compatibility model entry points.

(define-module (app models comfy)
  #:use-module (khala config)
  #:use-module (khala comfy object-info)
  #:use-module (khala comfy validate)
  #:use-module (khala comfy worker)
  #:use-module (khala comfy queue)
  #:use-module (khala comfy persistence-api)
  #:export (comfy-config
            comfy-object-info
            comfy-validate-prompt
            comfy-restore-queue!
            comfy-start-worker!
            comfy-next-prompt-number!))

(define prompt-counter 0)

(define (comfy-config)
  (load-config))

(define (comfy-object-info config . maybe-name)
  (apply object-info config maybe-name))

(define (comfy-validate-prompt config prompt)
  (validate-prompt config prompt))

(define (comfy-restore-queue! config)
  (for-each
   (lambda (item)
     (set! prompt-counter (max prompt-counter (assq-ref item 'number)))
     (queue-submit! item))
   (or (persistence-call config 'fetch-pending-queue) '())))

(define (comfy-start-worker! config)
  (start-worker! config))

(define (comfy-next-prompt-number!)
  (set! prompt-counter (+ prompt-counter 1))
  prompt-counter)
