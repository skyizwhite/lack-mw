(defpackage #:lack-mw-test/trailing-slash
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:ningle)
  (:import-from #:lack-mw/trailing-slash
                #:*mw-trim-trailing-slash*
                #:*mw-append-trailing-slash*))
(in-package #:lack-mw-test/trailing-slash)

(defparameter *app-without-trailing-slash*
  (lack:builder
   *mw-trim-trailing-slash*
   (let ((raw-app (make-instance 'ningle:app)))
     (setf (ningle:route raw-app "/") "ok")
     (setf (ningle:route raw-app "/without/trailing/slash") "ok")
     raw-app)))

(defparameter *app-with-trailing-slash*
  (lack:builder
   *mw-append-trailing-slash*
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
                     "http://localhost/without/trailing/slash")))
      
      (multiple-value-bind (body status headers)
          (request "/without/trailing/slash/?param=foo" :max-redirects 0)
        (ok (string= body ""))
        (ok (eql status 301))
        (ok (string= (gethash "location" headers)
                     "http://localhost/without/trailing/slash?param=foo")))))
  
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
                     "http://localhost/with/trailing/slash/")))

      (multiple-value-bind (body status headers)
          (request "/with/trailing/slash?param=foo" :max-redirects 0)
        (ok (string= body ""))
        (ok (eql status 301))
        (ok (string= (gethash "location" headers)
                     "http://localhost/with/trailing/slash/?param=foo"))))))

(defun not-found-app (env)
  (declare (ignore env))
  '(404 () ("not found")))

(defun redirect-location (mw request-uri)
  (let ((headers (make-hash-table :test 'equal)))
    (setf (gethash "host" headers) "localhost")
    (let ((response (funcall (funcall mw #'not-found-app)
                             (list :request-method :get
                                   :request-uri request-uri
                                   :url-scheme "http"
                                   :headers headers))))
      (and (eql (first response) 301)
           (getf (second response) :location)))))

(deftest trailing-slash-open-redirect
  (testing "trim"
    (ok (string= (redirect-location *mw-trim-trailing-slash* "//evil.example/x/")
                 "http://localhost//evil.example/x"))
    (ok (string= (redirect-location *mw-trim-trailing-slash* "/\\evil.example/x/")
                 "http://localhost/\\evil.example/x"))
    (ok (string= (redirect-location *mw-trim-trailing-slash*
                                    (format nil "/~C/evil.example/x/" #\Tab))
                 (format nil "http://localhost/~C/evil.example/x" #\Tab)))
    (ok (string= (redirect-location *mw-trim-trailing-slash* "/a%3Fb/?q=1")
                 "http://localhost/a%3Fb?q=1")))

  (testing "append"
    (ok (string= (redirect-location *mw-append-trailing-slash* "//evil.example/x")
                 "http://localhost//evil.example/x/"))
    (ok (string= (redirect-location *mw-append-trailing-slash* "/\\evil.example/x")
                 "http://localhost/\\evil.example/x/"))
    (ok (string= (redirect-location *mw-append-trailing-slash*
                                    (format nil "/~C/evil.example/x" #\Tab))
                 (format nil "http://localhost/~C/evil.example/x/" #\Tab)))
    (ok (string= (redirect-location *mw-append-trailing-slash* "/a%3Fb?q=1")
                 "http://localhost/a%3Fb/?q=1"))))
