# jwk middleware

This middleware verifies a JWT against a set of public JSON Web Keys, selected by the token's `kid` header, and makes its payload available to the application.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*mw-jwk*
                #:jwt-payload
                #:with-args))
(in-package #:app/main)

(defparameter *keys*
  '((:kid "my-key-1" :kty "RSA" :alg "RS256" :e "AQAB" :n "2XGQh8VC_p8g...")))

(defparameter *app*
  (lack:builder
    (with-args *mw-jwk* :keys *keys* :alg '("RS256"))
    (lambda (env)
      `(200 (:content-type "text/plain")
            (,(format nil "~S" (jwt-payload env)))))))
```

To use keys from a JWKS endpoint, pass a function that returns them (fetch and cache them with the HTTP client of your choice):

```lisp
(with-args *mw-jwk*
  :keys (lambda (env)
          (declare (ignore env))
          (gethash "keys" (yason:parse (fetch-jwks-cached))))
  :alg '("RS256" "ES256"))
```

## Options

| Keyword | Default | Description |
| --- | --- | --- |
| `:keys` | - (required) | A list of public JWKs (each a plist, alist or hash-table), or a function of `env` returning one. |
| `:alg` | - (required) | The list of allowed asymmetric algorithms: `RS256` `RS384` `RS512` `PS256` `PS384` `PS512` `ES256` `ES384` `ES512` `EdDSA`. `HS*` is never accepted. |
| `:allow-anon` | `nil` | If true, requests without any token are passed through without a payload. |
| `:cookie` | `nil` | Same as the jwt middleware: a cookie name, or `(:key name :secret signing-secret :prefix-options :secure/:host)`. |
| `:header-name` | `"Authorization"` | The header to read the token from. |
| `:realm` | request URL | The `realm` of the `WWW-Authenticate` challenge header. |
| `:verification` | `nil` | Same claim checks as the jwt middleware (`:iss` `:aud` `:nbf` `:exp` `:iat`). |

The token must have a `kid` header matching a key's `kid`, and if the key has an `alg` member it must equal the token's `alg`.
Supported key types: `RSA`, `EC` (`P-256`, `P-384`, `P-521`) and `OKP` (`Ed25519`).
Errors and the payload accessor (`jwt-payload`, env key `:lack-mw.jwt-payload`) are the same as in the jwt middleware.

## Notes

- Ported from Hono's `jwk`.
- `jwks_uri` (and the `init` fetch options) is not supported, since it needs an HTTP client dependency. Use a `:keys` function instead.
- Errors signalled by a `:keys` function are not caught (Hono rethrows plain `Error`s too).
