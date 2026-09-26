(defpackage #:lack-mw-test/body-limit
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request
                #:generate-env)
  (:import-from #:lack/request
                #:make-request
                #:request-content)
  (:import-from #:babel)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/body-limit
                #:*mw-body-limit*))
(in-package #:lack-mw-test/body-limit)

(defvar *called* nil)

(defun echo-app (env)
  (setf *called* t)
  (list 200 (list :content-type "text/plain")
        (list (if (getf env :raw-body)
                  (babel:octets-to-string (request-content (make-request env)))
                  "index"))))

(defun chunked-env (content &key content-length)
  "An env like a server gives for a Transfer-Encoding: chunked request."
  (let ((env (generate-env "/test" :method :post :content content
                                   :headers '(("content-type" . "text/plain")))))
    (setf (getf env :content-length) content-length)
    (setf (gethash "transfer-encoding" (getf env :headers)) "chunked")
    env))

(defun call (app env)
  (setf *called* nil)
  (destructuring-bind (status headers body) (funcall app env)
    (declare (ignore headers))
    (values status (format nil "~{~a~}" body))))

(defparameter *text* "hono is so hot")              ; 14 bytes
(defparameter *text2* "hono is so hot and cute")    ; 23 bytes

(deftest body-limit
  (let ((app (lack:builder (with-args *mw-body-limit* :max-size 14) #'echo-app)))
    (testing "GET request"
      (testing-app app
        (multiple-value-bind (body status) (request "/")
          (ok (= status 200))
          (ok (string= body "index")))))

    (testing "Content-Length within the limit"
      (testing-app app
        (multiple-value-bind (body status)
            (request "/body-limit-15byte" :method :post :content *text*
                                          :headers '(("content-type" . "text/plain")))
          (ok (= status 200))
          (ok (string= body *text*)))))

    (testing "Content-Length over the limit"
      (testing-app app
        (multiple-value-bind (body status)
            (request "/body-limit-15byte" :method :post :content *text2*
                                          :headers '(("content-type" . "text/plain")))
          (ok (= status 413))
          (ok (string= body "Payload Too Large")))))

    (testing "chunked body within the limit is readable downstream"
      (multiple-value-bind (status body) (call app (chunked-env "abc"))
        (ok (= status 200))
        (ok (string= body "abc"))))

    (testing "chunked body over the limit"
      (multiple-value-bind (status body) (call app (chunked-env *text2*))
        (ok (= status 413))
        (ok (string= body "Payload Too Large"))
        (ng *called*)))

    (testing "chunked body exactly at the limit"
      (multiple-value-bind (status body) (call app (chunked-env *text*))
        (ok (= status 200))
        (ok (string= body *text*)))))

  (testing "custom error handler"
    (let ((app (lack:builder
                (with-args *mw-body-limit*
                  :max-size 15
                  :on-error (lambda (env)
                              (declare (ignore env))
                              (list 413 (list :content-type "text/plain") (list "no"))))
                (lambda (env)
                  (declare (ignore env))
                  (list 200 (list :content-type "text/plain") (list "yes"))))))
      (testing-app app
        (multiple-value-bind (body status)
            (request "/text-limit-15byte-custom" :method :post :content *text2*
                                                 :headers '(("content-type" . "text/plain")))
          (ok (= status 413))
          (ok (string= body "no"))))))

  (testing "Transfer-Encoding takes precedence over Content-Length"
    (let ((app (lack:builder (with-args *mw-body-limit* :max-size 10) #'echo-app)))
      (ok (= (call app (chunked-env "this is a large content that exceeds 10 bytes"
                                    :content-length 5))
             413))
      (ng *called*)
      (ok (= (call app (chunked-env "test")) 200))))

  (testing "large chunked body is rejected without being read whole"
    (let ((app (lack:builder (with-args *mw-body-limit* :max-size 8) #'echo-app)))
      (ok (= (call app (chunked-env (make-string 100000 :initial-element #\a))) 413))
      (ng *called*)))

  (testing ":max-size is required"
    (ok (signals (lack:builder *mw-body-limit* #'echo-app)))))
