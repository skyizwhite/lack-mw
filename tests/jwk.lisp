(defpackage #:lack-mw-test/jwk
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
  (:import-from #:cl-base64)
  (:import-from #:quri)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/jwk
                #:*jwk*
                #:jwt-payload)
  (:import-from #:lack-mw/jwt
                #:jwk-get))
(in-package #:lack-mw-test/jwk)

(defparameter *public-jwks*
  ;; from hono/src/middleware/jwk/keys.test.json
  '((:kid "hono-test-kid-1" :kty "RSA" :use "sig" :alg "RS256" :e "AQAB" :n "2XGQh8VC_p8gRqfBLY0E3RycnfBl5g1mKyeiyRSPjdaR7fmNPuC3mHjVWXtyXWSvAuRYPYfL_pSi6erpxVv7NuPJbKaZ-I1MwdRPdG2qHu9mNYxniws73gvF3tUN9eSsQUIBL0sYEOnVMjniDcOxIr3Rgz_RxdLB_FxTDXYhzzG49L79wGV1udILGHq0lqlMtmUX6LRtbaoRt1fJB4rTCkYeQp9r5HYP79PKTR43vLIq0aZryI4CyBkPG_0vGEvnzasGdp-qE9Ywt_J2anQKt3nvVVR4Yhs2EIoPQkYoDnVySjeuRsUA5JQYKThrM4sFZSQsO82dHTvwKo2z2x6ZMw")
    (:kid "hono-test-kid-2" :kty "RSA" :use "sig" :alg "RS256" :e "AQAB" :n "uRVR5DkH22a_FM4RtqvnVxd6QAjdfj8oFYPaxIux7K8oTaBy5YagxTWN0qeKI5lI3nL20cx72XxD_UF4TETCFgfD-XB48cdjnSQlOXXbRPXUX0Rdte48naAt4przAb7ydUxrfvDlbSZe02Du-ZGRzEB6RW6KLFWUvTadI4w33qb2i8hauQuTcRmaIUESt8oytUGS44dXAw3Nqt_NL-e7TRgX5o1u_31Uvet1ofsv6Mx8vxJ6zMdM_AKvzLt2iuoK_8vL4R86CjD3dpal2BwO7RkRl2Wcuf5jxjM4pruJ2RBCpzBieEvSIH8kKHIm9SfTzTDJqRhoXd7KM5jL1GNzyw")))

(defparameter *private-jwks*
  '((:kid "hono-test-kid-1" :n "2XGQh8VC_p8gRqfBLY0E3RycnfBl5g1mKyeiyRSPjdaR7fmNPuC3mHjVWXtyXWSvAuRYPYfL_pSi6erpxVv7NuPJbKaZ-I1MwdRPdG2qHu9mNYxniws73gvF3tUN9eSsQUIBL0sYEOnVMjniDcOxIr3Rgz_RxdLB_FxTDXYhzzG49L79wGV1udILGHq0lqlMtmUX6LRtbaoRt1fJB4rTCkYeQp9r5HYP79PKTR43vLIq0aZryI4CyBkPG_0vGEvnzasGdp-qE9Ywt_J2anQKt3nvVVR4Yhs2EIoPQkYoDnVySjeuRsUA5JQYKThrM4sFZSQsO82dHTvwKo2z2x6ZMw" :e "AQAB" :d "A5CR2gGPegHwOYUbUzylZvdgUFNWMetOUK7M3TClGdVgSkWpELrTLhpTa3m50KYlG446x03baxUGU4D_MoKx7GukX0-fGCzY17FvWNOwOLACcPMYT3ZwfAQ2_jkBimJxU7CNUtH18KQ-U1B3nQ1apHZc-1Xa6CKIY5nv32yfj6uTrERRLOs7Fn9xpOE4uMHEf-l1ppIEIqK5QkEoPRMCUBABsGBSfiJP2hQVa-R-nezX3kVSxKTxAjDEOkquzb-CKlJW7xN2xQ7p40Wi7lDWZkOapBNGr59Z4gcFfo6f8XpQrqoFjDfsGsdH5q9MH_3lEEtD14wymXNnCoRHNr_mwQ")
    (:kid "hono-test-kid-2" :n "uRVR5DkH22a_FM4RtqvnVxd6QAjdfj8oFYPaxIux7K8oTaBy5YagxTWN0qeKI5lI3nL20cx72XxD_UF4TETCFgfD-XB48cdjnSQlOXXbRPXUX0Rdte48naAt4przAb7ydUxrfvDlbSZe02Du-ZGRzEB6RW6KLFWUvTadI4w33qb2i8hauQuTcRmaIUESt8oytUGS44dXAw3Nqt_NL-e7TRgX5o1u_31Uvet1ofsv6Mx8vxJ6zMdM_AKvzLt2iuoK_8vL4R86CjD3dpal2BwO7RkRl2Wcuf5jxjM4pruJ2RBCpzBieEvSIH8kKHIm9SfTzTDJqRhoXd7KM5jL1GNzyw" :e "AQAB" :d "JCIL50TVClnQQyUJ40JDO0b7mGXCrCNzVWP1ATsOhNkbQrBozfOPDoEqi24m81U5GyiRlBraMPboJRizfhxMUdW5RkjVa8pT4blNRR8DrD5b9C9aJir5DYLYgm1itLwNBKZjNBieicUcbSL29KUdNCWAWW6_rfEVRS1U1zxIKgDUPVd6d7jiIwAKuKvGlMc11RGRZj5eKSNMQyLU5u8Qs_VQuoBRNAyWLZZcHMlAWbh3er7m0jkmUDRdVU0y_n1UAGsr9cAxPwf2HtS5j5R2ahEodatsJynnafYtj6jbOR6jvO3N2Vf-NJ7jVY2-kfv1rJd86KAxD-tIAGx2w1VRTQ")))

(defparameter *es256-jwk*
  ;; generated with openssl
  '(:kty "EC" :crv "P-256" :x "bIGgtHLBRZq0U082jXh7KfdcPYyXqxcxyU2bBe743-o" :y "y3EbN6aC0fsKGsfC5HBV7xquekh7s39r3xoyftxzfVU" :kid "ES256-kid"))

(defparameter *es256-token*
  "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IkVTMjU2LWtpZCJ9.eyJtZXNzYWdlIjoiaGVsbG8gd29ybGQifQ.Mjy-ycvRbN0NeHUbzfPdxG65CCcKqqgDAu9hhtosGoCGsDYlJBlJf44Jyma-RdDnDOiXvDSkkOgkXsHVla1fkg")

(defun now () (- (get-universal-time) #.(encode-universal-time 0 0 0 1 1 1970 0)))

(defun private-key (kid)
  (let ((jwk (find kid *private-jwks* :key (lambda (k) (jwk-get k "kid")) :test #'string=)))
    (ironclad:make-private-key :rsa
                               :n (base64url-decode (jwk-get jwk "n") :as :integer)
                               :d (base64url-decode (jwk-get jwk "d") :as :integer))))

(defun sign (claims &key (kid "hono-test-kid-1") (key-kid kid) (alg :rs256))
  (jose:encode alg (private-key key-kid) claims :headers (and kid `(("kid" . ,kid)))))

(defparameter *hello* '(("message" . "hello world")))

(defun payload-app (env)
  `(200 (:content-type "text/plain")
        (,(or (cdr (assoc "message" (jwt-payload env) :test #'string=)) "no message"))))

(defun build (&rest options)
  (lack:builder (apply #'with-args *jwk* options) #'payload-app))

(defmacro with-response ((body status headers) (app path &rest request-args) &body forms)
  `(testing-app ,app
     (multiple-value-bind (,body ,status ,headers) (request ,path ,@request-args)
       (declare (ignorable ,body ,status ,headers))
       ,@forms)))

(defun bearer (token &optional (name "authorization") (scheme "Bearer"))
  `((,name . ,(format nil "~A ~A" scheme token))))

(deftest options
  (ok (signals (funcall *jwk* #'payload-app :alg '("RS256"))))
  (ok (signals (funcall *jwk* #'payload-app :keys *public-jwks*)))
  (ok (signals (funcall *jwk* #'payload-app :keys *public-jwks* :alg '("HS256")))))

(deftest allow-anon
  (let ((app (build :keys *public-jwks* :alg '("RS256") :allow-anon t)))
    (with-response (body status headers) (app "/")
      (ok (= status 200))
      (ok (string= body "no message")))
    (with-response (body status headers) (app "/" :headers (bearer (sign *hello*)))
      (ok (= status 200))
      (ok (string= body "hello world")))
    (with-response (body status headers) (app "/" :headers (bearer (sign *hello*) "authorization" "Basic"))
      (ok (= status 401)))
    (with-response (body status headers) (app "/" :headers (bearer "invalid-token"))
      (ok (= status 401)))))

(deftest credentials-in-header
  (let ((app (build :keys *public-jwks* :alg '("RS256"))))
    (testing "missing token"
      (with-response (body status headers) (app "http://localhost/auth/a")
        (ok (= status 401))
        (ok (string= body "Unauthorized"))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_request\",error_description=\"no authorization included in request\""))))
    (testing "static keys"
      (dolist (kid '("hono-test-kid-1" "hono-test-kid-2"))
        (with-response (body status headers) (app "/" :headers (bearer (sign *hello* :kid kid)))
          (ok (= status 200))
          (ok (string= body "hello world")))))
    (testing "unicode payload"
      (with-response (body status headers)
          (app "/" :headers (bearer (sign '(("message" . "こんにちは世界")))))
        (ok (= status 200))
        (ok (string= body "こんにちは世界"))))
    (testing "mixed-case scheme"
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello*) "authorization" "bEaReR"))
        (ok (= status 200))))
    (testing "token without header"
      (let ((token (sign *hello*)))
        (with-response (body status headers)
            (app "/" :headers (bearer (subseq token (1+ (position #\. token)))))
          (ok (= status 401)))))
    (testing "missing kid"
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello* :kid nil :key-kid "hono-test-kid-1")))
        (ok (= status 401))))
    (testing "unknown kid"
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello* :kid "invalid-kid" :key-kid "hono-test-kid-1")))
        (ok (= status 401))))
    (testing "kid signed by another key"
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello* :kid "hono-test-kid-1" :key-kid "hono-test-kid-2")))
        (ok (= status 401))))
    (testing "non-Bearer scheme"
      (with-response (body status headers)
          (app "http://localhost/auth/a" :headers (bearer (sign *hello*) "authorization" "Basic"))
        (ok (= status 401))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_request\",error_description=\"invalid credentials structure\""))))
    (testing "invalid token"
      (with-response (body status headers)
          (app "http://localhost/auth/a" :headers (bearer (concatenate 'string "ss" (sign *hello*))))
        (ok (= status 401))
        (ok (string= (gethash "www-authenticate" headers)
                     "Bearer realm=\"http://localhost/auth/a\",error=\"invalid_token\",error_description=\"token verification failure\""))))
    (testing "malformed token"
      (with-response (body status headers) (app "/" :headers (bearer "invalid.token"))
        (ok (= status 401)))))
  (testing "keys as a function"
    (let ((app (build :keys (lambda (env) (declare (ignore env)) *public-jwks*) :alg '(:rs256))))
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello*)))
        (ok (= status 200)))))
  (testing "keys as hash-tables"
    (let* ((keys (mapcar (lambda (k)
                           (let ((h (make-hash-table :test #'equal)))
                             (loop for (name value) on k by #'cddr
                                   do (setf (gethash (string-downcase name) h) value))
                             h))
                         *public-jwks*))
           (app (build :keys keys :alg '("RS256"))))
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello*)))
        (ok (= status 200))))))

(deftest custom-header-and-cookie
  (let ((app (build :keys *public-jwks* :alg '("RS256") :header-name "x-custom-auth-header")))
    (with-response (body status headers) (app "/") (ok (= status 401)))
    (with-response (body status headers) (app "/" :headers (bearer (sign *hello*)))
      (ok (= status 401)))
    (with-response (body status headers) (app "/" :headers (bearer (sign *hello*) "x-custom-auth-header"))
      (ok (= status 200))))
  (let ((app (build :keys *public-jwks* :alg '("RS256") :cookie "access_token")))
    (with-response (body status headers) (app "/") (ok (= status 401)))
    (with-response (body status headers)
        (app "/" :headers `(("cookie" . ,(format nil "access_token=~A" (sign *hello*)))))
      (ok (= status 200))
      (ok (string= body "hello world")))
    (with-response (body status headers)
        (app "/" :headers '(("cookie" . "access_token=invalid.token")))
      (ok (= status 401))))
  (let ((app (build :keys *public-jwks* :alg '("RS256") :cookie '(:key "access_token" :prefix-options :secure))))
    (with-response (body status headers)
        (app "/" :headers `(("cookie" . ,(format nil "__Secure-access_token=~A" (sign *hello*)))))
      (ok (= status 200)))
    (with-response (body status headers)
        (app "/" :headers `(("cookie" . ,(format nil "access_token=~A" (sign *hello*)))))
      (ok (= status 401))))
  (testing "signed cookie"
    (let* ((token (sign *hello*))
           (hmac (ironclad:make-hmac (ironclad:ascii-string-to-byte-array "cookie_secret") :sha256))
           (app (build :keys *public-jwks* :alg '("RS256")
                       :cookie '(:key "access_token" :secret "cookie_secret"))))
      (ironclad:update-hmac hmac (ironclad:ascii-string-to-byte-array token))
      (let ((signature (cl-base64:usb8-array-to-base64-string (ironclad:hmac-digest hmac))))
        (with-response (body status headers)
            (app "/" :headers `(("cookie" . ,(format nil "access_token=~A.~A" token
                                                     (quri:url-encode signature)))))
          (ok (= status 200))))
      (with-response (body status headers)
          (app "/" :headers `(("cookie" . ,(format nil "access_token=~A" token))))
        (ok (= status 401))))))

(deftest verification
  (let ((app (build :keys *public-jwks* :alg '("RS256")))
        (iss-app (build :keys *public-jwks* :alg '("RS256") :verification '(:iss "http://issuer.test")))
        (future (+ (now) 100))
        (past (- (now) 100)))
    (flet ((status (app claims)
             (with-response (body status headers) (app "/" :headers (bearer (sign claims)))
               status)))
      (ok (= 200 (status app `(("exp" . ,future) ("nbf" . ,past) ("iat" . ,past)
                               ("iss" . "http://not-checked.test")))))
      (ok (= 401 (status app `(("exp" . ,past)))))
      (ok (= 401 (status app `(("nbf" . ,future)))))
      (ok (= 401 (status app `(("iat" . ,future)))))
      (ok (= 200 (status iss-app '(("iss" . "http://issuer.test")))))
      (ok (= 401 (status iss-app '())))
      (ok (= 401 (status iss-app '(("iss" . "http://bad-issuer.test"))))))))

(deftest algorithm-whitelist
  (let ((rs256 (build :keys (cons *es256-jwk* *public-jwks*) :alg '("RS256")))
        (multi (build :keys (cons *es256-jwk* *public-jwks*) :alg '("RS256" "ES256"))))
    (with-response (body status headers) (rs256 "/" :headers (bearer (sign *hello*)))
      (ok (= status 200)))
    (with-response (body status headers) (rs256 "/" :headers (bearer *es256-token*))
      (ok (= status 401))
      (ok (search "token verification failure" (gethash "www-authenticate" headers))))
    (with-response (body status headers) (multi "/" :headers (bearer (sign *hello*)))
      (ok (= status 200)))
    (with-response (body status headers) (multi "/" :headers (bearer *es256-token*))
      (ok (= status 200))
      (ok (string= body "hello world"))))
  (testing "JWK alg must match the header alg"
    (let ((app (build :keys *public-jwks* :alg '("RS256" "PS256"))))
      (with-response (body status headers) (app "/" :headers (bearer (sign *hello* :alg :ps256)))
        (ok (= status 401)))))
  (testing "symmetric algorithms are rejected"
    (let* ((secret-jwk '(:kid "hs" :kty "oct" :k "YS1zZWNyZXQ"))
           (app (build :keys (list secret-jwk) :alg '("RS256")))
           (token (jose:encode :hs256 (ironclad:ascii-string-to-byte-array "a-secret") *hello*
                               :headers '(("kid" . "hs")))))
      (with-response (body status headers) (app "/" :headers (bearer token))
        (ok (= status 401))))))

(deftest realm
  (with-response (body status headers)
      ((build :keys *public-jwks* :alg '("RS256") :realm "my \"quoted\" api") "/")
    (ok (string= (gethash "www-authenticate" headers)
                 "Bearer realm=\"my \\\"quoted\\\" api\",error=\"invalid_request\",error_description=\"no authorization included in request\"")))
  (with-response (body status headers)
      ((build :keys *public-jwks* :alg '("RS256") :realm "my-api") "/" :headers (bearer "invalid-token"))
    (ok (string= (gethash "www-authenticate" headers)
                 "Bearer realm=\"my-api\",error=\"invalid_token\",error_description=\"token verification failure\""))))
