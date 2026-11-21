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

;; Deterministic fixtures used only by engine = fake. They let Character Studio
;; exercise its real validation, draft and approval paths without a GPU.
(define character-dev-fixture
  `(("literary_identity" .
     (("background" . "Raised among repair yards and inherited a practical distrust of borrowed help.")
      ("personality" . "Independent, watchful and quietly stubborn; warm only after trust is earned.")
      ("values" . "Competence, self-reliance, and keeping promises made to people who cannot repay them.")
      ("motivations" . "To prove the workshop can survive without patronage and to protect the people who stayed.")
      ("fears" . "Being reduced to someone else's dependent.")
      ("goals" . "Finish the workshop's first independent commission and expose a sabotage attempt.")
      ("relationships" . "A former mentor who now works for the rival house; a younger apprentice she protects.")
      ("arc" . "From refusing all help to choosing which alliances are worth the risk.")))
    ("visual_identity" .
     (("standard_appearance" . "A lean young mechanic in a worn leather work coat, visibly practical and alert.")
      ("face" . "Angular face with a small burn scar near the left temple and a default expression of concentration.")
      ("body" . "Compact, wiry build with strong hands and a slight forward lean from years of bench work.")
      ("hair" . "Dark brown hair cut short and tied back with a strip of black cord.")
      ("eyes" . "Grey-green eyes; direct gaze that softens only when she is listening rather than calculating.")
      ("skin" . "Warm olive skin marked by soot and small tool nicks.")
      ("distinctive_features" . "A brass thumb guard and a chipped left incisor.")
      ("clothing" . "Work shirt, reinforced trousers, leather apron and a long charcoal coat.")
      ("palette" . "Charcoal, oxblood leather, aged brass and steam-grey.")
      ("expressions" . "Suspicion appears as stillness; amusement shows first at the eyes, not the mouth.")
      ("posture" . "Upright but never rigid; weight usually shifted toward the nearest exit.")))
    ("vocal_identity" .
     (("voice_character" . "Low, dry and precise, with a habit of finishing technical explanations quickly.")
      ("timbre" . "Warm-grained but slightly hoarse from workshop air.")
      ("range" . "Clear in the middle register; drops lower when angry rather than rising.")
      ("pitch" . "Low for her age.")
      ("accent" . "Industrial district accent softened by years of reading manuals.")
      ("pronunciation" . "Crisp consonants; clips the ends of familiar words when impatient.")
      ("pace" . "Measured, with deliberate pauses before answering personal questions.")
      ("speech_habits" . "Calls tools by their numbers; avoids saying the names of people she is protecting.")))
    ("performance_identity" .
     (("habits" . "Taps a brass rule against her knuckle while thinking.")
      ("movement" . "Economical, deliberate motion; picks up and tests an object during conversation.")
      ("gestures" . "Uses her thumb to indicate direction and rarely gestures broadly.")
      ("emotional_responses" . "Withdraws into precision when afraid; becomes honest and blunt when exhausted.")
      ("behavioral_traits" . "Fixes small problems before responding to large ones.")
      ("typical_reactions" . "Checks an exit before entering a room and never asks for help twice.")
      ("situations" . "Defiant but controlled under authority; gentle and indirect with the apprentice.")))))

(define (message-text messages)
  (let ((items (if (vector? messages) (vector->list messages) messages)))
    (string-join
     (filter-map (lambda (message) (assoc-ref message "content"))
                 (if (list? items) items '()))
     "\n")))

(define (character-section-marker text)
  (let ((needle "KHALA_CHARACTER_SECTION: ")
        (start #f))
    (and (string? text)
         (string-contains text needle)
         (begin
           (set! start (+ (string-contains text needle) (string-length needle)))
           (let* ((end (or (string-index text #\newline start)
                           (string-length text)))
                  (section (string-trim-both (substring text start end))))
             (and (not (string-null? section)) section))))))

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
         (all-text (message-text messages))
         (character-full? (string-contains all-text "KHALA_CHARACTER_DEVELOP"))
         (character-section (character-section-marker all-text))
         (character-reply?
          (and character-section
               (assoc-ref character-dev-fixture character-section)))
         (text (cond
                (character-full?
                 (scm->json-string character-dev-fixture))
                (character-reply?
                 (scm->json-string (assoc-ref character-dev-fixture
                                               character-section)))
                (else text)))
         (words (string-split text #\space))
         ;; Chat echoes the words reversed. The enhancement reply is JSON the
         ;; caller parses, so its words must keep their order.
         (tokens (cond
                  ((or character-full? character-reply?) (list text))
                  (enhance? words)
                  (else (reverse words))))
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
