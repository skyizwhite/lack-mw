(defpackage #:lack-mw-test/trailing-slash
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:ningle)
  (:import-from #:lack-mw/trailing-slash
                #:*trim-trailing-slash*
                #:*append-trailing-slash*))
(in-package #:lack-mw-test/trailing-slash)

(defparameter *app-without-trailing-slash*
  (lack:builder
   *trim-trailing-slash*
   (let ((raw-app (make-instance 'ningle:app)))
     (setf (ningle:route raw-app "/") "ok")
     (setf (ningle:route raw-app "/without/trailing/slash") "ok")
     raw-app)))

(defparameter *app-with-trailing-slash*
  (lack:builder
   *append-trailing-slash*
   (let ((raw-app (make-instance 'ningle:app)))
     (setf (ningle:route raw-app "/") "ok")
     (setf (ningle:route raw-app "/something.file") "ok")
     (setf (ningle:route raw-app "/with/trailing/slash/") "ok")
     raw-app)))

(deftest trailing-slash
  (testing "trim"
    (testing-app *app-without-trailing-slash*
      (multiple-value-bind (body status headers)
          (request "/")
        (declare (ignore headers))
        (ok (string= body "ok"))
        (ok (eql status 200)))
      
      (multiple-value-bind (body status headers)
          (request "/without/trailing/slash")
        (declare (ignore headers))
        (ok (string= body "ok"))
        (ok (eql status 200)))
      
      (multiple-value-bind (body status headers)
          (request "/without/trailing/slash/" :max-redirects 0)
        (ok (string= body ""))
        (ok (eql status 301))
        (ok (string= (gethash "location" headers)
                     "/without/trailing/slash")))
      
      (multiple-value-bind (body status headers)
          (request "/without/trailing/slash/?param=foo" :max-redirects 0)
        (ok (string= body ""))
        (ok (eql status 301))
        (ok (string= (gethash "location" headers)
                     "/without/trailing/slash?param=foo")))))
  
  (testing "append"
    (testing-app *app-with-trailing-slash*
      (multiple-value-bind (body status headers)
          (request "/")
        (declare (ignore headers))        
        (ok (string= body "ok"))
        (ok (eql status 200)))
      
      (multiple-value-bind (body status headers)
          (request "/something.file")
        (declare (ignore headers))
        (ok (string= body "ok"))
        (ok (eql status 200)))

      (multiple-value-bind (body status headers)
          (request "/with/trailing/slash/")
        (declare (ignore headers))
        (ok (string= body "ok"))
        (ok (eql status 200)))
      
      (multiple-value-bind (body status headers)
          (request "/with/trailing/slash" :max-redirects 0)
        (ok (string= body ""))
        (ok (eql status 301))
        (ok (string= (gethash "location" headers)
                     "/with/trailing/slash/")))

      (multiple-value-bind (body status headers)
          (request "/with/trailing/slash?param=foo" :max-redirects 0)
        (ok (string= body ""))
        (ok (eql status 301))
        (ok (string= (gethash "location" headers)
                     "/with/trailing/slash/?param=foo"))))))
