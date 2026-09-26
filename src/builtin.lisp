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
  (:export #:*accesslog*
           #:*time-format*
           #:default-formatter
           #:*basic-auth*
           #:*backtrace*
           #:*session-csrf*
           #:csrf-token
           #:csrf-html-tag
           #:*mount*
           #:*session*
           #:make-cookie-state
           #:make-memory-store
           #:*static*
           #:*when*))
(in-package #:lack-mw/builtin)

;;; Lack's built-in middlewares under shorter names. Each looks the original up on
;;; every call, so redefining it in Lack is picked up here.

(defparameter *accesslog* (with-args '*lack-middleware-accesslog*))
(defparameter *basic-auth* (with-args '*lack-middleware-auth-basic*))
(defparameter *backtrace* (with-args '*lack-middleware-backtrace*))
;; token based, kept apart from lack-mw's Origin based *csrf*
(defparameter *session-csrf* (with-args '*lack-middleware-csrf*))
(defparameter *mount* (with-args '*lack-middleware-mount*))
(defparameter *session* (with-args '*lack-middleware-session*))
(defparameter *static* (with-args '*lack-middleware-static*))
(defparameter *when* (with-args '*lack-middleware-when*))
