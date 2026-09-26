(defpackage #:lack-mw/cors
  (:use #:cl)
  (:import-from #:alexandria
                #:remove-from-plist)
  (:import-from #:cl-ppcre)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:export #:*mw-cors*))
(in-package #:lack-mw/cors)

(defun join (strings)
  (format nil "~{~a~^,~}" strings))

(defun set-header (headers key value)
  (list* key value (remove-from-plist headers key)))

(defun append-vary (headers value)
  (let ((current (getf headers :vary)))
    (cond ((null current) (set-header headers :vary value))
          ((member value (ppcre:split "\\s*,\\s*" current) :test #'string-equal)
           headers)
          (t (set-header headers :vary (format nil "~a, ~a" current value))))))

(defun origin-finder (origin)
  (cond ((equal origin "*") (constantly "*"))
        ((stringp origin) (lambda (o env)
                            (declare (ignore env))
                            (and (string= o origin) o)))
        ((functionp origin) origin)
        (t (lambda (o env)
             (declare (ignore env))
             (and (member o origin :test #'string=) o)))))

(defparameter *mw-cors*
  (lambda (app &key (origin "*")
                    (allow-methods '("GET" "HEAD" "PUT" "POST" "DELETE" "PATCH" "QUERY"))
                    (allow-headers '())
                    max-age
                    credentials
                    (expose-headers '()))
    (let ((find-origin (origin-finder origin))
          (find-methods (if (functionp allow-methods)
                            allow-methods
                            (constantly allow-methods)))
          (allow-headers-str (and allow-headers (join allow-headers)))
          (expose-headers-str (and expose-headers (join expose-headers)))
          (wildcard-p (equal origin "*")))
      (lambda (env)
        (let* ((req-headers (getf env :headers))
               (req-origin (or (gethash "origin" req-headers) ""))
               (allow-origin (funcall find-origin req-origin env))
               (cors-headers
                 (append (and allow-origin
                              (list :access-control-allow-origin allow-origin))
                         (and credentials
                              (list :access-control-allow-credentials "true"))
                         (and expose-headers-str
                              (list :access-control-expose-headers expose-headers-str)))))
          (if (eq (getf env :request-method) :options)
              ;; Preflight: answered here, never reaches the app
              (let ((headers cors-headers)
                    (methods (funcall find-methods req-origin env))
                    (headers-str
                      (or allow-headers-str
                          (let ((requested (gethash "access-control-request-headers"
                                                    req-headers)))
                            (and requested
                                 (plusp (length requested))
                                 (join (mapcar (lambda (h) (string-trim '(#\Space #\Tab) h))
                                               (ppcre:split "," requested))))))))
                (unless wildcard-p
                  (setf headers (append-vary headers "Origin")))
                (when max-age
                  (setf headers (set-header headers :access-control-max-age
                                            (princ-to-string max-age))))
                (when methods
                  (setf headers (set-header headers :access-control-allow-methods
                                            (join methods))))
                (when headers-str
                  (setf headers (set-header headers :access-control-allow-headers headers-str))
                  (setf headers (append-vary headers "Access-Control-Request-Headers")))
                (list 204 headers '()))
              (funcall-with-cb
               app env
               (lambda (response)
                 (destructuring-bind (status headers &rest body) response
                   (loop for (k v) on cors-headers by #'cddr
                         do (setf headers (set-header headers k v)))
                   (unless wildcard-p
                     (setf headers (append-vary headers "Origin")))
                   (list* status headers body)))))))))
  "CORS middleware. Options: :origin (\"*\", a string, a list of strings, or a
function (origin env) returning the allowed origin or NIL), :allow-methods (a list
or a function (origin env) returning a list), :allow-headers, :max-age,
:credentials, :expose-headers.")
