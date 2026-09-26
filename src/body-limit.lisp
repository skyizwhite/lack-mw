(defpackage #:lack-mw/body-limit
  (:use #:cl)
  (:import-from #:circular-streams
                #:circular-input-stream
                #:make-circular-input-stream)
  (:export #:*mw-body-limit*))
(in-package #:lack-mw/body-limit)

(defun payload-too-large (env)
  (declare (ignore env))
  (list 413 (list :content-type "text/plain; charset=utf-8") (list "Payload Too Large")))

(defun body-exceeds-p (stream max-size)
  "Reads STREAM (a circular stream) until EOF or past MAX-SIZE, then rewinds it."
  (let ((buffer (make-array 16384 :element-type '(unsigned-byte 8)))
        (size 0))
    (prog1
        (loop for read = (read-sequence buffer stream)
              do (incf size read)
              when (> size max-size) return t
              when (< read (length buffer)) return nil)
      (file-position stream 0))))

(defparameter *mw-body-limit*
  (lambda (app &key (max-size (error ":max-size is required for *mw-body-limit*"))
                    (on-error #'payload-too-large))
    (check-type max-size (integer 0))
    (lambda (env)
      (let ((chunked (gethash "transfer-encoding" (getf env :headers)))
            (content-length (let ((cl (getf env :content-length)))
                              (if (stringp cl) (parse-integer cl :junk-allowed t) cl)))
            (raw-body (getf env :raw-body)))
        (cond
          ;; Only Content-Length: trust it
          ((and content-length (not chunked))
           (if (> content-length max-size)
               (funcall on-error env)
               (funcall app env)))
          ;; Transfer-Encoding takes precedence over Content-Length (RFC 7230):
          ;; read the body up front so the check is final before the app runs
          ((and chunked raw-body)
           (let ((stream (if (typep raw-body 'circular-input-stream)
                             raw-body
                             (make-circular-input-stream raw-body))))
             (if (body-exceeds-p stream max-size)
                 (funcall on-error env)
                 (funcall app (list* :raw-body stream env)))))
          ;; No length headers: there is no body
          (t (funcall app env))))))
  "Rejects request bodies larger than :max-size bytes (required) by calling
:on-error, a function taking env and returning a response (default: 413
\"Payload Too Large\"). A body of unknown length (Transfer-Encoding) is read up
to the limit before the app runs.")
