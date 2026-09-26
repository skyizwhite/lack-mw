(defpackage #:lack-mw/etag
  (:use #:cl)
  (:import-from #:ironclad)
  (:import-from #:babel)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:export #:*mw-etag*
           #:+retained-304-headers+))
(in-package #:lack-mw/etag)

(defparameter +retained-304-headers+
  '(:cache-control :content-location :date :etag :expires :vary)
  "Headers kept on a 304 response by default: those an equivalent 200 would carry
(RFC 9110 section 15.4.5).")

(defconstant +chunk-size+ (* 256 1024))

(defun sha1-digest (octets)
  ;; Hono digests the body in 256 KiB chunks, each time over the previous digest
  ;; followed by the chunk; done the same way so the tags match Hono's.
  (let ((result nil))
    (loop :for start :from 0 :below (length octets) :by +chunk-size+
          :for chunk := (subseq octets start (min (length octets) (+ start +chunk-size+)))
          :do (setf result (ironclad:digest-sequence
                            :sha1 (if result (concatenate '(vector (unsigned-byte 8)) result chunk) chunk))))
    (ironclad:byte-array-to-hex-string result)))

(defun body-octets (body)
  "The response body as one octet vector, or NIL when it cannot be read."
  (flet ((to-octets (x)
           (etypecase x
             (string (babel:string-to-octets x :encoding :utf-8))
             ((vector (unsigned-byte 8)) x))))
    (typecase body
      ((vector (unsigned-byte 8)) body)
      (pathname
       (with-open-file (in body :element-type '(unsigned-byte 8))
         (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
           (read-sequence octets in)
           octets)))
      (list
       (let ((parts (mapcar #'to-octets (remove nil body))))
         (if (= (length parts) 1)
             (first parts)
             (let ((octets (make-array (reduce #'+ parts :key #'length)
                                       :element-type '(unsigned-byte 8)))
                   (pos 0))
               (dolist (part parts octets)
                 (replace octets part :start1 pos)
                 (incf pos (length part)))))))
      (t nil))))

(defun strip-weak (tag)
  (let ((tag (string-trim '(#\Space #\Tab) tag)))
    (if (and (>= (length tag) 2) (string= "W/" tag :end2 2))
        (subseq tag 2)
        tag)))

(defun etag-matches-p (etag if-none-match)
  (and if-none-match
       (or (string= (string-trim '(#\Space #\Tab) if-none-match) "*")
           (let ((opaque (strip-weak etag)))
             (loop :for start := 0 :then (1+ end)
                   :for end := (position #\, if-none-match :start start)
                   :thereis (string= opaque (strip-weak (subseq if-none-match start end)))
                   :while end)))))

(defun retain-headers (headers retained)
  (loop :for (key val) :on headers :by #'cddr
        :when (member key retained :test #'string-equal)
          :append (list key val)))

(defparameter *mw-etag*
  (lambda (app &key (retained-headers +retained-304-headers+)
                 weak
                 (generate-digest #'sha1-digest))
    (lambda (env)
      (let ((if-none-match (gethash "if-none-match" (getf env :headers)))
            (method (getf env :request-method)))
        (funcall-with-cb
         app env
         (lambda (res)
           (destructuring-bind (status headers &optional (body nil body-p)) res
             (if (or (not body-p)       ; streaming response
                     (not (member method '(:get :head :query)))
                     (not (<= 200 status 299)))
                 res
                 (let ((etag (or (getf headers :etag)
                                 (let* ((octets (body-octets body))
                                        (hash (and generate-digest octets (plusp (length octets))
                                                   (funcall generate-digest octets))))
                                   (and hash
                                        (format nil "~:[~;W/~]\"~a\"" weak hash))))))
                   (cond
                     ((null etag) res)
                     ((etag-matches-p etag if-none-match)
                      (let ((headers (copy-list headers)))
                        (setf (getf headers :etag) etag)
                        (list 304 (retain-headers headers retained-headers) '())))
                     (t
                      (let ((headers (copy-list headers)))
                        (setf (getf headers :etag) etag)
                        (list status headers body))))))))))))
  "Adds an ETag header computed from the response body and answers a matching
If-None-Match on GET, HEAD and QUERY with 304 Not Modified.
Options: :RETAINED-HEADERS (headers kept on a 304), :WEAK (prefix the tag with W/),
:GENERATE-DIGEST (function of an octet vector returning the tag's string, SHA-1 hex
by default; NIL from it means no ETag).")
