(define-module (khala comfy validate)
  #:use-module (khala comfy object-info)
  #:use-module (khala json)
  #:use-module (srfi srfi-1)
  #:export (validate-prompt))

(define (ref object key . default)
  (let ((item (and (list? object) (assoc key object))))
    (if item (cdr item) (if (null? default) #f (car default)))))

(define (make-error type message details extra)
  (make-json-object
   (list (cons "type" type) (cons "message" message)
         (cons "details" details) (cons "extra_info" extra))))

(define (validate-prompt config prompt)
  (let* ((nodes (if (list? prompt) prompt '()))
         (registry (object-info config))
         (known (map car registry))
         (errors
          (filter-map
           (lambda (entry)
             (let* ((node-id (car entry))
                    (node (cdr entry))
                    (class (ref node "class_type"))
                    (inputs (ref node "inputs" '()))
                    (known-node (and class (assoc class registry))))
               (cond
                ((not class)
                 (cons node-id
                       (make-json-object
                        (list (cons "errors"
                                    (list (make-error "missing_node_type"
                                                      "Node has no class_type"
                                                      node-id
                                                      (make-json-object '()))))
                              (cons "dependent_outputs" '())
                              (cons "class_type" 'null)))))
                ((not known-node)
                 (cons node-id
                       (make-json-object
                        (list (cons "errors"
                                    (list (make-error "missing_node_type"
                                                      "Node type is not in the Khala compatibility registry"
                                                      class
                                                      (make-json-object
                                                       (list (cons "node_id" node-id)
                                                             (cons "class_type" class))))))
                              (cons "dependent_outputs" '())
                              (cons "class_type" class)))))
                (else
                 (let* ((schema (cdr known-node))
                        (required-object
                         (cdr (assoc "required"
                                     (json-object-fields
                                      (cdr (assoc "input"
                                                  (json-object-fields schema)))))))
                        (required (json-object-fields required-object))
                        (missing (filter (lambda (input)
                                           (not (assoc (car input) inputs)))
                                         required)))
                   (if (null? missing)
                       #f
                       (cons node-id
                             (make-json-object
                              (list
                               (cons "errors"
                                     (map (lambda (input)
                                            (make-error "required_input_missing"
                                                        "Required input is missing"
                                                        (car input)
                                                        (make-json-object
                                                         (list (cons "input_name" (car input))))))
                                          missing))
                               (cons "dependent_outputs" '())
                               (cons "class_type" class))))))))))
           nodes))
         (has-output
          (any (lambda (entry)
                 (let ((info (assoc (ref (cdr entry) "class_type") registry)))
                   (and info
                        (cdr (assoc "output_node"
                                    (json-object-fields (cdr info)))))))
               nodes))
         (shape-error
          (not (or (and has-output
                        (any (lambda (entry)
                               (string=? (ref (cdr entry) "class_type" "")
                                         "EmptyImage"))
                             nodes))
                   (t2i-shape? nodes)))))
    (if (pair? errors)
        (values #f (validation-failure errors "Prompt outputs failed validation"))
        (cond
     ((not (list? prompt))
      (values #f
              (make-json-object
               (list (cons "error" (make-error "no_prompt" "No prompt provided"
                                               "No prompt provided"
                                               (make-json-object '())))
                     (cons "node_errors" (make-json-object '())))))
     ((or (null? nodes) (not has-output))
      (format #t "DEBUG no-output~%")
      (values #f (validation-failure errors "Prompt has no outputs")))
     (shape-error
      (values #f
              (make-json-object
               (list (cons "error"
                           (make-error "prompt_outputs_failed_validation"
                                       "workflow shape not supported by Khala yet"
                                       "workflow shape not supported by Khala yet"
                                       (make-json-object '())))
                     (cons "node_errors"
                           (make-json-object
                            (list (cons (car (last nodes))
                                        (make-json-object
                                         (list (cons "errors"
                                                     (list (make-error
                                                            "custom_validation_failed"
                                                            "workflow shape not supported by Khala yet"
                                                            "workflow shape not supported by Khala yet"
                                                            (make-json-object '()))))
                                               (cons "dependent_outputs" '())
                                               (cons "class_type"
                                                     (ref (cdr (last nodes)) "class_type")))))))))))))
     (else (values #t (make-json-object '())))))))

(define (validation-failure errors message)
  (make-json-object
   (list (cons "error"
               (make-error "prompt_outputs_failed_validation" message message
                           (make-json-object '())))
         (cons "node_errors" (make-json-object errors)))))

(define (t2i-shape? nodes)
  (let ((classes (map (lambda (entry) (ref (cdr entry) "class_type")) nodes)))
    (and (or (member "CheckpointLoaderSimple" classes)
             (and (member "UNETLoader" classes)
                  (or (member "CLIPLoader" classes)
                      (member "DualCLIPLoader" classes))
                  (member "VAELoader" classes)))
         (>= (count (lambda (type) (string=? type "CLIPTextEncode")) classes) 2)
         (member "EmptyLatentImage" classes)
         (member "KSampler" classes)
         (member "VAEDecode" classes)
         (or (member "SaveImage" classes) (member "PreviewImage" classes)))))
