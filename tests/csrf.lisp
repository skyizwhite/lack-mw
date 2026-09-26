(defpackage #:lack-mw-test/csrf
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:alexandria)
  (:import-from #:cl-ppcre)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack/request
                #:make-request
                #:request-body-parameters)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/csrf
                #:*mw-csrf*))
(in-package #:lack-mw-test/csrf)

(defvar *called* nil)

(defun post-app (env)
  (setf *called* t)
  (let ((name (cdr (assoc "name" (request-body-parameters (make-request env))
                          :test #'string=))))
    (list 200 (list :content-type "text/plain") (list (if name (format nil "~a" name) "OK")))))

(defun post (app uri &key origin sec-fetch-site
                          (content-type "application/x-www-form-urlencoded")
                          (method :post) (content "name=hono"))
  "Returns (values status body called-p)."
  (setf *called* nil)
  (testing-app app
    (multiple-value-bind (body status)
        (request uri
                 :method method
                 :content content
                 :headers (append (and content-type `(("content-type" . ,content-type)))
                                  (and origin `(("origin" . ,origin)))
                                  (and sec-fetch-site `(("sec-fetch-site" . ,sec-fetch-site)))))
      (values status body *called*))))

(defun ends-with-example-com-p (origin env)
  (declare (ignore env))
  (and (ppcre:scan "^https://(\\w+\\.)?example\\.com$" origin) t))

(deftest simple-usage
  (let ((app (lack:builder *mw-csrf* #'post-app)))
    (testing "safe methods are always allowed"
      (dolist (method '(:get :head :options))
        (ok (= (post app "http://localhost/form" :method method :content nil) 200))))

    (testing "POST for local request"
      (multiple-value-bind (status body)
          (post app "http://localhost/form" :origin "http://localhost")
        (ok (= status 200))
        (ok (string= body "hono"))))

    (testing "403 for form content types from cross origin"
      (dolist (ct '("application/x-www-form-urlencoded" "multipart/form-data" "text/plain"
                    "Application/x-www-form-urlencoded"))
        (multiple-value-bind (status body called)
            (post app "http://localhost/form" :origin "http://example.com" :content-type ct)
          (ok (= status 403))
          (ok (string= body "Forbidden"))
          (ng called))))

    (testing "403 if request has no origin header"
      (multiple-value-bind (status body called) (post app "http://localhost/form")
        (declare (ignore body))
        (ok (= status 403))
        (ng called)))

    (testing "200 for application/json"
      (ok (= (post app "http://localhost/form"
                   :origin "http://example.com"
                   :content-type "application/json"
                   :content "{\"name\":\"hono\"}")
             200)))

    (testing "403 for other unsafe methods"
      (dolist (method '(:put :delete :patch))
        (ok (= (post app "http://localhost/form" :method method :origin "http://example.com")
               403))))

    (testing "403 if the content-type is not set"
      (let ((env (lack/test:generate-env "/form" :method :post :content "test")))
        (remhash "content-type" (getf env :headers))
        (setf (getf env :content-type) nil)
        (setf *called* nil)
        (ok (= (first (funcall app env)) 403))
        (ng *called*)))

    (testing "default origin is taken from the Host header, port included"
      (flet ((status (origin)
               (let ((env (lack/test:generate-env "/form" :method :post :content "name=hono"
                                                          :headers `(("host" . "localhost:8080")
                                                                     ("origin" . ,origin)))))
                 (first (funcall app env)))))
        (ok (= (status "http://localhost:8080") 200))
        (ok (= (status "http://localhost") 403))))
    (testing "without a Host header the server name and port are used"
      (let ((env (lack/test:generate-env "http://localhost:8080/form"
                                         :method :post :content "name=hono"
                                         :headers '(("origin" . "http://localhost:8080")))))
        (remhash "host" (getf env :headers))
        (ok (= (first (funcall app env)) 200))))))

(deftest origin-option
  (testing "string"
    (let ((app (lack:builder (with-args *mw-csrf* :origin "https://example.com") #'post-app)))
      (ok (= (post app "https://example.com/form" :origin "https://example.com") 200))
      (multiple-value-bind (status body called)
          (post app "https://example.jp/form" :origin "https://example.jp")
        (declare (ignore body))
        (ok (= status 403))
        (ng called))))

  (testing "list"
    (let ((app (lack:builder
                (with-args *mw-csrf* :origin '("https://example.com" "https://hono.example.com"))
                #'post-app)))
      (ok (= (post app "https://hono.example.com/form" :origin "https://hono.example.com") 200))
      (ok (= (post app "https://example.com/form" :origin "https://example.com") 200))
      (ok (= (post app "http://example.jp/form" :origin "http://example.jp") 403))))

  (testing "function"
    (let ((app (lack:builder (with-args *mw-csrf* :origin #'ends-with-example-com-p) #'post-app)))
      (ok (= (post app "https://hono.example.com/form" :origin "https://hono.example.com") 200))
      (ok (= (post app "https://example.com/form" :origin "https://example.com") 200))
      (ok (= (post app "http://honojs.hono.example.jp/form" :origin "http://example.jp") 403))
      (ok (= (post app "http://example.jp/form" :origin "http://example.jp") 403)))))

(deftest sec-fetch-site-option
  (testing "string"
    (let ((app (lack:builder (with-args *mw-csrf* :sec-fetch-site "same-origin") #'post-app)))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "same-origin") 200))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "cross-site") 403))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "any") 403))))

  (testing "default allows same-origin"
    (let ((app (lack:builder *mw-csrf* #'post-app)))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "same-origin") 200))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "same-site") 403))))

  (testing "list"
    (let ((app (lack:builder (with-args *mw-csrf* :sec-fetch-site '("same-origin" "none"))
                             #'post-app)))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "same-origin") 200))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "none") 200))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "cross-site") 403))))

  (testing "function"
    (let ((app (lack:builder
                (with-args *mw-csrf*
                  :sec-fetch-site (lambda (value env)
                                    (or (string= value "same-origin")
                                        (alexandria:starts-with-subseq
                                         "/webhook/" (getf env :path-info)))))
                #'post-app)))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "same-origin") 200))
      (ok (= (post app "http://localhost/webhook/test" :sec-fetch-site "cross-site") 200))
      (ok (= (post app "http://localhost/form" :sec-fetch-site "cross-site") 403)))))
