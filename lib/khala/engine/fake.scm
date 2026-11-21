(define-module (khala engine fake)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 format)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (engine-run-t2i engine-image-capabilities
            fake-last-image-references fake-reset-image-reference-trace!))

;; Test-only observability. The fake adapter accepts the same internal
;; reference descriptors as a future reference-conditioned backend and retains
;; the actual bytevectors it received so tests can prove the plumbing is not
;; filename-only. Production adapters do not expose this hook.
(define last-image-references #f)

(define (fake-last-image-references) last-image-references)
(define (fake-reset-image-reference-trace!) (set! last-image-references #f))

(define (engine-image-capabilities)
  '((reference_images . #t)
    (reference_mode . "fake-byte-buffer")
    (max_references . 32)))

(define (bytevector-digest bytes)
  (let loop ((index 0) (hash 2166136261))
    (if (= index (bytevector-length bytes))
        (logand hash #xffffffff)
        (loop (+ index 1)
              (logand #xffffffff
                      (* (logxor hash (bytevector-u8-ref bytes index)) 16777619))))))

(define (references-digest references)
  (fold (lambda (reference result)
          (let* ((data (assoc-ref reference 'data))
                 (length (if (bytevector? data) (bytevector-length data) 0))
                 (digest (if (bytevector? data) (bytevector-digest data) 0)))
            (logand #xffffffff
                    (+ (logxor result digest)
                       (logxor length (string-hash
                                       (format #f "~a:"
                                               (or (assoc-ref reference 'role)
                                                   ""))))))))
        2166136261
        references))

(define* (engine-run-t2i params #:key (on-progress (lambda args #t))
                         (cancelled? (lambda () #f)))
  (let* ((width (or (assq-ref params 'width) 512))
         (height (or (assq-ref params 'height) 512))
         (steps (or (assq-ref params 'steps) 20))
         (fail-at-step (assq-ref params 'fail_at_step))
         (seed (or (assq-ref params 'seed) 0))
         (prompt (or (assq-ref params 'positive) ""))
         (references (or (assq-ref params 'references) '()))
         (reference-hash (references-digest references))
         (hash (logand #xffffffff
                       (+ (string-hash (format #f "~a:~a" prompt seed))
                          reference-hash)))
         (rgb (make-bytevector (* width height 3))))
    (set! last-image-references references)
    (do ((i 0 (+ i 1))) ((= i (* width height)))
      (bytevector-u8-set! rgb (* i 3) (logand hash #xff))
      (bytevector-u8-set! rgb (+ (* i 3) 1) (logand (ash hash -8) #xff))
      (bytevector-u8-set! rgb (+ (* i 3) 2) (logand (ash hash -16) #xff)))
    (let loop ((step 1))
      (when (and (<= step steps) (not (cancelled?)))
        (usleep 20000)
        (when (and fail-at-step (= step fail-at-step))
          (error "fake engine failure at step" step))
        (on-progress step steps)
        (loop (+ step 1))))
    (if (cancelled?)
        '()
        (list ((module-ref (resolve-interface '(khala png)) 'rgb->png)
               width height rgb)))))
