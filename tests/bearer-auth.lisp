(defpackage #:lack-mw-test/bearer-auth
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/bearer-auth
                #:*bearer-auth*
                #:timing-safe-equal))
(in-package #:lack-mw-test/bearer-auth)

(defparameter *token* "abcdefg12345-._~+/=")
(defparameter *tokens* (list *token* "alternative"))

(defun ok-app (body)
  (lambda (env)
    (declare (ignore env))
    `(200 (:content-type "text/plain" :x-custom "foo") (,body))))

(defun build (body &rest options)
  (lack:builder (apply #'with-args *bearer-auth* options) (ok-app body)))

(defmacro with-response ((body status headers) (app path &rest request-args) &body forms)
  `(testing-app ,app
     (multiple-value-bind (,body ,status ,headers) (request ,path ,@request-args)
       (declare (ignorable ,body ,status ,headers))
       ,@forms)))

(deftest basic
  (let ((app (build "auth" :token *token*)))
    (testing "authorize"
      (with-response (body status headers)
          (app "/auth/a" :headers `(("authorization" . ,(format nil "Bearer ~A" *token*))))
        (ok (= status 200))
        (ok (string= body "auth"))
        (ok (string= (gethash "x-custom" headers) "foo"))))
    (testing "prefix is case-insensitive"
      (dolist (prefix '("bearer" "BEARER" "BeArEr"))
        (with-response (body status headers)
            (app "/auth/a" :headers `(("authorization" . ,(format nil "~A ~A" prefix *token*))))
          (ok (= status 200)))))
    (testing "no authorization header"
      (with-response (body status headers) (app "/auth/a")
        (ok (= status 401))
        (ok (string= body "Unauthorized"))
        (ok (string= (gethash "www-authenticate" headers) "Bearer realm=\"\""))
        (ok (null (gethash "x-custom" headers)))))
    (testing "invalid request"
      (with-response (body status headers)
          (app "/auth/a" :headers '(("authorization" . "Beare abcdefg12345-._~+/=")))
        (ok (= status 400))
        (ok (string= body "Bad Request"))
        (ok (string= (gethash "www-authenticate" headers) "Bearer error=\"invalid_request\""))))
    (testing "invalid token"
      (with-response (body status headers)
          (app "/auth/a" :headers '(("authorization" . "Bearer invalid-token")))
        (ok (= status 401))
        (ok (string= body "Unauthorized"))
        (ok (string= (gethash "www-authenticate" headers) "Bearer error=\"invalid_token\""))))
    (testing "token is case-sensitive"
      (with-response (body status headers)
          (app "/auth/a" :headers `(("authorization" . ,(format nil "Bearer ~A" (string-upcase *token*)))))
        (ok (= status 401))))))

(deftest prefix-and-header
  (testing "custom prefix"
    (let ((app (build "auth bot" :token *token* :prefix "Bot")))
      (with-response (body status headers)
          (app "/" :headers '(("authorization" . "Bot abcdefg12345-._~+/=")))
        (ok (= status 200))
        (ok (string= body "auth bot")))
      (with-response (body status headers)
          (app "/" :headers '(("authorization" . "Bearer abcdefg12345-._~+/=")))
        (ok (= status 400))
        (ok (string= body "Bad Request")))))
  (testing "empty prefix with custom header"
    (let ((app (build "auth apiKey" :token *token* :prefix "" :header-name "X-Api-Key")))
      (with-response (body status headers)
          (app "/" :headers '(("x-api-key" . "abcdefg12345-._~+/=")))
        (ok (= status 200))
        (ok (string= body "auth apiKey")))
      (with-response (body status headers)
          (app "/" :headers '(("authorization" . "Bearer abcdefg12345-._~+/=")))
        (ok (= status 401))
        (ok (string= body "Unauthorized"))
        (ok (string= (gethash "www-authenticate" headers) "realm=\"\"")))))
  (testing "custom header"
    (let ((app (build "ok" :token *tokens* :header-name "X-Auth")))
      (with-response (body status headers)
          (app "/" :headers '(("x-auth" . "Bearer abcdefg12345-._~+/=")))
        (ok (= status 200)))
      (with-response (body status headers)
          (app "/" :headers '(("authorization" . "Bearer abcdefg12345-._~+/=")))
        (ok (= status 401)))))
  (testing "prefix with regex metacharacters"
    (with-response (body status headers)
        ((build "ok" :token "testtoken123" :prefix "Bearer(v2)")
         "/" :headers '(("authorization" . "Bearer(v2) testtoken123")))
      (ok (= status 200)))
    (with-response (body status headers)
        ((build "ok" :token "testtoken123" :prefix "X.Auth+v2")
         "/" :headers '(("authorization" . "X.Auth+v2 testtoken123")))
      (ok (= status 200)))
    (with-response (body status headers)
        ((build "ok" :token "testtoken123" :prefix "X.Y")
         "/" :headers '(("authorization" . "XZY testtoken123")))
      (ok (= status 400)))))

(deftest tokens-and-verify
  (testing "any token in list"
    (let ((app (build "auths" :token *tokens*)))
      (dolist (tk *tokens*)
        (with-response (body status headers)
            (app "/" :headers `(("authorization" . ,(format nil "Bearer ~A" tk))))
          (ok (= status 200))
          (ok (string= body "auths"))))))
  (testing "verify-token"
    (let ((app (build "verified"
                      :verify-token (lambda (token env)
                                      (and (string= (getf env :path-info) "/auth-verify-token")
                                           (string= token "dynamic-token"))))))
      (with-response (body status headers)
          (app "/auth-verify-token" :headers '(("authorization" . "Bearer dynamic-token")))
        (ok (= status 200))
        (ok (string= body "verified")))
      (with-response (body status headers)
          (app "/auth-verify-token" :headers '(("authorization" . "Bearer invalid-token")))
        (ok (= status 401))
        (ok (string= body "Unauthorized")))))
  (testing "hash-function"
    (let ((app (build "ok" :token *token* :hash-function #'string-upcase)))
      (with-response (body status headers)
          (app "/" :headers `(("authorization" . ,(format nil "Bearer ~A" *token*))))
        (ok (= status 200)))))
  (testing "requires token or verify-token"
    (ok (signals (funcall *bearer-auth* (ok-app "x")))))
  (testing "timing-safe-equal"
    (ok (timing-safe-equal "abc" "abc"))
    (ok (not (timing-safe-equal "abc" "abd")))
    (ok (not (timing-safe-equal "abc" "abcd")))
    (ok (not (timing-safe-equal "a" "b" (constantly "same"))))
    (ok (not (timing-safe-equal "a" "a" (constantly nil))))))

(deftest custom-error-responses
  (flet ((check (options request-headers status www-authenticate body &optional content-type)
           (with-response (b s h)
               ((apply #'build "ok" :token *tokens* options) "/" :headers request-headers)
             (ok (= s status))
             (ok (string= (gethash "www-authenticate" h) www-authenticate))
             (ok (string= b body))
             (when content-type
               (ok (string= (gethash "content-type" h) content-type))))))
    (let ((none '())
          (invalid '(("authorization" . "Beare abcdefg12345-._~+/=")))
          (wrong '(("authorization" . "Bearer invalid-token"))))
      (testing "no authentication header"
        (check '(:no-authentication-header
                 (:www-authenticate-header "Bearer error=\"Unauthorized\",error_description=\"Unauthorized\""))
               none 401 "Bearer error=\"Unauthorized\",error_description=\"Unauthorized\"" "Unauthorized")
        (check '(:no-authentication-header
                 (:www-authenticate-header (:error "Unauthorized" :error_description "Unauthorized")))
               none 401 "Bearer error=\"Unauthorized\",error_description=\"Unauthorized\"" "Unauthorized")
        (check `(:no-authentication-header
                 (:www-authenticate-header ,(lambda (env) (declare (ignore env))
                                              "Bearer error=\"Unauthorized\"")))
               none 401 "Bearer error=\"Unauthorized\"" "Unauthorized")
        (check `(:no-authentication-header
                 (:www-authenticate-header ,(lambda (env) (declare (ignore env))
                                              '(("error" . "Unauthorized")))))
               none 401 "Bearer error=\"Unauthorized\"" "Unauthorized")
        (check '(:no-authentication-header (:message "Custom no authentication header message as string"))
               none 401 "Bearer realm=\"\"" "Custom no authentication header message as string"
               "text/plain; charset=UTF-8")
        (check '(:no-authentication-header
                 (:message (:message "Custom no authentication header message as object")))
               none 401 "Bearer realm=\"\""
               "{\"message\":\"Custom no authentication header message as object\"}"
               "application/json")
        (check `(:no-authentication-header
                 (:message ,(lambda (env) (declare (ignore env)) "from function")))
               none 401 "Bearer realm=\"\"" "from function")
        (check '(:no-authentication-header-message "deprecated option")
               none 401 "Bearer realm=\"\"" "deprecated option"))
      (testing "invalid authentication header"
        (check '(:invalid-authentication-header
                 (:www-authenticate-header "Bearer error=\"invalid_request\",error_description=\"Custom\""))
               invalid 400 "Bearer error=\"invalid_request\",error_description=\"Custom\"" "Bad Request")
        (check '(:invalid-authentication-header
                 (:www-authenticate-header (:error "invalid_request" :error_description "Custom")))
               invalid 400 "Bearer error=\"invalid_request\",error_description=\"Custom\"" "Bad Request")
        (check '(:invalid-authentication-header (:message "Custom invalid"))
               invalid 400 "Bearer error=\"invalid_request\"" "Custom invalid")
        (check `(:invalid-authentication-header
                 (:message ,(lambda (env) (declare (ignore env)) '(:message "obj"))))
               invalid 400 "Bearer error=\"invalid_request\"" "{\"message\":\"obj\"}" "application/json")
        (check '(:invalid-authentication-header-message "deprecated")
               invalid 400 "Bearer error=\"invalid_request\"" "deprecated"))
      (testing "invalid token"
        (check '(:invalid-token
                 (:www-authenticate-header "Bearer error=\"invalid_token\",error_description=\"Custom\""))
               wrong 401 "Bearer error=\"invalid_token\",error_description=\"Custom\"" "Unauthorized")
        (check '(:invalid-token
                 (:www-authenticate-header (:error "invalid_token" :error_description "Custom")))
               wrong 401 "Bearer error=\"invalid_token\",error_description=\"Custom\"" "Unauthorized")
        (check '(:invalid-token (:message "Custom invalid token"))
               wrong 401 "Bearer error=\"invalid_token\"" "Custom invalid token")
        (check '(:invalid-token (:message (:message "Custom invalid token message as object")))
               wrong 401 "Bearer error=\"invalid_token\""
               "{\"message\":\"Custom invalid token message as object\"}" "application/json")
        (check '(:invalid-token-message "deprecated")
               wrong 401 "Bearer error=\"invalid_token\"" "deprecated"))
      (testing "realm is escaped"
        (check '(:realm "my \"realm\"") none 401 "Bearer realm=\"my \\\"realm\\\"\"" "Unauthorized")))))
