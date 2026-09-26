(defpackage #:lack-mw/oauth-providers/google
  (:use #:cl)
  (:import-from #:quri)
  (:import-from #:lack-mw/helpers/url
                #:request-url)
  (:import-from #:lack-mw/oauth-providers
                #:oauth-middleware
                #:oauth-error
                #:fetch-json
                #:query-string
                #:*http-client*)
  (:export #:*google-auth*
           #:google-user
           #:google-revoke-token))
(in-package #:lack-mw/oauth-providers/google)

(defun google-user (env)
  "The Google user signed in with *GOOGLE-AUTH*, as a hash table of the userinfo JSON."
  (getf env :lack-mw.google-user))

(defun request-url-without-query (env)
  (let ((url (request-url env)))
    (subseq url 0 (position #\? url))))

(defun option-value (value)
  "A keyword option such as :select-account as Google spells it, select_account."
  (if (keywordp value)
      (substitute #\_ #\- (string-downcase value))
      value))

(defun authorize-url (state &key client-id redirect-uri scope prompt login-hint access-type)
  (format nil "https://accounts.google.com/o/oauth2/v2/auth?~a"
          (query-string
           `(("response_type" . "code")
             ("redirect_uri" . ,redirect-uri)
             ("client_id" . ,client-id)
             ("include_granted_scopes" . t)
             ("scope" . ,(format nil "~{~a~^ ~}" scope))
             ("state" . ,state)
             ("prompt" . ,(option-value prompt))
             ("login_hint" . ,login-hint)
             ("access_type" . ,(option-value access-type))))))

(defun error-message (json)
  "The message of an error answer, or NIL when JSON is not one."
  (and (hash-table-p json)
       (multiple-value-bind (err found) (gethash "error" json)
         (and found
              (or (and (hash-table-p err) (gethash "message" err))
                  (gethash "error_description" json)
                  (and (stringp err) err)
                  "Bad Request")))))

(defun token-from-code (client-id client-secret redirect-uri code)
  (let ((json (fetch-json :post "https://oauth2.googleapis.com/token"
                          :headers '(("Content-Type" . "application/x-www-form-urlencoded")
                                     ("Accept" . "application/json"))
                          :content (query-string `(("client_id" . ,client-id)
                                                   ("client_secret" . ,client-secret)
                                                   ("redirect_uri" . ,redirect-uri)
                                                   ("code" . ,code)
                                                   ("grant_type" . "authorization_code"))))))
    (let ((message (error-message json)))
      (when message (oauth-error message)))
    (let ((access-token (gethash "access_token" json))
          (refresh-token (gethash "refresh_token" json)))
      (unless access-token
        (oauth-error "No access token in Google's answer"))
      (list :token (list :token access-token :expires-in (gethash "expires_in" json))
            :refresh-token (and refresh-token
                                (list :token refresh-token
                                      :expires-in (gethash "refresh_token_expires_in" json)))
            :granted-scopes (uiop:split-string (or (gethash "scope" json) "") :separator " ")))))

(defun fetch-user (client-id client-secret redirect-uri code)
  (let* ((result (token-from-code client-id client-secret redirect-uri code))
         (user (fetch-json :get "https://www.googleapis.com/oauth2/v2/userinfo"
                           :headers `(("Authorization"
                                       . ,(format nil "Bearer ~a" (getf (getf result :token) :token)))))))
    (let ((message (error-message user)))
      (when message (oauth-error message)))
    (list* :user user result)))

(defun google-revoke-token (token)
  "Revoke TOKEN, an access or refresh token. True when Google accepted it."
  (multiple-value-bind (body status)
      (funcall *http-client* :post
               (format nil "https://oauth2.googleapis.com/revoke?~a" (query-string `(("token" . ,token))))
               :headers '(("Content-Type" . "application/x-www-form-urlencoded")))
    (declare (ignore body))
    (eql status 200)))

(defparameter *google-auth*
  (lambda (app &key scope client-id client-secret redirect-uri state
                 login-hint prompt access-type)
    (unless scope
      (error ":scope is required in *google-auth*"))
    (flet ((redirect-uri (env) (or redirect-uri (request-url-without-query env))))
      (oauth-middleware
       app
       :state state
       :user-key :lack-mw.google-user
       :authorize-url (lambda (env state)
                        (authorize-url state
                                       :client-id (or client-id (uiop:getenv "GOOGLE_ID"))
                                       :redirect-uri (redirect-uri env)
                                       :scope scope :prompt prompt
                                       :login-hint login-hint :access-type access-type))
       :fetch (lambda (env code)
                (let ((client-id (or client-id (uiop:getenv "GOOGLE_ID")))
                      (client-secret (or client-secret (uiop:getenv "GOOGLE_SECRET"))))
                  (unless (and client-id client-secret)
                    (oauth-error "Required parameters were not found. Please provide them to proceed."))
                  (fetch-user client-id client-secret (redirect-uri env) code))))))
  "Middleware signing the user in with Google. Without a code it redirects to
Google; back with one, it puts the token and the user in env and calls the app.")
