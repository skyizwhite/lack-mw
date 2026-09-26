# body-limit middleware

This middleware limits the size of request bodies. A request whose body is larger than `:max-size` bytes is answered by `:on-error` (by default `413 Payload Too Large`) and never reaches the app.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*body-limit*
                #:with-args))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *body-limit*
      :max-size (* 50 1024) ; 50kb
      :on-error (lambda (env)
                  (declare (ignore env))
                  '(413 (:content-type "text/plain") ("overflow :("))))
    *raw-app*))
```

The error answer can depend on the request, e.g. HTML for htmx and JSON otherwise:

```lisp
(with-args *body-limit*
  :max-size +max-body-bytes+
  :on-error (lambda (env)
              (if (gethash "hx-request" (getf env :headers))
                  '(413 (:content-type "text/html; charset=utf-8") ("<p>Too large</p>"))
                  '(413 (:content-type "application/json; charset=utf-8")
                    ("{\"error\":{\"code\":\"too_large\"}}")))))
```

## Options

| Keyword | Default | Description |
|---|---|---|
| `:max-size` | (required) | The maximum body size in bytes. Building the middleware without it signals an error. |
| `:on-error` | 413 `Payload Too Large` (text/plain) | A function taking env and returning the response sent when the body is too large. |

## Note

- With only `Content-Length`, it is trusted: the check is made before anything reads the body.
- With `Transfer-Encoding` (chunked), which takes precedence over `Content-Length` (RFC 7230), the body is read up front, stopping as soon as it goes past the limit, so the check is final before the app runs. The body is kept in a `circular-streams` stream (the one `lack/request` uses) and rewound, so the app reads it as usual.
- A request with neither header has no body and passes (reading `:raw-body` there could block on the connection).
- Differences from Hono: Hono's default error handler throws an `HTTPException`; here it returns the 413 response. Hono also reads a body of unknown length without `Transfer-Encoding`, which in Lack cannot happen for a well-formed HTTP/1.1 request.
