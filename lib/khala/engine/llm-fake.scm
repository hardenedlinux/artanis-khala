(define-module (khala engine llm-fake)
  #:use-module (ice-9 format)
  #:use-module (ice-9 threads)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (engine-chat))

(define (last-user-message messages)
  (let* ((items (if (vector? messages) (vector->list messages) messages))
         (entry (find (lambda (m) (equal? (assoc-ref m "role") "user"))
                      (reverse (if (list? items) items '()))))
         (content (and entry (assoc-ref entry "content"))))
    (if (string? content) content "")))

(define* (engine-chat model messages options #:key (on-token (lambda (_) #t))
                      (cancelled? (lambda () #f)))
  (let* ((items (if (vector? messages) (vector->list messages) messages))
         ;; Prompt enhancement asks for a JSON reply (format = json) under a
         ;; system prompt. The wording of conf/prompt-enhance.txt is free to
         ;; change, so the request's format decides, not a phrase in it.
         (json-reply? (and (list? options)
                           (equal? (assoc-ref options "format") "json")))
         (enhance? (any (lambda (message)
                          (and (equal? (assoc-ref message "role") "system")
                               (or json-reply?
                                   (string-contains (or (assoc-ref message "content") "")
                                                    "Rewrite the request"))))
                        items))
         (text (last-user-message messages))
         (text (if enhance?
                   (scm->json-string
                    `(("prompt" . ,(string-append
                                    "Detailed image: " text
                                    ", balanced composition, soft lighting, editorial style"))
                      ("negative" . "blurry, low quality")))
                   text))
         (words (string-split text #\space))
         ;; Chat echoes the words reversed. The enhancement reply is JSON the
         ;; caller parses, so its words must keep their order.
         (tokens (if enhance? words (reverse words)))
         (start (get-internal-real-time)))
    (for-each (lambda (word)
                (unless (cancelled?)
                  (usleep 20000)
                  (on-token (string-append word " "))))
              tokens)
    (let* ((elapsed (max 1 (- (get-internal-real-time) start)))
           (ns (inexact->exact (* elapsed (/ 1000000000 internal-time-units-per-second)))))
      `((text . ,(string-join tokens " ")) (tokens . ,(length tokens))
        (total_duration . ,ns) (load_duration . 1000000)
        (prompt_eval_count . ,(length words)) (prompt_eval_duration . 1000000)
        (eval_count . ,(length tokens)) (eval_duration . ,ns)
        (done . ,(not (cancelled?)))))))
