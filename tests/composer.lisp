(defpackage #:lack-mw-test/composer
  (:use #:cl
        #:rove
        #:mockingbird)
  (:import-from #:lack/response
                #:response-status
                #:response-headers)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:ningle
                #:route)
  (:import-from #:lack-mw/composer
                #:only
                #:except))
(in-package #:lack-mw-test/composer)

(defun redirect (url &optional (status 302))
  (setf (getf (response-headers ningle:*response*) :location) url)
  (setf (response-status ningle:*response*) status)
  nil)

(defun middleware1 ())
(defun middleware2 ())

(defparameter *stub*
  (lambda (app)
    (lambda (env)
      (funcall app env))))

(deftest composer-test
  (testing "except"
    (with-dynamic-stubs
        ((middleware1 *stub*)
         (middleware2 *stub*))
      (testing-app (lack:builder
                    (except "/maintenance"
                            #'middleware1
                            #'middleware2)
                    (let ((app (make-instance 'ningle:app)))
                      (setf (route app "/maintenance")
                            "Hello Maintenance")
                      (setf (route app "*")
                            (lambda (params)
                              (declare (ignore params))
                              (redirect "/maintenance")))
                      app))

        (multiple-value-bind (body status headers)
            (request "/" :max-redirects 0)
          (declare (ignore body status))
          (ok (verify-call-times-for 'middleware1 1))
          (ok (verify-call-times-for 'middleware2 1))
          (ok (string= (gethash "location" headers) "/maintenance")))
        (clear-calls)

        (let ((body (request "/maintenance")))
          (ok (string= body "Hello Maintenance"))
          (ok (verify-call-times-for 'middleware1 0))
          (ok (verify-call-times-for 'middleware2 0)))
        (clear-calls)))))
