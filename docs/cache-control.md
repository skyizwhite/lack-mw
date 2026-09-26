# cache-control middleware

This middleware sets a `Cache-Control` header on responses from an ordered list of rules. The first rule that matches wins; an optional default covers everything else. It has no Hono equivalent.

## Usage

A rule is a list `(matcher value &key status)`:

- `matcher` is a path prefix string (matched against `:path-info`) or a function of `(env response)` returning true when the rule applies.
- `value` is the Cache-Control string, or a function of `(env response)` returning one. A `nil` value sets nothing (and still stops the search).
- `:status` limits the rule to a list of response statuses. Without it the rule applies to any status.

Immutable versioned assets, `no-store` for everything else, and keep what the app set itself (e.g. a `/media/` handler):

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*cache-control*
                #:with-args))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *cache-control*
      :rules '(("/assets/" "public, max-age=31536000, immutable" :status (200)))
      :default "no-store")
    (:static :path "/assets/" :root #p"assets/")
    *raw-app*))
```

Assets only: immutable when the URL is versioned (`?v=...` or a font), revalidate otherwise, on 200 and 304, replacing any value the app set. Other paths are left alone:

```lisp
(defun versioned-asset-p (env res)
  (declare (ignore res))
  (let ((path (getf env :path-info))
        (query (or (getf env :query-string) "")))
    (and (uiop:string-prefix-p "/assets/" path)
         (or (uiop:string-prefix-p "v=" query)
             (uiop:string-prefix-p "/assets/fonts/" path)))))

(defparameter *app*
  (lack:builder
    (with-args *cache-control*
      :rules '((versioned-asset-p "public, max-age=31536000, immutable" :status (200 304))
               ("/assets/" "public, max-age=0, must-revalidate" :status (200 304)))
      :override t)
    (:static :path "/assets/" :root #p"assets/")
    *raw-app*))
```

## Options

| Option | Default | Description |
| --- | --- | --- |
| `:rules` | `nil` | Ordered list of rules, as above. |
| `:default` | `nil` | Value (string or function of `(env response)`) used when no rule matches. `nil` sets nothing. |
| `:override` | `nil` | When true, replaces a `Cache-Control` the app already set. By default such responses are left untouched and no rule is consulted. |

## Notes

- Matchers and value functions receive a copy of the env taken before the app is called, because the static middleware strips its prefix from `:path-info`. Install this middleware outside (before) `:static`.
- Delayed responses are handled; streaming responses get the header too.
- The matcher in a rule can be a symbol naming a function, since it is called with `funcall`.
