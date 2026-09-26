# jwt middleware

This middleware verifies a JWT sent in the `Authorization: Bearer` header (or in a cookie) and makes its payload available to the application.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*jwt*
                #:jwt-payload
                #:with-args))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *jwt* :secret "it-is-very-secret" :alg "HS256")
    (lambda (env)
      ;; claims alist, e.g. (("sub" . "1234") ("exp" . 1790000000))
      (let ((payload (jwt-payload env)))
        `(200 (:content-type "text/plain")
              (,(format nil "Hello ~A" (cdr (assoc "sub" payload :test #'string=)))))))))
```

## Options

| Keyword | Default | Description |
| --- | --- | --- |
| `:secret` | - (required) | For `HS*`: a string or octet vector. For other algorithms: an ironclad public key, or a public JWK (plist, alist or hash-table). |
| `:alg` | - (required) | `HS256` `HS384` `HS512` `RS256` `RS384` `RS512` `PS256` `PS384` `PS512` `ES256` `ES384` `ES512` `EdDSA` (string or keyword). The token header `alg` must match. |
| `:cookie` | `nil` | Read the token from this cookie when the header is absent. A cookie name, or a plist `(:key name :secret signing-secret :prefix-options :secure/:host)`. With `:secret`, the cookie must be signed like Hono's `setSignedCookie` (`value.base64(HMAC-SHA256)`). |
| `:header-name` | `"Authorization"` | The header to read the token from. |
| `:realm` | request URL | The `realm` of the `WWW-Authenticate` challenge header. |
| `:verification` | `nil` | Plist of claim checks: `:iss` (string, list or predicate), `:aud` (string, list or predicate), `:nbf` / `:exp` / `:iat` (default `t`; `nil` disables the check). |

On failure the response is `401 Unauthorized` with `WWW-Authenticate: Bearer realm="...",error="invalid_request"|"invalid_token",error_description="..."`.
The verified claims are stored in env under `:lack-mw.jwt-payload`; read them with `(jwt-payload env)`.

## Notes

- Ported from Hono's `jwt`, built on the [jose](https://github.com/fukamachi/jose) library. jose supports HS*/RS*/PS* only; ES256/ES384/ES512 and EdDSA (Ed25519) are verified directly with ironclad, and HMAC signatures are compared in constant time.
- The payload is an alist with string keys (as decoded by jose / cl-json); JSON numbers with fractions are read as double floats.
- Hono accepts a `RegExp` for `iss`/`aud`; pass a predicate function instead (e.g. `(lambda (s) (ppcre:scan "^https://" s))`).
- `crypto.subtle` / `CryptoKey` specifics are not applicable. Hono's `sign`/`verify`/`decode` helpers are not re-exported; use jose directly.
