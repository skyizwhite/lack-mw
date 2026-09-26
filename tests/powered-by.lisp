(defpackage #:lack-mw-test/powered-by
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/powered-by
                #:*powered-by*))
(in-package #:lack-mw-test/powered-by)

(defun raw-app (env)
  (declare (ignore env))
  '(200 (:content-type "text/plain") ("root")))

(deftest powered-by
  (testing "should return with X-Powered-By header"
    (testing-app (lack:builder *powered-by* #'raw-app)
      (multiple-value-bind (body status headers) (request "/")
        (ok (string= body "root"))
        (ok (eql status 200))
        (ok (string= (gethash "x-powered-by" headers) "Lack")))))

  (testing "should not return duplicate values"
    (testing-app (lack:builder *powered-by* *powered-by* #'raw-app)
      (multiple-value-bind (body status headers) (request "/")
        (declare (ignore body))
        (ok (eql status 200))
        (ok (string= (gethash "x-powered-by" headers) "Lack")))))

  (testing "should return custom server-name"
    (testing-app (lack:builder (with-args *powered-by* :server-name "Foo") #'raw-app)
      (multiple-value-bind (body status headers) (request "/")
        (declare (ignore body))
        (ok (eql status 200))
        (ok (string= (gethash "x-powered-by" headers) "Foo")))))

  (testing "delayed response"
    (let* ((app (funcall *powered-by*
                         (lambda (env)
                           (declare (ignore env))
                           (lambda (responder)
                             (funcall responder '(200 () ("ok")))))))
           (result nil))
      (funcall (funcall app (lack/test:generate-env "/"))
               (lambda (res) (setf result res)))
      (ok (string= (getf (second result) :x-powered-by) "Lack")))))
