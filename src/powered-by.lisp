(defpackage #:lack-mw/powered-by
  (:use #:cl)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:export #:*mw-powered-by*))
(in-package #:lack-mw/powered-by)

(defparameter *mw-powered-by*
  (lambda (app &key (server-name "Lack"))
    (lambda (env)
      (funcall-with-cb
       app env
       (lambda (res)
         (destructuring-bind (status headers &rest body) res
           (list* status
                  (append (loop for (k v) on headers by #'cddr
                                unless (string-equal k "X-Powered-By")
                                  append (list k v))
                          (list :x-powered-by server-name))
                  body))))))
  "Middleware that sets the X-Powered-By response header (port of Hono's poweredBy).")
