(defpackage #:lack-mw/bearer-auth
  (:use #:cl)
  (:import-from #:ironclad)
  (:import-from #:babel)
  (:import-from #:cl-ppcre)
  (:export #:*bearer-auth*
           #:timing-safe-equal))
(in-package #:lack-mw/bearer-auth)

(defun sha256-hex (string)
  (ironclad:byte-array-to-hex-string
   (ironclad:digest-sequence :sha256 (babel:string-to-octets string :encoding :utf-8))))

(defun constant-time-equal-string (a b)
  (let ((out (logxor (length a) (length b))))
    (dotimes (i (max (length a) (length b)))
      (setf out (logior out (logxor (if (< i (length a)) (char-code (char a i)) 0)
                                    (if (< i (length b)) (char-code (char b i)) 0)))))
    (zerop out)))

(defun timing-safe-equal (a b &optional hash-function)
  "Compares strings A and B in constant time, after hashing both with HASH-FUNCTION
(string -> string, SHA-256 hex by default)."
  (let* ((hash-function (or hash-function #'sha256-hex))
         (sa (funcall hash-function a))
         (sb (funcall hash-function b)))
    (and (stringp sa) (stringp sb)
         ;; evaluate both comparisons to avoid short-circuit timing differences
         (let ((hash-equal (constant-time-equal-string sa sb))
               (original-equal (constant-time-equal-string a b)))
           (and hash-equal original-equal)))))

;;; Minimal JSON encoding for object messages

(defun object-pairs (object)
  "Returns (key . value) pairs of a hash-table, an alist or a plist."
  (cond ((hash-table-p object)
         (loop for k being the hash-keys of object using (hash-value v) collect (cons k v)))
        ((consp (first object)) object)
        (t (loop for (k v) on object by #'cddr collect (cons k v)))))

(defun key-string (key)
  (if (symbolp key) (string-downcase (symbol-name key)) (princ-to-string key)))

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for c across string
        do (case c
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (t (if (< (char-code c) 32)
                    (format stream "\\u~4,'0X" (char-code c))
                    (write-char c stream)))))
  (write-char #\" stream))

(defun write-json (value stream)
  (cond ((eq value t) (write-string "true" stream))
        ((member value '(nil :null)) (write-string "null" stream))
        ((eq value :false) (write-string "false" stream))
        ((stringp value) (write-json-string value stream))
        ((integerp value) (format stream "~D" value))
        ((realp value) (format stream "~F" value))
        ((symbolp value) (write-json-string (key-string value) stream))
        ((vectorp value)
         (write-char #\[ stream)
         (loop for v across value for first = t then nil
               do (unless first (write-char #\, stream))
                  (write-json v stream))
         (write-char #\] stream))
        (t
         (write-char #\{ stream)
         (loop for (k . v) in (object-pairs value) for first = t then nil
               do (unless first (write-char #\, stream))
                  (write-json-string (key-string k) stream)
                  (write-char #\: stream)
                  (write-json v stream))
         (write-char #\} stream))))

(defun to-json (value)
  (with-output-to-string (s) (write-json value s)))

;;; Middleware

(defparameter +token-regexp+ (ppcre:create-scanner "^[A-Za-z0-9._~+/-]+=*$"))

(defun resolve (option env)
  (if (functionp option) (funcall option env) option))

(defun error-response (env status www-authenticate-prefix www-authenticate message)
  (let* ((www-authenticate (resolve www-authenticate env))
         (header (if (stringp www-authenticate)
                     www-authenticate
                     (format nil "~A~{~A~^,~}"
                             www-authenticate-prefix
                             (loop for (k . v) in (object-pairs www-authenticate)
                                   collect (format nil "~A=\"~A\"" (key-string k) v)))))
         (message (resolve message env)))
    (if (stringp message)
        `(,status (:www-authenticate ,header :content-type "text/plain; charset=UTF-8")
                  (,message))
        `(,status (:www-authenticate ,header :content-type "application/json")
                  (,(to-json message))))))

(defparameter *bearer-auth*
  (lambda (app &key (token nil token-p)
                 verify-token
                 (realm "")
                 (prefix "Bearer")
                 (header-name "Authorization")
                 hash-function
                 no-authentication-header
                 no-authentication-header-message
                 invalid-authentication-header
                 invalid-authentication-header-message
                 invalid-token
                 invalid-token-message)
    (unless (or token-p verify-token)
      (error "bearer auth middleware requires options for \"token\" or \"verifyToken\""))
    (let* ((realm (ppcre:regex-replace-all "\"" (or realm "") "\\\""))
           (www-prefix (if (string= prefix "") "" (format nil "~A " prefix)))
           (tokens (remove nil (if (listp token) token (list token)))))
      (lambda (env)
        (let ((header-token (let ((headers (getf env :headers)))
                              (and headers (gethash (string-downcase header-name) headers)))))
          (if (or (null header-token) (string= header-token ""))
              (error-response env 401 www-prefix
                              (or (getf no-authentication-header :www-authenticate-header)
                                  (format nil "~Arealm=\"~A\"" www-prefix realm))
                              (or (getf no-authentication-header :message)
                                  no-authentication-header-message
                                  "Unauthorized"))
              (let ((token-value
                      (cond ((string= prefix "") header-token)
                            ((and (> (length header-token) (length prefix))
                                  (string-equal prefix header-token :end2 (length prefix))
                                  (char= (char header-token (length prefix)) #\Space))
                             (string-left-trim '(#\Space #\Tab #\Newline #\Return)
                                               (subseq header-token (length prefix)))))))
                (cond
                  ((or (null token-value) (not (ppcre:scan +token-regexp+ token-value)))
                   (error-response env 400 www-prefix
                                   (or (getf invalid-authentication-header :www-authenticate-header)
                                       (format nil "~Aerror=\"invalid_request\"" www-prefix))
                                   (or (getf invalid-authentication-header :message)
                                       invalid-authentication-header-message
                                       "Bad Request")))
                  ((if verify-token
                       (funcall verify-token token-value env)
                       (some (lambda (tk) (timing-safe-equal tk token-value hash-function))
                             tokens))
                   (funcall app env))
                  (t
                   (error-response env 401 www-prefix
                                   (or (getf invalid-token :www-authenticate-header)
                                       (format nil "~Aerror=\"invalid_token\"" www-prefix))
                                   (or (getf invalid-token :message)
                                       invalid-token-message
                                       "Unauthorized"))))))))))
  "Bearer auth middleware. Accepts requests whose Authorization header carries one of TOKEN
(a string or a list of strings), or a token accepted by VERIFY-TOKEN (function token env -> bool).")
