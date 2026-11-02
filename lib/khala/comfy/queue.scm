(define-module (khala comfy queue)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 threads)
  #:export (queue-submit! queue-list queue-take! queue-current queue-finish!
            queue-remove! queue-clear!
            queue-interrupt! queue-interrupted? queue-reset-interrupt!))

(define queue-lock (make-mutex))
(define pending '())
(define running #f)
(define interrupted #f)

(define* (queue-submit! item #:optional (front? #f))
  (with-mutex queue-lock
    (set! pending (if front? (cons item pending) (append pending (list item))))
    (length pending)))

(define (queue-list)
  (with-mutex queue-lock (append '() pending)))

(define (queue-take!)
  (with-mutex queue-lock
    (and (pair? pending)
         (let ((item (car pending)))
           (set! pending (cdr pending))
           (set! running item)
           item))))

(define (queue-current) (with-mutex queue-lock running))
(define (queue-finish!) (with-mutex queue-lock (set! running #f)))

(define (queue-remove! id)
  (with-mutex queue-lock
    (let ((old (length pending)))
      (set! pending (filter (lambda (item) (not (equal? id (assq-ref item 'prompt_id)))) pending))
      (- old (length pending)))))

(define (queue-clear!)
  (with-mutex queue-lock (let ((n (length pending))) (set! pending '()) n)))
(define (queue-interrupt!) (with-mutex queue-lock (set! interrupted #t)))
(define (queue-interrupted?) (with-mutex queue-lock interrupted))
(define (queue-reset-interrupt!) (with-mutex queue-lock (set! interrupted #f)))
