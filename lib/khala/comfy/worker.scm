(define-module (khala comfy worker)
  #:use-module (artanis websocket)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 format)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (srfi srfi-1)
  #:use-module (khala config)
  #:use-module (khala json)
  #:use-module (khala engine)
  #:use-module (khala png)
  #:use-module (khala comfy queue)
  #:use-module (khala comfy history)
  #:use-module (khala comfy lower)
  #:use-module (khala comfy ws)
  #:use-module (khala comfy persistence-api)
  #:export (start-worker! image-frame image-frame-bytes preview-step?))

(define running? #f)
(define (obj . fields) (make-json-object fields))
(define (send client type data)
  (when client (ws-send-client! client (obj (cons "type" type) (cons "data" data)))))
(define (node-class node) (assoc-ref (cdr node) "class_type"))
(define (output-nodes prompt)
  (filter (lambda (node) (member (node-class node) '("SaveImage" "PreviewImage"))) prompt))

(define (write-png path bytes)
  (let ((port (open-file path "wb")))
    (put-bytevector port bytes)
    (close-port port)))

(define (image-frame-bytes png)
  (let ((frame (make-bytevector (+ 8 (bytevector-length png)) 0)))
    (bytevector-u32-set! frame 0 1 (endianness big))
    (bytevector-u32-set! frame 4 2 (endianness big))
    (bytevector-copy! png 0 frame 8 (bytevector-length png))
    frame))
(define (image-frame png) (bytevector->ws-buffer (image-frame-bytes png)))
(define (preview-step? step) (zero? (modulo step 5)))

(define (execute-prompt! config item)
  (let* ((id (assq-ref item 'prompt_id))
         (client (assq-ref item 'client_id))
         (prompt (assq-ref item 'prompt))
         (extra (or (assq-ref item 'extra_data) '()))
         (json-prompt (json-normalize prompt))
         (json-workflow (json-normalize (or (assoc-ref extra "extra_pnginfo") '()))))
    (let ((preview-png (rgb->png 1 1 #vu8(80 110 150))))
    (call-with-values
        (lambda () (lower-workflow prompt))
      (lambda (params order)
        (send client "execution_start" (obj (cons "prompt_id" id) (cons "timestamp" 0)))
        (when (and params order)
          (for-each
           (lambda (node-id)
             (send client "executing"
                   (obj (cons "node" node-id) (cons "display_node" node-id)
                        (cons "prompt_id" id))))
           order)
          (let* ((engine-name (string->symbol (config-ref config 'engine)))
                 (pngs (engine-run-t2i params #:engine engine-name
                       #:cancelled? queue-interrupted?
                       #:on-progress
                       (lambda (step total)
                         (send client "progress"
                               (obj (cons "value" step) (cons "max" total)
                                    (cons "prompt_id" id)))
                         (when (and client (preview-step? step))
                           (ws-send-client! client (image-frame preview-png))))))
                 (directory (config-ref config 'output_dir)))
            (unless (file-exists? directory) (mkdir directory #o755))
            (let ((images
                   (map (lambda (png index)
                          (let* ((filename (format #f "khala_~a_~a.png" id index))
                                 (path (string-append directory "/" filename))
                                 (complete (png-with-metadata png
                                              (json-encode json-prompt)
                                              (json-encode json-workflow))))
                            (write-png path complete)
                            (obj (cons "filename" filename)
                                 (cons "subfolder" "") (cons "type" "output"))))
                        pngs (iota (length pngs)))))
              (for-each
               (lambda (output)
                 (let ((node-id (car output)))
                   (send client "executed"
                         (obj (cons "node" node-id) (cons "display_node" node-id)
                              (cons "output" (obj (cons "images" images)))
                              (cons "prompt_id" id)))))
               (output-nodes prompt))
              (let ((record
                     (obj (cons "prompt" (list (assq-ref item 'number) id
                                                json-prompt (json-normalize extra)))
                          (cons "outputs"
                                (make-json-object
                                 (map (lambda (output)
                                        (cons (car output) (obj (cons "images" images))))
                                      (filter (lambda (node)
                                                (equal? "SaveImage" (node-class node)))
                                              (output-nodes prompt))))
                          (cons "status" (obj (cons "completed" #t)))))))
                (history-add! id record)
                (persistence-call config 'save-history! id record))
              (send client "execution_success"
                    (obj (cons "prompt_id" id) (cons "timestamp" 0)))
              (send client "executing"
                    (obj (cons "node" 'null) (cons "prompt_id" id)))))))))))

(define (run-queued! config item)
  (persistence-call config 'mark-queue-item-done! (assq-ref item 'prompt_id))
  (queue-reset-interrupt!)
  (dynamic-wind
    (lambda () #t)
    (lambda ()
      (catch #t
        (lambda () (execute-prompt! config item))
        (lambda (key . args)
          (format (current-error-port) "Khala prompt ~a failed: ~s ~s~%"
                  (assq-ref item 'prompt_id) key args)
          (send (assq-ref item 'client_id) "execution_error"
                (obj (cons "prompt_id" (assq-ref item 'prompt_id))
                     (cons "exception_message" (format #f "~s" args)))))))
    queue-finish!))

(define (start-worker! config)
  (unless running?
    (set! running? #t)
    (call-with-new-thread
     (lambda ()
       (let loop ()
         (let ((item (queue-take!)))
           (if item (run-queued! config item) (usleep 50000)))
         (loop)))))
  #t)
