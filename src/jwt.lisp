(defpackage #:lack-mw/jwt
  (:use #:cl)
  (:import-from #:jose)
  (:import-from #:jose/base64
                #:base64url-decode)
  (:import-from #:ironclad)
  (:import-from #:babel)
  (:import-from #:cl-base64)
  (:import-from #:cl-ppcre)
  (:import-from #:quri)
  (:import-from #:lack-mw/helpers/url
                #:request-url)
  (:export #:*mw-jwt*
           #:jwt-payload
           ;; shared with lack-mw/jwk
           #:jwk-to-key
           #:jwk-get
           #:verify-jwt
           #:extract-token
           #:unauthorized-response))
(in-package #:lack-mw/jwt)

(defun jwt-payload (env)
  "Returns the verified JWT claims (an alist with string keys) set by *MW-JWT* / *MW-JWK*."
  (getf env :lack-mw.jwt-payload))

(defun now ()
  (- (get-universal-time) #.(encode-universal-time 0 0 0 1 1 1970 0)))

(defun normalize-alg (alg)
  (let ((alg (string-upcase (string alg))))
    (or (find alg '(:hs256 :hs384 :hs512 :rs256 :rs384 :rs512 :ps256 :ps384 :ps512
                    :es256 :es384 :es512 :eddsa)
              :test #'string= :key #'symbol-name)
        (error "~A is not an implemented algorithm" alg))))

(defun alg-name (alg)
  (if (eq alg :eddsa) "EdDSA" (symbol-name alg)))

;;; JWK

(defun jwk-get (jwk name)
  "Gets the member NAME (a string) of JWK, which may be a hash-table,
an alist (string or symbol keys) or a plist (keyword keys)."
  (cond ((hash-table-p jwk) (values (gethash name jwk)))
        ((and (consp jwk) (consp (first jwk)))
         (cdr (assoc name jwk :test #'string-equal)))
        (t (loop for (k v) on jwk by #'cddr
                 when (string-equal k name) return v))))

(defun pad-octets (octets size)
  (if (< (length octets) size)
      (concatenate '(simple-array (unsigned-byte 8) (*))
                   (make-array (- size (length octets))
                               :element-type '(unsigned-byte 8) :initial-element 0)
                   octets)
      octets))

(defun jwk-to-key (jwk)
  "Converts a public JWK (RSA, EC P-256/P-384/P-521, OKP Ed25519) into an ironclad public key."
  (let ((kty (jwk-get jwk "kty")))
    (cond
      ((equal kty "RSA")
       (ironclad:make-public-key :rsa
                                 :n (base64url-decode (jwk-get jwk "n") :as :integer)
                                 :e (base64url-decode (jwk-get jwk "e") :as :integer)))
      ((equal kty "EC")
       (let* ((crv (jwk-get jwk "crv"))
              (spec (cond ((equal crv "P-256") '(:secp256r1 32))
                          ((equal crv "P-384") '(:secp384r1 48))
                          ((equal crv "P-521") '(:secp521r1 66))
                          (t (error "Unsupported EC curve: ~A" crv))))
              (size (second spec)))
         (ironclad:make-public-key
          (first spec)
          :y (concatenate '(simple-array (unsigned-byte 8) (*))
                          #(4)
                          (pad-octets (base64url-decode (jwk-get jwk "x")) size)
                          (pad-octets (base64url-decode (jwk-get jwk "y")) size)))))
      ((and (equal kty "OKP") (equal (jwk-get jwk "crv") "Ed25519"))
       (ironclad:make-public-key :ed25519 :y (base64url-decode (jwk-get jwk "x"))))
      (t (error "Unsupported JWK key type: ~A" kty)))))

(defun to-key (secret alg)
  (cond ((member alg '(:hs256 :hs384 :hs512))
         (if (stringp secret) (babel:string-to-octets secret :encoding :utf-8) secret))
        ((or (hash-table-p secret) (consp secret)) (jwk-to-key secret))
        (t secret)))

;;; Verification

(defun verify-local (alg key message signature)
  (case alg
    ((:hs256 :hs384 :hs512)
     (let ((hmac (ironclad:make-hmac key (ecase alg (:hs256 :sha256) (:hs384 :sha384) (:hs512 :sha512)))))
       (ironclad:update-hmac hmac message)
       (let ((digest (ironclad:hmac-digest hmac)))
         (and (= (length digest) (length signature))
              (ironclad:constant-time-equal digest signature)))))
    (:eddsa (ironclad:verify-signature key message signature))
    (t (ironclad:verify-signature
        key
        (ironclad:digest-sequence (ecase alg (:es256 :sha256) (:es384 :sha384) (:es512 :sha512))
                                  message)
        signature))))

(defun verify-signature (alg key token)
  "Verifies the signature and the header alg of TOKEN. Returns true on success."
  (handler-case
      (handler-bind ((warning #'muffle-warning))
        (if (member alg '(:rs256 :rs384 :rs512 :ps256 :ps384 :ps512))
            (progn (jose/jws:verify alg key token) t)
            ;; jose supports neither ES*/EdDSA nor constant-time HMAC comparison
            (multiple-value-bind (headers payload signature)
                (jose/jws:decode-token token)
              (declare (ignore payload))
              (and (equal (cdr (assoc "alg" headers :test #'equal)) (alg-name alg))
                   (verify-local alg key
                                 (babel:string-to-octets
                                  token :end (position #\. token :from-end t) :encoding :utf-8)
                                 signature)))))
    (error () nil)))

(defun match-claim (expected value)
  (and (stringp value)
       (if (functionp expected)
           (funcall expected value)
           (member value (if (listp expected) expected (list expected)) :test #'string=))))

(defun check-claims (claims &key iss (nbf t) (exp t) (iat t) aud)
  (flet ((claim (name) (assoc name claims :test #'string=)))
    (let ((now (now)))
      (and (or (not nbf) (not (claim "nbf"))
               (and (realp (cdr (claim "nbf"))) (<= (cdr (claim "nbf")) now)))
           (or (not exp) (not (claim "exp"))
               (and (realp (cdr (claim "exp"))) (> (cdr (claim "exp")) now)))
           (or (not iat) (not (claim "iat"))
               (and (realp (cdr (claim "iat"))) (<= (cdr (claim "iat")) now)))
           (or (not iss) (match-claim iss (cdr (claim "iss"))))
           (or (not aud)
               (let ((value (cdr (claim "aud"))))
                 (some (lambda (a) (match-claim aud a))
                       (if (listp value) value (list value)))))))))

(defun verify-jwt (token key alg &optional verification)
  "Verifies TOKEN with KEY (octets/string for HS*, an ironclad public key or a JWK otherwise)
and ALG, then checks the claims per VERIFICATION (plist of :iss :nbf :exp :iat :aud).
Returns (values claims-alist T) on success, NIL when verification fails."
  (let ((alg (normalize-alg alg)))
    (when (and (= (count #\. token) 2)
               (verify-signature alg (to-key key alg) token))
      (multiple-value-bind (claims headers)
          ;; keep numeric claims (e.g. fractional exp) precise
          (handler-case (let ((*read-default-float-format* 'double-float))
                          (jose:inspect-token token))
            (error () (return-from verify-jwt nil)))
        (let ((typ (assoc "typ" headers :test #'equal)))
          (when (and (listp claims)
                     (or (null typ) (equal (cdr typ) "JWT"))
                     (apply #'check-claims claims verification))
            (values claims t)))))))

;;; Request helpers

(defun header (env name)
  (let ((headers (getf env :headers)))
    (and headers (gethash (string-downcase name) headers))))

(defun trim-cookie-whitespace (s)
  (string-trim '(#\Space #\Tab) s))

(defun parse-cookie (cookie name)
  (dolist (pair (ppcre:split ";" cookie))
    (let ((pos (position #\= pair)))
      (when (and pos (string= (trim-cookie-whitespace (subseq pair 0 pos)) name))
        (let ((value (trim-cookie-whitespace (subseq pair (1+ pos)))))
          (when (and (> (length value) 1)
                     (char= (char value 0) #\")
                     (char= (char value (1- (length value))) #\"))
            (setf value (subseq value 1 (1- (length value)))))
          (when (ppcre:scan "^[ !#-:<-\\[\\]-~]*$" value)
            (return (handler-case (quri:url-decode value :lenient t)
                      (error () value)))))))))

(defun verify-signed-cookie (value secret)
  (let ((pos (position #\. value :from-end t)))
    (when pos
      (let ((signed (subseq value 0 pos))
            (signature (subseq value (1+ pos))))
        (when (and (= (length signature) 44)
                   (char= (char signature 43) #\=))
          (let ((hmac (ironclad:make-hmac (if (stringp secret)
                                              (babel:string-to-octets secret :encoding :utf-8)
                                              secret)
                                          :sha256)))
            (ironclad:update-hmac hmac (babel:string-to-octets signed :encoding :utf-8))
            (when (handler-case
                      (ironclad:constant-time-equal
                       (ironclad:hmac-digest hmac)
                       (cl-base64:base64-string-to-usb8-array signature))
                    (error () nil))
              signed)))))))

(defun get-cookie-token (env cookie)
  "COOKIE is a cookie name, or a plist (:key name :secret secret :prefix-options :secure/:host)."
  (let ((header (header env "cookie")))
    (when header
      (destructuring-bind (&key key secret prefix-options)
          (if (stringp cookie) (list :key cookie) cookie)
        (let* ((name (case prefix-options
                       (:secure (concatenate 'string "__Secure-" key))
                       (:host (concatenate 'string "__Host-" key))
                       (t key)))
               (value (parse-cookie header name)))
          (cond ((null value) nil)
                (secret (verify-signed-cookie value secret))
                (t value)))))))

(defun extract-token (env header-name cookie)
  "Returns (values token error-description). TOKEN is NIL when missing or malformed."
  (let ((credentials (header env header-name)))
    (if (and credentials (string/= credentials ""))
        (let ((parts (ppcre:split "\\s+" credentials)))
          (if (and (= (length parts) 2)
                   (string-equal (first parts) "bearer"))
              (second parts)
              (values nil "invalid credentials structure")))
        (let ((token (and cookie (get-cookie-token env cookie))))
          (if (and token (string/= token ""))
              token
              (values nil "no authorization included in request"))))))

(defun escape-quotes (s)
  (ppcre:regex-replace-all "\"" s "\\\""))

(defun unauthorized-response (env realm error description)
  `(401 (:www-authenticate
         ,(format nil "Bearer realm=\"~A\",error=\"~A\",error_description=\"~A\""
                  (escape-quotes (or realm (request-url env)))
                  error
                  (escape-quotes description))
         :content-type "text/plain; charset=UTF-8")
        ("Unauthorized")))

(defparameter *mw-jwt*
  (lambda (app &key secret alg cookie (header-name "Authorization") realm verification)
    (unless secret
      (error "JWT auth middleware requires options for \"secret\""))
    (unless alg
      (error "JWT auth middleware requires options for \"alg\""))
    (let* ((alg (normalize-alg alg))
           (key (to-key secret alg)))
      (lambda (env)
        (multiple-value-bind (token description)
            (extract-token env header-name cookie)
          (if (null token)
              (unauthorized-response env realm "invalid_request" description)
              (multiple-value-bind (payload ok) (verify-jwt token key alg verification)
                (if ok
                    (funcall app (list* :lack-mw.jwt-payload payload env))
                    (unauthorized-response env realm "invalid_token"
                                           "token verification failure"))))))))
  "JWT auth middleware. Verifies a Bearer token (or cookie) with SECRET and ALG,
and stores the claims in env (see JWT-PAYLOAD).")
