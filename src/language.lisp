(defpackage #:lack-mw/language
  (:use #:cl)
  (:import-from #:cl-ppcre)
  (:import-from #:quri)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:import-from #:lack-mw/helpers/cookie
                #:parse-cookie
                #:serialize-cookie)
  (:export #:*mw-language*
           #:language))
(in-package #:lack-mw/language)

(defun language (env)
  "Return the language detected by *MW-LANGUAGE* for this request."
  (getf env :lack-mw.language))

(defparameter +detectors+ '(:querystring :cookie :header :path))

(defparameter +default-cookie-options+
  '(:same-site "Strict" :secure t :max-age 31536000 :http-only t))

(defun trim (s)
  (string-trim '(#\Space #\Tab #\Newline #\Return) s))

;;; Accept-Language

(defun parse-quality (q)
  (cond ((or (null q) (string= q "")) 1)
        ((string= q "NaN") 0)
        (t (let ((n (ignore-errors
                     (let ((*read-default-float-format* 'double-float)
                           (*read-eval* nil))
                       (and (ppcre:scan "^[+-]?(?:[0-9]+\\.?[0-9]*|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$" q)
                            (read-from-string q))))))
             (cond ((not (realp n)) 1)
                   ((< n 0) 0)
                   ((> n 1) 1)
                   (t n))))))

(defun parse-accept-language (header)
  "Return a list of (LANG . Q) sorted by descending quality."
  (let ((values '()))
    (dolist (item (ppcre:split "," header))
      (let* ((parts (ppcre:split ";" item))
             (lang (trim (or (first parts) ""))))
        (unless (string= lang "")
          (let ((q nil))
            (dolist (param (rest parts))
              (let ((eq-pos (position #\= param)))
                (when (and eq-pos (null q)
                           (string-equal (trim (subseq param 0 eq-pos)) "q"))
                  (setf q (trim (subseq param (1+ eq-pos)))))))
            (push (cons lang (parse-quality q)) values)))))
    (stable-sort (nreverse values) #'> :key #'cdr)))

;;; Detection

(defun normalize-language (lang opts)
  (when (and lang (string/= lang ""))
    (handler-case
        (destructuring-bind (&key convert-detected-language ignore-case supported-languages
                             &allow-other-keys)
            opts
          (let* ((normalized (trim lang))
                 (normalized (if convert-detected-language
                                 (funcall convert-detected-language normalized)
                                 normalized))
                 (comp (if ignore-case (string-downcase normalized) normalized))
                 (supported (mapcar (lambda (l) (if ignore-case (string-downcase l) l))
                                    supported-languages)))
            (let ((exact (position comp supported :test #'string=)))
              (when exact
                (return-from normalize-language (nth exact supported-languages))))
            ;; Progressive truncation (RFC 4647 Lookup), longest match wins.
            (let ((best nil) (best-length -1))
              (loop for candidate in supported
                    for original in supported-languages
                    for len = (length candidate)
                    when (and (< len (length comp))
                              (> len best-length)
                              (string= candidate comp :end2 len)
                              (char= (char comp len) #\-))
                      do (setf best original best-length len))
              best)))
      (error () nil))))

(defun query-param (env name)
  (let ((qs (getf env :query-string)))
    (when (and qs (string/= qs ""))
      (cdr (assoc name (quri:url-decode-params qs :lenient t) :test #'string=)))))

(defun request-path (env)
  (let ((uri (getf env :request-uri)))
    (or (and uri (quri:uri-path (quri:uri uri)))
        (getf env :path-info)
        "")))

(defun header (env name)
  (let ((headers (getf env :headers)))
    (and (hash-table-p headers)
         (gethash (string-downcase name) headers))))

(defun detect (detector env opts)
  (ecase detector
    (:querystring
     (normalize-language (query-param env (getf opts :lookup-query-string)) opts))
    (:cookie
     (let ((cookie (header env "cookie")))
       (and cookie
            (normalize-language (parse-cookie cookie (getf opts :lookup-cookie)) opts))))
    (:header
     (let ((accept (header env (getf opts :lookup-from-header-key))))
       (when accept
         (loop for (lang . q) in (parse-accept-language accept)
               for normalized = (and (/= q 0) (normalize-language lang opts))
               when normalized return normalized))))
    (:path
     (let ((segments (remove "" (ppcre:split "/" (request-path env)) :test #'string=)))
       (normalize-language (nth (getf opts :lookup-from-path-index) segments) opts)))))

(defun detect-language (env opts)
  "Return (values language detected-p)."
  (let ((debug (getf opts :debug)))
    (dolist (detector (getf opts :order) (values (getf opts :fallback-language) nil))
      (handler-case
          (let ((lang (detect detector env opts)))
            (when lang
              (when debug
                (format *standard-output* "~&Language detected from ~(~a~): ~a~%" detector lang))
              (return (values lang t))))
        (error (e)
          (when debug
            (format *error-output* "~&Error in ~(~a~) detector: ~a~%" detector e)))))))

(defun merge-plist (defaults overrides)
  (let ((result (copy-list overrides)))
    (loop for (k v) on defaults by #'cddr
          unless (nth-value 2 (get-properties overrides (list k)))
            do (setf result (list* k v result)))
    result))

(defun add-header (res key value)
  (list* (first res) (append (second res) (list key value)) (cddr res)))

(defparameter *mw-language*
  (lambda (app &key (order '(:querystring :cookie :header))
                 (lookup-query-string "lang")
                 (lookup-cookie "language")
                 (lookup-from-header-key "accept-language")
                 (lookup-from-path-index 0)
                 (caches '(:cookie))
                 cookie-options
                 (ignore-case t)
                 (fallback-language "en")
                 (supported-languages '("en"))
                 convert-detected-language
                 debug)
    (unless (member fallback-language supported-languages :test #'equal)
      (error "Fallback language must be included in supported languages"))
    (when (< lookup-from-path-index 0)
      (error "Path index must be non-negative"))
    (unless (every (lambda (d) (member d +detectors+)) order)
      (error "Invalid detector type in order: ~s" order))
    (loop for key in cookie-options by #'cddr
          unless (member key '(:domain :path :same-site :secure :max-age :http-only))
            do (error "Unknown cookie option: ~s" key))
    (let ((opts (list :order order
                      :lookup-query-string lookup-query-string
                      :lookup-cookie lookup-cookie
                      :lookup-from-header-key lookup-from-header-key
                      :lookup-from-path-index lookup-from-path-index
                      :ignore-case ignore-case
                      :fallback-language fallback-language
                      :supported-languages supported-languages
                      :convert-detected-language convert-detected-language
                      :debug debug))
          (cookie-options (merge-plist +default-cookie-options+ cookie-options)))
      (lambda (env)
        (multiple-value-bind (lang detected-p) (detect-language env opts)
          (let ((set-cookie
                  (when (and detected-p (listp caches) (member :cookie caches))
                    (handler-case
                        (apply #'serialize-cookie lookup-cookie lang cookie-options)
                      (error (e)
                        (when debug
                          (format *error-output* "~&Failed to cache language: ~a~%" e))
                        nil))))
                (env (list* :lack-mw.language lang env)))
            (if set-cookie
                (funcall-with-cb app env
                                 (lambda (res) (add-header res :set-cookie set-cookie)))
                (funcall app env)))))))
  "Language detector middleware. Detects the request language from the query
string, cookie, Accept-Language header and/or path (see :ORDER), stores it in
ENV (read it with LANGUAGE) and optionally caches it in a cookie.")
