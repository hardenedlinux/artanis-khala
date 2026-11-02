#!/usr/bin/env -S guile -s
!#
(use-modules (ice-9 popen) (ice-9 rdelim) (ice-9 textual-ports) (ice-9 ftw)
             (srfi srfi-13) (srfi srfi-1))

(define version "1.57.6")
(define pin-file "../khala-private/docs/compat-pin.md")
(define work "/tmp/khala-frontend-fetch")
(define wheel-dir (string-append work "/wheel"))
(define frontend-dir "vendor/comfyui-frontend")

(define (run . args)
  (let ((status (apply system* args)))
    (unless (zero? status) (error "command failed" args status))))
(define (lines path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((acc '()))
        (let ((line (read-line port)))
          (if (eof-object? line) (reverse acc) (loop (cons line acc))))))))
(define (digest path)
  (let* ((port (open-pipe* OPEN_READ "sha256sum" path))
         (line (read-line port)))
    (close-pipe port)
    (car (string-split line #\space))))
(define (replace-pin hash)
  (let* ((content (lines pin-file))
         (updated (map (lambda (line)
                         (if (string-prefix? "frontend_sha256:" line)
                             (string-append "frontend_sha256: " hash)
                             line)) content)))
    (call-with-output-file pin-file
      (lambda (port) (for-each (lambda (line) (display line port) (newline port)) updated)))))
(define (pinned-hash)
  (let loop ((rest (lines pin-file)))
    (if (null? rest)
        #f
        (let ((line (car rest)))
          (if (string-prefix? "frontend_sha256:" line)
              (let ((value (string-trim-both (substring line 16))))
                (and (not (string=? value "pending")) value))
              (loop (cdr rest)))))))

(unless (file-exists? pin-file) (error "compat pin file not found" pin-file))
(run "mkdir" "-p" wheel-dir)
(let ((primary (system* "python3" "-m" "pip" "download" "--no-deps"
                        "--index-url" "https://pypi.org/simple"
                        "--only-binary=:all:" "--dest" wheel-dir
                        (string-append "comfyui-frontend-package==" version))))
  (unless (zero? primary)
    (run "python3" "-m" "pip" "download" "--no-deps" "--only-binary=:all:"
         "--index-url" "https://pypi.tuna.tsinghua.edu.cn/simple"
         "--dest" wheel-dir (string-append "comfyui-frontend-package==" version))))
(let* ((wheel (find (lambda (name) (string-suffix? ".whl" name))
                    (scandir wheel-dir)))
       (path (and wheel (string-append wheel-dir "/" wheel))))
  (unless path (error "frontend wheel not found"))
  (let* ((actual (digest path))
         (pinned (pinned-hash)))
    (if pinned
        (unless (string=? pinned actual)
          (error "frontend SHA-256 mismatch" pinned actual))
        (replace-pin actual))
    (run "mkdir" "-p" frontend-dir)
    (run "unzip" "-q" "-o" path "comfyui_frontend_package/static/*"
         "-d" (string-append work "/unpacked"))
    (run "cp" "-a"
         (string-append work "/unpacked/comfyui_frontend_package/static/.")
         (string-append frontend-dir "/"))
    (run "mkdir" "-p" "pub")
    (run "ln" "-sfn" "../vendor/comfyui-frontend/assets" "pub/assets")
    (run "rm" "-rf" work)
    (display (string-append "Fetched frontend " version " sha256=" actual "\n"))))
