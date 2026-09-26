# cors middleware

This middleware adds the CORS (Cross-Origin Resource Sharing) headers to responses and answers preflight (`OPTIONS`) requests itself.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*mw-cors*
                #:with-args))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *mw-cors*
      :origin "http://example.com"
      :allow-headers '("X-Custom-Header" "Upgrade-Insecure-Requests")
      :allow-methods '("POST" "GET" "OPTIONS")
      :expose-headers '("Content-Length" "X-Kuma-Revision")
      :max-age 600
      :credentials t)
    (lambda (env)
      (declare (ignore env))
      '(200 (:content-type "application/json") ("{\"success\":true}")))))
```

With all defaults (`Access-Control-Allow-Origin: *`), pass `*mw-cors*` as is:

```lisp
(lack:builder *mw-cors* *raw-app*)
```

An origin can be chosen per request by a function:

```lisp
(with-args *mw-cors*
  :origin (lambda (origin env)
            (declare (ignore env))
            (if (alexandria:ends-with-subseq ".example.com" origin)
                origin
                "http://example.com")))
```

## Options

| Keyword | Default | Description |
|---|---|---|
| `:origin` | `"*"` | The value of `Access-Control-Allow-Origin`. A string, a list of strings (the request's `Origin` is echoed when it is in the list), or a function `(origin env)` returning the value to send or `NIL` to send none. `origin` is `""` when the request has no `Origin` header. |
| `:allow-methods` | `'("GET" "HEAD" "PUT" "POST" "DELETE" "PATCH" "QUERY")` | The value of `Access-Control-Allow-Methods` on preflight. A list of strings, or a function `(origin env)` returning one. An empty list sends no header. |
| `:allow-headers` | `'()` | The value of `Access-Control-Allow-Headers` on preflight. When empty, the request's `Access-Control-Request-Headers` is echoed. |
| `:max-age` | `nil` | The value of `Access-Control-Max-Age` (seconds) on preflight. |
| `:credentials` | `nil` | When true, sends `Access-Control-Allow-Credentials: true`. |
| `:expose-headers` | `'()` | The value of `Access-Control-Expose-Headers`. |

## Note

- A preflight request is answered with `204` and never reaches the app.
- When `:origin` is not `"*"`, `Origin` is added to the response's `Vary` header (appended to an existing `Vary`, and not twice). `Access-Control-Request-Headers` is added to `Vary` on preflight when `Access-Control-Allow-Headers` is sent.
- The CORS headers overwrite headers of the same name set by the app, as in Hono.
- `:origin "*"` with `:credentials t` always sends `*`, never the reflected origin (browsers reject that combination, so it fails closed).
- Differences from Hono: functions may not return promises (plain values only). Hono's preflight answer carries headers set on the context by earlier middleware; in Lack, outer middleware post-process the 204 response instead.
