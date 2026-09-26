# secure-headers middleware

This middleware sets security-related response headers, including an optional Content-Security-Policy with per-request nonces.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*mw-secure-headers*
                #:secure-headers-nonce))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *mw-secure-headers*
      :x-frame-options "DENY"
      :strict-transport-security "max-age=63072000; includeSubDomains; preload"
      :content-security-policy '(:default-src ("'self'")
                                 :script-src ("'self'" :nonce)
                                 :img-src ("'self'" "data:")
                                 :upgrade-insecure-requests ())
      :permissions-policy '(:camera nil
                            :microphone t
                            :fullscreen ("self")
                            :payment ("self" "example.com")))
    (lambda (env)
      `(200 (:content-type "text/html")
            (,(format nil "<script nonce=\"~A\">...</script>"
                      (secure-headers-nonce env)))))))
```

Plain `*mw-secure-headers*` sets the default headers listed below.

## Options

Options for simple headers take `t` (send the default value), `nil` (do not send), or a string (send that value).

| Option                               | Default | Header / default value |
|--------------------------------------|---------|------------------------|
| `:cross-origin-embedder-policy`      | `nil`   | `Cross-Origin-Embedder-Policy: require-corp` |
| `:cross-origin-resource-policy`      | `t`     | `Cross-Origin-Resource-Policy: same-origin` |
| `:cross-origin-opener-policy`        | `t`     | `Cross-Origin-Opener-Policy: same-origin` |
| `:origin-agent-cluster`              | `t`     | `Origin-Agent-Cluster: ?1` |
| `:referrer-policy`                   | `t`     | `Referrer-Policy: no-referrer` |
| `:strict-transport-security`         | `t`     | `Strict-Transport-Security: max-age=15552000; includeSubDomains` |
| `:x-content-type-options`            | `t`     | `X-Content-Type-Options: nosniff` |
| `:x-dns-prefetch-control`            | `t`     | `X-DNS-Prefetch-Control: off` |
| `:x-download-options`                | `t`     | `X-Download-Options: noopen` |
| `:x-frame-options`                   | `t`     | `X-Frame-Options: SAMEORIGIN` |
| `:x-permitted-cross-domain-policies` | `t`     | `X-Permitted-Cross-Domain-Policies: none` |
| `:x-xss-protection`                  | `t`     | `X-XSS-Protection: 0` |
| `:remove-powered-by`                 | `t`     | Removes `X-Powered-By` from the response. |
| `:content-security-policy`           | `nil`   | A CSP plist (see below) for `Content-Security-Policy`. |
| `:content-security-policy-report-only` | `nil` | A CSP plist for `Content-Security-Policy-Report-Only`. |
| `:permissions-policy`                | `nil`   | A plist for `Permissions-Policy` (see below). |
| `:reporting-endpoints`               | `nil`   | A list of `(:name "e1" :url "https://...")`, sent as `Reporting-Endpoints: e1="https://..."`. |
| `:report-to`                         | `nil`   | A list of `(:group "g" :max-age 10886400 :endpoints ((:url "https://...")))`, sent as JSON in `Report-To`. |

### Content Security Policy

The CSP option is a plist of directive keyword to list of sources, for example `:default-src`, `:script-src`, `:style-src-elem`, `:frame-ancestors`, `:report-uri`, or `:require-trusted-types-for`. The keyword name is used as the directive name, and directives are sent in the order given. A single string is also accepted (`:report-to "endpoint-1"`, `:report-uri "/csp"`), and an empty list sends a directive with no value (`:upgrade-insecure-requests ()`).

A source can also be:

- `:nonce`: a random base64 nonce (16 bytes), rendered as `'nonce-...'`. One nonce is made per request and shared by every directive and both CSP headers. Read it with `(secure-headers-nonce env)`, which reads the env key `:lack-mw.secure-headers-nonce`.
- A function `(lambda (env directive) ...)`: `directive` is the directive keyword. It returns the source string, and can return a plist as a second value, which is added to the env passed to the app. This is the equivalent of Hono's `ctx.set()`.

Dynamic sources are resolved before the app is called, so their values are available to the app.

### Permissions Policy

The plist maps a feature keyword (`:camera`, `:sync-xhr`, ...) to:

- `t`: `feature=*`
- `nil` / `()` / `("none")`: `feature=()`
- `("*")`: `feature=*`
- a list of origins: `feature=(self "https://a.example.com")`. `"self"` and `"src"` are not quoted.

## Note

- Ported from Hono's `secureHeaders`. Headers are set after the app runs and replace any value the app set.
- In Hono, the `NONCE` handler constant becomes the `:nonce` keyword, and `c.get('secureHeadersNonce')` becomes `(secure-headers-nonce env)`.
- Hono sends an empty `Content-Security-Policy` header when the policy is `{}`. Here an empty plist is the same as `nil`, so no header is sent.
- The nonce is made with `ironclad:random-data` instead of Web Crypto.
