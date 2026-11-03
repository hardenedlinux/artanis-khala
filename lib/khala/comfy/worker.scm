(define-module (khala comfy worker)
  #:use-module (artanis websocket)
  #:use-module (ice-9 threads)
  #:use-module (ice-9 format)
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs io ports)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-34)
  #:use-module (khala config)
  #:use-module (khala json)
  #:use-module (khala engine)
  #:use-module (khala png)
  #:use-module (khala comfy queue)
  #:use-module (khala comfy history)
  #:use-module (khala comfy lower)
  #:use-module (khala comfy ws)
  #:use-module (khala comfy persistence-api)
  #:export (start-worker! image-frame image-frame-bytes preview-step?
            workflow-fingerprints))

(define running? #f)
(define last-successful-fingerprints '())
(define last-successful-pngs '())
(define (obj . fields) (make-json-object fields))
(define (broadcast-queue-status!)
  (ws-broadcast!
   (obj (cons "type" "status")
        (cons "data"
              (obj (cons "status"
                         (obj (cons "exec_info"
                                    (obj (cons "queue_remaining"
                                               (+ (length (queue-list))
                                                  (if (queue-current) 1 0))))))))))))
(define (send client type data)
  (when client (ws-send-client! client (obj (cons "type" type) (cons "data" data)))))
(define (node-class node) (assoc-ref (cdr node) "class_type"))
(define (send-executing! client node-id id)
  (send client "executing"
        (obj (cons "node" node-id) (cons "display_node" node-id)
             (cons "prompt_id" id))))
(define (output-nodes prompt)
  (filter (lambda (node) (member (node-class node) '("SaveImage" "PreviewImage"))) prompt))

(define (workflow-fingerprints prompt order)
  (let ((known '()))
    (for-each
     (lambda (id)
       (let* ((node (assoc id prompt))
              (body (cdr node))
              (inputs (assoc-ref body "inputs"))
              (canonical
               (map (lambda (field)
                      (cons (car field)
                            (let ((value (cdr field)))
                              (if (and (list? value) (= (length value) 2)
                                       (string? (car value))
                                       (number? (cadr value))
                                       (assoc (car value) prompt))
                                  (list "khala-link" (or (assoc-ref known (car value)) "missing"))
                                  value))))
                    inputs))
              (fingerprint (format #f "~s" (list (assoc-ref body "class_type") canonical))))
         (set! known (acons id fingerprint known))))
     order)
    known))

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
        (let* ((fingerprints (workflow-fingerprints prompt order))
               (cached (filter (lambda (node-id)
                                 (equal? (assoc-ref fingerprints node-id)
                                         (assoc-ref last-successful-fingerprints node-id)))
                               order))
               (all-cached? (and (pair? order) (= (length cached) (length order)))))
        (send client "execution_start" (obj (cons "prompt_id" id) (cons "timestamp" 0)))
        (when (pair? cached)
          (send client "execution_cached"
                (obj (cons "prompt_id" id) (cons "nodes" cached) (cons "timestamp" 0))))
        (when (and params order)
          (let* ((sampler (find (lambda (node) (equal? "KSampler" (node-class node)))
                                prompt))
                 (sampler-id (and sampler (car sampler)))
                 (params (if (assoc-ref extra "fail_at_step")
                             (acons 'fail_at_step (assoc-ref extra "fail_at_step") params)
                             params))
                 (before (if sampler-id (take-while (lambda (node-id)
                                                     (not (equal? node-id sampler-id))) order)
                             order))
                 (after (if sampler-id (drop-while (lambda (node-id)
                                                    (not (equal? node-id sampler-id))) order)
                            '())))
          (for-each (lambda (node-id)
                      (unless (member node-id cached) (send-executing! client node-id id)))
                    before)
          (when (and sampler-id (not (member sampler-id cached)))
            (send-executing! client sampler-id id))
          (let* ((engine-name (string->symbol (config-ref config 'engine)))
                 (pngs (if all-cached?
                           last-successful-pngs
                           (engine-run-t2i params #:engine engine-name
                       #:cancelled? queue-interrupted?
                       #:on-progress
                       (lambda (step total)
                         (send client "progress"
                               (obj (cons "value" step) (cons "max" total)
                                    (cons "prompt_id" id)))
                         (when (and client sampler-id (preview-step? step))
                           (ws-send-client! client (image-frame preview-png)))))))
                 (directory (config-ref config 'output_dir)))
            (for-each (lambda (node-id)
                        (unless (member node-id cached) (send-executing! client node-id id)))
                      (if sampler-id (cdr after) '()))
            (when (queue-interrupted?) (throw 'khala-interrupted id))
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
              (set! last-successful-fingerprints fingerprints)
              (set! last-successful-pngs pngs)
              (send client "executing"
                    (obj (cons "node" 'null) (cons "prompt_id" id)))))))))))))

(define (handle-prompt-error! item key args)
  (let* ((prompt (assq-ref item 'prompt))
         (sampler (find (lambda (node) (equal? "KSampler" (node-class node))) prompt))
         (id (assq-ref item 'prompt_id)))
    (if (eq? key 'khala-interrupted)
        (ws-broadcast!
         (obj (cons "type" "execution_interrupted")
              (cons "data"
                    (obj (cons "prompt_id" id)
                         (cons "node_id" (if sampler (car sampler) 'null))
                         (cons "node_type" (if sampler "KSampler" 'null))
                         (cons "executed" '()) (cons "timestamp" 0)))))
        (begin
          (format (current-error-port) "Khala prompt ~a failed: ~s ~s~%" id key args)
          (send (assq-ref item 'client_id) "execution_error"
                (obj (cons "prompt_id" id)
                     (cons "node_id" (if sampler (car sampler) 'null))
                     (cons "node_type" (if sampler "KSampler" 'null))
                     (cons "executed" '())
                     (cons "exception_message" (format #f "~s" args))
                     (cons "exception_type" "Error")
                     (cons "traceback" '())
                     (cons "current_inputs" '())
                     (cons "current_outputs" '())
                     (cons "timestamp" 0)))))))

(define (run-queued! config item)
  (persistence-call config 'mark-queue-item-done! (assq-ref item 'prompt_id))
  (queue-reset-interrupt!)
  (dynamic-wind
    (lambda () #t)
    (lambda ()
      (catch #t
        (lambda () (execute-prompt! config item))
        (lambda (key . args) (handle-prompt-error! item key args))))
    queue-finish!)
  (broadcast-queue-status!))

(define (start-worker! config)
  (unless running?
    (set! running? #t)
    (call-with-new-thread
     (lambda ()
       (let loop ()
         (guard (ex
                 (#t
                  (format (current-error-port) "Khala worker loop failed: ~s~%" ex)
                  (display-backtrace (make-stack #t) (current-error-port))))
           (let ((item (queue-take!)))
             (if item (run-queued! config item) (usleep 50000))))
         (loop)))))
  #t)
