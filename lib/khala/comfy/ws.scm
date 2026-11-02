(define-module (khala comfy ws)
  #:use-module (artanis websocket)
  #:use-module (ice-9 threads)
  #:use-module (srfi srfi-1)
  #:use-module (khala json)
  #:export (ws-register! ws-unregister! ws-broadcast! ws-send-client!))

(define lock (make-mutex))
(define clients '())

(define (ws-register! client-id connection)
  (with-mutex lock (set! clients (acons client-id connection clients)))
  client-id)
(define (ws-unregister! client-id)
  (with-mutex lock (set! clients (assoc-delete-all client-id clients))))
(define (ws-send-client! client-id message)
  (let ((connection (with-mutex lock (assoc-ref clients client-id))))
    (and connection
         (ws-send connection
                  (if (ws-buffer? message) message (json-encode message))))))
(define (ws-broadcast! message)
  (let ((connections (with-mutex lock (map cdr clients))))
    (for-each (lambda (connection) (ws-send connection (json-encode message)))
              connections)))
