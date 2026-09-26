# powered-by middleware

This middleware sets the `X-Powered-By` response header.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*powered-by*))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    *powered-by*                                  ; X-Powered-By: Lack
    ;; or: (with-args *powered-by* :server-name "My Server")
    (lambda (env)
      (declare (ignore env))
      '(200 (:content-type "text/plain") ("Hello")))))
```

## Options

| Option         | Default  | Description                         |
|----------------|----------|-------------------------------------|
| `:server-name` | `"Lack"` | The value of the `X-Powered-By` header. |

## Note

- Ported from Hono's `poweredBy`. Any existing `X-Powered-By` header in the response is replaced, so stacking the middleware never duplicates the value.
- Hono's default value is `"Hono"`. Here it is `"Lack"`.
