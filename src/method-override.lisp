(defpackage #:lack-mw/method-override
  (:use #:cl)
  (:import-from #:alexandria
                #:copy-hash-table
                #:starts-with-subseq)
  (:import-from #:quri)
  (:import-from #:lack/request
                #:make-request
                #:request-body-parameters)
  (:export #:*mw-method-override*))
(in-package #:lack-mw/method-override)

(defun method-keyword (name)
  ;; FIND-SYMBOL rather than INTERN: a method no one routes on has no keyword,
  ;; and interning arbitrary client input would grow the keyword package
  (and (stringp name)
       (plusp (length name))
       (find-symbol (string-upcase name) :keyword)))

(defun remove-param (name params)
  (remove name params :key #'car :test #'equal))

(defun override-by-form (env name)
  (let ((content-type (or (getf env :content-type) "")))
    (when (or (starts-with-subseq "multipart/form-data" content-type)
              (starts-with-subseq "application/x-www-form-urlencoded" content-type))
      ;; lack/request parses the body, rewinds :raw-body and caches the
      ;; parameters in env for the requests made downstream
      (let* ((params (request-body-parameters (make-request env)))
             (method (method-keyword (cdr (assoc name params :test #'equal)))))
        (when method
          (list* :request-method method
                 :body-parameters (remove-param name params)
                 env))))))

(defun override-by-header (env name)
  (let* ((name (string-downcase name))
         (method (method-keyword (gethash name (getf env :headers)))))
    (when method
      (let ((headers (copy-hash-table (getf env :headers))))
        (remhash name headers)
        (list* :request-method method :headers headers env)))))

(defun override-by-query (env name)
  (let* ((query (getf env :query-string))
         (params (and query (quri:url-decode-params query :lenient t)))
         (method (method-keyword (cdr (assoc name params :test #'equal)))))
    (when method
      (let* ((rest (remove-param name params))
             (new-query (and rest (quri:url-encode-params rest)))
             (uri (getf env :request-uri))
             (path (subseq uri 0 (position #\? uri))))
        (list* :request-method method
               :query-string new-query
               :query-parameters rest
               :request-uri (format nil "~a~@[?~a~]" path new-query)
               env)))))

(defparameter *mw-method-override*
  (lambda (app &key form header query)
    (lambda (env)
      (funcall app
               (or (and (not (eq (getf env :request-method) :get))
                        (cond (header (override-by-header env header))
                              (query (override-by-query env query))
                              (t (override-by-form env (or form "_method")))))
                   env))))
  "Overrides the request method (except for GET) by a form field (:form, default
\"_method\"), a header (:header) or a query parameter (:query). The field,
header or parameter used is removed from what the app sees.")
