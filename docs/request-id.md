# request-id middleware

This middleware gives every request an id. Handlers can read it from the env, and it is sent back in a response header.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*request-id*
                #:request-id))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *request-id* :header-name "X-Request-Id")
    (lambda (env)
      (format t "request id: ~A~%" (request-id env))
      '(200 (:content-type "text/plain") ("Hello")))))
```

When the request has a valid `X-Request-Id` header, that value is reused. Otherwise a new id is generated (a random UUID v4 by default).

## Options

| Option          | Default                     | Description |
|-----------------|-----------------------------|-------------|
| `:limit-length` | `255`                       | The longest incoming id accepted. A longer one is replaced by a generated id. |
| `:header-name`  | `"X-Request-Id"`            | The header read from the request and set on the response. `""` or `nil` means no header is read or set, and the id is only stored in the env. |
| `:generator`    | `(lambda (env) (generate-uuid))` | A function `(env) -> string` that makes a new id. |

## API

- `(request-id env)`: returns the id. It is stored in the env under `:lack-mw.request-id`.
- `(generate-uuid)`: returns a random UUID v4 string.

## Note

- Ported from Hono's `requestId`. An incoming id is accepted only when it is non-empty, no longer than `:limit-length`, and made only of `[A-Za-z0-9_\-=]`.
- As with Hono's `c.header()` before `next()`, the app can override the header: if the response already has it, the middleware leaves it unchanged.
