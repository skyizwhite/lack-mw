(defpackage #:lack-mw/request-id
  (:use #:cl)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:import-from #:ironclad)
  (:export #:*request-id*
           #:request-id
           #:generate-uuid))
(in-package #:lack-mw/request-id)

(defun request-id (env)
  "Return the request id assigned by *request-id*."
  (getf env :lack-mw.request-id))

(defun generate-uuid ()
  "Generate a random UUID v4 string."
  (let ((bytes (ironclad:random-data 16)))
    (setf (aref bytes 6) (logior #x40 (logand (aref bytes 6) #x0f))
          (aref bytes 8) (logior #x80 (logand (aref bytes 8) #x3f)))
    (let ((hex (ironclad:byte-array-to-hex-string bytes)))
      (format nil "~A-~A-~A-~A-~A"
              (subseq hex 0 8) (subseq hex 8 12) (subseq hex 12 16)
              (subseq hex 16 20) (subseq hex 20 32)))))

(defun valid-id-char-p (c)
  ;; JS /[\w\-=]/
  (or (char<= #\a c #\z) (char<= #\A c #\Z) (char<= #\0 c #\9)
      (member c '(#\_ #\- #\=))))

(defparameter *request-id*
  (lambda (app &key (limit-length 255)
                 (header-name "X-Request-Id")
                 (generator (lambda (env)
                              (declare (ignore env))
                              (generate-uuid))))
    (let ((header-name (and header-name (string/= header-name "") header-name)))
      (lambda (env)
        (let ((req-id (and header-name
                           (getf env :headers)
                           (gethash (string-downcase header-name) (getf env :headers)))))
          (when (or (not req-id)
                    (string= req-id "")
                    (> (length req-id) limit-length)
                    (notevery #'valid-id-char-p req-id))
            (setf req-id (funcall generator env)))
          (funcall-with-cb
           app (list* :lack-mw.request-id req-id env)
           (lambda (res)
             (destructuring-bind (status headers &rest body) res
               ;; like Hono's c.header() before next(): the app may override it
               (if (or (null header-name)
                       (loop for (k) on headers by #'cddr
                             thereis (string-equal k header-name)))
                   res
                   (list* status
                          (append headers
                                  (list (intern (string-upcase header-name) :keyword)
                                        req-id))
                          body)))))))))
  "Middleware that assigns a request id (port of Hono's requestId).
The id is available downstream via (request-id env) and is sent back in the response header.")
