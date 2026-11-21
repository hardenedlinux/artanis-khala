(use-modules (khala config)
             ((khala studio persistence) #:prefix db:)
             (app models studio)
             (ice-9 format)
             (srfi srfi-1))

(define db-path "/tmp/khala-character-studio.sqlite3")
(define assets-dir "/tmp/khala-character-studio-assets")
(define (cleanup)
  (for-each (lambda (path)
              (when (file-exists? path) (delete-file path)))
            (list db-path (string-append db-path "-journal")
                  (string-append db-path "-wal")
                  (string-append db-path "-shm"))))

(define (check name condition)
  (unless condition (error "Character Studio test failed" name))
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

(check 'schema-version (= 8 (db:studio-schema-version config)))
(define workplace
  (db:studio-create-workplace! config (db:studio-new-id) "Character Studio"
                               "Test world" "#713D3B" #f))
(define wid (assoc-ref workplace 'id))
(define other-workplace
  (db:studio-create-workplace! config (db:studio-new-id) "Other Studio"
                               "Other world" "#354B40" #f))
(define other-wid (assoc-ref other-workplace 'id))
(define character
  (db:studio-create-character!
   config (db:studio-new-id) wid "Sera Voss" "Mechanic"
   "A young mechanic who refuses to depend on anyone."
   "{}" "{\"face\":\"A fixed angular face with a burn scar.\"}" "{}" "{}"
   #:concept "A young mechanic in a steampunk world who values independence."))
(define cid (assoc-ref character 'id))

(check 'character-concept-stored
       (string-contains (assoc-ref character 'concept) "steampunk"))

(define drafts
  (studio-develop-character! config wid cid
                             (list (cons "concept"
                                         "A young mechanic in a steampunk world."))
                             #f))
(check 'development-creates-four-drafts
       (equal? (map (lambda (draft) (assoc-ref draft "section")) drafts)
               '("literary_identity" "visual_identity"
                 "vocal_identity" "performance_identity")))
(define visual-draft (find (lambda (draft)
                             (equal? (assoc-ref draft "section")
                                     "visual_identity"))
                           drafts))
(check 'draft-respects-locked-canon
       (and (not (assoc-ref (assoc-ref visual-draft "content") "face"))
            (assoc-ref (assoc-ref visual-draft "content")
                       "standard_appearance")))

(define edited-draft
  (studio-update-character-draft!
   config wid cid "visual_identity"
   (list (cons "content"
               (list (cons "face" "Angular face, author-approved edit.")
                     (cons "hair" "Dark hair tied back."))))))
(check 'draft-author-edit-kept-separate
       (and (assoc-ref edited-draft "author_edited")
            (equal? (assoc-ref (db:studio-get-character config wid cid)
                               'visual_identity)
                    "{\"face\":\"A fixed angular face with a burn scar.\"}")))

(define protected
  (catch 'studio-api-error
    (lambda ()
      (studio-develop-character! config wid cid
                                 (list (cons "concept" "regenerate"))
                                 "visual_identity")
      #f)
    (lambda (key status code message details) (list status code))))
(check 'draft-regeneration-protected
       (equal? protected '(409 "DRAFT_PROTECTED")))
(define regenerated
  (studio-develop-character! config wid cid
                             (list (cons "concept" "regenerate")
                                   (cons "force" #t))
                             "visual_identity"))
(check 'forced-regeneration-works
       (= 1 (length (filter (lambda (draft)
                              (equal? (assoc-ref draft "section")
                                      "visual_identity"))
                            regenerated))))

(define applied
  (studio-apply-character-draft! config wid cid "visual_identity"))
(define applied-canon
  (assoc-ref (db:studio-get-character config wid cid) 'visual_identity))
(check 'apply-updates-canon
       (and (assoc-ref (assoc-ref applied "visual_identity") "standard_appearance")
            (string-contains (assoc-ref (assoc-ref applied "visual_identity") "face")
                             "fixed angular face")))
(check 'apply-removes-draft
       (not (any (lambda (draft)
                   (equal? (assoc-ref draft "section") "visual_identity"))
                 (db:studio-list-character-drafts config wid cid))))

(define standard
  (studio-create-character-outfit!
   config wid cid
   (list (cons "name" "Standard Outfit") (cons "kind" "standard")
         (cons "colors" (list "charcoal" "brass"))
         (cons "components" (list "long coat" "work trousers")))))
(define standard-id (assoc-ref standard "id"))
(check 'first-outfit-is-default (assoc-ref standard "is_default"))
(define casual
  (studio-create-character-outfit!
   config wid cid
   (list (cons "name" "Casual Outfit") (cons "kind" "casual")
         (cons "is_default" #t))))
(define casual-id (assoc-ref casual "id"))
(check 'new-default-replaces-old
       (let ((outfits (studio-list-character-outfits config wid cid)))
         (and (not (assoc-ref (find (lambda (outfit)
                                      (equal? (assoc-ref outfit "id") standard-id))
                                    outfits)
                              "is_default"))
              (assoc-ref (find (lambda (outfit)
                                 (equal? (assoc-ref outfit "id") casual-id))
                               outfits)
                         "is_default"))))
(define defaulted
  (studio-set-default-character-outfit! config wid cid standard-id))
(check 'default-outfit-explicit
       (assoc-ref defaulted "is_default"))
(define updated-outfit
  (studio-update-character-outfit!
   config wid cid standard-id
   (list (cons "description" "Workwear with a reinforced apron."))))
(check 'outfit-updated
       (equal? (assoc-ref updated-outfit "description")
               "Workwear with a reinforced apron."))
(check 'outfit-is-character-scoped
       (not (db:studio-get-character-outfit config other-wid cid standard-id)))

(define prompt
  (studio-character-artwork-prompt config wid cid
                                  (list (cons "artwork_type" "full_body")
                                        (cons "outfit_id" standard-id))))
(check 'artwork-prompt-uses-canon-and-outfit
       (and (string-contains (assoc-ref prompt "prompt") "fixed angular face")
            (string-contains (assoc-ref prompt "prompt") "long coat")
            (string-contains (assoc-ref prompt "prompt") "charcoal")))

(define first-artwork
  (studio-generate-character-artwork!
   config wid cid
   (list (cons "artwork_type" "full_body")
         (cons "outfit_id" standard-id))))
(define first-asset-id (assoc-ref (assoc-ref first-artwork "asset") "id"))
(check 'artwork-generated
       (and first-asset-id
            (equal? (assoc-ref (assoc-ref first-artwork "asset") "source")
                    "generated")
            (equal? (assoc-ref (assoc-ref first-artwork "asset") "asset_type")
                    "image")))
(define second-artwork
  (studio-generate-character-artwork!
   config wid cid
   (list (cons "artwork_type" "full_body")
         (cons "outfit_id" standard-id))))
(define second-asset-id (assoc-ref (assoc-ref second-artwork "asset") "id"))
(check 'artwork-regeneration-keeps-old
       (and (not (equal? first-asset-id second-asset-id))
            (db:studio-get-asset config wid first-asset-id)))
(check 'artworks-linked-to-character
       (= 2 (length (studio-list-character-artworks config wid cid))))

(define avatar-character
  (studio-set-character-avatar! config wid cid
                                (list (cons "asset_id" second-asset-id))))
(check 'avatar-approved
       (equal? (assoc-ref (db:studio-get-character config wid cid)
                          'avatar_asset_id)
               second-asset-id))
(define referenced
  (studio-set-character-outfit-reference!
   config wid cid standard-id
   (list (cons "asset_id" first-asset-id))))
(check 'outfit-reference-approved
       (equal? (assoc-ref referenced "reference_asset_id") first-asset-id))
(check 'artwork-does-not-change-identity
       (equal? (assoc-ref (db:studio-get-character config wid cid)
                          'visual_identity)
               applied-canon))
(define canon
  (studio-character-canon config wid cid))
(check 'canon-reports-approved-avatar
       (equal? (assoc-ref (assoc-ref canon "avatar") "id") second-asset-id))

(format #t "Character Studio model tests passed~%")
