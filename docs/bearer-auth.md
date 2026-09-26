# bearer-auth middleware

This middleware provides Bearer authentication: requests are accepted only when the `Authorization` header carries a valid token.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*mw-bearer-auth*
                #:with-args))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *mw-bearer-auth* :token "honoishot")
    (lambda (env)
      (declare (ignore env))
      '(200 (:content-type "text/plain") ("You are authorized")))))
```

Validating tokens dynamically:

```lisp
(with-args *mw-bearer-auth*
  :verify-token (lambda (token env)
                  (declare (ignore env))
                  (valid-token-p token)))
```

## Options

| Keyword | Default | Description |
| --- | --- | --- |
| `:token` | - | A string, or a list of strings, to compare the incoming token against. Either `:token` or `:verify-token` is required. |
| `:verify-token` | - | A function `(token env) -> boolean` used instead of `:token`. |
| `:realm` | `""` | The realm of the `WWW-Authenticate` challenge header. |
| `:prefix` | `"Bearer"` | The scheme expected before the token (case-insensitive). If `""`, the whole header value is the token. |
| `:header-name` | `"Authorization"` | The header to read the token from. |
| `:hash-function` | SHA-256 hex | A function `(string) -> string` used by the timing-safe comparison. |
| `:no-authentication-header` | `(:www-authenticate-header "Bearer realm=\"\"" :message "Unauthorized")` | Response options (plist) when the header is missing. Status 401. |
| `:invalid-authentication-header` | `(:www-authenticate-header "Bearer error=\"invalid_request\"" :message "Bad Request")` | Response options when the header is malformed. Status 400. |
| `:invalid-token` | `(:www-authenticate-header "Bearer error=\"invalid_token\"" :message "Unauthorized")` | Response options when the token does not match. Status 401. |
| `:no-authentication-header-message`, `:invalid-authentication-header-message`, `:invalid-token-message` | - | Deprecated in Hono; same as the `:message` of the options above. |

`:www-authenticate-header` may be a string (used as-is), an object (a plist, alist or hash-table rendered as `<prefix> key="value",...`), or a function of `env` returning either.
`:message` may be a string (sent as `text/plain`), an object (plist, alist or hash-table, sent as `application/json`), or a function of `env` returning either.

`timing-safe-equal` (`a b &optional hash-function`) is also exported.

## Notes

- Ported from Hono's `bearerAuth`. Hono throws `HTTPException`; here the error response is returned directly.
- JSON for object messages is produced by a small built-in encoder (keyword keys are downcased; `t` -> `true`, `nil`/`:null` -> `null`, `:false` -> `false`, vectors -> arrays).
