(defpackage #:lack-mw-test/secure-headers
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:cl-ppcre)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/powered-by
                #:*powered-by*)
  (:import-from #:lack-mw/secure-headers
                #:*secure-headers*
                #:secure-headers-nonce))
(in-package #:lack-mw-test/secure-headers)

(defun raw-app (env)
  (declare (ignore env))
  '(200 (:content-type "text/plain") ("test")))

(defun app (&rest args)
  (lack:builder (apply #'with-args *secure-headers* args) #'raw-app))

(defmacro with-response ((headers &optional (body (gensym)) (status (gensym)))
                         (app &rest request-args) &body forms)
  `(testing-app ,app
     (multiple-value-bind (,body ,status ,headers) (request "/" ,@request-args)
       (declare (ignorable ,body ,status))
       ,@forms)))

(defun h (headers name)
  (gethash (string-downcase name) headers))

(defun check-defaults (headers)
  (ok (equal (h headers "X-Frame-Options") "SAMEORIGIN"))
  (ok (equal (h headers "Strict-Transport-Security") "max-age=15552000; includeSubDomains"))
  (ok (equal (h headers "X-Download-Options") "noopen"))
  (ok (equal (h headers "X-XSS-Protection") "0"))
  (ok (null (h headers "X-Powered-By")))
  (ok (equal (h headers "X-DNS-Prefetch-Control") "off"))
  (ok (equal (h headers "X-Content-Type-Options") "nosniff"))
  (ok (equal (h headers "Referrer-Policy") "no-referrer"))
  (ok (equal (h headers "X-Permitted-Cross-Domain-Policies") "none"))
  (ok (equal (h headers "Cross-Origin-Resource-Policy") "same-origin"))
  (ok (equal (h headers "Cross-Origin-Opener-Policy") "same-origin"))
  (ok (equal (h headers "Origin-Agent-Cluster") "?1")))

(deftest secure-headers-basic
  (testing "default middleware"
    (with-response (headers body status) ((app))
      (ok (eql status 200))
      (check-defaults headers)
      (ok (null (h headers "Cross-Origin-Embedder-Policy")))
      (ok (null (h headers "Permissions-Policy")))
      (ok (null (h headers "Content-Security-Policy")))
      (ok (null (h headers "Content-Security-Policy-Report-Only")))))

  (testing "all headers enabled"
    (with-response (headers body status)
        ((app :content-security-policy '(:default-src ("'self'"))
              :content-security-policy-report-only '(:default-src ("'self'"))
              :cross-origin-embedder-policy t
              :permissions-policy '(:camera ())))
      (ok (eql status 200))
      (check-defaults headers)
      (ok (equal (h headers "Cross-Origin-Embedder-Policy") "require-corp"))
      (ok (equal (h headers "Permissions-Policy") "camera=()"))
      (ok (equal (h headers "Content-Security-Policy") "default-src 'self'"))
      (ok (equal (h headers "Content-Security-Policy-Report-Only") "default-src 'self'"))))

  (testing "specific headers disabled"
    (with-response (headers) ((app :x-frame-options nil :x-xss-protection nil))
      (ok (null (h headers "X-Frame-Options")))
      (ok (null (h headers "X-XSS-Protection")))
      (ok (equal (h headers "X-Download-Options") "noopen"))
      (ok (null (h headers "Permissions-Policy")))))

  (testing "should remove x-powered-by header"
    ;; secure-headers outside powered-by: powered-by sets it first, then it is removed
    (with-response (headers) ((lack:builder *secure-headers* *powered-by* #'raw-app))
      (ok (null (h headers "X-Powered-By"))))
    (with-response (headers) ((lack:builder *powered-by* *secure-headers* #'raw-app))
      (ok (equal (h headers "X-Powered-By") "Lack")))
    (with-response (headers) ((lack:builder (with-args *secure-headers* :remove-powered-by nil)
                                            *powered-by* #'raw-app))
      (ok (equal (h headers "X-Powered-By") "Lack"))))

  (testing "should override Strict-Transport-Security header set by the app"
    (with-response (headers) ((lack:builder *secure-headers*
                                            (lambda (env)
                                              (declare (ignore env))
                                              '(200 (:strict-transport-security "Hono") ("ok")))))
      (ok (equal (h headers "Strict-Transport-Security")
                 "max-age=15552000; includeSubDomains"))))

  (testing "should use custom value when overridden"
    (with-response (headers)
        ((app :strict-transport-security "max-age=31536000; includeSubDomains; preload;"
              :x-frame-options "DENY"
              :x-xss-protection "1"))
      (ok (equal (h headers "Strict-Transport-Security")
                 "max-age=31536000; includeSubDomains; preload;"))
      (ok (equal (h headers "X-Frame-Options") "DENY"))
      (ok (equal (h headers "X-XSS-Protection") "1"))))

  (testing "should set Permissions-Policy header correctly"
    (with-response (headers)
        ((app :permissions-policy
              '(:fullscreen ("self")
                :bluetooth ("none")
                :payment ("self" "example.com")
                :sync-xhr ()
                :camera nil
                :microphone t
                :geolocation ("*")
                :usb ("self" "https://a.example.com" "https://b.example.com")
                :accelerometer ("https://*.example.com")
                :gyroscope ("src")
                :magnetometer ("https://a.example.com" "https://b.example.com")
                :mediasession ("self")
                :deferred-fetch ("none"))))
      (ok (equal (h headers "Permissions-Policy")
                 (concatenate 'string
                              "fullscreen=(self), bluetooth=(), payment=(self \"example.com\"), sync-xhr=(), camera=(), microphone=*, "
                              "geolocation=*, usb=(self \"https://a.example.com\" \"https://b.example.com\"), "
                              "accelerometer=(\"https://*.example.com\"), gyroscope=(src), "
                              "magnetometer=(\"https://a.example.com\" \"https://b.example.com\"), "
                              "mediasession=(self), deferred-fetch=()")))))

  (testing "delayed response"
    (let* ((mw (funcall *secure-headers*
                        (lambda (env)
                          (declare (ignore env))
                          (lambda (responder)
                            (funcall responder '(200 (:x-powered-by "x") ("ok")))))))
           (result nil))
      (funcall (funcall mw (lack/test:generate-env "/"))
               (lambda (res) (setf result res)))
      (ok (equal (getf (second result) :x-frame-options) "SAMEORIGIN"))
      (ok (null (getf (second result) :x-powered-by))))))

(defun nonce-app (&rest args)
  (lack:builder (apply #'with-args *secure-headers* args)
                (lambda (env)
                  `(200 (:content-type "text/plain")
                        (,(format nil "nonce: ~A" (secure-headers-nonce env)))))))

(defun set-nonce (env directive)
  (declare (ignore env))
  (values (format nil "'nonce-~(~A~)'" directive)
          (list (intern (format nil "TEST-~A-NONCE" directive) :keyword)
                (string-downcase (string directive)))))

(deftest secure-headers-csp
  (dolist (setting '((:content-security-policy "Content-Security-Policy")
                     (:content-security-policy-report-only "Content-Security-Policy-Report-Only")))
    (destructuring-bind (key header) setting
      (testing (format nil "CSP setting (~A)" key)
        (with-response (headers)
            ((app key '(:default-src ("'self'")
                        :base-uri ("'self'")
                        :font-src ("'self'" "https:" "data:")
                        :frame-ancestors ("'self'")
                        :img-src ("'self'" "data:")
                        :object-src ("'none'")
                        :script-src ("'self'")
                        :script-src-attr ("'none'")
                        :style-src ("'self'" "https:" "'unsafe-inline'")
                        :require-trusted-types-for ("'script'")
                        :trusted-types ("'none'"))))
          (ok (equal (h headers header)
                     "default-src 'self'; base-uri 'self'; font-src 'self' https: data:; frame-ancestors 'self'; img-src 'self' data:; object-src 'none'; script-src 'self'; script-src-attr 'none'; style-src 'self' https: 'unsafe-inline'; require-trusted-types-for 'script'; trusted-types 'none'"))))

      (testing (format nil "CSP setting one only (~A)" key)
        (with-response (headers) ((app key '(:default-src ("'self'"))))
          (ok (equal (h headers header) "default-src 'self'"))))

      (testing (format nil "CSP valueless directive (~A)" key)
        (with-response (headers) ((app key '(:default-src ("'self'") :upgrade-insecure-requests ())))
          (ok (equal (h headers header) "default-src 'self'; upgrade-insecure-requests"))))

      (testing (format nil "CSP with report-to (~A)" key)
        (with-response (headers)
            ((app :reporting-endpoints '((:name "endpoint-1" :url "https://example.com/reports"))
                  key '(:default-src ("'self'") :report-to "endpoint-1")))
          (ok (equal (h headers "Reporting-Endpoints") "endpoint-1=\"https://example.com/reports\""))
          (ok (equal (h headers header) "default-src 'self'; report-to endpoint-1")))
        (with-response (headers)
            ((app :report-to '((:group "endpoint-1" :max-age 10886400
                                :endpoints ((:url "https://example.com/reports"))))
                  key '(:default-src ("'self'") :report-to "endpoint-1")))
          (ok (equal (h headers "Report-To")
                     "{\"group\":\"endpoint-1\",\"max_age\":10886400,\"endpoints\":[{\"url\":\"https://example.com/reports\"}]}"))
          (ok (equal (h headers header) "default-src 'self'; report-to endpoint-1")))
        (with-response (headers)
            ((app :report-to '((:group "g1" :max-age 10886400
                                :endpoints ((:url "https://a.example.com/reports")
                                            (:url "https://b.example.com/reports")))
                               (:group "g2" :max-age 10886400
                                :endpoints ((:url "https://c.example.com/reports")
                                            (:url "https://d.example.com/reports"))))
                  key '(:default-src ("'self'") :report-to "g2")))
          (ok (equal (h headers "Report-To")
                     "{\"group\":\"g1\",\"max_age\":10886400,\"endpoints\":[{\"url\":\"https://a.example.com/reports\"},{\"url\":\"https://b.example.com/reports\"}]}, {\"group\":\"g2\",\"max_age\":10886400,\"endpoints\":[{\"url\":\"https://c.example.com/reports\"},{\"url\":\"https://d.example.com/reports\"}]}"))
          (ok (equal (h headers header) "default-src 'self'; report-to g2")))
        (with-response (headers)
            ((app :reporting-endpoints '((:name "e1" :url "https://a.example.com/reports")
                                         (:name "e2" :url "https://b.example.com/reports"))
                  key '(:default-src ("'self'") :report-to "e1")))
          (ok (equal (h headers "Reporting-Endpoints")
                     "e1=\"https://a.example.com/reports\", e2=\"https://b.example.com/reports\""))
          (ok (equal (h headers header) "default-src 'self'; report-to e1"))))

      (testing (format nil "CSP report-uri (~A)" key)
        (with-response (headers) ((app key '(:default-src ("'self'") :report-uri "/csp-report")))
          (ok (equal (h headers header) "default-src 'self'; report-uri /csp-report")))
        (with-response (headers) ((app key '(:default-src ("'self'")
                                             :report-uri ("/endpoint1" "/endpoint2"))))
          (ok (equal (h headers header) "default-src 'self'; report-uri /endpoint1 /endpoint2")))
        (with-response (headers) ((app key '(:default-src ("'self'")
                                             :report-to "endpoint-1"
                                             :report-uri "/legacy-report")))
          (ok (equal (h headers header)
                     "default-src 'self'; report-to endpoint-1; report-uri /legacy-report")))
        (with-response (headers) ((app key '(:default-src ("'self'"))))
          (ok (not (search "report-uri" (h headers header))))))

      (testing (format nil "CSP nonce for script-src (~A)" key)
        (with-response (headers body) ((nonce-app key '(:script-src ("'self'" :nonce))))
          (let* ((csp (h headers header))
                 (nonce (nth-value 1 (cl-ppcre:scan-to-strings
                                      "script-src 'self' 'nonce-([a-zA-Z0-9+/]+=*)'" csp))))
            (ok nonce)
            (ok (equal body (format nil "nonce: ~A" (aref nonce 0)))))))

      (testing (format nil "CSP nonce for script-src and style-src (~A)" key)
        (with-response (headers body) ((nonce-app key '(:script-src ("'self'" :nonce)
                                                        :style-src ("'self'" :nonce))))
          (let* ((csp (h headers header))
                 (nonce (aref (nth-value 1 (cl-ppcre:scan-to-strings
                                            "script-src 'self' 'nonce-([a-zA-Z0-9+/]+=*)'" csp))
                              0)))
            (ok (search (format nil "style-src 'self' 'nonce-~A'" nonce) csp))
            (ok (equal body (format nil "nonce: ~A" nonce))))))

      (testing (format nil "CSP nonce by app own function (~A)" key)
        (with-response (headers body)
            ((lack:builder
              (with-args *secure-headers* key (list :script-src (list "'self'" #'set-nonce)
                                                    :style-src (list "'self'" #'set-nonce)))
              (lambda (env)
                `(200 () (,(format nil "script: ~A, style: ~A"
                                   (getf env :test-script-src-nonce)
                                   (getf env :test-style-src-nonce)))))))
          (let ((csp (h headers header)))
            (ok (search "script-src 'self' 'nonce-script-src'" csp))
            (ok (search "style-src 'self' 'nonce-style-src'" csp))
            (ok (equal body "script: script-src, style: style-src")))))))

  (testing "CSP with combined modes"
    (with-response (headers)
        ((app :content-security-policy '(:default-src ("'self'"))
              :content-security-policy-report-only '(:script-src ("'self'" :nonce))))
      (ok (equal (h headers "Content-Security-Policy") "default-src 'self'"))
      (ok (cl-ppcre:scan "^script-src 'self' 'nonce-[a-zA-Z0-9+/]+=*'$"
                         (h headers "Content-Security-Policy-Report-Only"))))
    (with-response (headers)
        ((app :content-security-policy '(:script-src ("'self'" :nonce))
              :content-security-policy-report-only '(:default-src ("'self'"))))
      (ok (cl-ppcre:scan "^script-src 'self' 'nonce-[a-zA-Z0-9+/]+=*'$"
                         (h headers "Content-Security-Policy")))
      (ok (equal (h headers "Content-Security-Policy-Report-Only") "default-src 'self'")))
    (with-response (headers)
        ((app :content-security-policy '(:script-src ("'self'" :nonce))
              :content-security-policy-report-only '(:style-src ("'self'" :nonce))))
      (let ((nonce (aref (nth-value 1 (cl-ppcre:scan-to-strings
                                       "'nonce-([^']+)'" (h headers "Content-Security-Policy")))
                         0)))
        (ok (search (format nil "'nonce-~A'" nonce)
                    (h headers "Content-Security-Policy-Report-Only"))))))

  (testing "nonce differs per request"
    (let ((app (app :content-security-policy '(:script-src (:nonce)))))
      (ok (not (equal (with-response (headers) (app) (h headers "Content-Security-Policy"))
                      (with-response (headers) (app) (h headers "Content-Security-Policy"))))))))
