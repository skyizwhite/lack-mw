(defpackage #:lack-mw-test/recovery
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:com.inuoe.jzon)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/recovery
                #:*mw-recovery*)
  (:import-from #:lack-mw/helpers/escape
                #:escape-html
                #:escape-json))
(in-package #:lack-mw-test/recovery)

(define-condition custom-error (error) ()
  (:report "custom <failure> & \"quoted\""))

(defun failing-app (&optional (message "boom"))
  (lambda (env)
    (declare (ignore env))
    (error message)))

(defun ok-app (env)
  (declare (ignore env))
  '(200 (:content-type "text/plain") ("ok")))

(defun recovery (app &rest args)
  (lack:builder (apply #'with-args *mw-recovery* (append args '(:logger nil))) app))

(defmacro with-response ((body &optional (status (gensym)) (headers (gensym)))
                         (app &optional (path "/")) &body forms)
  `(testing-app ,app
     (multiple-value-bind (,body ,status ,headers) (request ,path)
       (declare (ignorable ,body ,status ,headers))
       ,@forms)))

(deftest escape-helpers
  (ok (string= (escape-html "<a href=\"x\">'&'</a>")
               "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;"))
  (ok (string= (escape-json (format nil "a\"b\\c~Cd~Ce~Cf" #\Newline #\Tab (code-char 1)))
               "a\\\"b\\\\c\\nd\\te\\u0001f")))

(deftest html-format
  (with-response (body status headers) ((recovery (failing-app "secret message")))
    (ok (eql status 500))
    (ok (string= (gethash "content-type" headers) "text/html; charset=utf-8"))
    (ok (search "Internal Server Error" body))
    (ok (search "<html>" body))
    (ng (search "secret message" body) "no message without dev-mode")
    (ng (search "SIMPLE-ERROR" body) "no type without dev-mode")))

(deftest json-format
  (with-response (body status headers) ((recovery (failing-app "secret message") :format :json))
    (ok (eql status 500))
    (ok (string= (gethash "content-type" headers) "application/json; charset=utf-8"))
    (ok (string= body "{\"error\":{\"message\":\"Internal Server Error\"}}"))))

(deftest text-format
  (with-response (body status headers) ((recovery (failing-app "secret message") :format :text))
    (ok (eql status 500))
    (ok (string= (gethash "content-type" headers) "text/plain; charset=utf-8"))
    (ok (string= body "Internal Server Error"))))

(deftest invalid-format
  (ok (signals (funcall *mw-recovery* #'ok-app :format :xml))))

(deftest dev-mode-html
  (with-response (body status) ((recovery (failing-app "<script>alert(1)</script>") :dev-mode t))
    (ok (eql status 500))
    (ok (search "SIMPLE-ERROR" body) "shows the type")
    (ok (search "&lt;script&gt;alert(1)&lt;/script&gt;" body) "shows the escaped message")
    (ng (search "<script>" body) "the message is not raw")
    (ok (search "Backtrace" body))
    (ok (search "<pre>" body)))
  (with-response (body) ((recovery (lambda (env) (declare (ignore env)) (error 'custom-error))
                                   :dev-mode t))
    (ok (search "CUSTOM-ERROR" body))
    (ok (search "custom &lt;failure&gt; &amp; &quot;quoted&quot;" body))))

(deftest dev-mode-json
  (with-response (body status) ((recovery (lambda (env) (declare (ignore env)) (error 'custom-error))
                                          :format :json :dev-mode t))
    (ok (eql status 500))
    (let ((error (gethash "error" (com.inuoe.jzon:parse body))))
      (ok (string= (gethash "message" error) "Internal Server Error"))
      (ok (search "CUSTOM-ERROR" (gethash "type" error)))
      (ok (string= (gethash "detail" error) "custom <failure> & \"quoted\""))
      (ok (plusp (length (gethash "backtrace" error))))))
  (with-response (body) ((recovery (failing-app (format nil "line1~%\"line2\"\\~C" (code-char 7)))
                                   :format :json :dev-mode t))
    (ok (string= (gethash "detail" (gethash "error" (com.inuoe.jzon:parse body)))
                 (format nil "line1~%\"line2\"\\~C" (code-char 7))))))

(deftest dev-mode-text
  (with-response (body) ((recovery (failing-app "visible message") :format :text :dev-mode t))
    (ok (eql 0 (search "Internal Server Error" body)))
    (ok (search "SIMPLE-ERROR: visible message" body))
    (ok (> (count #\Newline body) 3) "has a backtrace")))

(deftest logger
  (let (calls)
    (testing-app (lack:builder
                  (with-args *mw-recovery*
                    :logger (lambda (condition backtrace env)
                              (push (list condition backtrace env) calls)))
                  (lambda (env) (declare (ignore env)) (error 'custom-error)))
      (ok (eql (nth-value 1 (request "/foo")) 500)))
    (ok (= (length calls) 1))
    (destructuring-bind (condition backtrace env) (first calls)
      (ok (typep condition 'custom-error))
      (ok (stringp backtrace))
      (ok (plusp (length backtrace)))
      (ok (string= (getf env :path-info) "/foo")))))

(deftest default-logger
  (let* ((output (make-string-output-stream))
         (*error-output* output))
    (with-response (body status) ((lack:builder *mw-recovery* (failing-app "logged message"))
                                  "/path")
      (ok (eql status 500))
      (ng (search "logged message" body)))
    (let ((log (get-output-stream-string output)))
      (ok (search "GET /path: logged message" log))
      (ok (> (count #\Newline log) 1) "includes the backtrace"))))

(deftest logger-nil
  (let* ((output (make-string-output-stream))
         (*error-output* output))
    (with-response (body status) ((recovery (failing-app)))
      (ok (eql status 500)))
    (ok (string= (get-output-stream-string output) ""))))

(deftest failing-logger
  (testing-app (lack:builder (with-args *mw-recovery* :logger (lambda (&rest args)
                                                                (declare (ignore args))
                                                                (error "logger broke")))
                             (failing-app))
    (ok (eql (nth-value 1 (request "/")) 500))))

(deftest on-error
  (let (seen)
    (with-response (body status) ((recovery (failing-app)
                                            :on-error (lambda (condition env)
                                                        (declare (ignore env))
                                                        (setf seen condition)
                                                        '(503 (:content-type "text/plain") ("custom")))))
      (ok (eql status 503))
      (ok (string= body "custom"))
      (ok (typep seen 'simple-error))))
  (with-response (body status) ((recovery (failing-app)
                                          :format :json
                                          :on-error (lambda (c e)
                                                      (declare (ignore c e))
                                                      (error "on-error broke"))))
    (ok (eql status 500) "falls back to a static 500")
    (ok (string= body "Internal Server Error"))))

(deftest inner-handler-wins
  (with-response (body status) ((recovery (lambda (env)
                                            (handler-case (funcall (failing-app) env)
                                              (error () '(404 (:content-type "text/plain") ("handled")))))))
    (ok (eql status 404))
    (ok (string= body "handled"))))

(deftest non-error-passes
  (with-response (body status) ((recovery #'ok-app))
    (ok (eql status 200))
    (ok (string= body "ok")))
  (let ((*error-output* (make-broadcast-stream)))
    (with-response (body status) ((recovery (lambda (env)
                                              (warn "just a warning")
                                              (ok-app env))))
      (ok (eql status 200) "warnings are not caught"))))

(defun call-delayed (app)
  (let ((response (funcall app '(:request-method :get :request-uri "/" :path-info "/")))
        result)
    (ok (functionp response))
    (funcall response (lambda (r) (setf result r)))
    result))

(deftest delayed-response
  (let ((result (call-delayed (recovery (lambda (env)
                                          (declare (ignore env))
                                          (lambda (responder)
                                            (declare (ignore responder))
                                            (error "before responder")))
                                        :format :text))))
    (ok (eql (first result) 500))
    (ok (equal (third result) '("Internal Server Error"))))
  (let ((result (call-delayed (recovery (lambda (env)
                                          (declare (ignore env))
                                          (lambda (responder)
                                            (funcall responder '(200 () ("fine")))))))))
    (ok (equal result '(200 () ("fine")))))
  (let (logged)
    (ok (signals (call-delayed (recovery (lambda (env)
                                           (declare (ignore env))
                                           (lambda (responder)
                                             (funcall responder '(200 () ("started")))
                                             (error 'custom-error)))
                                         :logger (lambda (c bt env)
                                                   (declare (ignore bt env))
                                                   (setf logged c))))
                 'custom-error)
        "re-signals after the response started")
    (ok (typep logged 'custom-error) "and logs it")))

(deftest circular-condition
  (let* ((output (make-string-output-stream))
         (*error-output* output)
         (circular (list 1 2)))
    (setf (cdr (last circular)) circular)
    (with-response (body status) ((lack:builder (with-args *mw-recovery* :format :text :dev-mode t)
                                                (lambda (env)
                                                  (declare (ignore env))
                                                  (error "bad ~A" circular))))
      (ok (eql status 500) "a condition holding a circular list is still answered")
      (ok (search "bad" body)))
    (ok (search "bad" (get-output-stream-string output)) "and logged")))

(deftest delayed-response-failures
  (let ((result (call-delayed (recovery (lambda (env)
                                          (declare (ignore env))
                                          (lambda (responder)
                                            (declare (ignore responder))
                                            (error "before responder")))
                                        :on-error (lambda (c env)
                                                    (declare (ignore c env))
                                                    (lambda (responder)
                                                      (funcall responder '(503 () ("later")))))))))
    (ok (equal result '(503 () ("later"))) ":on-error may answer with a delayed response"))
  (let (logged)
    (ok (progn (funcall (funcall (recovery (lambda (env)
                                            (declare (ignore env))
                                            (lambda (responder)
                                              (declare (ignore responder))
                                              (error "before responder")))
                                          :logger (lambda (c bt env)
                                                    (declare (ignore bt env))
                                                    (push c logged)))
                                '(:request-method :get :request-uri "/" :path-info "/"))
                       (lambda (r)
                         (declare (ignore r))
                         (error "connection closed")))
               t)
        "a responder failing on the 500 does not escape")
    (ok (= (length logged) 2) "both errors are logged")))

(deftest default-options
  (let ((*error-output* (make-broadcast-stream)))
    (with-response (body status headers) ((lack:builder *mw-recovery* (failing-app "hidden")))
      (ok (eql status 500))
      (ok (string= (gethash "content-type" headers) "text/html; charset=utf-8"))
      (ok (search "Internal Server Error" body))
      (ng (search "hidden" body)))
    (with-response (body status) ((lack:builder *mw-recovery* #'ok-app))
      (ok (eql status 200))
      (ok (string= body "ok")))))
