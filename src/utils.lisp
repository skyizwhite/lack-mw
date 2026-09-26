(defpackage #:lack-mw/utils
  (:use #:cl)
  (:export #:with-args))
(in-package #:lack-mw/utils)

(defun with-args (mw &rest args)
  "Return a middleware that calls MW with ARGS. MW may be a symbol, whose value is
looked up on every call. Arguments given to the returned middleware come first,
so they override ARGS."
  (lambda (app &rest more)
    (apply (if (symbolp mw) (symbol-value mw) mw) app (append more args))))
