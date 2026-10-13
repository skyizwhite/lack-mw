(defpackage #:lack-mw/trailing-slash
  (:use #:cl)
  (:export #:*mw-trim-trailing-slash*
           #:*mw-append-trailing-slash*))
(in-package #:lack-mw/trailing-slash)

(defun last-string (str)
  (subseq str (- (length str) 1)))

(defun split-request-uri (request-uri)
  (let ((query-start (position #\? request-uri)))
    (values (subseq request-uri 0 query-start)
            (and query-start (subseq request-uri query-start)))))

(defun local-path-p (path)
  (and (plusp (length path))
       (let ((next (find-if-not (lambda (c) (member c '(#\Tab #\Linefeed #\Return)))
                                path :start 1)))
         (not (member next '(#\/ #\\))))))

(defparameter *mw-trim-trailing-slash*
  (lambda (app)
    (lambda (env)
      (multiple-value-bind (req-path req-query)
          (split-request-uri (getf env :request-uri))
        (let* ((req-method (getf env :request-method))
               (response (funcall app env))
               (res-status (first response)))
          (let ((location (and (= res-status 404)
                               (eq req-method :get)
                               (not (string= req-path "/"))
                               (string= (last-string req-path) "/")
                               (concatenate 'string
                                            (string-right-trim "/" req-path)
                                            req-query))))
            (if (and location (local-path-p location))
                `(301 (:location ,location) ())
                response)))))))

(defparameter *mw-append-trailing-slash*
  (lambda (app)
    (lambda (env)
      (multiple-value-bind (req-path req-query)
          (split-request-uri (getf env :request-uri))
        (let* ((req-method (getf env :request-method))
               (response (funcall app env))
               (res-status (first response)))
          (let ((location (and (= res-status 404)
                               (eq req-method :get)
                               (not (string= (last-string req-path) "/"))
                               (concatenate 'string req-path "/" req-query))))
            (if (and location (local-path-p location))
                `(301 (:location ,location) ())
                response)))))))
