(defpackage #:lack-mw/csrf
  (:use #:cl)
  (:import-from #:cl-ppcre)
  (:export #:*mw-csrf*))
(in-package #:lack-mw/csrf)

(defparameter +sec-fetch-site-values+ '("same-origin" "same-site" "none" "cross-site"))

(defparameter +form-content-type-re+
  (ppcre:create-scanner
   "^\\b(application/x-www-form-urlencoded|multipart/form-data|text/plain)\\b"
   :case-insensitive-mode t))

(defun request-origin (env)
  "The origin of the request URL, e.g. \"http://localhost:8080\"."
  (let* ((scheme (string-downcase (string (or (getf env :url-scheme) "http"))))
         (host (or (gethash "host" (getf env :headers))
                   (let ((name (getf env :server-name))
                         (port (getf env :server-port)))
                     (if (or (null port)
                             (and (string= scheme "http") (eql port 80))
                             (and (string= scheme "https") (eql port 443)))
                         name
                         (format nil "~a:~a" name port))))))
    (format nil "~a://~a" scheme host)))

(defun matcher (option default)
  "Turns a string / list of strings / function (value env) option into a predicate."
  (cond ((null option) default)
        ((stringp option) (lambda (value env)
                            (declare (ignore env))
                            (string= value option)))
        ((functionp option) option)
        (t (lambda (value env)
             (declare (ignore env))
             (member value option :test #'string=)))))

(defparameter *mw-csrf*
  (lambda (app &key origin sec-fetch-site)
    (let ((origin-p (matcher origin
                             (lambda (value env) (string= value (request-origin env)))))
          (sec-fetch-site-p (matcher sec-fetch-site
                                     (lambda (value env)
                                       (declare (ignore env))
                                       (string= value "same-origin")))))
      (lambda (env)
        (let* ((headers (getf env :headers))
               (content-type (or (gethash "content-type" headers)
                                 (getf env :content-type)
                                 "text/plain"))
               (req-origin (gethash "origin" headers))
               (req-sec-fetch-site (gethash "sec-fetch-site" headers)))
          (if (and (not (member (getf env :request-method) '(:get :head :options)))
                   (ppcre:scan +form-content-type-re+ content-type)
                   (not (and req-sec-fetch-site
                             (member req-sec-fetch-site +sec-fetch-site-values+
                                     :test #'string=)
                             (funcall sec-fetch-site-p req-sec-fetch-site env)))
                   (not (and req-origin
                             (funcall origin-p req-origin env))))
              (list 403 (list :content-type "text/plain; charset=utf-8") (list "Forbidden"))
              (funcall app env))))))
  "CSRF protection by the Origin and Sec-Fetch-Site headers. A non-safe request
whose Content-Type a form can send is rejected with 403 unless either header is
allowed. Options: :origin (a string, a list of strings, or a function (origin env);
default: the request URL's origin) and :sec-fetch-site (a string, a list of strings,
or a function (value env); default: \"same-origin\").")
