# language middleware

This middleware detects the user's preferred language from the query string, cookie, `Accept-Language` header and/or URL path, and stores it in the Lack env.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*mw-language*
                #:language))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *mw-language*
      :supported-languages '("en" "ja") ; must include the fallback language
      :fallback-language "en")
    (lambda (env)
      `(200 (:content-type "text/plain")
            (,(format nil "Current language: ~a" (language env)))))))
```

`(language env)` returns the detected language (the `:lack-mw.language` key in env). It is always one of `:supported-languages`, exactly as written there.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `:order` | `'(:querystring :cookie :header)` | Detection strategies in order. Any of `:querystring`, `:cookie`, `:header`, `:path`. |
| `:lookup-query-string` | `"lang"` | Query parameter name. |
| `:lookup-cookie` | `"language"` | Cookie name (for detection and caching). |
| `:lookup-from-header-key` | `"accept-language"` | Header parsed as an `Accept-Language` list (sorted by `q`; `q=0` entries are ignored). |
| `:lookup-from-path-index` | `0` | Index of the path segment holding the language (`/ja/page` → `"ja"`). |
| `:caches` | `'(:cookie)` | Where to cache a detected language. `'(:cookie)` or `nil`. |
| `:cookie-options` | `'(:same-site "Strict" :secure t :max-age 31536000 :http-only t)` | Cookie attributes, merged over the defaults. Keys: `:domain`, `:path` (default `"/"`), `:same-site`, `:secure`, `:max-age`, `:http-only`. |
| `:ignore-case` | `t` | Compare language codes case-insensitively. |
| `:fallback-language` | `"en"` | Language used when nothing is detected. Must be in `:supported-languages`. |
| `:supported-languages` | `'("en")` | Supported language codes. |
| `:convert-detected-language` | `nil` | Function transforming a detected code before matching (e.g. `"en-US"` → `"en"`). |
| `:debug` | `nil` | Log detection results to `*standard-output*` and errors to `*error-output*`. |

A detected code matches a supported one exactly, or by RFC 4647 lookup truncation (`zh-Hant-CN` → `zh-Hant` → `zh`, longest match wins).

## Notes

- The cookie is only set when a language was actually detected (not for the fallback), as a `Set-Cookie` header appended to the response.
- Invalid options (fallback not supported, negative path index, unknown detector, unknown cookie option) signal an error when the middleware is built.
- The `:path` detector reads the original `:request-uri`, so it still works when `:path-info` has been rewritten (e.g. by `lack/middleware/mount`).
- Errors inside a detector or `:convert-detected-language` are ignored and the next detector is tried; errors while building the cookie (e.g. an invalid cookie name) skip caching.
- Cookie parsing and serialization are small built-in helpers (no extra dependency). The cookie value is URL-encoded, like Hono's `setCookie`.
- Detectors are not exported as separate functions (Hono exports `detectFromQuery` etc.).
