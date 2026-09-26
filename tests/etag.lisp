(defpackage #:lack-mw-test/etag
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:ironclad)
  (:import-from #:lack/test
                #:testing-app
                #:request
                #:generate-env)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/etag
                #:*mw-etag*
                #:+retained-304-headers+))
(in-package #:lack-mw-test/etag)

(defun text-app (text &rest headers)
  (lambda (env)
    (declare (ignore env))
    `(200 (:content-type "text/plain" ,@headers) (,text))))

(defun body-app (body &key (status 200) headers)
  (lambda (env)
    (declare (ignore env))
    (list status headers body)))

(defun octets (&rest bytes)
  (make-array (length bytes) :element-type '(unsigned-byte 8) :initial-contents bytes))

(defun etag-of (app &rest args)
  (testing-app app
    (multiple-value-bind (body status headers) (apply #'request "/" args)
      (declare (ignore body status))
      (gethash "etag" headers))))

(defun patterned-body (length)
  (let ((body (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (i length body)
      (setf (aref body i) (mod i 256)))))

(deftest etag
  (testing "returns an etag header"
    (ok (string= (etag-of (lack:builder *mw-etag* (text-app "Hono is hot")))
                 "\"d104fafdb380655dab607c9bddc4d4982037afa1\""))
    (ok (string= (etag-of (lack:builder *mw-etag* (text-app "{\"message\":\"Hono is hot\"}")))
                 "\"67340414f1a52c4669a6cec71f0ae04532b29249\"")))

  (testing "another algorithm"
    (let ((mw (with-args *mw-etag*
                :generate-digest (lambda (body)
                                   (ironclad:byte-array-to-hex-string
                                    (ironclad:digest-sequence :sha256 body))))))
      (ok (string= (etag-of (lack:builder mw (text-app "Hono is hot")))
                   "\"ed00834279b4fd5dcdc7ab6a5c9774de8afb2de30da2c8e0f17d0952839b5370\""))
      (ok (string= (etag-of (lack:builder mw (text-app "{\"message\":\"Hono is hot\"}")))
                   "\"83b61a767db6e22afea68dd645b4d4597a06276c8ce7f895ad865cf4ab154ec4\""))))

  (testing "binary bodies"
    (ok (string= (etag-of (lack:builder *mw-etag* (body-app (octets 0))))
                 "\"5ba93c9db0cff93f52b521d7420e43f6eda2784f\""))
    (ok (string/= (etag-of (lack:builder *mw-etag* (body-app (octets 0))))
                  (etag-of (lack:builder *mw-etag* (body-app (octets 0 0))))))
    (ok (string/= (etag-of (lack:builder *mw-etag* (body-app (octets 1 2 3))))
                  (etag-of (lack:builder *mw-etag* (body-app (octets 1 2 3 4))))))
    (ok (string= (etag-of (lack:builder *mw-etag* (body-app (patterned-body (* 256 1024)))))
                 "\"37ef77696fc255bf53b4cdd014b223676f2dc8bb\"")))

  (testing "same etag regardless of body chunks"
    (ok (string= (getf (second (funcall (lack:builder *mw-etag* (body-app '("Hono " "is " "hot")))
                                        (generate-env "/")))
                       :etag)
                 "\"d104fafdb380655dab607c9bddc4d4982037afa1\""))
    (ok (string= (etag-of (lack:builder *mw-etag* (body-app (patterned-body 1000000))))
                 "\"550563e0460b33a3540278a8446a70bb96eb5172\"")))

  (testing "pathname body"
    (let ((path (uiop:tmpize-pathname (uiop:merge-pathnames* "lack-mw-etag" (uiop:temporary-directory)))))
      (unwind-protect
           (progn
             (with-open-file (out path :direction :output :if-exists :supersede)
               (write-string "Hono is hot" out))
             (ok (string= (etag-of (lack:builder *mw-etag* (body-app path)))
                          "\"d104fafdb380655dab607c9bddc4d4982037afa1\"")))
        (uiop:delete-file-if-exists path))))

  (testing "no etag for an empty body or an error"
    (ok (null (etag-of (lack:builder *mw-etag* (body-app '())))))
    (ok (null (etag-of (lack:builder *mw-etag* (body-app '() :status 500))))))

  (testing "no etag without a digest function"
    (ok (null (etag-of (lack:builder (with-args *mw-etag* :generate-digest nil)
                                     (text-app "Hono is hot"))))))

  (testing "weak"
    (ok (string= (etag-of (lack:builder (with-args *mw-etag* :weak t) (text-app "Hono is hot")))
                 "W/\"d104fafdb380655dab607c9bddc4d4982037afa1\"")))

  (testing "conditional GETs"
    (testing-app (lack:builder
                  *mw-etag*
                  (text-app "Hono is great"
                            :cache-control "public, max-age=120"
                            :date "Mon, Feb 27 2023 12:08:36 GMT"
                            :expires "Mon, Feb 27 2023 12:10:36 GMT"
                            :server "Upstream 1.2"
                            :vary "Accept-Language"))
      (let ((etag (multiple-value-bind (body status headers) (request "/")
                    (declare (ignore body))
                    (ok (eql status 200))
                    (gethash "etag" headers))))
        (ok etag)
        (ok (eql (nth-value 1 (request "/" :headers '(("if-none-match" . "\"not the right etag\""))))
                 200))
        (multiple-value-bind (body status headers)
            (request "/" :headers `(("if-none-match" . ,etag)))
          (ok (eql status 304))
          (ok (string= body ""))
          (ok (string= (gethash "etag" headers) etag))
          (ok (string= (gethash "cache-control" headers) "public, max-age=120"))
          (ok (string= (gethash "date" headers) "Mon, Feb 27 2023 12:08:36 GMT"))
          (ok (string= (gethash "expires" headers) "Mon, Feb 27 2023 12:10:36 GMT"))
          (ok (string= (gethash "vary" headers) "Accept-Language"))
          (ok (null (gethash "server" headers)))
          (ok (null (gethash "content-type" headers))))
        (ok (eql (nth-value 1 (request "/" :headers `(("if-none-match" . ,(format nil "\"mismatch 1\", ~a, \"mismatch 2\"" etag)))))
                 304))
        (ok (eql (nth-value 1 (request "/" :headers `(("if-none-match" . ,(format nil "\"mismatch 1\", ~a , \"mismatch 2\"" etag)))))
                 304))
        (ok (eql (nth-value 1 (request "/" :headers '(("if-none-match" . "*"))))
                 304))
        (ok (eql (nth-value 1 (request "/" :headers `(("if-none-match" . ,(format nil "W/~a" etag)))))
                 304))
        (ok (eql (nth-value 1 (request "/" :method :head :headers `(("if-none-match" . ,etag))))
                 304))
        (ok (eql (nth-value 1 (request "/" :method :query :headers `(("if-none-match" . ,etag))))
                 304)))))

  (testing "no 304 on unsafe methods or error responses"
    (testing-app (lack:builder
                  *mw-etag*
                  (lambda (env)
                    (if (eq (getf env :request-method) :put)
                        '(201 (:etag "\"etag-123\"") ("created"))
                        '(404 (:etag "\"etag-123\"") ("not found")))))
      (dolist (inm '("*" "\"etag-123\""))
        (multiple-value-bind (body status)
            (request "/" :method :put :headers `(("if-none-match" . ,inm)))
          (ok (eql status 201))
          (ok (string= body "created")))
        (ok (eql (nth-value 1 (request "/" :headers `(("if-none-match" . ,inm)))) 404)))))

  (testing "no duplicate etag values"
    (testing-app (lack:builder *mw-etag* *mw-etag* (text-app "Hono is hot"))
      (ok (string= (gethash "etag" (nth-value 2 (request "/")))
                   "\"d104fafdb380655dab607c9bddc4d4982037afa1\""))))

  (testing "does not override an upstream etag"
    (ok (string= (etag-of (lack:builder *mw-etag* (text-app "x" :etag "\"f-0194-d\"")))
                 "\"f-0194-d\"")))

  (testing "retains the default and the specified headers"
    (testing-app (lack:builder
                  (with-args *mw-etag* :retained-headers (cons "x-message-retain" +retained-304-headers+))
                  (text-app "Hono is hot"
                            :cache-control "public, max-age=120"
                            :x-message-retain "Hello!"
                            :x-message "Hello!"))
      (multiple-value-bind (body status headers)
          (request "/" :headers '(("if-none-match" . "\"d104fafdb380655dab607c9bddc4d4982037afa1\"")))
        (declare (ignore body))
        (ok (eql status 304))
        (ok (string= (gethash "etag" headers) "\"d104fafdb380655dab607c9bddc4d4982037afa1\""))
        (ok (string= (gethash "cache-control" headers) "public, max-age=120"))
        (ok (string= (gethash "x-message-retain" headers) "Hello!"))
        (ok (null (gethash "x-message" headers))))))

  (testing "delayed responses"
    (let ((app (funcall *mw-etag*
                        (lambda (env)
                          (declare (ignore env))
                          (lambda (responder)
                            (funcall responder '(200 (:content-type "text/plain") ("Hono is hot"))))))))
      (let (res)
        (funcall (funcall app (generate-env "/")) (lambda (r) (setf res r)))
        (ok (string= (getf (second res) :etag) "\"d104fafdb380655dab607c9bddc4d4982037afa1\"")))
      (let (res)
        (funcall (funcall app (generate-env "/" :headers '(("if-none-match" . "*"))))
                 (lambda (r) (setf res r)))
        (ok (eql (first res) 304)))))

  (testing "streaming responses pass through"
    (let* ((app (funcall *mw-etag*
                         (lambda (env)
                           (declare (ignore env))
                           (lambda (responder)
                             (funcall responder '(200 (:content-type "text/plain")))))))
           res)
      (funcall (funcall app (generate-env "/" :headers '(("if-none-match" . "*"))))
               (lambda (r) (setf res r)))
      (ok (equal res '(200 (:content-type "text/plain")))))))
