(defpackage #:lack-mw/temporary-file
  (:use #:cl)
  (:export #:*temporary-file*
           #:+temporary-file-header+))
(in-package #:lack-mw/temporary-file)

(defparameter +temporary-file-header+ :x-lack-mw-temporary-file
  "Default response header marking a pathname body to delete once it is sent.")

(defun without-header (headers header)
  (loop :for (key val) :on headers :by #'cddr
        :unless (eq key header) :append (list key val)))

(defparameter *temporary-file*
  (lambda (app &key (header +temporary-file-header+))
    (flet ((respond (res responder)
             (if (and (consp res) (getf (second res) header))
                 (destructuring-bind (status headers &rest body) res
                   (let ((res (list* status (without-header headers header) body)))
                     (if (and body (pathnamep (first body)))
                         (unwind-protect (funcall responder res)
                           (uiop:delete-file-if-exists (first body)))
                         (funcall responder res))))
                 (funcall responder res))))
      (lambda (env)
        (let ((res (funcall app env)))
          (cond
            ((functionp res)
             (lambda (responder)
               (funcall res (lambda (r) (respond r responder)))))
            ((and (consp res) (getf (second res) header))
             (lambda (responder) (respond res responder)))
            (t res))))))
  "Deletes the pathname body of a response marked with the :HEADER header (default
+TEMPORARY-FILE-HEADER+) once the responder returns, and strips the header. Marked
responses are turned into delayed ones, so install this outside middlewares that
read responses as lists.")
