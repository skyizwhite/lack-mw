# temporary-file middleware

This middleware deletes the file a response sends when the response is marked as temporary with a header, once the server has it. Useful for files made for one answer only, such as a generated archive.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*temporary-file*
                #:+temporary-file-header+))
(in-package #:app/main)

(defun export-app (env)
  (declare (ignore env))
  (let ((archive (make-archive)))   ; returns a pathname
    (list 200
          (list :content-type "application/zip"
                +temporary-file-header+ t)
          archive)))

(defparameter *app*
  (lack:builder
    *temporary-file*
    #'export-app))

;; with another marker header
(defparameter *app*
  (lack:builder
    (with-args *temporary-file* :header :x-delete-after-send)
    #'export-app))
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `:header` | `+temporary-file-header+` (`:x-lack-mw-temporary-file`) | Response header keyword that marks a response as temporary. Any non-nil value marks it. |

## Notes

- The marker header is removed before the response reaches the server.
- The body is deleted (with `unwind-protect`) after the responder returns, so also when sending fails. Woo opens the file before the responder returns and Hunchentoot sends it whole, so deleting then is safe.
- Only pathname bodies are deleted; a marked response with another body just loses the header.
- A marked list response is turned into a delayed one (`(lambda (responder) ...)`), so install this middleware outside everything that reads responses as lists. Delayed responses from the app are handled too.
- There is no Hono equivalent.
