(defpackage #:lack-mw-test/oauth-providers
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:quri)
  (:import-from #:alexandria)
  (:import-from #:cl-ppcre)
  (:import-from #:com.inuoe.jzon)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/oauth-providers
                #:*http-client*
                #:oauth-token
                #:oauth-refresh-token
                #:oauth-granted-scopes
                #:generate-state)
  (:import-from #:lack-mw/oauth-providers/github
                #:*mw-github-auth*
                #:github-user)
  (:import-from #:lack-mw/oauth-providers/google
                #:*mw-google-auth*
                #:google-user
                #:google-revoke-token))
(in-package #:lack-mw-test/oauth-providers)

;;; The providers' answers, as in @hono/oauth-providers' mocks.ts

(defparameter +code+ "4/0AfJohXl9tS46EmTA6u9x3pJQiyCNyahx4DLJaeJelzJ0E5KkT4qJmCtjq9n3FxBvO40ofg")
(defparameter +access-token+ "15d42a4d-1948-4de4-ba78-b8a893feaf45")

(defparameter +google-token+
  "{\"access_token\":\"15d42a4d-1948-4de4-ba78-b8a893feaf45\",\"expires_in\":60000,
    \"scope\":\"openid email profile\",\"refresh_token\":\"1//04dX-1234567890abcdef-567890abcdef1234\",
    \"refresh_token_expires_in\":3600}")
(defparameter +google-user+
  "{\"id\":\"1abc345-75uyut\",\"email\":\"example@email.com\",\"verified_email\":true,
    \"name\":\"Carlos Aldazosa\",\"given_name\":\"Carlos\",\"family_name\":\"Aldazosa\",
    \"picture\":\"https://www.severnedgevets.co.uk/sites/default/files/guides/kitten.png\",\"locale\":\"es-419\"}")
(defparameter +google-code-error+
  "{\"error\":{\"code\":401,\"message\":\"Invalid code.\",\"status\":\"401\",\"error\":\"code_invalid\"},
    \"error_description\":\"Invalid code.\"}")
(defparameter +google-token-error+
  "{\"error\":{\"code\":401,\"message\":\"Invalid token.\",\"status\":\"401\",\"error\":\"token_invalid\"},
    \"error_description\":\"Invalid token.\"}")

(defparameter +github-token+
  "{\"access_token\":\"15d42a4d-1948-4de4-ba78-b8a893feaf45\",\"expires_in\":60000,\"scope\":\"public_repo,user\",
    \"refresh_token\":\"t4589fh-9gj3g93-34f5t64n\",\"refresh_token_expires_in\":6000000,\"token_type\":\"bearer\"}")
(defparameter +github-user+
  "{\"login\":\"monoald\",\"id\":9876543210,\"name\":\"Carlos Aldazosa\",\"email\":null,\"hireable\":null}")
(defparameter +github-emails+
  "[{\"email\":\"671450+test@users.noreply.github.com\",\"primary\":false,\"verified\":true,\"visibility\":null},
    {\"email\":\"test@email.com\",\"primary\":true,\"verified\":true,\"visibility\":\"public\"}]")
(defparameter +github-code-error+ "{\"error_description\":\"Invalid Code.\"}")

(defvar *requests*)

(defun header-value (headers name)
  (cdr (assoc name headers :test #'string-equal)))

(defun form-value (content name)
  (cdr (assoc name (quri:url-decode-params content) :test #'string=)))

(defun fake-client (method url &key headers content)
  (push (list method url headers content) *requests*)
  (let ((path (subseq url 0 (or (position #\? url) (length url)))))
    (flet ((answer (body &optional (status 200)) (values body status))
           (bearer-p () (equal (header-value headers "Authorization")
                               (format nil "Bearer ~a" +access-token+))))
      (cond
        ((string= path "https://oauth2.googleapis.com/token")
         (if (equal (form-value content "code") +code+)
             (answer +google-token+)
             (answer +google-code-error+ 400)))
        ((string= path "https://www.googleapis.com/oauth2/v2/userinfo")
         (if (bearer-p) (answer +google-user+) (answer +google-token-error+ 401)))
        ((string= path "https://oauth2.googleapis.com/revoke")
         (answer "{}" (if (search +access-token+ url) 200 400)))
        ((string= path "https://github.com/login/oauth/access_token")
         (if (equal (gethash "code" (com.inuoe.jzon:parse content)) +code+)
             (answer +github-token+)
             (answer +github-code-error+)))
        ((string= path "https://api.github.com/user")
         (answer +github-user+))
        ((string= path "https://api.github.com/user/emails")
         (answer +github-emails+))
        (t (error "Unexpected request: ~a ~a" method url))))))

(defmacro with-fake-providers (&body body)
  `(let ((*http-client* #'fake-client)
         (*requests* '()))
     ,@body))

(defun token-json (token)
  (if token
      (alexandria:plist-hash-table
       (list "token" (getf token :token) "expires_in" (getf token :expires-in))
       :test #'equal)
      'null))

(defun report-app (user-fn)
  "An app answering what the middleware put in env, as JSON."
  (lambda (env)
    `(200 (:content-type "application/json")
          (,(com.inuoe.jzon:stringify
             (alexandria:plist-hash-table
              (list "user" (funcall user-fn env)
                    "token" (token-json (oauth-token env))
                    "refreshToken" (token-json (oauth-refresh-token env))
                    "grantedScopes" (coerce (oauth-granted-scopes env) 'vector))
              :test #'equal))))))

(defun location-params (headers)
  (let ((uri (quri:uri (gethash "location" headers))))
    (values (quri:url-decode-params (quri:uri-query uri))
            (format nil "~a://~a~a" (quri:uri-scheme uri) (quri:uri-host uri) (quri:uri-path uri)))))

(defun param (params name)
  (cdr (assoc name params :test #'string=)))

(defun valid-cookie ()
  '(("cookie" . "state=valid-state")))

(deftest generate-state
  (let ((states (loop :repeat 200 :collect (generate-state))))
    (ok (every (lambda (s) (ppcre:scan "^[A-Za-z0-9_-]{43}$" s)) states) "43 url-safe characters")
    (ok (= (length (remove-duplicates states :test #'string=)) 200) "no repeats")))

(deftest google-auth
  (let ((app (lack:builder
              (with-args *mw-google-auth*
                :client-id "google-id" :client-secret "google-secret"
                :scope '("openid" "email" "profile"))
              (report-app #'google-user)))
        (custom (lack:builder
                 (with-args *mw-google-auth*
                   :client-id "google-id" :client-secret "google-secret"
                   :scope '("openid" "email" "profile")
                   :redirect-uri "http://localhost:3000/google"
                   :login-hint "test-login-hint" :prompt :select-account
                   :state "test-state" :access-type :offline)
                 (report-app #'google-user))))
    (testing "redirects to Google with a state kept in a cookie"
      (testing-app app
        (multiple-value-bind (body status headers) (request "http://localhost/google?x=1" :max-redirects 0)
          (declare (ignore body))
          (ok (eql status 302))
          (multiple-value-bind (params base) (location-params headers)
            (ok (string= base "https://accounts.google.com/o/oauth2/v2/auth"))
            (ok (string= (param params "redirect_uri") "http://localhost/google") "the URL without its query")
            (ok (string= (param params "client_id") "google-id"))
            (ok (string= (param params "response_type") "code"))
            (ok (string= (param params "include_granted_scopes") "true"))
            (ok (string= (param params "scope") "openid email profile"))
            (let ((cookie (gethash "set-cookie" headers)))
              (ok (search (format nil "state=~a" (param params "state")) cookie))
              (ok (search "Max-Age=600" cookie))
              (ok (search "HttpOnly" cookie))
              (ok (search "Secure" cookie))
              (ok (search "SameSite=Lax" cookie)))))))
    (testing "attaches custom parameters"
      (testing-app custom
        (multiple-value-bind (body status headers) (request "http://localhost/google-custom" :max-redirects 0)
          (declare (ignore body))
          (ok (eql status 302))
          (let ((params (location-params headers)))
            (ok (string= (param params "redirect_uri") "http://localhost:3000/google"))
            (ok (string= (param params "login_hint") "test-login-hint"))
            (ok (string= (param params "prompt") "select_account"))
            (ok (string= (param params "state") "test-state"))
            (ok (string= (param params "access_type") "offline"))))))
    (testing "prevents CSRF"
      (with-fake-providers
        (testing-app app
          (ok (eql (nth-value 1 (request (format nil "/google?code=~a&state=malware-state" +code+))) 401))
          (ok (eql (nth-value 1 (request (format nil "/google?code=~a" +code+) :headers (valid-cookie))) 401)
              "a state is required")
          (ok (eql (nth-value 1 (request (format nil "/google?code=~a&state=malware-state" +code+)
                                         :headers (valid-cookie)))
                   401))
          (ok (null *requests*) "nothing is asked of Google"))))
    (testing "answers 400 with Google's message for an invalid code"
      (with-fake-providers
        (testing-app app
          (multiple-value-bind (body status)
              (request "/google?code=9348ffdsd-sdsdbad-code&state=valid-state" :headers (valid-cookie))
            (ok (eql status 400))
            (ok (string= body "Invalid code."))))))
    (testing "puts the token and the user in env"
      (with-fake-providers
        (testing-app app
          (multiple-value-bind (body status)
              (request (format nil "/google?code=~a&state=valid-state" (quri:url-encode +code+))
                       :headers (valid-cookie))
            (ok (eql status 200))
            (let ((json (com.inuoe.jzon:parse body)))
              (ok (equalp (gethash "user" json) (com.inuoe.jzon:parse +google-user+)))
              (ok (equalp (gethash "grantedScopes" json) #("openid" "email" "profile")))
              (ok (string= (gethash "token" (gethash "token" json)) +access-token+))
              (ok (eql (gethash "expires_in" (gethash "token" json)) 60000))
              (ok (string= (gethash "token" (gethash "refreshToken" json)) "1//04dX-1234567890abcdef-567890abcdef1234"))
              (ok (eql (gethash "expires_in" (gethash "refreshToken" json)) 3600)))))
        (destructuring-bind (method url headers content) (car (last *requests*))
          (declare (ignore headers))
          (ok (eq method :post))
          (ok (string= url "https://oauth2.googleapis.com/token"))
          (ok (string= (form-value content "client_id") "google-id"))
          (ok (string= (form-value content "client_secret") "google-secret"))
          (ok (string= (form-value content "redirect_uri") "http://localhost/google"))
          (ok (string= (form-value content "grant_type") "authorization_code")))))
    (testing "requires a scope"
      (ok (signals (funcall *mw-google-auth* (report-app #'google-user)))))
    (testing "revokes a token"
      (with-fake-providers
        (ok (google-revoke-token +access-token+))
        (ng (google-revoke-token "other-token"))))))

(deftest github-auth
  (let ((github-app (lack:builder
                     (with-args *mw-github-auth* :client-id "github-id" :client-secret "github-secret")
                     (report-app #'github-user)))
        (github-app-custom (lack:builder
                            (with-args *mw-github-auth*
                              :client-id "github-id" :client-secret "github-secret"
                              :redirect-uri "http://localhost:3000/github/app")
                            (report-app #'github-user)))
        (oauth-app (lack:builder
                    (with-args *mw-github-auth*
                      :client-id "github-id" :client-secret "github-secret"
                      :scope '("public_repo" "read:user" "user" "user:email" "user:follow")
                      :oauth-app t)
                    (report-app #'github-user))))
    (testing "a GitHub App is redirected back to the requested URL"
      (testing-app github-app
        (multiple-value-bind (body status headers) (request "http://localhost/github/app?next=%2Fhome" :max-redirects 0)
          (declare (ignore body))
          (ok (eql status 302))
          (multiple-value-bind (params base) (location-params headers)
            (ok (string= base "https://github.com/login/oauth/authorize"))
            (ok (string= (param params "client_id") "github-id"))
            (ok (string= (param params "redirect_uri") "http://localhost/github/app?next=%2Fhome"))
            (ok (null (param params "scope")) "a GitHub App sets its scopes itself")
            (ok (search (format nil "state=~a" (param params "state")) (gethash "set-cookie" headers)))))))
    (testing "a custom redirect_uri"
      (testing-app github-app-custom
        (multiple-value-bind (body status headers) (request "/github/app-custom-redirect" :max-redirects 0)
          (declare (ignore body))
          (ok (eql status 302))
          (ok (string= (param (location-params headers) "redirect_uri") "http://localhost:3000/github/app")))))
    (testing "an OAuth app asks for its scopes and no redirect_uri"
      (testing-app oauth-app
        (multiple-value-bind (body status headers) (request "/github/oauth-app" :max-redirects 0)
          (declare (ignore body))
          (ok (eql status 302))
          (let ((params (location-params headers)))
            (ok (string= (param params "scope") "public_repo,read:user,user,user:email,user:follow"))
            (ok (null (param params "redirect_uri")))))))
    (testing "prevents CSRF"
      (with-fake-providers
        (testing-app github-app
          (ok (eql (nth-value 1 (request (format nil "/github/app?code=~a&state=malware-state" +code+))) 401))
          (ok (eql (nth-value 1 (request (format nil "/github/app?code=~a" +code+) :headers (valid-cookie))) 401))
          (ok (null *requests*)))))
    (dolist (app (list github-app oauth-app))
      (testing "answers 400 with GitHub's message for an invalid code"
        (with-fake-providers
          (testing-app app
            (multiple-value-bind (body status)
                (request "/github?code=9348ffdsd-sdsdbad-code&state=valid-state" :headers (valid-cookie))
              (ok (eql status 400))
              (ok (string= body "Invalid Code."))))))
      (testing "puts the token and the user, with the primary email, in env"
        (with-fake-providers
          (testing-app app
            (multiple-value-bind (body status)
                (request (format nil "/github?code=~a&state=valid-state" (quri:url-encode +code+))
                         :headers (valid-cookie))
              (ok (eql status 200))
              (let* ((json (com.inuoe.jzon:parse body))
                     (user (gethash "user" json)))
                (ok (string= (gethash "login" user) "monoald"))
                (ok (string= (gethash "email" user) "test@email.com") "the primary address")
                (ok (equalp (gethash "grantedScopes" json) #("public_repo" "user")))
                (ok (string= (gethash "token" (gethash "token" json)) +access-token+))
                (ok (string= (gethash "token" (gethash "refreshToken" json)) "t4589fh-9gj3g93-34f5t64n"))
                (ok (eql (gethash "expires_in" (gethash "refreshToken" json)) 6000000)))))
          (let ((user-request (find "https://api.github.com/user" *requests* :key #'second :test #'string=)))
            (ok (equal (header-value (third user-request) "Authorization")
                       (format nil "Bearer ~a" +access-token+)))
            (ok (header-value (third user-request) "User-Agent") "GitHub requires a User-Agent")))))))
