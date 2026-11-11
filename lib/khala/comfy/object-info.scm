(define-module (khala comfy object-info)
  #:use-module (khala config)
  #:use-module (khala json)
  #:use-module (khala models)
  #:use-module (khala engine)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (object-info))

(define (field key value) (cons key value))
(define (obj . values) (make-json-object values))
(define (combo choices) (list choices))
(define (scalar type options) (if options (list type options) (list type)))
(define (input name schema) (cons name schema))

(define (schema name display category required outputs names is-output hidden)
  (let ((hidden (or hidden '())))
    (obj
     (field "input" (obj (field "required" (make-json-object required))
                         (field "optional" (make-json-object '()))
                         (field "hidden" (make-json-object hidden))))
     (field "input_order" (obj (field "required" (map car required))
                               (field "optional" '())
                               (field "hidden" (map car hidden))))
     (field "is_input_list" #f)
     (field "output" outputs)
     (field "output_is_list" (map (lambda (_) #f) outputs))
     (field "output_name" names)
     (field "name" name)
     (field "display_name" display)
     (field "description" "")
     (field "python_module" "nodes")
     (field "category" category)
     (field "output_node" is-output)
     (field "has_intermediate_output" #f)
     (field "search_aliases" '()))))

(define (registry)
  (let ((int (lambda (name default min max step)
               (input name (scalar "INT" (obj (field "default" default)
                                               (field "min" min)
                                               (field "max" max)
                                               (field "step" step))))))
        (float (lambda (name default min max step)
                 (input name (scalar "FLOAT" (obj (field "default" default)
                                                  (field "min" min)
                                                  (field "max" max)
                                                  (field "step" step))))))
        (str (lambda (name default) (input name (scalar "STRING" (obj (field "default" default))))))
        ;; A linked input: NAME is the key a workflow uses, TYPE the socket
        ;; type the frontend matches against node outputs.
        (socket (lambda (name type) (input name (scalar type #f)))))
    (list
     (cons "CheckpointLoaderSimple"
       (schema "CheckpointLoaderSimple" "Load Checkpoint" "model/loaders"
        (list (input "ckpt_name" (combo '()))) '("MODEL" "CLIP" "VAE")
        '("MODEL" "CLIP" "VAE") #f #f))
     (cons "UNETLoader"
       (schema "UNETLoader" "Load Diffusion Model" "model/loaders"
        (list (input "unet_name" (combo '()))
              (input "weight_dtype" (combo '("default" "fp8_e4m3fn" "fp8_e4m3fn_fast" "fp8_e5m2"))))
        '("MODEL") '("MODEL") #f #f))
     (cons "CLIPLoader"
       (schema "CLIPLoader" "Load CLIP" "model/loaders"
        (list (input "clip_name" (combo '()))
              (input "type" (combo '("stable_diffusion" "stable_cascade" "sd3" "stable_audio" "mochi" "ltxv" "pixart" "cosmos" "lumina2" "wan" "hidream" "chroma" "ace" "omnigen2" "qwen_image" "hunyuan_image" "flux2" "ovis" "longcat_image" "cogvideox" "lens" "pixeldit" "ideogram4" "boogu" "krea2" "joyimage" "mage" "minimax" "yue2" "flux3" "moss_image" "fibo2"))))
        '("CLIP") '("CLIP") #f (list (input "device" (combo '("default" "cpu"))))))
     (cons "DualCLIPLoader"
       (schema "DualCLIPLoader" "DualCLIPLoader" "model/loaders"
        (list (input "clip_name1" (combo '()))
              (input "clip_name2" (combo '()))
              (input "type" (combo '("sdxl" "sd3" "flux" "hunyuan_video" "hidream" "hunyuan_image" "hunyuan_video_15" "kandinsky5" "kandinsky5_image" "ltxv" "newbie" "ace"))))
        '("CLIP") '("CLIP") #f (list (input "device" (combo '("default" "cpu"))))))
     (cons "VAELoader" (schema "VAELoader" "Load VAE" "model/loaders"
                                (list (input "vae_name" (combo '())))
                                '("VAE") '("VAE") #f #f))
     (cons "CLIPTextEncode"
       (schema "CLIPTextEncode" "CLIP Text Encode" "model/conditioning"
        (list (input "text" (scalar "STRING" (obj (field "multiline" #t) (field "dynamicPrompts" #t))))
              (socket "clip" "CLIP"))
        '("CONDITIONING") '("CONDITIONING") #f #f))
     (cons "EmptyLatentImage"
       (schema "EmptyLatentImage" "Empty Latent Image" "model/latent"
        (list (int "width" 1024 16 16384 8) (int "height" 1024 16 16384 8)
              (int "batch_size" 1 1 4096 1))
        '("LATENT") '("LATENT") #f #f))
     (cons "KSampler"
       (schema "KSampler" "KSampler" "model/sampling"
        (list (socket "model" "MODEL") (int "seed" 0 0 18446744073709551615 1)
              (int "steps" 20 1 10000 1) (float "cfg" 8.0 0.0 100.0 0.1)
              (input "sampler_name" (combo '("euler" "euler_ancestral" "dpmpp_2m")))
              (input "scheduler" (combo '("normal" "karras" "simple")))
              (input "positive" (scalar "CONDITIONING" #f))
              (input "negative" (scalar "CONDITIONING" #f))
              (input "latent_image" (scalar "LATENT" #f))
              (float "denoise" 1.0 0.0 1.0 0.01))
        '("LATENT") '("LATENT") #f #f))
     (cons "VAEDecode"
       (schema "VAEDecode" "VAE Decode" "model/latent"
        (list (socket "samples" "LATENT") (socket "vae" "VAE"))
        '("IMAGE") '("IMAGE") #f #f))
     (cons "SaveImage"
       (schema "SaveImage" "Save Image" "image"
        (list (socket "images" "IMAGE") (str "filename_prefix" "ComfyUI"))
        '("IMAGE") '("images") #t
        (list (input "prompt" (scalar "PROMPT" #f))
              (input "extra_pnginfo" (scalar "EXTRA_PNGINFO" #f)))))
     (cons "PreviewImage"
       (schema "PreviewImage" "Preview Image" "image" (list (socket "images" "IMAGE"))
        '("IMAGE") '("images") #t
        (list (input "prompt" (scalar "PROMPT" #f))
              (input "extra_pnginfo" (scalar "EXTRA_PNGINFO" #f)))))
     (cons "LoadImage"
       (schema "LoadImage" "Load Image" "image" (list (input "image" (combo '())))
        '("IMAGE" "MASK") '("IMAGE" "MASK") #f #f))
     (cons "EmptyImage"
       (schema "EmptyImage" "Empty Image" "image"
        (list (int "width" 512 1 16384 1) (int "height" 512 1 16384 1)
              (int "batch_size" 1 1 4096 1) (int "color" 0 0 16777215 1))
        '("IMAGE") '("IMAGE") #f #f)))))

;; COMBO inputs whose choices are the files of a folder: for each node class,
;; (input name . folder). "input" is the upload directory; every other folder
;; is a model folder under models_root.
(define combo-sources
  '(("CheckpointLoaderSimple" ("ckpt_name" . "checkpoints"))
    ("UNETLoader" ("unet_name" . "diffusion_models"))
    ("CLIPLoader" ("clip_name" . "text_encoders"))
    ("DualCLIPLoader" ("clip_name1" . "text_encoders")
                      ("clip_name2" . "text_encoders"))
    ("VAELoader" ("vae_name" . "vae"))
    ("LoadImage" ("image" . "input"))))

;; file-is-directory? raises for a path that does not exist; a catalog entry
;; whose model is not installed is simply not listed.
(define (directory? path)
  (and (file-exists? path) (file-is-directory? path)))

(define (folder-files config folder)
  (if (string=? folder "input")
      (let ((path (config-ref config 'input_dir)))
        (if (file-exists? path)
            (filter (lambda (name) (not (string-prefix? "." name))) (scandir path))
            '()))
      (let* ((files (or (model-files config folder) '()))
             (root (config-ref config 'models_root))
             (catalog (if (file-exists? "conf/image-catalog.scm")
                          (call-with-input-file "conf/image-catalog.scm" read)
                          '()))
             (directories
              (filter-map
               (lambda (entry)
                 (let ((body (cdr entry)))
                   (and (equal? (assq-ref body 'folder) folder)
                        (let ((directory (assq-ref body 'directory)))
                          (and directory
                               (or (directory?
                                    (string-append root "/" directory))
                                   (directory?
                                    (string-append root "/" folder "/" directory)))
                               directory)))))
               catalog)))
        (sort (delete-duplicates (append files directories) string=?)
              string<?))))

(define (replace-combo info field-name values)
  (let* ((fields (json-object-fields info))
         (input-object (cdr (assoc "input" fields)))
         (input-fields (json-object-fields input-object))
         (required (json-object-fields (cdr (assoc "required" input-fields))))
         (new-required
          (map (lambda (entry)
                 (if (string=? (car entry) field-name)
                     (cons field-name (list values))
                     entry)) required))
         (new-input
          (make-json-object
           (map (lambda (item)
                  (if (string=? (car item) "required")
                      (cons "required" (make-json-object new-required)) item))
                input-fields))))
    (make-json-object
     (map (lambda (item)
            (if (string=? (car item) "input")
                (cons "input" new-input) item)) fields))))

(define (object-info config . maybe-name)
  (let* ((all (registry))
         (listed '())                   ; folder -> files, read once per call
         (files (lambda (folder)
                  (cdr (or (assoc folder listed)
                           (let ((entry (cons folder (folder-files config folder))))
                             (set! listed (cons entry listed))
                             entry)))))
         (all (map (lambda (entry)
                     (let ((sources (assoc (car entry) combo-sources)))
                       (if sources
                           (cons (car entry)
                                 (fold (lambda (source info)
                                         (replace-combo info (car source)
                                                        (files (cdr source))))
                                       (cdr entry)
                                       (cdr sources)))
                           entry)))
                   all))
         (options (engine-sampler-options
                   (string->symbol (or (config-ref config 'engine) "fake"))))
         (all (map (lambda (entry)
                     (if (string=? (car entry) "KSampler")
                         (cons (car entry)
                               (replace-combo
                                (replace-combo (cdr entry) "sampler_name" (car options))
                                "scheduler" (cdr options)))
                         entry))
                   all)))
    (if (null? maybe-name)
        all
        (let ((found (assoc (car maybe-name) all)))
          (if found (list found) '())))))
