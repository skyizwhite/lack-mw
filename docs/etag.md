# etag middleware

This middleware adds an `ETag` header computed from the response body, and answers a conditional request whose `If-None-Match` matches with `304 Not Modified`.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:ningle)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*etag*
                #:+retained-304-headers+
                #:with-args))
(in-package #:app/main)

(defparameter *raw-app* (make-instance 'ningle:app))
(setf (ningle:route *raw-app* "/etag/abc")
      "Hono is hot")

(defparameter *app*
  (lack:builder
    *etag*
    *raw-app*))

;; weak tags, one more header on 304s, and SHA-256
(defparameter *app*
  (lack:builder
    (with-args *etag*
      :weak t
      :retained-headers (cons :x-message-retain +retained-304-headers+)
      :generate-digest (lambda (octets)
                         (ironclad:byte-array-to-hex-string
                          (ironclad:digest-sequence :sha256 octets))))
    *raw-app*))
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `:retained-headers` | `+retained-304-headers+` | Headers kept on a 304 response (keywords or strings, compared case-insensitively). The default is `(:cache-control :content-location :date :etag :expires :vary)`. |
| `:weak` | `nil` | When true, the tag is prefixed with `W/`. |
| `:generate-digest` | SHA-1 (ironclad) | Function of the body as an `(unsigned-byte 8)` vector, returning the tag's string (without quotes). Returning `nil`, or passing `nil` as the option, means no ETag is generated. |

## Notes

- Only GET, HEAD and QUERY requests with a 2xx response are handled. An `ETag` the app already set is kept and used for the comparison.
- `If-None-Match` is compared weakly: `W/` prefixes are ignored, the list is split on commas with surrounding whitespace trimmed, and `*` matches anything.
- The 304 response has an empty body and keeps only the retained headers (with `ETag` set).
- Bodies can be a list of strings (hashed as UTF-8), an octet vector, or a pathname (the file is read to hash it). An empty body gets no ETag, as in Hono.
- Delayed responses (`(lambda (responder) ...)`) are handled when the app responds with a full response; streaming responses (a response without a body, answered with a writer) pass through untouched.
- The default digest reproduces Hono's: the body is hashed in 256 KiB chunks, each over the previous digest followed by the chunk, so the tags equal Hono's for the same body (for bodies up to 256 KiB it is the plain SHA-1). A custom `:generate-digest` is called once with the whole body.
- Differences from Hono: `generate-digest` returns the hex string itself rather than an `ArrayBuffer`; there is no Web Crypto fallback check since ironclad is always available.
