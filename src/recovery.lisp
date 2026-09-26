(defpackage #:lack-mw/recovery
  (:use #:cl)
  (:import-from #:lack-mw/helpers/escape
                #:escape-html
                #:escape-json)
  (:export #:*recovery*))
(in-package #:lack-mw/recovery)

(defun content-type (format)
  (ecase format
    (:html "text/html; charset=utf-8")
    (:json "application/json; charset=utf-8")
    (:text "text/plain; charset=utf-8")))

(defun safe-princ (object)
  ;; bounded, so a condition holding a circular or huge structure still prints
  (handler-case (let ((*print-readably* nil)
                      (*print-circle* t)
                      (*print-length* 50)
                      (*print-level* 5))
                  (princ-to-string object))
    (error () "#<error printing object>")))

(defun backtrace-string (condition)
  (with-output-to-string (s)
    (uiop:print-backtrace :stream s :condition condition)))

(defun default-logger (condition backtrace env)
  (format *error-output* "~&[recovery] ~A ~A: ~A~%~A~&"
          (getf env :request-method) (getf env :request-uri)
          (safe-princ condition) backtrace))

(defun render-body (format dev-mode condition backtrace)
  (let ((type (prin1-to-string (type-of condition)))
        (detail (safe-princ condition)))
    (ecase format
      (:html
       (format nil "<!DOCTYPE html>
<html><head><meta charset=\"utf-8\"><title>500 Internal Server Error</title></head>
<body><h1>Internal Server Error</h1>~@[~A~]</body></html>
"
               (and dev-mode
                    (format nil "
<h2>~A</h2>
<pre>~A</pre>
<h2>Backtrace</h2>
<pre>~A</pre>
"
                            (escape-html type) (escape-html detail) (escape-html backtrace)))))
      (:json
       (if dev-mode
           (format nil "{\"error\":{\"message\":\"Internal Server Error\",\"type\":\"~A\",\"detail\":\"~A\",\"backtrace\":\"~A\"}}"
                   (escape-json type) (escape-json detail) (escape-json backtrace))
           "{\"error\":{\"message\":\"Internal Server Error\"}}"))
      (:text
       (if dev-mode
           (format nil "Internal Server Error~%~%~A: ~A~%~%~A" type detail backtrace)
           "Internal Server Error")))))

(defun call-with-recovery (thunk handle)
  "Calls THUNK. If an error is left unhandled by THUNK, captures its backtrace,
unwinds and returns the result of calling HANDLE with the condition and it."
  (multiple-value-bind (condition backtrace)
      (block caught
        (handler-bind ((error (lambda (c)
                                (return-from caught (values c (backtrace-string c))))))
          (return-from call-with-recovery (funcall thunk))))
    (funcall handle condition backtrace)))

(defparameter *recovery*
  (lambda (app &key (format :html) dev-mode (logger #'default-logger) on-error)
    (check-type format (member :html :json :text))
    (labels ((log-error (condition backtrace env)
               (when logger
                 (handler-case (funcall logger condition backtrace env)
                   (error () nil))))
             (error-response (condition backtrace env)
               (log-error condition backtrace env)
               ;; A failing :on-error or renderer falls back to a static response
               (handler-case
                   (if on-error
                       (funcall on-error condition env)
                       (list 500 (list :content-type (content-type format))
                             (list (render-body format dev-mode condition backtrace))))
                 (error ()
                   '(500 (:content-type "text/plain; charset=utf-8")
                     ("Internal Server Error"))))))
      (lambda (env)
        (let ((response (call-with-recovery
                         (lambda () (funcall app env))
                         (lambda (c bt) (error-response c bt env)))))
          (if (functionp response)
              (lambda (responder)
                (let ((started nil))
                  (call-with-recovery
                   (lambda ()
                     (funcall response (lambda (r)
                                         (setf started t)
                                         (funcall responder r))))
                   (lambda (c bt)
                     (cond
                       ;; Too late for a 500: log and let the server handle it
                       (started (log-error c bt env)
                                (error c))
                       (t (let ((answer (error-response c bt env)))
                            ;; the responder may fail too, e.g. on a closed connection:
                            ;; nothing more can be sent then
                            (handler-case (if (functionp answer)
                                              (funcall answer responder)
                                              (funcall responder answer))
                              (error (e) (log-error e "" env))))))))))
              response)))))
  "The last line of defense: catches any error left unhandled further in, and
answers 500. :FORMAT is :HTML (default), :JSON or :TEXT. With :DEV-MODE true,
the body also shows the condition's type, message and backtrace; never enable
it in production. :LOGGER, a function of (condition backtrace env), is called
for each caught error (default: writes to *ERROR-OUTPUT*; NIL disables it).
:ON-ERROR, a function of (condition env), returns a response replacing the
built-in one.")
