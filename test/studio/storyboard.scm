;; Strict schema checks for the LLM storyboard contract.

(use-modules (app models studio)
             (ice-9 format)
             (srfi srfi-1)
             (srfi srfi-13))

(define character-a "00000000-0000-4000-8000-000000000003")
(define character-b "00000000-0000-4000-8000-000000000004")
(define cast-ids (list character-a character-b))

(define (check name condition)
  (unless condition (error "studio storyboard test failed" name))
  (format #t "ok ~a~%" name))

(define (shot-json beat action ids)
  (format #f
          "{\"dramatic_beat\":\"~a\",\"action\":\"~a\",\"character_ids\":[~a],\"expression\":\"guarded\",\"performance\":\"stillness before movement\",\"camera\":\"medium two-shot\",\"visual_description\":\"wet stone and blue coat\",\"image_prompt\":\"cinematic frame\"}"
          beat action
          (string-join (map (lambda (id) (format #f "\"~a\"" id)) ids)
                       ",")))

(define valid-json
  (format #f "{\"shots\":[~a,~a,~a]}"
          (shot-json "Pressure enters" "Mara blocks the stair." (list character-a))
          (shot-json "The question lands" "Ilyan refuses the map." (list character-a character-b))
          (shot-json "The turn costs something" "Mara steps aside." (list character-b))))

(check 'valid-ai-storyboard
       (= 3 (length (studio-validate-storyboard-json valid-json cast-ids))))

(define (invalid? text)
  (catch 'studio-api-error
    (lambda ()
      (studio-validate-storyboard-json text cast-ids)
      #f)
    (lambda (key status code message details)
      (and (= status 502) (equal? code "INVALID_STORYBOARD_OUTPUT")))))

(check 'rejects-non-json (invalid? "not json"))
(check 'rejects-empty-shot-list (invalid? "{\"shots\":[]}"))
(check 'rejects-wrong-root (invalid? "[]"))
(check 'rejects-missing-field
       (invalid?
        "{\"shots\":[{\"dramatic_beat\":\"beat\",\"action\":\"act\",\"character_ids\":[],\"expression\":\"\",\"performance\":\"\",\"camera\":\"cam\",\"visual_description\":\"vis\"}]}"))
(check 'rejects-unknown-field
       (invalid?
        "{\"shots\":[{\"dramatic_beat\":\"beat\",\"action\":\"act\",\"character_ids\":[],\"expression\":\"\",\"performance\":\"\",\"camera\":\"cam\",\"visual_description\":\"vis\",\"image_prompt\":\"prompt\",\"unexpected\":\"no\"}]}"))
(check 'rejects-character-outside-cast
       (invalid?
        (format #f "{\"shots\":[~a]}"
                (shot-json "beat" "act"
                           (list "00000000-0000-4000-8000-000000000099")))))
(check 'rejects-duplicate-character-in-shot
       (invalid?
        (format #f "{\"shots\":[~a]}"
                (shot-json "beat" "act" (list character-a character-a)))))
(check 'rejects-too-many-shots
       (invalid?
        (format #f "{\"shots\":[~a]}"
                (string-join (map (lambda (index)
                                    (shot-json (format #f "beat ~a" index)
                                               "act" (list character-a)))
                                  (iota 9))
                             ","))))

(format #t "studio storyboard schema tests passed~%")
