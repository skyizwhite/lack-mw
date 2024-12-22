(defpackage #:lack-mw/trailing-slash
  (:use #:cl)
  (:import-from #:quri)
  (:export #:*trim-trailing-slash*
           #:*append-trailing-slash*))
(in-package #:lack-mw/trailing-slash)

(defun last-string (str)
  (subseq str (- (length str) 1)))

(defparameter *trim-trailing-slash*
  (lambda (app)
    (lambda (env)
      (let* ((req-uri (quri:uri (getf env :request-uri)))
             (req-path (quri:uri-path req-uri))
             (req-method (getf env :request-method))
             (response (funcall app env))
             (res-status (first response)))
        (if (and (= res-status 404)
                 (eq req-method :get)
                 (not (string= req-path "/"))
                 (string= (last-string req-path) "/"))
            (let ((red-uri (quri:copy-uri req-uri
                                          :path (string-right-trim "/" req-path))))
              `(301 (:location ,(quri:render-uri red-uri)) ()))
            response)))))

(defparameter *append-trailing-slash*
  (lambda (app)
    (lambda (env)
      (let* ((req-uri (quri:uri (getf env :request-uri)))
             (req-path (quri:uri-path req-uri))
             (req-method (getf env :request-method))
             (response (funcall app env))
             (res-status (first response)))
        (if (and (= res-status 404)
                 (eq req-method :get)
                 (not (string= (last-string req-path) "/")))
            (let ((red-uri (quri:copy-uri req-uri
                                          :path (concatenate 'string req-path "/"))))
              `(301 (:location ,(quri:render-uri red-uri)) ()))
            response)))))
