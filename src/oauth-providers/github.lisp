(defpackage #:lack-mw/oauth-providers/github
  (:use #:cl)
  (:import-from #:alexandria)
  (:import-from #:com.inuoe.jzon)
  (:import-from #:lack-mw/helpers/url
                #:request-url)
  (:import-from #:lack-mw/oauth-providers
                #:oauth-middleware
                #:oauth-error
                #:fetch-json
                #:query-string)
  (:export #:*mw-github-auth*
           #:github-user))
(in-package #:lack-mw/oauth-providers/github)

(defparameter +user-agent+ "lack-mw")

(defun github-user (env)
  "The GitHub user signed in with *MW-GITHUB-AUTH*, as a hash table of the API's JSON,
its \"email\" set to the primary address."
  (getf env :lack-mw.github-user))

(defun authorize-url (env state &key client-id scope oauth-app redirect-uri)
  (format nil "https://github.com/login/oauth/authorize?~a"
          (query-string
           `(("client_id" . ,client-id)
             ("state" . ,state)
             ;; an OAuth app asks for its scopes here; a GitHub App has them in its settings
             ,@(when oauth-app
                 `(("scope" . ,(format nil "~{~a~^,~}" scope))))
             ;; an OAuth app has one callback URL, a GitHub App may have several,
             ;; so a GitHub App is told to come back here
             ,@(unless oauth-app
                 `(("redirect_uri" . ,(or redirect-uri (request-url env)))))))))

(defun api-headers (token)
  `(("Authorization" . ,(format nil "Bearer ~a" token))
    ("Accept" . "application/json")
    ("User-Agent" . ,+user-agent+)))

(defun api-error (json)
  "The message of an API error answer, or NIL when JSON is not one."
  (and (hash-table-p json) (gethash "message" json)))

(defun token-from-code (client-id client-secret code)
  (let ((json (fetch-json :post "https://github.com/login/oauth/access_token"
                          :headers '(("Accept" . "application/json")
                                     ("Content-Type" . "application/json"))
                          :content (com.inuoe.jzon:stringify
                                    (alexandria:plist-hash-table
                                     (list "client_id" client-id
                                           "client_secret" client-secret
                                           "code" code)
                                     :test #'equal)))))
    (multiple-value-bind (description found) (gethash "error_description" json)
      (when found (oauth-error description)))
    (let ((access-token (gethash "access_token" json))
          (refresh-token (gethash "refresh_token" json))
          (refresh-expires-in (gethash "refresh_token_expires_in" json)))
      (unless access-token
        (oauth-error "No access token in GitHub's answer"))
      (list :token (list :token access-token :expires-in (gethash "expires_in" json))
            :refresh-token (and refresh-token refresh-expires-in
                                (list :token refresh-token :expires-in refresh-expires-in))
            :granted-scopes (uiop:split-string (or (gethash "scope" json) "") :separator ",")))))

(defun primary-email (token)
  (let ((emails (fetch-json :get "https://api.github.com/user/emails" :headers (api-headers token))))
    (let ((message (api-error emails)))
      (when message (oauth-error message)))
    (let ((emails (coerce emails 'list)))
      (gethash "email"
               (or (find-if (lambda (e) (eq (gethash "primary" e) t)) emails)
                   (find-if (lambda (e) (not (search "@users.noreply.github.com" (gethash "email" e))))
                            emails)
                   (make-hash-table))))))

(defun fetch-user (client-id client-secret code)
  (let* ((result (token-from-code client-id client-secret code))
         (token (getf (getf result :token) :token))
         (user (fetch-json :get "https://api.github.com/user" :headers (api-headers token))))
    (let ((message (api-error user)))
      (when message (oauth-error message)))
    (setf (gethash "email" user) (primary-email token))
    (list* :user user result)))

(defparameter *mw-github-auth*
  (lambda (app &key client-id client-secret scope oauth-app redirect-uri)
    (oauth-middleware
     app
     :user-key :lack-mw.github-user
     :authorize-url (lambda (env state)
                      (authorize-url env state
                                     :client-id (or client-id (uiop:getenv "GITHUB_ID"))
                                     :scope scope :oauth-app oauth-app :redirect-uri redirect-uri))
     :fetch (lambda (env code)
              (declare (ignore env))
              (fetch-user (or client-id (uiop:getenv "GITHUB_ID"))
                          (or client-secret (uiop:getenv "GITHUB_SECRET"))
                          code))))
  "Middleware signing the user in with GitHub. Without a code it redirects to
GitHub; back with one, it puts the token and the user in env and calls the app.")
