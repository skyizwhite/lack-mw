# trailing-slash middleware

This middleware handles Trailing Slash in the URL on a GET request.

`append-trailing-slash` redirects the URL to which it added the Trailing Slash if the content was not found. Also, `trim-trailing-slash` will remove the Trailing Slash.

## Usage

Example of redirecting a GET request of `/about/me` to `/about/me/`.

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:ningle)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:append-trailing-slash))
(in-package #:app/main)

(defparameter *raw-app* (make-instance 'ningle:app))
(setf (ningle:route *raw-app* "/about/me/")
      "With Trailing Slash")

(defparameter *app*
  (lack:builder
    (append-trailing-slash)
    *raw-app*))
```

Example of redirecting a GET request of `/about/me/` to `/about/me`.

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:ningle)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:trim-trailing-slash))
(in-package #:app/main)

(defparameter *raw-app* (make-instance 'ningle:app))
(setf (ningle:route *raw-app* "/about/me")
      "Without Trailing Slash")

(defparameter *app*
  (lack:builder
    (trim-trailing-slash)
    *raw-app*))
```

## Note

It will be enabled when the request method is GET and the response status is `404`.
