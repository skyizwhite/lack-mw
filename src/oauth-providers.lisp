(defpackage #:lack-mw/oauth-providers
  (:use #:cl)
  (:import-from #:dexador)
  (:import-from #:com.inuoe.jzon)
  (:import-from #:ironclad)
  (:import-from #:cl-base64)
  (:import-from #:quri)
  (:import-from #:lack-mw/helpers/cookie
                #:parse-cookie
                #:serialize-cookie)
  (:export #:oauth-token
           #:oauth-refresh-token
           #:oauth-granted-scopes
           #:*http-client*
           ;; for providers
           #:oauth-middleware
           #:oauth-error
           #:fetch-json
           #:query-string
           #:generate-state))
(in-package #:lack-mw/oauth-providers)

;;; The flow shared by the providers in lack-mw/oauth-providers/*: redirect to the
;;; provider with a state kept in a cookie, then, back with a code, check the state,
;;; let the provider fetch the token and the user, and put them in env.

(defun oauth-token (env)
  "The access token as (:token string :expires-in seconds)."
  (getf env :lack-mw.oauth-token))

(defun oauth-refresh-token (env)
  "The refresh token as (:token string :expires-in seconds), when the provider gave one."
  (getf env :lack-mw.oauth-refresh-token))

(defun oauth-granted-scopes (env)
  "The scopes the user granted, as a list of strings."
  (getf env :lack-mw.oauth-granted-scopes))

(define-condition oauth-error (error)
  ((message :initarg :message :reader oauth-error-message))
  (:report (lambda (c s) (format s "OAuth error: ~a" (oauth-error-message c)))))

(defun oauth-error (message)
  (error 'oauth-error :message (or message "Bad Request")))

(defun generate-state ()
  "32 random bytes in base64url, the anti-CSRF state of the flow (RFC 6749 10.12)."
  ;; cl-base64 pads a URI-safe string with "."
  (string-right-trim "." (cl-base64:usb8-array-to-base64-string (ironclad:random-data 32) :uri t)))

(defun query-string (params)
  "PARAMS, an alist, as a query string. Pairs whose value is NIL are left out."
  (quri:url-encode-params
   (loop :for (key . value) :in params
         :when value :collect (cons key (if (eq value t) "true" value)))))

(defun dexador-client (method url &key headers content)
  (handler-case (multiple-value-bind (body status)
                    (dex:request url :method method :headers headers :content content
                                     :force-string t)
                  (values body status))
    ;; an error status still carries the provider's JSON explaining it
    (dex:http-request-failed (e)
      (values (dex:response-body e) (dex:response-status e)))))

(defvar *http-client* #'dexador-client
  "The function the providers call HTTP with: (method url &key headers content),
returning the body as a string and the status. Rebind it to stub the providers.")

(defun fetch-json (method url &key headers content)
  "Call URL and parse the JSON it answers with. Objects become hash tables."
  (multiple-value-bind (body status)
      (funcall *http-client* method url :headers headers :content content)
    (values (handler-case (com.inuoe.jzon:parse body)
              (error () (oauth-error (format nil "Invalid response from ~a" url))))
            status)))

(defun query-param (env name)
  (let ((query (getf env :query-string)))
    (and query (plusp (length query))
         (cdr (assoc name (quri:url-decode-params query :lenient t) :test #'string=)))))

(defun text-response (status text &optional headers)
  `(,status (:content-type "text/plain; charset=UTF-8" ,@headers) (,text)))

(defun state-cookie (state)
  (serialize-cookie "state" state :max-age 600 :http-only t :path "/" :secure t :same-site "Lax"))

(defun oauth-middleware (app &key state authorize-url fetch user-key)
  "The middleware of a provider. AUTHORIZE-URL is a function of (env state) returning
the URL to send the user to. FETCH is a function of (env code) that fetches the
token and the user, returning a plist with :token, :refresh-token, :granted-scopes
and :user, and signals OAUTH-ERROR when the provider refuses. The user goes in env
under USER-KEY. STATE, when given, is used instead of a random one."
  (lambda (env)
    (let ((code (query-param env "code")))
      (if (null code)
          (let ((state (or state (generate-state))))
            `(302 (:location ,(funcall authorize-url env state)
                   :set-cookie ,(state-cookie state))
                  ()))
          (let ((stored (let ((header (gethash "cookie" (getf env :headers))))
                          (and header (parse-cookie header "state"))))
                (returned (query-param env "state")))
            (if (or (null stored) (null returned) (string/= stored returned))
                (text-response 401 "Unauthorized")
                (let ((result (handler-case (funcall fetch env code)
                                (oauth-error (e) e))))
                  (if (typep result 'oauth-error)
                      (text-response 400 (oauth-error-message result))
                      (progn
                        (setf (getf env :lack-mw.oauth-token) (getf result :token)
                              (getf env :lack-mw.oauth-refresh-token) (getf result :refresh-token)
                              (getf env :lack-mw.oauth-granted-scopes) (getf result :granted-scopes)
                              (getf env user-key) (getf result :user))
                        (funcall app env))))))))))
