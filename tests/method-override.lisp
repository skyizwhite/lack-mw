(defpackage #:lack-mw-test/method-override
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack/request
                #:make-request
                #:request-method
                #:request-body-parameters
                #:request-query-parameters
                #:request-content)
  (:import-from #:babel)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/method-override
                #:*method-override*))
(in-package #:lack-mw-test/method-override)

(defun describe-app (env)
  "Answers \"<METHOD> <message field> <_method field>\", or 404 for PATCH."
  (let* ((req (make-request env))
         (params (request-body-parameters req)))
    (if (eq (request-method req) :patch)
        (list 404 nil (list "Not Found"))
        (list 200 (list :content-type "text/plain")
              (list (format nil "~a ~a ~a"
                            (request-method req)
                            (cdr (assoc "message" params :test #'string=))
                            (or (cdr (assoc "_method" params :test #'string=))
                                (cdr (assoc "custom-input-name" params :test #'string=)))))))))

(defun multipart (fields)
  (format nil "~{--XyZ~c~cContent-Disposition: form-data; name=\"~a\"~c~c~c~c~a~c~c~}--XyZ--~c~c"
          (loop for (k . v) in fields
                append (list #\Return #\Newline k #\Return #\Newline #\Return #\Newline
                             v #\Return #\Newline))
          #\Return #\Newline))

(defun post (app uri &key content content-type headers (method :post))
  (testing-app app
    (multiple-value-bind (body status)
        (request uri :method method :content content
                     :headers (append (and content-type `(("content-type" . ,content-type)))
                                      headers))
      (values status body))))

(deftest form
  (let ((app (lack:builder *method-override* #'describe-app))
        (custom (lack:builder (with-args *method-override* :form "custom-input-name")
                              #'describe-app)))
    (testing "multipart/form-data"
      (multiple-value-bind (status body)
          (post app "/posts" :content (multipart '(("message" . "Hello") ("_method" . "DELETE")))
                             :content-type "multipart/form-data; boundary=XyZ")
        (ok (= status 200))
        (ok (string= body "DELETE Hello NIL")))
      (multiple-value-bind (status body)
          (post custom "/posts-custom"
                :content (multipart '(("message" . "Hello") ("custom-input-name" . "DELETE")))
                :content-type "multipart/form-data; boundary=XyZ")
        (ok (= status 200))
        (ok (string= body "DELETE Hello NIL")))
      (ok (= (post app "/posts" :content (multipart '(("message" . "Hello") ("_method" . "PATCH")))
                                :content-type "multipart/form-data; boundary=XyZ")
             404)))

    (testing "application/x-www-form-urlencoded"
      (multiple-value-bind (status body)
          (post app "/posts" :content "message=Hello&_method=DELETE"
                             :content-type "application/x-www-form-urlencoded")
        (ok (= status 200))
        (ok (string= body "DELETE Hello NIL")))
      (multiple-value-bind (status body)
          (post custom "/posts-custom" :content "message=Hello&custom-input-name=DELETE"
                                       :content-type "application/x-www-form-urlencoded")
        (ok (= status 200))
        (ok (string= body "DELETE Hello NIL")))
      (multiple-value-bind (status body)
          (post app "/posts" :content "message=Hello&_method=DELETE"
                             :content-type "application/x-www-form-urlencoded;charset=UTF-8")
        (ok (= status 200))
        (ok (string= body "DELETE Hello NIL")))
      (ok (= (post app "/posts" :content "message=Hello&_method=PATCH"
                                :content-type "application/x-www-form-urlencoded")
             404)))

    (testing "body stays readable downstream"
      (let ((app (lack:builder *method-override*
                               (lambda (env)
                                 (list 200 nil
                                       (list (babel:octets-to-string
                                              (request-content (make-request env)))))))))
        (multiple-value-bind (status body)
            (post app "/posts" :content "message=Hello&_method=DELETE"
                               :content-type "application/x-www-form-urlencoded")
          (ok (= status 200))
          (ok (string= body "message=Hello&_method=DELETE")))))

    (testing "no override without the field, or for unknown methods"
      (multiple-value-bind (status body)
          (post app "/posts" :content "message=Hello"
                             :content-type "application/x-www-form-urlencoded")
        (ok (= status 200))
        (ok (string= body "POST Hello NIL")))
      (multiple-value-bind (status body)
          (post app "/posts" :content "message=Hello&_method=NO-SUCH-METHOD-XYZZY"
                             :content-type "application/x-www-form-urlencoded")
        (ok (= status 200))
        (ok (string= body "POST Hello NO-SUCH-METHOD-XYZZY"))))))

(defun header-app (env)
  (list 200 nil (list (format nil "~a ~a"
                              (getf env :request-method)
                              (gethash "x-method-override" (getf env :headers))))))

(deftest header
  (let ((app (lack:builder (with-args *method-override* :header "X-METHOD-OVERRIDE")
                           #'header-app)))
    (testing "Should override POST to DELETE"
      (multiple-value-bind (status body)
          (post app "/posts" :headers '(("X-METHOD-OVERRIDE" . "DELETE")))
        (ok (= status 200))
        (ok (string= body "DELETE NIL"))))
    (testing "Should not override GET request"
      (multiple-value-bind (status body)
          (post app "/posts" :method :get :headers '(("X-METHOD-OVERRIDE" . "DELETE")))
        (ok (= status 200))
        (ok (string= body "GET DELETE"))))))

(defun query-app (env)
  (let ((req (make-request env)))
    (list 200 nil (list (format nil "~a ~a ~a ~a"
                                (request-method req)
                                (cdr (assoc "_method" (request-query-parameters req)
                                            :test #'string=))
                                (getf env :request-uri)
                                (babel:octets-to-string (request-content req)))))))

(deftest query
  (let ((app (lack:builder (with-args *method-override* :query "_method") #'query-app)))
    (testing "Should override POST to DELETE"
      (multiple-value-bind (status body) (post app "/posts?_method=delete&a=1")
        (ok (= status 200))
        (ok (string= body "DELETE NIL /posts?a=1 "))))
    (testing "Should override POST to DELETE when the request has a body"
      (multiple-value-bind (status body)
          (post app "/posts?_method=delete" :content "message=Hello"
                                            :content-type "application/x-www-form-urlencoded")
        (ok (= status 200))
        (ok (string= body "DELETE NIL /posts message=Hello"))))
    (testing "Should not override GET request"
      (multiple-value-bind (status body) (post app "/posts?_method=delete" :method :get)
        (ok (= status 200))
        (ok (string= body "GET delete /posts?_method=delete "))))))
