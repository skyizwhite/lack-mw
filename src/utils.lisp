(defpackage #:lack-mw/utils
  (:use #:cl)
  (:export #:with-args))
(in-package #:lack-mw/utils)

(defun with-args (mw &rest args)
  (lambda (app) (apply mw app args)))
