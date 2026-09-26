(defpackage #:lack-mw-test/cors
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/cors
                #:*cors*))
(in-package #:lack-mw-test/cors)

(defun ok-app (env)
  (declare (ignore env))
  (list 200 (list :content-type "application/json") (list "{\"success\":true}")))

(defun vary-app (env)
  (declare (ignore env))
  (list 200 (list :vary "X-Custom-Vary-Value") (list "{\"success\":true}")))

(defun header (headers name)
  (gethash name headers))

(defmacro with-response ((app uri &rest args) &body body)
  `(testing-app ,app
     (multiple-value-bind (body status headers) (request ,uri ,@args)
       (declare (ignorable body status headers))
       ,@body)))

(defparameter *api2*
  (with-args *cors*
    :origin "http://example.com"
    :allow-headers '("X-Custom-Header" "Upgrade-Insecure-Requests")
    :allow-methods '("POST" "GET" "OPTIONS")
    :expose-headers '("Content-Length" "X-Kuma-Revision")
    :max-age 600
    :credentials t))

(defparameter *api3*
  (with-args *cors* :origin '("http://example.com" "http://example.org" "http://example.dev")))

(defparameter *api4*
  (with-args *cors*
    :origin (lambda (origin env)
              (declare (ignore env))
              (let ((suffix ".example.com"))
                (if (and (> (length origin) (length suffix))
                         (string= suffix origin :start2 (- (length origin) (length suffix))))
                    origin
                    "http://example.com")))))

(defparameter *api7*
  (with-args *cors*
    :origin (lambda (origin env)
              (declare (ignore env))
              (if (string= origin "http://example.com") origin "*"))
    :allow-methods (lambda (origin env)
                     (declare (ignore env))
                     (if (string= origin "http://example.com")
                         '("GET" "HEAD" "POST" "PATCH" "DELETE")
                         '("GET" "HEAD")))))

(defparameter *api10*
  (with-args *cors* :origin "*" :credentials t))

(deftest cors
  (testing "GET default"
    (with-response ((lack:builder *cors* #'ok-app) "/api/abc")
      (ok (= status 200))
      (ok (equal (header headers "access-control-allow-origin") "*"))
      (ok (null (header headers "vary")))))

  (testing "Preflight default"
    (with-response ((lack:builder *cors* #'ok-app) "/api/abc"
                    :method :options
                    :headers '(("access-control-request-method" . "QUERY")
                               ("access-control-request-headers" . "X-PINGOTHER, Content-Type")))
      (ok (= status 204))
      (ok (equal (header headers "access-control-allow-methods")
                 "GET,HEAD,PUT,POST,DELETE,PATCH,QUERY"))
      (ok (equal (header headers "access-control-allow-headers") "X-PINGOTHER,Content-Type"))
      (ok (equal (header headers "vary") "Access-Control-Request-Headers"))))

  (testing "Preflight handles a large Access-Control-Request-Headers value"
    (with-response ((lack:builder *cors* #'ok-app) "/api/abc"
                    :method :options
                    :headers `(("access-control-request-headers"
                                . ,(format nil "x~ax" (make-string 200000 :initial-element #\Space)))))
      (ok (= status 204))))

  (testing "Preflight with options"
    (with-response ((lack:builder *api2* #'ok-app) "/api2/abc"
                    :method :options
                    :headers '(("origin" . "http://example.com")))
      (ok (equal (header headers "access-control-allow-origin") "http://example.com"))
      (ok (equal (header headers "vary") "Origin, Access-Control-Request-Headers"))
      (ok (equal (header headers "access-control-allow-headers")
                 "X-Custom-Header,Upgrade-Insecure-Requests"))
      (ok (equal (header headers "access-control-allow-methods") "POST,GET,OPTIONS"))
      (ok (equal (header headers "access-control-expose-headers")
                 "Content-Length,X-Kuma-Revision"))
      (ok (equal (header headers "access-control-max-age") "600"))
      (ok (equal (header headers "access-control-allow-credentials") "true"))))

  (testing "Disallow an unmatched origin"
    (with-response ((lack:builder *api2* #'ok-app) "/api2/abc"
                    :method :options
                    :headers '(("origin" . "http://example.net")))
      (ok (null (header headers "access-control-allow-origin")))))

  (testing "Allow multiple origins"
    (with-response ((lack:builder *api3* #'ok-app) "/api3/abc"
                    :headers '(("origin" . "http://example.org")))
      (ok (equal (header headers "access-control-allow-origin") "http://example.org")))
    (with-response ((lack:builder *api3* #'ok-app) "/api3/abc")
      (ok (null (header headers "access-control-allow-origin"))))
    (with-response ((lack:builder *api3* #'ok-app) "/api3/abc"
                    :headers '(("referer" . "http://example.net/")))
      (ok (null (header headers "access-control-allow-origin")))))

  (testing "Set \"Origin\" to Vary header"
    (with-response ((lack:builder *api3* #'ok-app) "/api3/abc"
                    :headers '(("origin" . "http://example.com")))
      (ok (= status 200))
      (ok (equal (header headers "access-control-allow-origin") "http://example.com"))
      (ok (equal (header headers "vary") "Origin"))))

  (testing "Keep original Vary header"
    (with-response ((lack:builder *cors* #'vary-app) "/api/vary-header"
                    :headers '(("origin" . "http://example.com")))
      (ok (= status 200))
      (ok (equal (header headers "access-control-allow-origin") "*"))
      (ok (equal (header headers "vary") "X-Custom-Vary-Value"))))

  (testing "Append \"Origin\" to Vary header, if response has some Vary header"
    (with-response ((lack:builder *api3* #'vary-app) "/api3/vary-header"
                    :headers '(("origin" . "http://example.com")))
      (ok (= status 200))
      (ok (equal (header headers "access-control-allow-origin") "http://example.com"))
      (ok (equal (header headers "vary") "X-Custom-Vary-Value, Origin"))))

  (testing "Allow origins by function"
    (with-response ((lack:builder *api4* #'ok-app) "/api4/abc"
                    :headers '(("origin" . "http://subdomain.example.com")))
      (ok (equal (header headers "access-control-allow-origin") "http://subdomain.example.com")))
    (with-response ((lack:builder *api4* #'ok-app) "/api4/abc")
      (ok (equal (header headers "access-control-allow-origin") "http://example.com")))
    (with-response ((lack:builder *api4* #'ok-app) "/api4/abc"
                    :headers '(("referer" . "http://evil-example.com/")))
      (ok (equal (header headers "access-control-allow-origin") "http://example.com"))))

  (testing "Should not return duplicate header values"
    (let ((mw (with-args *cors* :origin "http://example.com")))
      (with-response ((lack:builder mw mw #'ok-app) "/api6/abc"
                      :headers '(("origin" . "http://example.com")))
        (ok (equal (header headers "access-control-allow-origin") "http://example.com"))
        (ok (equal (header headers "vary") "Origin")))))

  (testing "Allow methods by function"
    (with-response ((lack:builder *api7* #'ok-app) "/api7/abc"
                    :method :options
                    :headers '(("origin" . "http://example.com")))
      (ok (equal (header headers "access-control-allow-origin") "http://example.com"))
      (ok (equal (header headers "access-control-allow-methods") "GET,HEAD,POST,PATCH,DELETE")))
    (with-response ((lack:builder *api7* #'ok-app) "/api7/abc"
                    :method :options
                    :headers '(("origin" . "http://example.org")))
      (ok (equal (header headers "access-control-allow-origin") "*"))
      (ok (equal (header headers "access-control-allow-methods") "GET,HEAD"))))

  (testing "Does not set allow methods when function returns an empty list"
    (with-response ((lack:builder (with-args *cors* :allow-methods (lambda (o e)
                                                                     (declare (ignore o e))
                                                                     '()))
                                  #'ok-app)
                    "/" :method :options)
      (ok (null (header headers "access-control-allow-methods")))))

  (testing "Emits the wildcard, not the reflected origin, with credentials and wildcard origin"
    (dolist (origin '("http://example.com" "http://other.com" "null"))
      (with-response ((lack:builder *api10* #'ok-app) "/api10/abc"
                      :headers `(("origin" . ,origin)))
        (ok (= status 200))
        (ok (equal (header headers "access-control-allow-origin") "*"))
        (ok (equal (header headers "access-control-allow-credentials") "true"))
        (ok (null (header headers "vary")))))
    (with-response ((lack:builder *api10* #'ok-app) "/api10/abc")
      (ok (equal (header headers "access-control-allow-origin") "*"))
      (ok (equal (header headers "access-control-allow-credentials") "true")))
    (with-response ((lack:builder *api10* #'ok-app) "/api10/abc"
                    :method :options
                    :headers '(("origin" . "http://example.com")))
      (ok (= status 204))
      (ok (equal (header headers "access-control-allow-origin") "*"))
      (ok (equal (header headers "access-control-allow-credentials") "true"))))

  (testing "Should not reflect an arbitrary Origin with credentials and default origin"
    (dolist (origin '("https://attacker.example" "http://evil.test" "null"))
      (with-response ((lack:builder (with-args *cors* :credentials t) #'ok-app) "/api/me"
                      :headers `(("origin" . ,origin)))
        (ng (equal (header headers "access-control-allow-origin") origin)))))

  (testing "Options without origin fall back to wildcard default"
    (let ((app (lack:builder (with-args *cors* :allow-methods '("GET" "POST")) #'ok-app)))
      (with-response (app "/api/abc")
        (ok (= status 200))
        (ok (equal (header headers "access-control-allow-origin") "*")))
      (with-response (app "/api/abc" :method :options)
        (ok (equal (header headers "access-control-allow-methods") "GET,POST")))))

  (testing "Delayed responses"
    (let* ((app (funcall *api3*
                         (lambda (env)
                           (declare (ignore env))
                           (lambda (responder)
                             (funcall responder '(200 (:content-type "text/plain") ("ok")))))))
           (res (funcall app (lack/test:generate-env
                              "/" :headers '(("origin" . "http://example.com")))))
           (got nil))
      (funcall res (lambda (r) (setf got r)))
      (ok (equal (getf (second got) :access-control-allow-origin) "http://example.com"))
      (ok (equal (getf (second got) :vary) "Origin"))))

  (testing "koya's delivery CORS"
    (let ((mw (with-args *cors*
                :origin "*"
                :allow-methods '("GET")
                :allow-headers '("X-KOYA-DELIVERY-KEY")
                :max-age 86400)))
      (with-response ((lack:builder mw #'ok-app) "/delivery"
                      :method :options
                      :headers '(("origin" . "https://site.example")))
        (ok (= status 204))
        (ok (equal (header headers "access-control-allow-origin") "*"))
        (ok (equal (header headers "access-control-allow-methods") "GET"))
        (ok (equal (header headers "access-control-allow-headers") "X-KOYA-DELIVERY-KEY"))
        (ok (equal (header headers "access-control-max-age") "86400")))
      (with-response ((lack:builder mw (lambda (env)
                                         (declare (ignore env))
                                         (list 401 nil (list "no key"))))
                      "/delivery")
        (ok (= status 401))
        (ok (equal (header headers "access-control-allow-origin") "*"))))))
