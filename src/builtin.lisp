(defpackage #:lack-mw/builtin
  (:use #:cl)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack/middleware/accesslog
                #:*lack-middleware-accesslog*
                #:*time-format*
                #:default-formatter)
  (:import-from #:lack/middleware/auth/basic
                #:*lack-middleware-auth-basic*)
  (:import-from #:lack/middleware/backtrace
                #:*lack-middleware-backtrace*)
  (:import-from #:lack/middleware/csrf
                #:*lack-middleware-csrf*
                #:csrf-token
                #:csrf-html-tag)
  (:import-from #:lack/middleware/mount
                #:*lack-middleware-mount*)
  (:import-from #:lack/middleware/session
                #:*lack-middleware-session*)
  (:import-from #:lack/middleware/session/state/cookie
                #:make-cookie-state)
  (:import-from #:lack/middleware/session/store/memory
                #:make-memory-store)
  (:import-from #:lack/middleware/static
                #:*lack-middleware-static*)
  (:import-from #:lack/middleware/when
                #:*lack-middleware-when*)
  (:export #:*mw-accesslog*
           #:*time-format*
           #:default-formatter
           #:*mw-basic-auth*
           #:*mw-backtrace*
           #:*mw-session-csrf*
           #:csrf-token
           #:csrf-html-tag
           #:*mw-mount*
           #:*mw-session*
           #:make-cookie-state
           #:make-memory-store
           #:*mw-static*
           #:*mw-when*))
(in-package #:lack-mw/builtin)

;;; Lack's built-in middlewares under shorter names. Each looks the original up on
;;; every call, so redefining it in Lack is picked up here.

(defparameter *mw-accesslog* (with-args '*lack-middleware-accesslog*))
(defparameter *mw-basic-auth* (with-args '*lack-middleware-auth-basic*))
(defparameter *mw-backtrace* (with-args '*lack-middleware-backtrace*))
;; token based, kept apart from lack-mw's Origin based *mw-csrf*
(defparameter *mw-session-csrf* (with-args '*lack-middleware-csrf*))
(defparameter *mw-mount* (with-args '*lack-middleware-mount*))
(defparameter *mw-session* (with-args '*lack-middleware-session*))
(defparameter *mw-static* (with-args '*lack-middleware-static*))
(defparameter *mw-when* (with-args '*lack-middleware-when*))
