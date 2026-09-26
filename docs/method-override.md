# method-override middleware

This middleware lets a request override its method (other than `GET`) by a form field, a header or a query parameter, so that an HTML form can send `DELETE`, `PUT` and so on.

## Usage

By default the `_method` form field is used:

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:ningle)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:*method-override*
                #:with-args))
(in-package #:app/main)

(defparameter *raw-app* (make-instance 'ningle:app))
(setf (ningle:route *raw-app* "/posts/:id" :method :delete)
      "Deleted")

;; <form action="/posts/1" method="POST">
;;   <input type="hidden" name="_method" value="DELETE" />
;; </form>
(defparameter *app*
  (lack:builder
    *method-override*
    *raw-app*))
```

Other sources:

```lisp
(with-args *method-override* :form "custom-input-name")
(with-args *method-override* :header "X-HTTP-Method-Override")
(with-args *method-override* :query "_method")   ; POST /posts/1?_method=DELETE
```

## Options

| Keyword | Default | Description |
|---|---|---|
| `:form` | `"_method"` | Form field holding the method. Used when neither `:header` nor `:query` is given. |
| `:header` | `nil` | Header holding the method. |
| `:query` | `nil` | Query parameter holding the method. |

## Note

- `GET` requests are never overridden. The value is case-insensitive (`delete` gives `:delete`).
- The field, header or query parameter used is removed from what the app sees: from `:body-parameters`, from `:headers` (a copy), or from `:query-string`, `:query-parameters` and `:request-uri`.
- Form: `application/x-www-form-urlencoded` and `multipart/form-data` bodies are parsed with `lack/request`, which caches the parameters in `:body-parameters` and rewinds `:raw-body`, so the app can still read the body. The raw body itself is left as sent (it still contains the field); only the parsed parameters have it removed.
- Only methods that exist as keywords are accepted (the value is looked up with `find-symbol`, never interned, so clients cannot grow the keyword package). Any method a router routes on exists as a keyword; other values leave the request unchanged.
- Differences from Hono: Hono takes the `app` and re-dispatches a new request through it (running its middleware again). Here the modified env is passed to the next app instead, so no `app` option is needed. Hono rebuilds the body without the field; here only the parsed parameters change.
