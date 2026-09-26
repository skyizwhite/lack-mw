(defpackage #:lack-mw-test/jwt
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:jose)
  (:import-from #:jose/base64
                #:base64url-decode)
  (:import-from #:ironclad)
  (:import-from #:babel)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/jwt
                #:*jwt*
                #:jwt-payload
                #:jwk-get
                #:jwk-to-key))
(in-package #:lack-mw-test/jwt)

(defparameter *credential*
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.B54pAqIiLbu170tGQ1rY06Twv__0qSHTA0ioQPIOvFE")

(defparameter *invalid-credential*
  "ssyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.B54pAqIiLbu170tGQ1rY06Twv__0qSHTA0ioQPIOvFE")

(defparameter *public-jwks*
  ;; from hono/src/middleware/jwk/keys.test.json
  '((:kid "hono-test-kid-1" :kty "RSA" :use "sig" :alg "RS256" :e "AQAB" :n "2XGQh8VC_p8gRqfBLY0E3RycnfBl5g1mKyeiyRSPjdaR7fmNPuC3mHjVWXtyXWSvAuRYPYfL_pSi6erpxVv7NuPJbKaZ-I1MwdRPdG2qHu9mNYxniws73gvF3tUN9eSsQUIBL0sYEOnVMjniDcOxIr3Rgz_RxdLB_FxTDXYhzzG49L79wGV1udILGHq0lqlMtmUX6LRtbaoRt1fJB4rTCkYeQp9r5HYP79PKTR43vLIq0aZryI4CyBkPG_0vGEvnzasGdp-qE9Ywt_J2anQKt3nvVVR4Yhs2EIoPQkYoDnVySjeuRsUA5JQYKThrM4sFZSQsO82dHTvwKo2z2x6ZMw")
    (:kid "hono-test-kid-2" :kty "RSA" :use "sig" :alg "RS256" :e "AQAB" :n "uRVR5DkH22a_FM4RtqvnVxd6QAjdfj8oFYPaxIux7K8oTaBy5YagxTWN0qeKI5lI3nL20cx72XxD_UF4TETCFgfD-XB48cdjnSQlOXXbRPXUX0Rdte48naAt4przAb7ydUxrfvDlbSZe02Du-ZGRzEB6RW6KLFWUvTadI4w33qb2i8hauQuTcRmaIUESt8oytUGS44dXAw3Nqt_NL-e7TRgX5o1u_31Uvet1ofsv6Mx8vxJ6zMdM_AKvzLt2iuoK_8vL4R86CjD3dpal2BwO7RkRl2Wcuf5jxjM4pruJ2RBCpzBieEvSIH8kKHIm9SfTzTDJqRhoXd7KM5jL1GNzyw")))

(defparameter *private-jwks*
  '((:kid "hono-test-kid-1" :n "2XGQh8VC_p8gRqfBLY0E3RycnfBl5g1mKyeiyRSPjdaR7fmNPuC3mHjVWXtyXWSvAuRYPYfL_pSi6erpxVv7NuPJbKaZ-I1MwdRPdG2qHu9mNYxniws73gvF3tUN9eSsQUIBL0sYEOnVMjniDcOxIr3Rgz_RxdLB_FxTDXYhzzG49L79wGV1udILGHq0lqlMtmUX6LRtbaoRt1fJB4rTCkYeQp9r5HYP79PKTR43vLIq0aZryI4CyBkPG_0vGEvnzasGdp-qE9Ywt_J2anQKt3nvVVR4Yhs2EIoPQkYoDnVySjeuRsUA5JQYKThrM4sFZSQsO82dHTvwKo2z2x6ZMw" :e "AQAB" :d "A5CR2gGPegHwOYUbUzylZvdgUFNWMetOUK7M3TClGdVgSkWpELrTLhpTa3m50KYlG446x03baxUGU4D_MoKx7GukX0-fGCzY17FvWNOwOLACcPMYT3ZwfAQ2_jkBimJxU7CNUtH18KQ-U1B3nQ1apHZc-1Xa6CKIY5nv32yfj6uTrERRLOs7Fn9xpOE4uMHEf-l1ppIEIqK5QkEoPRMCUBABsGBSfiJP2hQVa-R-nezX3kVSxKTxAjDEOkquzb-CKlJW7xN2xQ7p40Wi7lDWZkOapBNGr59Z4gcFfo6f8XpQrqoFjDfsGsdH5q9MH_3lEEtD14wymXNnCoRHNr_mwQ")
    (:kid "hono-test-kid-2" :n "uRVR5DkH22a_FM4RtqvnVxd6QAjdfj8oFYPaxIux7K8oTaBy5YagxTWN0qeKI5lI3nL20cx72XxD_UF4TETCFgfD-XB48cdjnSQlOXXbRPXUX0Rdte48naAt4przAb7ydUxrfvDlbSZe02Du-ZGRzEB6RW6KLFWUvTadI4w33qb2i8hauQuTcRmaIUESt8oytUGS44dXAw3Nqt_NL-e7TRgX5o1u_31Uvet1ofsv6Mx8vxJ6zMdM_AKvzLt2iuoK_8vL4R86CjD3dpal2BwO7RkRl2Wcuf5jxjM4pruJ2RBCpzBieEvSIH8kKHIm9SfTzTDJqRhoXd7KM5jL1GNzyw" :e "AQAB" :d "JCIL50TVClnQQyUJ40JDO0b7mGXCrCNzVWP1ATsOhNkbQrBozfOPDoEqi24m81U5GyiRlBraMPboJRizfhxMUdW5RkjVa8pT4blNRR8DrD5b9C9aJir5DYLYgm1itLwNBKZjNBieicUcbSL29KUdNCWAWW6_rfEVRS1U1zxIKgDUPVd6d7jiIwAKuKvGlMc11RGRZj5eKSNMQyLU5u8Qs_VQuoBRNAyWLZZcHMlAWbh3er7m0jkmUDRdVU0y_n1UAGsr9cAxPwf2HtS5j5R2ahEodatsJynnafYtj6jbOR6jvO3N2Vf-NJ7jVY2-kfv1rJd86KAxD-tIAGx2w1VRTQ")))

(defparameter *asymmetric-fixtures*
  ;; generated with openssl
  '((:alg "ES256" :jwk (:kty "EC" :crv "P-256" :x "bIGgtHLBRZq0U082jXh7KfdcPYyXqxcxyU2bBe743-o" :y "y3EbN6aC0fsKGsfC5HBV7xquekh7s39r3xoyftxzfVU" :kid "ES256-kid")
  :token "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkVTMjU2LWtpZCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.Mjy-ycvRbN0NeHUbzfPdxG65CCcKqqgDAu9hhtosGoCGsDYlJBlJf44Jyma-RdDnDOiXvDSkkOgkXsHVla1fkg")
    (:alg "ES384" :jwk (:kty "EC" :crv "P-384" :x "t9HM9vLudcQqPJxEHon86Vw3TCMdmojEG3B4klujob0e5hxTGuenBOhwxghIy3gq" :y "zFYWia9fRWeZK61dK81sWHTBkF6i2IPd9vTfozOlkCz_V9JUs1_SMzp7He51-Joc" :kid "ES384-kid")
  :token "eyJhbGciOiJFUzM4NCIsInR5cCI6IkpXVCIsImtpZCI6IkVTMzg0LWtpZCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.2uxo5BukG7-9DWqfahuHsJnkEYHzZs5fBM1P7SeyVT-N1YfzXIGXfGsElJvDvofj29YPfjAyiG3vOjV7Isg6t7CS8twz_E0VZDOsuH99m6tCq4-0dXCFTjsGmrxXrZBX")
    (:alg "ES512" :jwk (:kty "EC" :crv "P-521" :x "AGxXrgxY9J6Ei5BAsft3ar5XFzqXE-W-JlHT3dDxiGqXiDJmVMDoXarub7cc6iCNmO3g3yOxi4avzmHyfo_CfpLk" :y "AOcnt3EUII4EQFSYzLZ_g82mw2g5Hnqz2Sj4H9sMlOeaU315g_m3CfLGcT8dKxIj_PpxDVFDjOLWzP4JaP7ObhuN" :kid "ES512-kid")
  :token "eyJhbGciOiJFUzUxMiIsInR5cCI6IkpXVCIsImtpZCI6IkVTNTEyLWtpZCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.AXNiWkAndyLogTvxY9lcF_2zM3ISgHJ7ys1gLqE4I9uCoMTq8rEj4Zg21HcNFPUDOtFXayWd-2SRbOpCvaDqyCazAWxVwlcO3B32L2giT1KrLFDo2z0hsJUiMll1TzrLrorwlI9UVwVwCe0p58zQmQM2YJu8ZKCM8pciBeMja-0cuihf")
    (:alg "EdDSA" :jwk (:kty "OKP" :crv "Ed25519" :x "dEMMXOwp9BHhuFv3k0DtmBGaJRrJ2CVXhPZRfzCmRZ4" :kid "ed-kid")
  :token "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCIsImtpZCI6ImVkLWtpZCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.DCZ9XnGkz2fqFbVUysOSRVHa2q-VS4zvf0GMV2GEr1IE3OQLqcC-8S6uRwwKgfMubgiw6y_sLXVdEawy5odrCg")))

(defun rsa-private-key (jwk)
  (ironclad:make-private-key :rsa
                             :n (base64url-decode (jwk-get jwk "n") :as :integer)
                             :d (base64url-decode (jwk-get jwk "d") :as :integer)))

(defun now () (- (get-universal-time) #.(encode-universal-time 0 0 0 1 1 1970 0)))

(defun payload-app (env)
  `(200 (:content-type "text/plain")
        (,(or (cdr (assoc "message" (jwt-payload env) :test #'string=)) "no message"))))

(defun build (&rest options)
  (lack:builder (apply #'with-args *jwt* options) #'payload-app))

(defmacro with-response ((body status headers) (app path &rest request-args) &body forms)
  `(testing-app ,app
     (multiple-value-bind (,body ,status ,headers) (request ,path ,@request-args)
       (declare (ignorable ,body ,status ,headers))
       ,@forms)))

(defun bearer (token &optional (name "authorization") (scheme "Bearer"))
  `((,name . ,(format nil "~A ~A" scheme token))))

(deftest credentials-in-header
  (let ((app (build :secret "a-secret" :alg "HS256")))
    (testing "not authorize without credentials"
      (with-response (body status headers) (app "http://localhost/auth/a")
        (ok (= status 401))
        (ok (string= body "Unauthorized"))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_request\",error_description=\"no authorization included in request\""))))
    (testing "authorize"
      (dolist (scheme '("Bearer" "bearer" "bEaReR"))
        (with-response (body status headers)
            (app "/auth/a" :headers (bearer *credential* "authorization" scheme))
          (ok (= status 200))
          (ok (string= body "hello world")))))
    (testing "non-Bearer scheme"
      (with-response (body status headers)
          (app "http://localhost/auth/a" :headers (bearer *credential* "authorization" "Basic"))
        (ok (= status 401))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_request\",error_description=\"invalid credentials structure\""))))
    (testing "invalid token"
      (with-response (body status headers)
          (app "http://localhost/auth/a" :headers (bearer *invalid-credential*))
        (ok (= status 401))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_token\",error_description=\"token verification failure\""))))
    (testing "token with space"
      (with-response (body status headers)
          (app "http://localhost/auth/a" :headers (bearer "invalid token"))
        (ok (= status 401))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_request\",error_description=\"invalid credentials structure\""))))
    (testing "wrong secret"
      (with-response (body status headers)
          ((build :secret "another-secret" :alg :hs256) "/" :headers (bearer *credential*))
        (ok (= status 401))))))

(deftest credentials-in-custom-header
  (let ((app (build :secret "a-secret" :alg "HS256" :header-name "x-custom-auth-header")))
    (with-response (body status headers) (app "/auth/a")
      (ok (= status 401)))
    (testing "ignore default authorization header"
      (with-response (body status headers)
          (app "http://localhost/auth/a" :headers (bearer *credential*))
        (ok (= status 401))
        (ok (search "no authorization included in request" (gethash "www-authenticate" headers)))))
    (with-response (body status headers)
        (app "/auth/a" :headers (bearer *credential* "x-custom-auth-header"))
      (ok (= status 200))
      (ok (string= body "hello world")))
    (with-response (body status headers)
        (app "/auth/a" :headers (bearer *credential* "x-custom-auth-header" "Basic"))
      (ok (= status 401))
      (ok (search "invalid credentials structure" (gethash "www-authenticate" headers))))
    (with-response (body status headers)
        (app "/auth/a" :headers (bearer *invalid-credential* "x-custom-auth-header"))
      (ok (= status 401))
      (ok (search "token verification failure" (gethash "www-authenticate" headers))))))

(deftest credentials-in-cookie
  (testing "plain cookie"
    (let ((app (build :secret "a-secret" :alg "HS256" :cookie "access_token")))
      (with-response (body status headers) (app "/auth/a")
        (ok (= status 401))
        (ok (string= body "Unauthorized")))
      (with-response (body status headers)
          (app "/auth/a" :headers `(("cookie" . ,(format nil "access_token=~A" *credential*))))
        (ok (= status 200))
        (ok (string= body "hello world")))
      (with-response (body status headers)
          (app "http://localhost/auth/a"
               :headers `(("cookie" . ,(format nil "access_token=~A" *invalid-credential*))))
        (ok (= status 401))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_token\",error_description=\"token verification failure\"")))))
  (testing "signed cookie with prefix options"
    (let ((app (build :secret "a-secret" :alg "HS256"
                      :cookie '(:key "cookie_name" :secret "cookie_secret" :prefix-options :host))))
      (with-response (body status headers) (app "/auth/a")
        (ok (= status 401)))
      (with-response (body status headers)
          (app "/auth/a" :headers `(("cookie" . ,(format nil "__Host-cookie_name=~A.i2NSvtJOXOPS9NDL1u8dqTYmMrzcD4mNSws6P6qmeV0%3D; Path=/" *credential*))))
        (ok (= status 200))
        (ok (string= body "hello world")))))
  (testing "signed cookie without prefix options"
    (let ((app (build :secret "a-secret" :alg "HS256"
                      :cookie '(:key "cookie_name" :secret "cookie_secret"))))
      (with-response (body status headers)
          (app "/auth/a" :headers `(("cookie" . ,(format nil "cookie_name=~A.i2NSvtJOXOPS9NDL1u8dqTYmMrzcD4mNSws6P6qmeV0%3D; Path=/" *credential*))))
        (ok (= status 200)))
      (testing "unsigned cookie is rejected"
        (with-response (body status headers)
            (app "/auth/a" :headers `(("cookie" . ,(format nil "cookie_name=~A" *credential*))))
          (ok (= status 401))))
      (testing "bad signature is rejected"
        (with-response (body status headers)
            (app "/auth/a" :headers `(("cookie" . ,(format nil "cookie_name=~A.j2NSvtJOXOPS9NDL1u8dqTYmMrzcD4mNSws6P6qmeV0%3D" *credential*))))
          (ok (= status 401))))))
  (testing "cookie object with and without prefix options"
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "HS256" :cookie '(:key "cookie_name" :prefix-options :host))
         "/auth/a" :headers `(("cookie" . ,(format nil "__Host-cookie_name=~A" *credential*))))
      (ok (= status 200)))
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "HS256" :cookie '(:key "cookie_name"))
         "/auth/a" :headers `(("cookie" . ,(format nil "cookie_name=~A" *credential*))))
      (ok (= status 200)))))

(deftest options
  (testing "secret and alg are required"
    (ok (signals (funcall *jwt* #'payload-app :alg "HS256")))
    (ok (signals (funcall *jwt* #'payload-app :secret "a-secret")))
    (ok (signals (funcall *jwt* #'payload-app :secret "a-secret" :alg "XX999"))))
  (testing "mismatched algorithm is rejected"
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "RS256") "/" :headers (bearer *credential*))
      (ok (= status 401))))
  (testing "realm"
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "HS256") "http://localhost/auth/page?a=1")
      (ok (string= (gethash "www-authenticate" headers)
                   "Bearer realm=\"http://localhost/auth/page?a=1\",error=\"invalid_request\",error_description=\"no authorization included in request\"")))
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "HS256" :realm "my-api") "/auth/page")
      (ok (string= (gethash "www-authenticate" headers)
                   "Bearer realm=\"my-api\",error=\"invalid_request\",error_description=\"no authorization included in request\"")))
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "HS256" :realm "my-api") "/auth/page"
         :headers (bearer "invalid-token"))
      (ok (string= (gethash "www-authenticate" headers)
                   "Bearer realm=\"my-api\",error=\"invalid_token\",error_description=\"token verification failure\"")))
    (with-response (body status headers)
        ((build :secret "a-secret" :alg "HS256" :realm "my \"quoted\" api") "/auth/page")
      (ok (string= (gethash "www-authenticate" headers)
                   "Bearer realm=\"my \\\"quoted\\\" api\",error=\"invalid_request\",error_description=\"no authorization included in request\"")))))

(defun sign-hs256 (claims)
  (jose:encode :hs256 (babel:string-to-octets "a-secret") claims))

(defun status-for (claims &rest verification)
  (with-response (body status headers)
      ((build :secret "a-secret" :alg "HS256" :verification verification)
       "/" :headers (bearer (sign-hs256 claims)))
    status))

(deftest verification
  (let ((future (+ (now) 100)) (past (- (now) 100)))
    (testing "exp/nbf/iat pass when good"
      (ok (= 200 (status-for `(("exp" . ,future) ("nbf" . ,past) ("iat" . ,past)))))
      (ok (= 200 (status-for `(("exp" . ,(+ future 0.5d0)) ("nbf" . ,(- past 0.5d0)))))))
    (testing "exp"
      (ok (= 401 (status-for `(("exp" . ,past)))))
      (ok (= 401 (status-for `(("exp" . ,(now))))))
      (ok (= 401 (status-for '(("exp" . "soon")))))
      (ok (= 200 (status-for `(("exp" . ,past)) :exp nil))))
    (testing "nbf"
      (ok (= 401 (status-for `(("nbf" . ,future)))))
      (ok (= 200 (status-for `(("nbf" . ,future)) :nbf nil))))
    (testing "iat"
      (ok (= 401 (status-for `(("iat" . ,future)))))
      (ok (= 200 (status-for `(("iat" . ,future)) :iat nil))))
    (testing "iss"
      (ok (= 200 (status-for '(("iss" . "http://issuer.test")) :iss "http://issuer.test")))
      (ok (= 401 (status-for '(("message" . "x")) :iss "http://issuer.test")))
      (ok (= 401 (status-for '(("iss" . "http://bad-issuer.test")) :iss "http://issuer.test")))
      (ok (= 200 (status-for '(("iss" . "http://issuer.test"))
                             :iss (lambda (iss) (search "issuer.test" iss))))))
    (testing "aud"
      (ok (= 200 (status-for '(("aud" . "a")) :aud "a")))
      (ok (= 200 (status-for '(("aud" . ("x" "b"))) :aud '("a" "b"))))
      (ok (= 401 (status-for '(("aud" . "c")) :aud '("a" "b"))))
      (ok (= 401 (status-for '(("message" . "x")) :aud "a"))))
    (testing "empty payload is valid"
      (ok (= 200 (status-for '()))))))

(deftest asymmetric
  (testing "RS/PS with an ironclad key and a JWK"
    (let* ((private (rsa-private-key (first *private-jwks*)))
           (public (first *public-jwks*))
           (claims '(("message" . "hello world"))))
      (dolist (alg '(:rs256 :rs384 :rs512 :ps256 :ps384 :ps512))
        (let ((token (jose:encode alg private claims)))
          (with-response (body status headers)
              ((build :secret (jwk-to-key public) :alg alg) "/" :headers (bearer token))
            (ok (= status 200) (format nil "~A with ironclad key" alg)))
          (with-response (body status headers)
              ((build :secret public :alg alg) "/" :headers (bearer token))
            (ok (= status 200) (format nil "~A with JWK" alg)))))
      (testing "other key is rejected"
        (with-response (body status headers)
            ((build :secret (second *public-jwks*) :alg :rs256)
             "/" :headers (bearer (jose:encode :rs256 private claims)))
          (ok (= status 401))))))
  (testing "ES/EdDSA (tokens signed by openssl)"
    (dolist (fixture *asymmetric-fixtures*)
      (destructuring-bind (&key alg jwk token) fixture
        (with-response (body status headers)
            ((build :secret jwk :alg alg) "/" :headers (bearer token))
          (ok (= status 200) (format nil "~A accepted" alg))
          (ok (string= body "hello world")))
        (let ((tampered (concatenate 'string (subseq token 0 (- (length token) 2))
                                     (if (char= (char token (- (length token) 2)) #\A) "BA" "AA"))))
          (with-response (body status headers)
              ((build :secret jwk :alg alg) "/" :headers (bearer tampered))
            (ok (= status 401) (format nil "~A tampered rejected" alg))))
        (with-response (body status headers)
            ((build :secret jwk :alg (if (string= alg "ES256") "ES384" "ES256"))
             "/" :headers (bearer token))
          (ok (= status 401) (format nil "~A with other alg rejected" alg)))))))
