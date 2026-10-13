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
  (let ((next (find-if-not (lambda (c) (member c '(#\Tab #\Linefeed #\Return)))
                           path :start 1)))
    (not (member next '(#\/ #\\)))))

(defparameter *mw-trim-trailing-slash*
  (lambda (app)
    (lambda (env)
      (multiple-value-bind (req-path req-query)
          (split-request-uri (getf env :request-uri))
        (let* ((req-method (getf env :request-method))
               (response (funcall app env))
               (res-status (first response)))
          (if (and (= res-status 404)
                   (eq req-method :get)
                   (local-path-p req-path)
                   (not (string= req-path "/"))
                   (string= (last-string req-path) "/"))
              `(301 (:location ,(concatenate 'string
                                             (string-right-trim "/" req-path)
                                             req-query))
                    ())
              response))))))

(defparameter *mw-append-trailing-slash*
  (lambda (app)
    (lambda (env)
      (multiple-value-bind (req-path req-query)
          (split-request-uri (getf env :request-uri))
        (let* ((req-method (getf env :request-method))
               (response (funcall app env))
               (res-status (first response)))
          (if (and (= res-status 404)
                   (eq req-method :get)
                   (local-path-p req-path)
                   (not (string= (last-string req-path) "/")))
              `(301 (:location ,(concatenate 'string req-path "/" req-query)) ())
              response))))))
