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

(defparameter *mw-trim-trailing-slash*
  (lambda (app)
    (lambda (env)
      (redirect-on-not-found app env
                             (lambda (req-path)
                               (and (not (string= req-path "/"))
                                    (string= (last-string req-path) "/")
                                    (string-right-trim "/" req-path)))))))

(defparameter *mw-append-trailing-slash*
  (lambda (app)
    (lambda (env)
      (redirect-on-not-found app env
                             (lambda (req-path)
                               (and (not (string= (last-string req-path) "/"))
                                    (concatenate 'string req-path "/")))))))
