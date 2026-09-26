(defpackage #:lack-mw-test/cache-control
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request
                #:generate-env)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/cache-control
                #:*mw-cache-control*))
(in-package #:lack-mw-test/cache-control)

(defparameter *immutable* "public, max-age=31536000, immutable")
(defparameter *revalidate* "public, max-age=0, must-revalidate")

;; answers 404 under /missing, sets its own Cache-Control under /media/,
;; and strips a leading /assets from path-info like the static middleware does
(defun app (env)
  (let ((path (getf env :path-info)))
    (when (and (>= (length path) 7) (string= "/assets" path :end2 7))
      (setf (getf env :path-info) (subseq path 7)))
    (cond
      ((search "/missing" path) '(404 (:content-type "text/plain") ("not found")))
      ((search "/media/" path) '(200 (:cache-control "private, max-age=60") ("media")))
      (t '(200 (:content-type "text/plain") ("ok"))))))

(defun cache-control-of (path &rest args)
  (gethash "cache-control" (nth-value 2 (apply #'request path args))))

(deftest cache-control
  (testing "no rules, no default: nothing set"
    (testing-app (lack:builder *mw-cache-control* #'app)
      (ok (null (cache-control-of "/")))))

  (testing "koya"
    (testing-app (lack:builder
                  (with-args *mw-cache-control*
                    :rules `(("/assets/" ,*immutable* :status (200)))
                    :default "no-store")
                  #'app)
      (ok (string= (cache-control-of "/assets/app.css?v=1") *immutable*))
      (ok (string= (cache-control-of "/assets/missing.css") "no-store"))
      (ok (string= (cache-control-of "/") "no-store"))
      (ok (string= (cache-control-of "/media/a.png") "private, max-age=60"))))

  (testing "website"
    (flet ((versioned-p (env res)
             (declare (ignore res))
             (or (uiop:string-prefix-p "v=" (or (getf env :query-string) ""))
                 (uiop:string-prefix-p "/assets/fonts/" (getf env :path-info)))))
      (testing-app (lack:builder
                    (with-args *mw-cache-control*
                      :rules `((,(lambda (env res)
                                   (and (uiop:string-prefix-p "/assets/" (getf env :path-info))
                                        (versioned-p env res)))
                                ,*immutable* :status (200 304))
                               ("/assets/" ,*revalidate* :status (200 304)))
                      :override t)
                    #'app)
        (ok (string= (cache-control-of "/assets/app.css?v=1") *immutable*))
        (ok (string= (cache-control-of "/assets/fonts/a.woff2") *immutable*))
        (ok (string= (cache-control-of "/assets/app.css") *revalidate*))
        (ok (string= (cache-control-of "/assets/media/x.png") *revalidate*))
        (ok (null (cache-control-of "/assets/missing.css")))
        (ok (null (cache-control-of "/")))
        (ok (string= (cache-control-of "/media/a.png") "private, max-age=60")))))

  (testing "first match wins, value functions"
    (testing-app (lack:builder
                  (with-args *mw-cache-control*
                    :rules (list (list "/a" (lambda (env res)
                                              (declare (ignore env))
                                              (format nil "max-age=~a" (first res))))
                                 (list "/a" "never")
                                 (list "/b" nil))
                    :default (constantly "fallback"))
                  #'app)
      (ok (string= (cache-control-of "/a") "max-age=200"))
      (ok (null (cache-control-of "/b")))
      (ok (string= (cache-control-of "/c") "fallback"))))

  (testing "override replaces the app's value"
    (testing-app (lack:builder
                  (with-args *mw-cache-control* :default "no-store" :override t)
                  #'app)
      (multiple-value-bind (body status headers) (request "/media/a.png")
        (declare (ignore body status))
        (ok (string= (gethash "cache-control" headers) "no-store")))))

  (testing "delayed responses"
    (let ((mw (funcall *mw-cache-control*
                       (lambda (env)
                         (declare (ignore env))
                         (lambda (responder) (funcall responder '(200 ()))))
                       :default "no-store"))
          res)
      (funcall (funcall mw (generate-env "/")) (lambda (r) (setf res r)))
      (ok (equal res '(200 (:cache-control "no-store")))))))
