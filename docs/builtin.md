# Lack built-in middlewares

lack-mw re-exports Lack's built-in middlewares under shorter names, so a single `lack-mw` import covers both.

| lack-mw | Lack |
|---|---|
| `*mw-accesslog*` | `lack/middleware/accesslog:*lack-middleware-accesslog*` |
| `*mw-basic-auth*` | `lack/middleware/auth/basic:*lack-middleware-auth-basic*` |
| `*mw-backtrace*` | `lack/middleware/backtrace:*lack-middleware-backtrace*` |
| `*mw-session-csrf*` | `lack/middleware/csrf:*lack-middleware-csrf*` |
| `*mw-mount*` | `lack/middleware/mount:*lack-middleware-mount*` |
| `*mw-session*` | `lack/middleware/session:*lack-middleware-session*` |
| `*mw-static*` | `lack/middleware/static:*lack-middleware-static*` |
| `*mw-when*` | `lack/middleware/when:*lack-middleware-when*` |

These helpers are re-exported as they are: `*time-format*`, `default-formatter` (accesslog), `csrf-token`, `csrf-html-tag` (session-csrf), `make-cookie-state`, `make-memory-store` (session).

Options are the same as Lack's.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*mw-accesslog*
                #:*mw-session*
                #:make-memory-store
                #:*mw-secure-headers*))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
   *mw-accesslog*
   (with-args *mw-session* :store (make-memory-store))
   *mw-secure-headers*
   (lambda (env)
     (declare (ignore env))
     '(200 (:content-type "text/plain") ("ok")))))
```

## Note

- `*mw-session-csrf*` is Lack's token based CSRF protection and needs `*mw-session*`. lack-mw's own [`*mw-csrf*`](/docs/csrf.md) checks the Origin and Sec-Fetch-Site headers instead.
- Each alias looks the Lack middleware up on every call, so redefining it in Lack is picked up.
- `dbpool` and `deflater` are not re-exported: they bring heavy dependencies (cl-dbi, libzstd). Use them from Lack directly.
