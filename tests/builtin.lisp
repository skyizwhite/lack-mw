(defpackage #:lack-mw-test/builtin
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/builtin
                #:*basic-auth*
                #:*session-csrf*
                #:*mount*
                #:*session*
                #:*when*
                #:make-memory-store
                #:make-cookie-state))
(in-package #:lack-mw-test/builtin)

(defun text-app (text)
  (lambda (env)
    (declare (ignore env))
    `(200 (:content-type "text/plain") (,text))))

(defparameter *mw* (lambda (app &key (suffix "") (tag ""))
                     (lambda (env)
                       (declare (ignore env))
                       `(200 () (,(format nil "~a~a~a" (third (funcall app nil)) suffix tag))))))

(defun body-of (app)
  (first (third (funcall app nil))))

(deftest with-args
  (testing "passes the given arguments"
    (ok (string= (body-of (funcall (with-args *mw* :suffix "!") (lambda (env) (declare (ignore env)) '(200 () "ok"))))
                 "ok!")))

  (testing "accepts more arguments, which override the given ones"
    (let ((mw (with-args *mw* :suffix "!" :tag "#")))
      (ok (string= (body-of (funcall mw (lambda (env) (declare (ignore env)) '(200 () "ok")) :suffix "?"))
                   "ok?#"))
      (ok (string= (body-of (funcall (with-args mw :tag "*") (lambda (env) (declare (ignore env)) '(200 () "ok"))))
                   "ok!*"))))

  (testing "looks a symbol's value up on every call"
    (let ((mw (with-args '*mw*))
          (*mw* (lambda (app) (declare (ignore app)) (lambda (env) (declare (ignore env)) '(200 () ("rebound"))))))
      (ok (string= (body-of (funcall mw (text-app "ok")))
                   "rebound")))))

(deftest builtin
  (testing "basic-auth"
    (testing-app (lack:builder
                  (with-args *basic-auth*
                    :authenticator (lambda (user pass) (and (string= user "u") (string= pass "p"))))
                  (text-app "ok"))
      (multiple-value-bind (body status) (request "/")
        (declare (ignore body))
        (ok (eql status 401)))
      (multiple-value-bind (body status)
          (request "/" :headers '(("authorization" . "Basic dTpw")))
        (ok (eql status 200))
        (ok (string= body "ok")))))

  (testing "mount"
    (testing-app (lack:builder
                  (with-args *mount* "/api" (text-app "api"))
                  (text-app "root"))
      (ok (string= (request "/api/x") "api"))
      (ok (string= (request "/x") "root"))))

  (testing "when"
    (testing-app (lack:builder
                  (with-args *when*
                    (lambda (env) (string= (getf env :path-info) "/guarded"))
                    (with-args *basic-auth* :authenticator (constantly nil)))
                  (text-app "ok"))
      (ok (eql (nth-value 1 (request "/guarded")) 401))
      (ok (eql (nth-value 1 (request "/open")) 200))))

  (testing "session and session-csrf"
    (testing-app (lack:builder
                  (with-args *session*
                    :store (make-memory-store)
                    :state (make-cookie-state))
                  *session-csrf*
                  (text-app "ok"))
      (ok (eql (nth-value 1 (request "/")) 200))
      (ok (eql (nth-value 1 (request "/" :method :post :content "a=b")) 400)))))
