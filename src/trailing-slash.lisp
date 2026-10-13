(defpackage #:lack-mw/trailing-slash
  (:use #:cl)
  (:import-from #:lack-mw/helpers/url
                #:request-path)
  (:export #:*mw-trim-trailing-slash*
           #:*mw-append-trailing-slash*))
(in-package #:lack-mw/trailing-slash)

(defun last-string (str)
  (subseq str (- (length str) 1)))

(defun local-path-p (path)
  (and (plusp (length path))
       (char= (char path 0) #\/)
       (let ((next (find-if-not (lambda (c) (member c '(#\Tab #\Linefeed #\Return)))
                                path :start 1)))
         (not (member next '(#\/ #\\))))))

(defun redirect-on-not-found (app env rewrite-path)
  (let* ((req-method (getf env :request-method))
         (response (funcall app env))
         (res-status (first response))
         (red-path (and (= res-status 404)
                        (eq req-method :get)
                        (funcall rewrite-path (request-path env))))
         (location (and red-path
                        (format nil "~A~@[?~A~]" red-path (getf env :query-string)))))
    (if (local-path-p location)
        `(301 (:location ,location) ())
        response)))

(defun trim-path (path)
  (and (not (string= path "/"))
       (string= (last-string path) "/")
       (string-right-trim "/" path)))

(defun append-path (path)
  (and (not (string= (last-string path) "/"))
       (concatenate 'string path "/")))

(defparameter *mw-trim-trailing-slash*
  (lambda (app)
    (lambda (env)
      (redirect-on-not-found app env #'trim-path))))

(defparameter *mw-append-trailing-slash*
  (lambda (app)
    (lambda (env)
      (redirect-on-not-found app env #'append-path))))
