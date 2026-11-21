(use-modules (khala config)
             ((khala studio persistence) #:prefix db:)
             ((khala studio assets) #:prefix fs:)
             ((khala engine fake) #:prefix fake:)
             (khala png)
             (app models studio)
             (ice-9 binary-ports)
             (ice-9 format)
             (rnrs bytevectors)
             (srfi srfi-1))

(define db-path "/tmp/khala-visual-consistency.sqlite3")
(define assets-dir "/tmp/khala-visual-consistency-assets")

(define (cleanup)
  (for-each (lambda (path)
              (when (file-exists? path) (delete-file path)))
            (list db-path (string-append db-path "-journal")
                  (string-append db-path "-wal")
                  (string-append db-path "-shm"))))

(define (check name condition)
  (unless condition (error "Visual consistency test failed" name))
  (format #t "ok ~a~%" name))

(cleanup)
(define config
  (map (lambda (entry)
         (case (car entry)
           ((studio_db) (cons 'studio_db db-path))
           ((studio_assets_dir) (cons 'studio_assets_dir assets-dir))
           ((engine) (cons 'engine "fake"))
           ((studio_model) (cons 'studio_model "fake"))
           (else entry)))
       (load-config)))

(define (asset-bytes asset)
  (let* ((key (assoc-ref asset 'storage_key))
         (path (fs:studio-asset-resolve-path config key)))
    (and path (call-with-input-file path get-bytevector-all))))

(define (find-reference usage role kind)
  (find (lambda (entry)
          (and (equal? (assoc-ref entry "role") role)
               (equal? (assoc-ref entry "reference_kind") kind)))
        (assoc-ref usage "references")))

(check 'schema-version (= 8 (db:studio-schema-version config)))

(define workplace
  (db:studio-create-workplace! config (db:studio-new-id) "Visual Canon"
                               "Reference conditioning test" "#713D3B" #f))
(define wid (assoc-ref workplace 'id))
(define other-workplace
  (db:studio-create-workplace! config (db:studio-new-id) "Other Canon"
                               "Another workplace" "#354B40" #f))
(define other-wid (assoc-ref other-workplace 'id))

(define (make-character name role face)
  (db:studio-create-character!
   config (db:studio-new-id) wid name role "Continuity test character."
   "{}" (format #f "{\"face\":\"~a\",\"hair\":\"Dark hair.\"}" face)
   "{}" "{}"))

(define character-a (make-character "Mara Vale" "Protagonist" "A fixed angular face."))
(define character-b (make-character "Ilyan Rook" "Rival" "A narrow face with grey eyes."))
(define cid-a (assoc-ref character-a 'id))
(define cid-b (assoc-ref character-b 'id))

(define outfit-a
  (db:studio-create-character-outfit!
   config (db:studio-new-id) wid cid-a
   '((name . "Standard Outfit") (kind . "standard") (is_default . #t)
     (colors . "[\"sea blue\"]") (components . "[\"blue coat\"]"))))
(define outfit-a-alt
  (db:studio-create-character-outfit!
   config (db:studio-new-id) wid cid-a
   '((name . "Battle Outfit") (kind . "battle")
     (colors . "[\"charcoal\"]") (components . "[\"reinforced coat\"]"))))
(define outfit-b
  (db:studio-create-character-outfit!
   config (db:studio-new-id) wid cid-b
   '((name . "Standard Outfit") (kind . "standard") (is_default . #t)
     (colors . "[\"rust red\"]") (components . "[\"long coat\"]"))))

(define (generate-art cid type outfit-id)
  (studio-generate-character-artwork!
   config wid cid
   (append (list (cons "artwork_type" type))
           (if outfit-id (list (cons "outfit_id" outfit-id)) '()))))

(define char-a-full (generate-art cid-a "full_body" (assoc-ref outfit-a 'id)))
(define char-a-avatar (generate-art cid-a "avatar" (assoc-ref outfit-a 'id)))
(define char-a-outfit (generate-art cid-a "outfit" (assoc-ref outfit-a-alt 'id)))
(define char-a-unapproved (generate-art cid-a "expression_sheet" #f))
(define char-b-avatar (generate-art cid-b "avatar" (assoc-ref outfit-b 'id)))
(define char-b-outfit (generate-art cid-b "outfit" (assoc-ref outfit-b 'id)))

(define char-a-full-id (assoc-ref (assoc-ref char-a-full "asset") "id"))
(define char-a-avatar-id (assoc-ref (assoc-ref char-a-avatar "asset") "id"))
(define char-a-outfit-id (assoc-ref (assoc-ref char-a-outfit "asset") "id"))
(define char-a-unapproved-id (assoc-ref (assoc-ref char-a-unapproved "asset") "id"))
(define char-b-avatar-id (assoc-ref (assoc-ref char-b-avatar "asset") "id"))
(define char-b-outfit-id (assoc-ref (assoc-ref char-b-outfit "asset") "id"))

(studio-set-character-full-body! config wid cid-a
                                (list (cons "asset_id" char-a-full-id)))
(studio-set-character-avatar! config wid cid-b
                              (list (cons "asset_id" char-b-avatar-id)))
(studio-set-character-outfit-reference!
 config wid cid-a (assoc-ref outfit-a 'id)
 (list (cons "asset_id" char-a-outfit-id)))
(studio-set-character-outfit-reference!
 config wid cid-b (assoc-ref outfit-b 'id)
 (list (cons "asset_id" char-b-outfit-id)))

(define stored-a (db:studio-get-character config wid cid-a))
(check 'full-body-approval-stored
       (equal? (assoc-ref stored-a 'full_body_asset_id) char-a-full-id))
(check 'unapproved-artwork-does-not-change-canon
       (and (not (equal? char-a-unapproved-id char-a-full-id))
            (equal? (assoc-ref stored-a 'avatar_asset_id) #f)))

(define scene
  (db:studio-create-scene! config (db:studio-new-id) wid
                           '((title . "The Drowned District")
                             (summary . "Mara and Ilyan meet at the tide line.")
                             (sort_order . 1)
                             (status . "ready")
                             (time . "Before dawn")
                             (place . "Northern harbor")
                             (environment . "Fog and low tide")
                             (background . "The district was abandoned.")
                             (prior_events . "Mara found the survey map.")
                             (central_question . "Who will admit why they returned?")
                             (primary_conflict . "Mara wants the truth; Ilyan wants her gone.")
                             (turn . "The lighthouse lamp is still warm."))))
(define sid (assoc-ref scene 'id))
(db:studio-replace-scene-cast!
 config wid sid
 (list (list (cons 'character_id cid-a) (cons 'objective "Make Ilyan admit he lied.")
             (cons 'action "Block the stair.") (cons 'conflict "Ilyan looks away.")
             (cons 'emotional_state "Controlled anger.")
             (cons 'performance_direction "Stay still.") (cons 'subtext "She knows.")
             (cons 'sort_order 0))
       (list (cons 'character_id cid-b) (cons 'objective "Keep Mara from the lamp.")
             (cons 'action "Refuse the map.") (cons 'conflict "The lie is visible.")
             (cons 'emotional_state "Exhausted defiance.")
             (cons 'performance_direction "Do not raise his voice.") (cons 'subtext "He is afraid.")
             (cons 'sort_order 1))))

(define scene-reference-png
  (rgb->png 8 8 (make-bytevector (* 8 8 3) 172)))
(define scene-reference
  (studio-create-uploaded-asset!
   config wid (db:studio-new-id) "harbor-reference.png" "image/png"
   scene-reference-png (list (cons "name" "Approved Harbor Reference"))))
(define scene-trace
  (studio-create-uploaded-asset!
   config wid (db:studio-new-id) "unapproved-trace.png" "image/png"
   (rgb->png 8 8 (make-bytevector (* 8 8 3) 33))
   (list (cons "name" "Unapproved Trace"))))
(db:studio-add-asset-link! config wid (assoc-ref scene-reference "id") "scene" sid)
(db:studio-add-asset-link! config wid (assoc-ref scene-trace "id") "scene" sid)
(define scene-references
  (studio-set-scene-references!
   config wid sid
   (list (cons "asset_ids" (list (assoc-ref scene-reference "id"))))))
(check 'scene-reference-approved
       (equal? (assoc-ref (db:studio-get-scene config wid sid) 'reference_asset_ids)
               (format #f "[\"~a\"]" (assoc-ref scene-reference "id"))))
(check 'public-scene-exposes-reference-ids
       (equal? (assoc-ref scene-references "reference_asset_ids")
               (list (assoc-ref scene-reference "id"))))

(define board (studio-create-storyboard! config wid sid '()))
(define shot (car (assoc-ref board "shots")))
(define shot-id (assoc-ref shot "id"))
(check 'storyboard-defaults-character-outfits
       (and (= 2 (length (assoc-ref shot "character_outfits")))
            (every (lambda (entry)
                     (and (assoc-ref entry "character_id")
                          (assoc-ref entry "outfit_id")))
                   (assoc-ref shot "character_outfits"))))

(define selected-shot
  (acons "character_ids" (list cid-a cid-b) shot))
(set! selected-shot
      (acons "character_outfits"
             (list->vector
              (list (list (cons "character_id" cid-a)
                          (cons "outfit_id" (assoc-ref outfit-a 'id)))
                    (list (cons "character_id" cid-b)
                          (cons "outfit_id" (assoc-ref outfit-b 'id)))))
             selected-shot))
(define updated-board
  (studio-update-storyboard! config wid sid
                             (list (cons "shots" (vector selected-shot)))))
(define selected-shot-id (assoc-ref (car (assoc-ref updated-board "shots")) "id"))

(fake:fake-reset-image-reference-trace!)
(define generated
  (studio-generate-storyboard-image! config wid sid selected-shot-id))
(define usage (assoc-ref generated "reference_usage"))
(define trace (assoc-ref usage "references"))
(define fake-inputs (fake:fake-last-image-references))

(check 'reference-mode-is-byte-conditioned
       (and (eq? (assoc-ref usage "applied") #t)
            (equal? (assoc-ref usage "mode") "reference-conditioned")))
(check 'multi-character-references-present
       (and (find-reference usage "character" "full_body")
            (find-reference usage "character" "avatar")))
(check 'both-outfit-references-present
       (= 2 (length (filter (lambda (entry)
                              (equal? (assoc-ref entry "role") "outfit"))
                            trace))))
(check 'scene-reference-present
       (find-reference usage "scene" "scene_reference"))
(check 'unapproved-artwork-excluded
       (not (any (lambda (entry)
                   (equal? (assoc-ref entry "asset_id") char-a-unapproved-id))
                 trace)))
(check 'unapproved-scene-linked-asset-excluded
       (not (any (lambda (entry)
                   (equal? (assoc-ref entry "asset_id")
                           (assoc-ref scene-trace "id")))
                 trace)))

(define expected-ids
  (list char-a-full-id char-a-outfit-id char-b-avatar-id
        char-b-outfit-id (assoc-ref scene-reference "id")))
(check 'trace-has-traceable-assets
       (lset= string=? expected-ids
              (map (lambda (entry) (assoc-ref entry "asset_id")) trace)))

(check 'adapter-received-actual-bytevectors
       (and (= (length fake-inputs) (length trace))
            (every (lambda (entry)
                     (let* ((asset (db:studio-get-asset
                                    config wid (assoc-ref entry 'asset_id)))
                            (expected (asset-bytes asset))
                            (actual (assoc-ref entry 'data)))
                       (and (bytevector? actual)
                            (= (bytevector-length actual)
                               (bytevector-length expected))
                            (equal? actual expected))))
                   fake-inputs)))

(define reference-a-bytes
  (asset-bytes (db:studio-get-asset config wid char-a-full-id)))
(define reference-b-bytes
  (asset-bytes (db:studio-get-asset config wid char-b-avatar-id)))
(define png-with-a
  (car (fake:engine-run-t2i
        `((positive . "same prompt") (seed . 7) (width . 8) (height . 8)
          (steps . 1)
          (references . (((role . "character") (data . ,reference-a-bytes))))))))
(define png-with-b
  (car (fake:engine-run-t2i
        `((positive . "same prompt") (seed . 7) (width . 8) (height . 8)
          (steps . 1)
          (references . (((role . "character") (data . ,reference-b-bytes))))))))
(check 'reference-bytes-influence-output
       (not (equal? png-with-a png-with-b)))

(define metadata
  (assoc-ref (assoc-ref generated "asset") "generation_metadata"))
(define metadata-references (assoc-ref metadata "references"))
(check 'generation-metadata-records-references
       (and (eq? (assoc-ref metadata "references_applied") #t)
            (= (if (vector? metadata-references)
                   (vector-length metadata-references)
                   (length metadata-references))
               (length trace))))

(define old-asset-id (assoc-ref (assoc-ref generated "shot") "asset_id"))
(define regenerated
  (studio-generate-storyboard-image! config wid sid selected-shot-id))
(check 'regeneration-keeps-old-asset
       (and (not (equal? old-asset-id
                        (assoc-ref (assoc-ref regenerated "shot") "asset_id")))
            (db:studio-get-asset config wid old-asset-id)))

(define scene-after (db:studio-get-scene config wid sid))
(define character-after-a (db:studio-get-character config wid cid-a))
(check 'generation-does-not-change-scene-or-canon
       (and (equal? (assoc-ref scene-after 'turn)
                    "The lighthouse lamp is still warm.")
            (equal? (assoc-ref character-after-a 'full_body_asset_id)
                    char-a-full-id)
            (equal? (assoc-ref (db:studio-get-scene config wid sid)
                               'reference_asset_ids)
                    (assoc-ref (db:studio-get-scene config wid sid)
                               'reference_asset_ids))))

(define disposable-reference
  (studio-create-uploaded-asset!
   config wid (db:studio-new-id) "disposable-reference.png" "image/png"
   (rgb->png 8 8 (make-bytevector (* 8 8 3) 9))
   (list (cons "name" "Disposable Reference"))))
(db:studio-add-asset-link! config wid
                           (assoc-ref disposable-reference "id") "scene" sid)
(studio-set-scene-references!
 config wid sid
 (list (cons "asset_ids" (list (assoc-ref scene-reference "id")
                               (assoc-ref disposable-reference "id")))))
(db:studio-archive-asset! config wid (assoc-ref disposable-reference "id"))
(check 'asset-delete-clears-scene-reference
       (equal? (assoc-ref (db:studio-get-scene config wid sid)
                          'reference_asset_ids)
               (format #f "[\"~a\"]" (assoc-ref scene-reference "id"))))

(define other-character
  (db:studio-create-character!
   config (db:studio-new-id) other-wid "Outsider" "Other" "" "{}" "{}" "{}" "{}"))
(define other-art
  (studio-generate-character-artwork!
   config other-wid (assoc-ref other-character 'id)
   (list (cons "artwork_type" "avatar"))))
(define other-art-id (assoc-ref (assoc-ref other-art "asset") "id"))
(check 'character-reference-is-workplace-scoped
       (catch 'studio-api-error
         (lambda ()
           (studio-set-character-full-body!
            config wid cid-a (list (cons "asset_id" other-art-id)))
           #f)
         (lambda (key status code message details) (= status 404))))

(check 'scene-reference-is-workplace-scoped
       (catch 'studio-api-error
         (lambda ()
           (studio-set-scene-references!
            config wid sid (list (cons "asset_ids" (list other-art-id))))
           #f)
         (lambda (key status code message details) (= status 404))))

(format #t "Character visual consistency tests passed~%")
