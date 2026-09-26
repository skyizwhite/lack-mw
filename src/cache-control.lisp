(defpackage #:lack-mw/cache-control
  (:use #:cl)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:export #:*cache-control*))
(in-package #:lack-mw/cache-control)

(defun prefix-p (prefix path)
  (and (stringp path)
       (>= (length path) (length prefix))
       (string= prefix path :end2 (length prefix))))

(defun resolve (value env res)
  (if (functionp value) (funcall value env res) value))

(defun rule-value (rule env res)
  "The Cache-Control value RULE gives, and whether it matched."
  (destructuring-bind (matcher value &key status) rule
    (if (and (or (null status) (member (first res) status))
             (if (stringp matcher)
                 (prefix-p matcher (getf env :path-info))
                 (funcall matcher env res)))
        (values (resolve value env res) t)
        (values nil nil))))

(defun cache-control-value (rules default env res)
  (dolist (rule rules (resolve default env res))
    (multiple-value-bind (value matched) (rule-value rule env res)
      (when matched (return value)))))

(defparameter *cache-control*
  (lambda (app &key rules default override)
    (lambda (env)
      ;; a copy taken before the call: the static middleware strips its prefix from path-info
      (let ((request-env (copy-list env)))
        (funcall-with-cb
         app env
         (lambda (res)
           (let ((headers (second res)))
             (if (and (getf headers :cache-control) (not override))
                 res
                 (let ((value (cache-control-value rules default request-env res)))
                   (if value
                       (list* (first res)
                              (list* :cache-control value
                                     (loop :for (key val) :on headers :by #'cddr
                                           :unless (eq key :cache-control)
                                             :append (list key val)))
                              (cddr res))
                       res)))))))))
  "Sets Cache-Control on responses from an ordered list of rules; the first that
matches wins. A rule is (MATCHER VALUE &key STATUS): MATCHER is a path prefix string
or a function of (ENV RESPONSE), VALUE a string or a function of (ENV RESPONSE)
returning one (NIL sets nothing), STATUS a list of statuses the rule is limited to.
Options: :RULES, :DEFAULT (value when no rule matches), :OVERRIDE (replace a
Cache-Control the app already set).")
