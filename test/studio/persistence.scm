(use-modules (khala config)
             (khala studio persistence)
             (khala studio assets)
             (ice-9 format)
             (rnrs bytevectors)
             (srfi srfi-1))

(define db-path "/tmp/khala-studio-persistence.sqlite3")
(define (cleanup)
  (for-each (lambda (path)
              (when (file-exists? path) (delete-file path)))
            (list db-path (string-append db-path "-journal")
                  (string-append db-path "-wal")
                  (string-append db-path "-shm"))))

(define (check name condition)
  (unless condition (error "studio persistence test failed" name))
  (format #t "ok ~a~%" name))

(cleanup)
(define config
  (map (lambda (entry)
         (case (car entry)
           ((studio_db) (cons 'studio_db db-path))
           ((studio_assets_dir) (cons 'studio_assets_dir
                                      "/tmp/khala-studio-test-assets"))
           ((engine) (cons 'engine "fake"))
           ((studio_model) (cons 'studio_model "fake"))
           (else entry)))
       (load-config)))

(check 'fresh-schema (= 6 (studio-schema-version config)))

(define workplace
  (studio-create-workplace! config (studio-new-id) "Persistence World"
                            "A test workplace" "#713D3B" #f))
(define workplace-id (assoc-ref workplace 'id))
(check 'workplace-created (and workplace-id (string? (assoc-ref workplace 'created_at))))
(check 'workplace-listed
       (equal? (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-workplaces config))
               (list workplace-id)))

(define document
  (studio-create-document! config (studio-new-id) workplace-id #f
                           "manuscript" "Book" "hello world" "markdown" 0))
(define document-id (assoc-ref document 'id))
(check 'document-roundtrip
       (equal? (assoc-ref (studio-get-document config workplace-id document-id)
                          'content)
               "hello world"))

(define same-result
  (studio-update-document! config workplace-id document-id
                           "Book" "hello world" "markdown" 1))
(check 'no-op-keeps-revision
       (and (eq? (car same-result) 'ok)
            (= 1 (assoc-ref (cdr same-result) 'revision))))

(define changed
  (studio-update-document! config workplace-id document-id
                           "Book" "hello brave world" "markdown" 1))
(check 'update-increments-revision
       (and (eq? (car changed) 'ok)
            (= 2 (assoc-ref (cdr changed) 'revision))))

(define stale
  (studio-update-document! config workplace-id document-id
                           "Book" "stale overwrite" "markdown" 1))
(check 'stale-update-conflicts
       (and (eq? (car stale) 'conflict)
            (= 2 (assoc-ref (cdr stale) 'revision))))
(check 'stale-update-does-not-overwrite
       (equal? (assoc-ref (studio-get-document config workplace-id document-id)
                          'content)
               "hello brave world"))

(define version
  (studio-create-version! config workplace-id document-id (studio-new-id)
                          "Before edits" "checkpoint"))
(define version-id (assoc-ref version 'id))
(studio-update-document! config workplace-id document-id
                         "Book" "later content" "markdown" 2)
(check 'version-is-immutable
       (equal? (assoc-ref (studio-get-version config workplace-id document-id
                                              version-id)
                          'content)
               "hello brave world"))

(define restored
  (studio-restore-version! config workplace-id document-id version-id))
(check 'restore-creates-new-revision
       (and (= 4 (assoc-ref restored 'revision))
            (equal? (assoc-ref restored 'content) "hello brave world")))
(check 'restore-preserves-historical-version
       (equal? (assoc-ref (studio-get-version config workplace-id document-id
                                              version-id)
                          'content)
               "hello brave world"))
(check 'restore-is-audited
       (any (lambda (entry) (equal? (assoc-ref entry 'source) "restore"))
            (studio-list-versions config workplace-id document-id)))

(define other-workplace
  (studio-create-workplace! config (studio-new-id) "Other" "" "#354B40" #f))
(check 'documents-are-workplace-scoped
       (not (studio-get-document config (assoc-ref other-workplace 'id)
                                 document-id)))

(define character
  (studio-create-character! config (studio-new-id) workplace-id
                            "Mara Vale" "Protagonist" "A cartographer."
                            "{\"background\":\"Raised by the coast.\"}"
                            "{\"standard_appearance\":\"Tall, weathered coat.\"}"
                            "{\"timbre\":\"Low and dry.\"}"
                            "{\"habits\":\"Taps twice before speaking.\"}"))
(define character-id (assoc-ref character 'id))
(check 'character-created
       (and character-id
            (equal? (assoc-ref character 'name) "Mara Vale")))
(check 'character-listed
       (equal? (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-characters config workplace-id))
               (list character-id)))
(check 'character-identities-roundtrip
       (and (string-contains (assoc-ref character 'literary_identity)
                             "Raised by the coast.")
            (string-contains (assoc-ref character 'visual_identity)
                             "weathered coat")))

(define updated-character
  (studio-update-character! config workplace-id character-id
                            `((visual_identity . "{\"clothing\":\"Blue coat.\"}")
                              (role . "POV character"))))
(check 'character-updated
       (and (equal? (assoc-ref updated-character 'role) "POV character")
            (string-contains (assoc-ref updated-character 'visual_identity)
                             "Blue coat")))
(check 'character-update-preserves-other-identities
       (string-contains (assoc-ref updated-character 'vocal_identity)
                        "Low and dry"))
(check 'characters-are-workplace-scoped
       (not (studio-get-character config (assoc-ref other-workplace 'id)
                                  character-id)))

(define scene
  (studio-create-scene! config (studio-new-id) workplace-id
                        `((title . "The Drowned District")
                          (summary . "A confrontation at the tide line.")
                          (sort_order . 1)
                          (status . "draft")
                          (time . "Before dawn")
                          (place . "Northern harbor")
                          (environment . "Fog and low tide")
                          (background . "Abandoned for ten years.")
                          (prior_events . "Mara found the survey map.")
                          (central_question . "Will Mara admit why she returned?")
                          (primary_conflict . "Mara wants the truth; Ilyan wants her gone.")
                          (turn . "The lighthouse was never abandoned.")
                          (dialogue . "MARA\nYou came back.")
                          (blocking . "Mara stays between Ilyan and the stairs.")
                          (spatial . "A narrow pier above black water.")
                          (performance_direction . "Speak quietly; do not cross the center line.")
                          (camera . "Hold on the map in Mara's hand."))))
(define scene-id (assoc-ref scene 'id))
(check 'scene-created
       (and scene-id
            (equal? (assoc-ref scene 'title) "The Drowned District")
            (equal? (assoc-ref scene 'time) "Before dawn")))
(check 'scene-listed
       (equal? (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-scenes config workplace-id))
               (list scene-id)))
(check 'scene-roundtrip
       (equal? (assoc-ref (studio-get-scene config workplace-id scene-id)
                          'central_question)
               "Will Mara admit why she returned?"))

(studio-update-scene! config workplace-id scene-id
                      `((title . "The Drowned District, Revised")
                        (status . "ready")
                        (place . "The tide stair")
                        (direction . "unused")))
(define updated-scene (studio-get-scene config workplace-id scene-id))
(check 'scene-updated
       (and (equal? (assoc-ref updated-scene 'title)
                    "The Drowned District, Revised")
            (equal? (assoc-ref updated-scene 'status) "ready")
            (equal? (assoc-ref updated-scene 'place) "The tide stair")))

(define cast
  (studio-replace-scene-cast! config workplace-id scene-id
                              (list `((character_id . ,character-id)
                                      (objective . "Make Ilyan admit he lied.")
                                      (action . "Ask a question he cannot answer.")
                                      (conflict . "Ilyan refuses to look at the map.")
                                      (emotional_state . "Controlled anger.")
                                      (performance_direction . "Do not raise her voice.")
                                      (subtext . "She already knows.")
                                      (sort_order . 0)))))
(check 'cast-created
       (and (= 1 (length cast))
            (equal? (assoc-ref (car cast) 'character_name) "Mara Vale")
            (equal? (assoc-ref (car cast) 'objective)
                    "Make Ilyan admit he lied.")))
(check 'cast-listed
       (equal? (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-scene-cast config workplace-id scene-id))
               (map (lambda (entry) (assoc-ref entry 'id)) cast)))

(define second-scene
  (studio-create-scene! config (studio-new-id) workplace-id
                        `((title . "The Empty Lighthouse")
                          (summary . "What remains after the argument.")
                          (sort_order . 2)
                          (status . "draft")
                          (time . "Midday")
                          (place . "Lighthouse stair")
                          (environment . "Salt wind")
                          (background . "")
                          (prior_events . "The pier confrontation.")
                          (central_question . "Who is willing to leave first?")
                          (primary_conflict . "Neither will abandon the light.")
                          (turn . "The lamp is still warm.")
                          (dialogue . "")
                          (blocking . "")
                          (spatial . "")
                          (performance_direction . "")
                          (camera . ""))))
(define second-scene-id (assoc-ref second-scene 'id))
(studio-replace-scene-cast! config workplace-id second-scene-id
                            (list `((character_id . ,character-id)
                                    (objective . "Protect the evidence.")
                                    (action . "Block the stair.")
                                    (conflict . "She cannot guard it forever.")
                                    (emotional_state . "Exhausted resolve.")
                                    (performance_direction . "")
                                    (subtext . "")
                                    (sort_order . 0))))
(check 'same-character-can-appear-in-multiple-scenes
       (and (= 1 (length (studio-list-scene-cast config workplace-id scene-id)))
            (= 1 (length (studio-list-scene-cast config workplace-id second-scene-id)))))

(define other-character
  (studio-create-character! config (studio-new-id)
                            (assoc-ref other-workplace 'id)
                            "Ilyan Ro" "Antagonist" "Harbor keeper."
                            "{}" "{}" "{}" "{}"))
(define other-character-id (assoc-ref other-character 'id))
(define cast-before (studio-list-scene-cast config workplace-id second-scene-id))
(define rejected
  (catch 'studio-cast-error
    (lambda ()
      (studio-replace-scene-cast! config workplace-id second-scene-id
                                  (list `((character_id . ,character-id)
                                          (objective . "Valid entry.")
                                          (action . "")
                                          (conflict . "")
                                          (emotional_state . "")
                                          (performance_direction . "")
                                          (subtext . "")
                                          (sort_order . 0))
                                        `((character_id . ,other-character-id)
                                          (objective . "Cross-workplace entry.")
                                          (action . "")
                                          (conflict . "")
                                          (emotional_state . "")
                                          (performance_direction . "")
                                          (subtext . "")
                                          (sort_order . 1))))
      #f)
    (lambda (key reason) reason)))
(check 'cast-cross-workplace-rejected
       (eq? rejected 'character-not-found))
(check 'cast-transaction-rolls-back
       (equal? (map (lambda (entry) (assoc-ref entry 'id)) cast-before)
               (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-scene-cast config workplace-id second-scene-id))))
(check 'scenes-are-workplace-scoped
       (not (studio-get-scene config (assoc-ref other-workplace 'id) scene-id)))

(define asset-id (studio-new-id))
(define asset-storage-key (studio-asset-storage-key asset-id ".md"))
(define asset-checksum
  (studio-asset-store-file! config asset-storage-key
                            (string->utf8 "# Harbor reference\n\nTide charts.")))
(check 'asset-file-stored
       (and (= 64 (string-length asset-checksum))
            (studio-asset-resolve-path config asset-storage-key)))
(define asset
  (studio-create-asset! config asset-id workplace-id
                        `((name . "Harbor reference")
                          (description . "Tide charts used by the scene.")
                          (asset_type . "document")
                          (storage_key . ,asset-storage-key)
                          (original_filename . "harbor.md")
                          (mime_type . "text/markdown")
                          (file_size . 31)
                          (checksum . ,asset-checksum)
                          (source . "upload")
                          (tags . ("reference" "harbor")))))
(check 'asset-created
       (and asset-id
            (equal? (assoc-ref asset 'name) "Harbor reference")
            (equal? (assoc-ref asset 'tags) '("harbor" "reference"))))
(check 'asset-listed
       (equal? (map (lambda (entry) (assoc-ref entry 'id))
                    (studio-list-assets config workplace-id))
               (list asset-id)))
(check 'assets-are-workplace-scoped
       (not (studio-get-asset config (assoc-ref other-workplace 'id) asset-id)))

(define updated-asset
  (studio-update-asset! config workplace-id asset-id
                        `((description . "Verified tide charts."))
                        #:tags '("reference" "harbor" "approved")))
(check 'asset-updated
       (and (equal? (assoc-ref updated-asset 'description)
                    "Verified tide charts.")
            (equal? (assoc-ref updated-asset 'tags)
                    '("approved" "harbor" "reference"))))

(define second-asset
  (studio-create-asset! config (studio-new-id) workplace-id
                        `((name . "Lighthouse sketch")
                          (description . "A loose visual reference.")
                          (asset_type . "image")
                          (source . "generated")
                          (generation_metadata . "{\"model\":\"test\"}")
                          (tags . ("visual")))))
(define second-asset-id (assoc-ref second-asset 'id))
(studio-add-asset-link! config workplace-id asset-id "character" character-id)
(studio-add-asset-link! config workplace-id asset-id "scene" scene-id)
(studio-add-asset-link! config workplace-id asset-id "document" document-id)
(studio-add-asset-link! config workplace-id second-asset-id "character" character-id)
(check 'asset-links-multiple-resources
       (= 3 (length (studio-list-asset-links config workplace-id asset-id))))
(check 'resource-links-multiple-assets
       (= 2 (length (studio-list-linked-assets config workplace-id
                                               "character" character-id))))
(check 'same-asset-linked-once
       (begin
         (studio-add-asset-link! config workplace-id asset-id
                                 "character" character-id)
         (= 3 (length (studio-list-asset-links config workplace-id asset-id)))))

(define deleted-at (studio-delete-scene! config workplace-id scene-id))
(check 'scene-soft-deleted
       (and deleted-at
            (not (studio-get-scene config workplace-id scene-id))
            (not (any (lambda (entry)
                        (equal? (assoc-ref entry 'id) scene-id))
                      (studio-list-scenes config workplace-id)))))
(check 'scene-delete-keeps-character
       (and (studio-get-character config workplace-id character-id)
            (= 1 (length (studio-list-scene-cast config workplace-id
                                                 second-scene-id)))))
(check 'scene-delete-is-not-repeated
       (not (studio-delete-scene! config workplace-id scene-id)))
(check 'scene-delete-removes-asset-links
       (not (any (lambda (link)
                   (and (equal? (assoc-ref link 'resource_type) "scene")
                        (equal? (assoc-ref link 'resource_id) scene-id)))
                 (studio-list-asset-links config workplace-id asset-id))))

(define archived-at
  (studio-archive-character! config workplace-id character-id))
(check 'character-soft-deleted
       (and archived-at
            (not (studio-get-character config workplace-id character-id))
            (null? (studio-list-characters config workplace-id))))
(check 'character-archive-is-not-repeated
       (not (studio-archive-character! config workplace-id character-id)))
(check 'character-archive-removes-asset-links
       (and (null? (studio-list-linked-assets config workplace-id
                                             "character" character-id))
            (= 1 (length (studio-list-asset-links config workplace-id asset-id)))))

(define archived-asset
  (studio-archive-asset! config workplace-id asset-id))
(check 'asset-soft-deleted
       (and archived-asset
            (not (studio-get-asset config workplace-id asset-id))
            (not (any (lambda (entry)
                        (equal? (assoc-ref entry 'id) asset-id))
                      (studio-list-assets config workplace-id)))))
(check 'asset-delete-clears-links
       (null? (studio-list-linked-assets config workplace-id
                                         "document" document-id)))
(check 'asset-delete-is-not-repeated
       (not (studio-archive-asset! config workplace-id asset-id)))
(studio-asset-delete-file! config asset-storage-key)

(cleanup)
(format #t "studio persistence tests passed~%")
