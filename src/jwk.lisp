(defpackage #:lack-mw/jwk
  (:use #:cl)
  (:import-from #:jose)
  (:import-from #:lack-mw/jwt
                #:jwt-payload
                #:jwk-get
                #:jwk-to-key
                #:verify-jwt
                #:extract-token
                #:unauthorized-response)
  (:export #:*mw-jwk*
           #:jwt-payload))
(in-package #:lack-mw/jwk)

(defparameter +asymmetric-algorithms+
  '("RS256" "RS384" "RS512" "PS256" "PS384" "PS512" "ES256" "ES384" "ES512" "EdDSA"))

(defun alg-string (alg)
  (let ((alg (string alg)))
    (or (find alg +asymmetric-algorithms+ :test #'string-equal)
        (error "~A is not an allowed asymmetric algorithm" alg))))

(defun verify-with-keys (token keys allowed-algs verification)
  (let* ((headers (handler-case (nth-value 1 (jose:inspect-token token))
                    (error () (return-from verify-with-keys nil))))
         (kid (cdr (assoc "kid" headers :test #'equal)))
         (alg (cdr (assoc "alg" headers :test #'equal))))
    ;; HS* is never in ALLOWED-ALGS, which prevents algorithm confusion attacks.
    (when (and kid alg (member alg allowed-algs :test #'equal))
      (let ((key (find kid keys :key (lambda (k) (jwk-get k "kid")) :test #'equal)))
        (when (and key
                   (or (null (jwk-get key "alg"))
                       (equal (jwk-get key "alg") alg)))
          (let ((public-key (handler-case (jwk-to-key key)
                              (error () (return-from verify-with-keys nil)))))
            (verify-jwt token public-key alg verification)))))))

(defparameter *mw-jwk*
  (lambda (app &key keys allow-anon cookie (header-name "Authorization") alg realm verification)
    (unless keys
      (error "JWK auth middleware requires options for \"keys\""))
    (unless alg
      (error "JWK auth middleware requires options for \"alg\""))
    (let ((allowed-algs (mapcar #'alg-string alg)))
      (lambda (env)
        (multiple-value-bind (token description)
            (extract-token env header-name cookie)
          (cond
            ((and (null token) allow-anon (string= description "no authorization included in request"))
             (funcall app env))
            ((null token)
             (unauthorized-response env realm "invalid_request" description))
            (t
             (multiple-value-bind (payload ok)
                 (verify-with-keys token
                                   (if (functionp keys) (funcall keys env) keys)
                                   allowed-algs
                                   verification)
               (if ok
                   (funcall app (list* :lack-mw.jwt-payload payload env))
                   (unauthorized-response env realm "invalid_token"
                                          "token verification failure")))))))))
  "JWK auth middleware. Verifies a Bearer token (or cookie) against the public JWKs in KEYS
(a list, or a function of env returning one), and stores the claims in env (see JWT-PAYLOAD).")
