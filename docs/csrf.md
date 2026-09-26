# csrf middleware

This middleware protects against CSRF (Cross-Site Request Forgery) by checking the `Origin` and `Sec-Fetch-Site` request headers. It needs no token.

A request is rejected with `403 Forbidden` when all of the following hold:

- its method is not `GET`, `HEAD` or `OPTIONS`;
- its `Content-Type` is one an HTML form can send: `application/x-www-form-urlencoded`, `multipart/form-data` or `text/plain` (a request without `Content-Type` counts as `text/plain`);
- its `Sec-Fetch-Site` header is missing or not allowed;
- its `Origin` header is missing or not allowed.

For the token-based CSRF protection, see Lack's own `lack/middleware/csrf`.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*csrf*
                #:with-args))
(in-package #:app/main)

;; Default: only same-origin requests
(defparameter *app*
  (lack:builder
    *csrf*
    *raw-app*))

;; Allow specific origins and Sec-Fetch-Site values
(defparameter *app2*
  (lack:builder
    (with-args *csrf*
      :origin '("https://app.example.com" "https://admin.example.com")
      :sec-fetch-site '("same-origin" "same-site"))
    *raw-app*))

;; Dynamic check: also accept cross-site webhooks
(defparameter *app3*
  (lack:builder
    (with-args *csrf*
      :sec-fetch-site (lambda (value env)
                        (or (string= value "same-origin")
                            (alexandria:starts-with-subseq "/webhook/" (getf env :path-info)))))
    *raw-app*))
```

## Options

| Keyword | Default | Description |
|---|---|---|
| `:origin` | the request URL's origin | Allowed origins. A string, a list of strings, or a function `(origin env)` returning true to allow. |
| `:sec-fetch-site` | `"same-origin"` | Allowed `Sec-Fetch-Site` values (`"same-origin"`, `"same-site"`, `"none"`, `"cross-site"`). A string, a list of strings, or a function `(value env)` returning true to allow. Other values are always rejected. |

## Note

- The request passes when either header is allowed.
- The default origin is built from the `:url-scheme` and the `Host` header (or `:server-name` and `:server-port` when there is no `Host`). Behind a reverse proxy that changes the scheme or host, pass `:origin` explicitly.
- Differences from Hono: functions may not return promises. The rejection is a plain `403` response rather than an `HTTPException`.
