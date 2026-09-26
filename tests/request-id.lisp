(defpackage #:lack-mw-test/request-id
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:cl-ppcre)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/request-id
                #:*mw-request-id*
                #:request-id
                #:generate-uuid))
(in-package #:lack-mw-test/request-id)

(defparameter +uuid-v4+
  "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")

(defun uuid-p (str)
  (and str (cl-ppcre:scan +uuid-v4+ str) t))

(defun raw-app (env)
  `(200 (:content-type "text/plain") (,(or (request-id env) "No Request ID"))))

(defun app (&rest args)
  (lack:builder (apply #'with-args *mw-request-id* args) #'raw-app))

(deftest request-id
  (testing "should return random request id"
    (testing-app (app)
      (multiple-value-bind (body status headers) (request "/")
        (ok (eql status 200))
        (ok (uuid-p (gethash "x-request-id" headers)))
        (ok (string= body (gethash "x-request-id" headers)))
        (ok (uuid-p body)))))

  (testing "should return custom request id"
    (testing-app (app)
      (multiple-value-bind (body status headers)
          (request "/" :headers '(("x-request-id" . "hono-is-hot")))
        (ok (eql status 200))
        (ok (string= (gethash "x-request-id" headers) "hono-is-hot"))
        (ok (string= body "hono-is-hot")))))

  (testing "should return custom request id with all valid characters"
    (let ((valid "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_="))
      (testing-app (app)
        (multiple-value-bind (body status headers)
            (request "/" :headers `(("x-request-id" . ,valid)))
          (ok (eql status 200))
          (ok (string= (gethash "x-request-id" headers) valid))
          (ok (string= body valid))))))

  (testing "should return random request id when the header is invalid"
    (testing-app (app)
      (multiple-value-bind (body status headers)
          (request "/" :headers '(("x-request-id" . "Hello!12345-@*^")))
        (ok (eql status 200))
        (ok (uuid-p (gethash "x-request-id" headers)))
        (ok (uuid-p body)))))

  (testing "custom generator"
    (testing-app (app :generator (lambda (env) (declare (ignore env)) "HonoIsWebFramework"))
      (multiple-value-bind (body status headers) (request "/")
        (ok (eql status 200))
        (ok (string= (gethash "x-request-id" headers) "HonoIsWebFramework"))
        (ok (string= body "HonoIsWebFramework"))))
    (testing-app (app :generator (lambda (env)
                                   (let* ((h (getf env :headers))
                                          (a (gethash "hono-request-id" h))
                                          (b (gethash "ohno-request-id" h)))
                                     (if (and a b)
                                         (concatenate 'string a b)
                                         (generate-uuid)))))
      (multiple-value-bind (body status headers)
          (request "/" :headers '(("hono-request-id" . "Hello")
                                  ("ohno-request-id" . "World")))
        (ok (eql status 200))
        (ok (string= (gethash "x-request-id" headers) "HelloWorld"))
        (ok (string= body "HelloWorld")))))

  (testing "limit length"
    (let ((s255 (make-string 255 :initial-element #\h))
          (s256 (make-string 256 :initial-element #\h)))
      (testing-app (app)
        (multiple-value-bind (body status headers)
            (request "/" :headers `(("x-request-id" . ,s255)))
          (ok (eql status 200))
          (ok (string= (gethash "x-request-id" headers) s255))
          (ok (string= body s255)))
        (multiple-value-bind (body status headers)
            (request "/" :headers `(("x-request-id" . ,s256)))
          (ok (eql status 200))
          (ok (uuid-p (gethash "x-request-id" headers)))
          (ok (uuid-p body))))
      (testing-app (app :limit-length 256)
        (multiple-value-bind (body status headers)
            (request "/" :headers `(("x-request-id" . ,s256)))
          (ok (eql status 200))
          (ok (string= (gethash "x-request-id" headers) s256))
          (ok (string= body s256))))))

  (testing "custom header"
    (testing-app (app :header-name "Hono-Request-Id")
      (multiple-value-bind (body status headers)
          (request "/" :headers '(("hono-request-id" . "hono-is-hot")))
        (ok (eql status 200))
        (ok (string= (gethash "hono-request-id" headers) "hono-is-hot"))
        (ok (null (gethash "x-request-id" headers)))
        (ok (string= body "hono-is-hot"))))
    (testing-app (app :header-name "")
      (multiple-value-bind (body status headers) (request "/")
        (ok (eql status 200))
        (ok (null (gethash "x-request-id" headers)))
        (ok (uuid-p body))))))
