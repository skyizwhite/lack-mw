(defpackage #:lack-mw-test/timing
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/timing
                #:*timing*
                #:set-metric
                #:start-time
                #:end-time
                #:wrap-time
                #:with-timing))
(in-package #:lack-mw-test/timing)

(defparameter *total-description* "my total DescRipTion!")

(defun ok-res (body)
  `(200 (:content-type "text/plain") (,body)))

(defun raw-app (env)
  (let ((path (getf env :path-info)))
    (cond
      ((string= path "/api")
       (start-time env "sleep")
       (sleep 0.03)
       (end-time env "sleep")
       (ok-res "api!"))
      ((string= path "/api-wrap")
       (wrap-time env "sleep" (lambda () (sleep 0.03)))
       (ok-res "api!"))
      ((string= path "/api-wrap-throw")
       (handler-case
           (with-timing (env "sleep")
             (sleep 0.03)
             (error "boom"))
         (error (e)
           `(500 (:content-type "text/plain") (,(format nil "error :( ~A" e))))))
      ((string= path "/cache")
       (set-metric env "region" "europe-west3")
       (ok-res "cache!"))
      (t (ok-res "/")))))

(defparameter *app*
  (lack:builder
   (with-args *timing* :total-description *total-description*)
   #'raw-app))

(defun server-timing (headers)
  (gethash "server-timing" headers))

(defun contains (sub str)
  (and str (search sub str) t))

(deftest server-timing-api
  (testing-app *app*
    (testing "should contain total duration"
      (multiple-value-bind (body status headers) (request "/")
        (declare (ignore body status))
        (ok (contains "total;dur=" (server-timing headers)))
        (ok (contains *total-description* (server-timing headers)))))

    (testing "should contain value metrics"
      (multiple-value-bind (body status headers) (request "/api")
        (declare (ignore body status))
        (ok (contains "sleep;dur=" (server-timing headers)))))

    (testing "should contain value metrics, wrapped"
      (multiple-value-bind (body status headers) (request "/api-wrap")
        (declare (ignore body status))
        (ok (contains "sleep;dur=" (server-timing headers)))))

    (testing "should contain value metrics, wrapped throw"
      (multiple-value-bind (body status headers) (request "/api-wrap-throw")
        (declare (ignore body))
        (ok (>= status 500))
        (ok (contains "sleep;dur=" (server-timing headers)))))

    (testing "should contain value-less metrics"
      (multiple-value-bind (body status headers) (request "/cache")
        (declare (ignore body status))
        (ok (contains "region;desc=\"europe-west3\"" (server-timing headers))))))

  (testing "should not be enabled if the outer app has the timing middleware"
    (testing-app (lack:builder
                  (with-args *timing* :total-description *total-description*)
                  *timing*
                  #'raw-app)
      (multiple-value-bind (body status headers) (request "/")
        (declare (ignore body))
        (ok (eql status 200))
        (ok (contains *total-description* (server-timing headers)))
        (ok (not (contains "Total Response Time" (server-timing headers)))))))

  (testing "duration format"
    (testing-app (lack:builder
                  (with-args *timing* :total nil)
                  (lambda (env)
                    (set-metric env "custom" 23.8 "My custom Metric")
                    (set-metric env "precise" 1.23456 nil 3)
                    (ok-res "ok")))
      (multiple-value-bind (body status headers) (request "/")
        (declare (ignore body status))
        (ok (string= (server-timing headers)
                     "custom;dur=23.8;desc=\"My custom Metric\",precise;dur=1.235")))))

  (testing "auto-end option"
    (flet ((app (&rest args)
             (lack:builder (apply #'with-args *timing* args)
                           (lambda (env) (start-time env "test") (ok-res "/")))))
      (testing-app (app)
        (multiple-value-bind (body status headers) (request "/")
          (declare (ignore body))
          (ok (eql status 200))
          (ok (contains "test;dur=" (server-timing headers)))))
      (testing-app (app :auto-end nil)
        (multiple-value-bind (body status headers) (request "/")
          (declare (ignore body))
          (ok (eql status 200))
          (ok (not (contains "test;dur=" (server-timing headers))))))))

  (testing "enabled function"
    (let ((called nil))
      (testing-app (lack:builder
                    (with-args *timing* :enabled (lambda (env)
                                                   (declare (ignore env))
                                                   (setf called t)
                                                   nil))
                    #'raw-app)
        (multiple-value-bind (body status headers) (request "/")
          (declare (ignore body))
          (ok (eql status 200))
          (ok called)
          (ok (null (server-timing headers)))))))

  (testing "total nil and value-less metric without description"
    (testing-app (lack:builder
                  (with-args *timing* :total nil)
                  (lambda (env) (set-metric env "test") (ok-res "/")))
      (multiple-value-bind (body status headers) (request "/")
        (declare (ignore body))
        (ok (eql status 200))
        (ok (string= (server-timing headers) "test")))))

  (testing "cross-origin"
    (flet ((allow-origin (&rest args)
             (testing-app (lack:builder (apply #'with-args *timing* args) #'raw-app)
               (multiple-value-bind (body status headers)
                   (request "/" :headers '(("origin" . "https://example.com")))
                 (declare (ignore body status))
                 (ok (server-timing headers))
                 (gethash "timing-allow-origin" headers)))))
      (ok (null (allow-origin :cross-origin nil)))
      (ok (equal (allow-origin :cross-origin t) "*"))
      (ok (equal (allow-origin :cross-origin "https://example.com") "https://example.com"))
      (ok (equal (allow-origin :cross-origin (lambda (env)
                                               (or (gethash "origin" (getf env :headers)) "*")))
                 "https://example.com"))))

  (testing "warnings"
    (let ((env (lack/test:generate-env "/")))
      (ok (signals (set-metric env "test" 123) 'warning))
      (ok (signals (start-time env "test") 'warning))
      (ok (signals (end-time env "test") 'warning)))
    (let ((warned nil))
      (testing-app (lack:builder
                    *timing*
                    (lambda (env)
                      (handler-bind ((warning (lambda (w)
                                                (setf warned (princ-to-string w))
                                                (muffle-warning w))))
                        (end-time env "nonExistentTimer"))
                      (ok-res "hello")))
        (multiple-value-bind (body status) (request "/")
          (declare (ignore body))
          (ok (eql status 200))
          (ok (equal warned "Timer \"nonExistentTimer\" does not exist!")))))))
