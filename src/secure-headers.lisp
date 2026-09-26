(defpackage #:lack-mw/secure-headers
  (:use #:cl)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:import-from #:ironclad)
  (:import-from #:cl-base64)
  (:export #:*secure-headers*
           #:secure-headers-nonce
           #:generate-nonce))
(in-package #:lack-mw/secure-headers)

(defparameter +headers-map+
  '((:cross-origin-embedder-policy "Cross-Origin-Embedder-Policy" "require-corp")
    (:cross-origin-resource-policy "Cross-Origin-Resource-Policy" "same-origin")
    (:cross-origin-opener-policy "Cross-Origin-Opener-Policy" "same-origin")
    (:origin-agent-cluster "Origin-Agent-Cluster" "?1")
    (:referrer-policy "Referrer-Policy" "no-referrer")
    (:strict-transport-security "Strict-Transport-Security" "max-age=15552000; includeSubDomains")
    (:x-content-type-options "X-Content-Type-Options" "nosniff")
    (:x-dns-prefetch-control "X-DNS-Prefetch-Control" "off")
    (:x-download-options "X-Download-Options" "noopen")
    (:x-frame-options "X-Frame-Options" "SAMEORIGIN")
    (:x-permitted-cross-domain-policies "X-Permitted-Cross-Domain-Policies" "none")
    (:x-xss-protection "X-XSS-Protection" "0")))

(defun secure-headers-nonce (env)
  "Return the CSP nonce generated for this request (set when a policy uses :nonce)."
  (getf env :lack-mw.secure-headers-nonce))

(defun generate-nonce ()
  (cl-base64:usb8-array-to-base64-string (ironclad:random-data 16)))

(defun header-key (name)
  (intern (string-upcase name) :keyword))

(defun remove-header (headers name)
  (loop for (k v) on headers by #'cddr
        unless (string-equal k name)
          append (list k v)))

(defun set-header (headers name value)
  (append (remove-header headers name) (list (header-key name) value)))

(defun directive-name (key)
  (string-downcase (string key)))

(defun make-csp-parts (policy)
  "Return a list of parts: strings, or (directive . fn) for dynamic values."
  (loop for (key value) on policy by #'cddr
        collect (let ((values (if (listp value) value (list value))))
                  (cons (directive-name key)
                        (mapcar (lambda (v)
                                  (if (stringp v) v (cons key v)))
                                values)))))

(defun csp-dynamic-p (parts)
  (some (lambda (part) (some #'consp (cdr part))) parts))

(defun resolve-source (source env)
  "Resolve a dynamic source (directive . handler). Returns (values string new-env)."
  (destructuring-bind (directive . handler) source
    (if (eq handler :nonce)
        (let ((nonce (or (secure-headers-nonce env) (generate-nonce))))
          (values (format nil "'nonce-~A'" nonce)
                  (if (secure-headers-nonce env)
                      env
                      (list* :lack-mw.secure-headers-nonce nonce env))))
        (multiple-value-bind (str additions) (funcall handler env directive)
          (values str (append additions env))))))

(defun render-csp (parts env)
  "Render CSP parts into a header value. Returns (values string new-env)."
  (values
   (format nil "~{~A~^; ~}"
           (loop for (name . sources) in parts
                 collect (format nil "~A~{ ~A~}"
                                 name
                                 (loop for s in sources
                                       collect (if (consp s)
                                                   (multiple-value-bind (str new-env)
                                                       (resolve-source s env)
                                                     (setf env new-env)
                                                     str)
                                                   s)))))
   env))

(defun permissions-policy-value (policy)
  (format nil "~{~A~^, ~}"
          (loop for (key value) on policy by #'cddr
                for name = (directive-name key)
                collect (cond ((eq value t) (format nil "~A=*" name))
                              ((null value) (format nil "~A=()" name))
                              ((equal value '("*")) (format nil "~A=*" name))
                              ((equal value '("none")) (format nil "~A=()" name))
                              (t (format nil "~A=(~{~A~^ ~})"
                                         name
                                         (mapcar (lambda (item)
                                                   (if (member item '("self" "src") :test #'string=)
                                                       item
                                                       (format nil "\"~A\"" item)))
                                                 value)))))))

(defun reporting-endpoints-value (endpoints)
  (format nil "~{~A~^, ~}"
          (loop for ep in endpoints
                collect (format nil "~A=\"~A\"" (getf ep :name) (getf ep :url)))))

(defun json-string (str)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for c across str
          do (case c
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (t (write-char c out))))
    (write-char #\" out)))

(defun json-value (value)
  (cond ((stringp value) (json-string value))
        ((numberp value) (princ-to-string value))
        ((and (consp value) (keywordp (first value))) (json-object value))
        ((listp value) (format nil "[~{~A~^,~}]" (mapcar #'json-value value)))
        (t (json-string (princ-to-string value)))))

(defun json-object (plist)
  ;; :max-age -> "max_age", matching Hono's Report-To keys
  (format nil "{~{~A~^,~}}"
          (loop for (k v) on plist by #'cddr
                collect (format nil "~A:~A"
                                (json-string (substitute #\_ #\- (string-downcase (string k))))
                                (json-value v)))))

(defun report-to-value (groups)
  (format nil "~{~A~^, ~}" (mapcar #'json-object groups)))

(defparameter *secure-headers*
  (lambda (app &key content-security-policy
                 content-security-policy-report-only
                 (cross-origin-embedder-policy nil)
                 (cross-origin-resource-policy t)
                 (cross-origin-opener-policy t)
                 (origin-agent-cluster t)
                 (referrer-policy t)
                 reporting-endpoints
                 report-to
                 (strict-transport-security t)
                 (x-content-type-options t)
                 (x-dns-prefetch-control t)
                 (x-download-options t)
                 (x-frame-options t)
                 (x-permitted-cross-domain-policies t)
                 (x-xss-protection t)
                 (remove-powered-by t)
                 permissions-policy)
    (let* ((options (list :cross-origin-embedder-policy cross-origin-embedder-policy
                          :cross-origin-resource-policy cross-origin-resource-policy
                          :cross-origin-opener-policy cross-origin-opener-policy
                          :origin-agent-cluster origin-agent-cluster
                          :referrer-policy referrer-policy
                          :strict-transport-security strict-transport-security
                          :x-content-type-options x-content-type-options
                          :x-dns-prefetch-control x-dns-prefetch-control
                          :x-download-options x-download-options
                          :x-frame-options x-frame-options
                          :x-permitted-cross-domain-policies x-permitted-cross-domain-policies
                          :x-xss-protection x-xss-protection))
           (static-headers
             (loop for (key name default) in +headers-map+
                   for value = (getf options key)
                   when value
                     collect (cons name (if (stringp value) value default))))
           ;; CSP policies: (header-name . parts); rendered once unless dynamic
           (csp-policies
             (loop for (name policy) in (list (list "Content-Security-Policy"
                                                    content-security-policy)
                                              (list "Content-Security-Policy-Report-Only"
                                                    content-security-policy-report-only))
                   when policy
                     collect (cons name (make-csp-parts policy)))))
      (loop for (name . parts) in csp-policies
            unless (csp-dynamic-p parts)
              do (setf static-headers
                       (append static-headers (list (cons name (render-csp parts nil))))))
      (setf csp-policies (remove-if-not #'csp-dynamic-p csp-policies :key #'cdr))
      (when permissions-policy
        (setf static-headers
              (append static-headers
                      (list (cons "Permissions-Policy"
                                  (permissions-policy-value permissions-policy))))))
      (when reporting-endpoints
        (setf static-headers
              (append static-headers
                      (list (cons "Reporting-Endpoints"
                                  (reporting-endpoints-value reporting-endpoints))))))
      (when report-to
        (setf static-headers
              (append static-headers
                      (list (cons "Report-To" (report-to-value report-to))))))
      (lambda (env)
        ;; Dynamic CSP values are resolved before calling the app so that
        ;; the nonce is available downstream via (secure-headers-nonce env).
        (let ((headers-to-set static-headers))
          (loop for (name . parts) in csp-policies
                do (multiple-value-bind (value new-env) (render-csp parts env)
                     (setf env new-env)
                     (setf headers-to-set
                           (append headers-to-set (list (cons name value))))))
          (funcall-with-cb
           app env
           (lambda (res)
             (destructuring-bind (status headers &rest body) res
               (loop for (name . value) in headers-to-set
                     do (setf headers (set-header headers name value)))
               (when remove-powered-by
                 (setf headers (remove-header headers "X-Powered-By")))
               (list* status headers body))))))))
  "Middleware that sets security-related response headers (port of Hono's secureHeaders).
CSP option values are plists like (:default-src (\"'self'\") :script-src (\"'self'\" :nonce)).
A source may be :nonce or a function (env directive) returning a string and,
optionally, a plist of values to add to env as a second value.")
