(defpackage #:lack-mw-test/combine
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:generate-env)
  (:import-from #:lack-mw/combine
                #:mw-some
                #:mw-every
                #:mw-except
                #:mw-condition
                #:unmet-condition))
(in-package #:lack-mw-test/combine)

(defparameter *app*
  (lambda (env)
    `(200 (:content-type "text/plain") (,(format nil "Hello ~a" (getf env :path-info))))))

(defvar *calls* nil)

(defun pass-through (name)
  "Middleware that records NAME and calls the app."
  (lambda (app)
    (lambda (env)
      (push name *calls*)
      (funcall app env))))

(defun failing-mw (name)
  "Middleware that records NAME and signals an error."
  (lambda (app)
    (declare (ignore app))
    (lambda (env)
      (declare (ignore env))
      (push name *calls*)
      (error "Error ~a" name))))

(defun rejecting (name &optional (status 401))
  "Middleware that records NAME and responds without calling the app."
  (lambda (app)
    (declare (ignore app))
    (lambda (env)
      (declare (ignore env))
      (push name *calls*)
      `(,status () (,(format nil "rejected by ~a" name))))))

(defun run-mw (mw &optional (path "/"))
  (setf *calls* nil)
  (funcall (funcall mw *app*) (generate-env path)))

(defun body (res) (first (third res)))

(defun error-message (thunk)
  (handler-case (progn (funcall thunk) nil)
    (error (e) (princ-to-string e))))

(deftest mw-some-test
  (testing "calls only the first middleware"
    (let ((res (run-mw (mw-some (pass-through :m1) (pass-through :m2)))))
      (ok (equal *calls* '(:m1)))
      (ok (equal (body res) "Hello /"))))
  (testing "tries the next middleware when the first one signals"
    (let ((res (run-mw (mw-some (failing-mw :m1) (pass-through :m2)))))
      (ok (equal *calls* '(:m2 :m1)))
      (ok (equal (body res) "Hello /"))))
  (testing "tries the next middleware when a condition is false"
    (let ((res (run-mw (mw-some (mw-condition (constantly nil)) (pass-through :m2)))))
      (ok (equal *calls* '(:m2)))
      (ok (equal (body res) "Hello /"))))
  (testing "tries the next middleware when the first one responds without calling the app"
    (let ((res (run-mw (mw-some (rejecting :m1) (pass-through :m2)))))
      (ok (equal *calls* '(:m2 :m1)))
      (ok (equal (body res) "Hello /"))))
  (testing "a true condition passes"
    (let ((res (run-mw (mw-some (mw-condition (constantly t)) (pass-through :m2)))))
      (ok (null *calls*))
      (ok (equal (body res) "Hello /"))))
  (testing "signals the last error if all middlewares signal"
    (ok (equal (error-message (lambda () (run-mw (mw-some (failing-mw :m1) (failing-mw :m2)))))
               "Error M2")))
  (testing "signals if all conditions are false"
    (ok (signals (run-mw (mw-some (mw-condition (constantly nil)) (mw-condition (constantly nil))))
                 'unmet-condition)))
  (testing "returns the last response if all middlewares reject"
    (let ((res (run-mw (mw-some (rejecting :m1) (rejecting :m2 403)))))
      (ok (= (first res) 403))
      (ok (equal (body res) "rejected by M2"))))
  (testing "does not call skipped middlewares when an error is signaled after the app was called"
    (ok (equal (error-message
                (lambda ()
                  (run-mw (mw-every (mw-some (pass-through :m1) (pass-through :m2))
                                 (failing-mw :m3)))))
               "Error M3"))
    (ok (equal *calls* '(:m3 :m1))))
  (testing "same with a true condition"
    (ok (equal (error-message
                (lambda ()
                  (run-mw (mw-every (mw-some (mw-condition (constantly t)) (pass-through :m2))
                                 (failing-mw :m3)))))
               "Error M3"))
    (ok (equal *calls* '(:m3))))
  (testing "nested"
    (let ((res (run-mw (mw-some (rejecting :m1)
                             (mw-every (mw-some (failing-mw :m2) (pass-through :m3))
                                       (pass-through :m4))))))
      (ok (equal *calls* '(:m4 :m3 :m2 :m1)))
      (ok (equal (body res) "Hello /")))))

(deftest mw-every-test
  (testing "calls all middlewares in order"
    (let ((res (run-mw (mw-every (pass-through :m1) (pass-through :m2)))))
      (ok (equal *calls* '(:m2 :m1)))
      (ok (equal (body res) "Hello /"))))
  (testing "signals if any middleware signals"
    (ok (equal (error-message (lambda () (run-mw (mw-every (failing-mw :m1) (pass-through :m2)))))
               "Error M1"))
    (ok (equal *calls* '(:m1))))
  (testing "signals if a condition is false"
    (ok (signals (run-mw (mw-every (mw-condition (constantly nil)) (pass-through :m2)))
                 'unmet-condition))
    (ok (null *calls*)))
  (testing "returns the response of a short-circuiting middleware"
    (let ((res (run-mw (mw-every (rejecting :m1) (pass-through :m2)))))
      (ok (equal (body res) "rejected by M1"))
      (ok (equal *calls* '(:m1)))))
  (testing "works inside lack:builder"
    (setf *calls* nil)
    (let ((app (lack:builder (mw-every (pass-through :m1) (pass-through :m2)) *app*)))
      (ok (equal (body (funcall app (generate-env "/x"))) "Hello /x"))
      (ok (equal *calls* '(:m2 :m1))))))

(deftest mw-except-test
  (testing "skips middlewares when the path matches"
    (let ((mw (mw-except "/maintenance" (pass-through :m1) (pass-through :m2))))
      (run-mw mw "/")
      (ok (equal *calls* '(:m2 :m1)))
      (ok (equal (body (run-mw mw "/maintenance")) "Hello /maintenance"))
      (ok (null *calls*))))
  (testing "any of several patterns"
    (let ((mw (mw-except '("/maintenance" "/public/users/:id")
                         (pass-through :m1) (pass-through :m2))))
      (run-mw mw "/secret")
      (ok (equal *calls* '(:m2 :m1)))
      (run-mw mw "/maintenance")
      (ok (null *calls*))
      (ok (equal (body (run-mw mw "/public/users/123")) "Hello /public/users/123"))
      (ok (null *calls*))
      (run-mw mw "/public/users/123/edit")
      (ok (equal *calls* '(:m2 :m1)))))
  (testing "patterns and predicates"
    (let ((mw (mw-except (list "/maintenance"
                               (lambda (env) (search "public" (getf env :path-info))))
                         (pass-through :m1) (pass-through :m2))))
      (run-mw mw "/secret")
      (ok (equal *calls* '(:m2 :m1)))
      (run-mw mw "/maintenance")
      (ok (null *calls*))
      (run-mw mw "/public/users/123")
      (ok (null *calls*))))
  (testing "wildcards"
    (let ((mw (mw-except "/api/public/*" (rejecting :auth))))
      (ok (= (first (run-mw mw "/api/public")) 200))
      (ok (= (first (run-mw mw "/api/public/foo/bar")) 200))
      (ok (= (first (run-mw mw "/api/private")) 401)))
    (let ((mw (mw-except "*" (rejecting :auth))))
      (ok (= (first (run-mw mw "/anything")) 200)))
    (let ((mw (mw-except "/files/*.png" (rejecting :auth))))
      (ok (= (first (run-mw mw "/files/a.png")) 200))
      (ok (= (first (run-mw mw "/files/a.jpg")) 401))))
  (testing "regex and optional params"
    (let ((mw (mw-except '("/posts/:id{[0-9]+}" "/animal/:type?") (rejecting :auth))))
      (ok (= (first (run-mw mw "/posts/123")) 200))
      (ok (= (first (run-mw mw "/posts/abc")) 401))
      (ok (= (first (run-mw mw "/animal")) 200))
      (ok (= (first (run-mw mw "/animal/dog")) 200))
      (ok (= (first (run-mw mw "/animal/dog/cat")) 401)))
    (let ((mw (mw-except "/:lang?" (rejecting :auth))))
      (ok (= (first (run-mw mw "/")) 200))
      (ok (= (first (run-mw mw "/en")) 200))
      (ok (= (first (run-mw mw "/en/about")) 401)))))
