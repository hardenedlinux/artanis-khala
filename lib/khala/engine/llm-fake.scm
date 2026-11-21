(define-module (khala engine llm-fake)
  #:use-module (ice-9 format)
  #:use-module (ice-9 threads)
  #:use-module (json)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:use-module (khala json)
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

(define (line-after-marker text marker)
  (let ((start (and (string? text) (string-contains text marker))))
    (and start
         (let* ((start (+ start (string-length marker)))
                (end (or (string-index text #\newline start)
                         (string-length text))))
           (string-trim-both (substring text start end))))))

(define (uuid-char? char)
  (or (char-numeric? char)
      (char<=? #\a char #\f)
      (char<=? #\A char #\F)))

(define (uuid-token? value)
  (and (string? value)
       (= (string-length value) 36)
       (every (lambda (index)
                (if (member index '(8 13 18 23))
                    (char=? (string-ref value index) #\-)
                    (uuid-char? (string-ref value index))))
              (iota 36))))

(define (token-at text start)
  (let loop ((index start))
    (cond
     ((>= index (string-length text)) (substring text start index))
     ((or (char-whitespace? (string-ref text index))
          (char=? (string-ref text index) #\]))
      (substring text start index))
     (else (loop (+ index 1))))))

(define (storyboard-cast-ids text)
  (let ((marker "Character ID: ")
        (marker-length (string-length "Character ID: ")))
    (let loop ((start 0) (ids '()))
      (let ((found (string-contains text marker start)))
        (if (not found)
            (reverse ids)
            (let* ((value-start (+ found marker-length))
                   (value (token-at text value-start)))
              (loop (+ value-start (string-length value))
                    (if (and (uuid-token? value)
                             (not (member value ids string=?)))
                        (cons value ids)
                        ids))))))))

(define (storyboard-fixture ids)
  (let* ((count (length ids))
         (first-two (take ids (min 2 count)))
         (last-two (take-right ids (min 2 count)))
         (groups (if (null? ids)
                     (list (vector))
                     (list ids first-two last-two)))
         (beats
          '(("Nira refuses the surveyor's warning while the tide rises."
             "Nira keeps one hand on the lamp mechanism and blocks Orin from the stair."
             "Controlled anger; eyes fixed on the oil trail."
             "Still posture, then a sharp turn toward the door as water reaches the threshold."
             "Wide establishing frame from the tide gate, figures small against the black water."
             "A lamp keeper in a charcoal oilskin coat stands between a blue-coated surveyor and a brass lamp mechanism while seawater seeps across the floor.")
            ("Tam reveals that the lamp was opened from inside."
             "Tam holds up the broken seal; Orin looks away, caught between relief and guilt."
             "Tam is frightened but determined; Orin's jaw tightens."
             "Tam steps forward with the seal, then retreats half a pace when Nira turns."
             "Tight three-shot across the workbench, the broken seal catching the lamp light."
             "Three figures around a scarred wooden workbench, the apprentice presenting a broken brass seal under warm lamplight.")
            ("Nira chooses to relight the lamp before answering Orin."
             "Nira strikes the match and the lamp flares, exposing the flooded floor and Orin's lie."
             "Nira's fear settles into resolve; Orin squints against the sudden light."
             "Nira kneels, shields the flame, then rises without looking at Orin."
             "Low angle on the lamp flare, silhouettes stretching across the tide gate."
             "A brass lamp erupts with warm light in a flooded stone chamber, the keeper kneeling beside it and the surveyor recoiling into shadow."))))
    `(("shots" .
       ,(map (lambda (group beat index)
               `(("dramatic_beat" . ,(list-ref beat 0))
                 ("action" . ,(list-ref beat 1))
                 ("character_ids" . ,group)
                 ("expression" . ,(list-ref beat 2))
                 ("performance" . ,(list-ref beat 3))
                 ("camera" . ,(list-ref beat 4))
                 ("visual_description" . ,(list-ref beat 5))
                 ("image_prompt" . ,(list-ref beat 5))))
             groups beats (iota (length groups)))))))

(define (scene-extraction-fixture text)
  (let* ((character-id (line-after-marker text "CHARACTER ID: "))
         (character-name (line-after-marker text "NAME: "))
         (cast (if (and character-id character-name
                        (not (string-null? character-id)))
                   (list
                    `(("character_id" . ,character-id)
                      ("character_name" . ,character-name)
                      ("objective" . "Keep the workshop and its secrets under her control.")
                      ("action" . "She blocks the doorway and refuses to answer the direct question.")
                      ("conflict" . "She needs help but will not admit that dependence is already a fact.")
                      ("emotional_state" . "Controlled anger over a current of fear.")
                      ("performance_direction" . "Still hands; a single glance toward the damaged machine.")
                      ("subtext" . "The person at the door may be the only one who can identify the sabotage.")))
                   (vector)))
         (unresolved
          (if (and character-id character-name)
              (vector)
              (list `(("name" . "The visitor")
                      ("reason" . "No existing Character in this Workplace matched the visitor."))))))
    `(("title" . "The Locked Workshop")
      ("summary" . "A visitor arrives with knowledge of the sabotage while the mechanic refuses to surrender control of the workshop.")
      ("given_circumstances"
       . (("time" . "Late evening")
          ("place" . "A narrow repair workshop beside the rail yard")
          ("environment" . "Oil lamps, cold rain and a half-dismantled engine")
          ("background" . "The workshop has survived on independent commissions.")
          ("prior_events" . "An important machine was found deliberately damaged.")))
      ("dramatic_situation"
       . (("central_question" . "Will the mechanic accept the visitor's help before the workshop is lost?")
          ("primary_conflict" . "She needs information; accepting it would make her dependent on someone else.")
          ("turn" . "The visitor names a detail only the saboteur or a witness could know.")))
      ("dialogue" . "MECHANIC\nYou came a long way to tell me something I already know.\n\nVISITOR\nThen you know who opened the pressure valve.")
      ("direction"
       . (("blocking" . "The mechanic remains between the visitor and the engine.")
          ("spatial" . "A narrow workbench divides the two figures.")
          ("performance_direction" . "Neither character moves toward the other. Let the pause carry the threat.")
          ("camera" . "Medium two-shot, then a close view of the mechanic's hand on the brass rule.")))
      ("cast" . ,cast)
      ("unresolved_characters" . ,unresolved))))

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
         (scene-extraction? (string-contains all-text "KHALA_SCENE_EXTRACTION"))
         (storyboard-generation?
          (string-contains all-text "SCENE-SPECIFIC CONTEXT"))
         (text (cond
                (character-full?
                 (scm->json-string character-dev-fixture))
                (character-reply?
                 (scm->json-string (assoc-ref character-dev-fixture
                                               character-section)))
                (scene-extraction?
                 (json-encode (json-normalize
                               (scene-extraction-fixture all-text))))
                (storyboard-generation?
                 (json-encode
                  (json-normalize
                   (storyboard-fixture (storyboard-cast-ids all-text)))))
                (else text)))
         (words (string-split text #\space))
         ;; Chat echoes the words reversed. The enhancement reply is JSON the
         ;; caller parses, so its words must keep their order.
         (tokens (cond
                  ((or character-full? character-reply? scene-extraction?
                       storyboard-generation?) (list text))
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
