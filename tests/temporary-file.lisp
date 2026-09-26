(defpackage #:lack-mw-test/temporary-file
  (:use #:cl
        #:rove)
  (:import-from #:lack/test
                #:generate-env)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/temporary-file
                #:*temporary-file*
                #:+temporary-file-header+))
(in-package #:lack-mw-test/temporary-file)

(defun make-temp-file ()
  (let ((path (uiop:tmpize-pathname
               (uiop:merge-pathnames* "lack-mw-temporary-file" (uiop:temporary-directory)))))
    (with-open-file (out path :direction :output :if-exists :supersede)
      (write-string "data" out))
    path))

(defun call-app (mw app)
  "Calls the built app like a server would; returns the response the responder got
and whether the body file still existed while it was responding."
  (let ((res (funcall (funcall mw app) (generate-env "/")))
        got existed)
    (if (functionp res)
        (funcall res (lambda (r)
                       (setf got r
                             existed (and (pathnamep (third r)) (probe-file (third r))))))
        (setf got res
              existed (and (pathnamep (third res)) (probe-file (third res)))))
    (values got (and existed t))))

(deftest temporary-file
  (testing "marked response: file deleted after responding, header stripped"
    (let ((path (make-temp-file)))
      (multiple-value-bind (res existed)
          (call-app *temporary-file*
               (lambda (env)
                 (declare (ignore env))
                 (list 200 (list :content-type "text/plain" +temporary-file-header+ t) path)))
        (ok existed)
        (ok (equal (second res) '(:content-type "text/plain")))
        (ok (null (probe-file path))))))

  (testing "unmarked response is left alone"
    (let ((path (make-temp-file)))
      (unwind-protect
           (let ((response (list 200 '(:content-type "text/plain") path)))
             (ok (eq (funcall (funcall *temporary-file* (lambda (env) (declare (ignore env)) response))
                              (generate-env "/"))
                     response))
             (ok (probe-file path)))
        (uiop:delete-file-if-exists path))))

  (testing "custom header, delayed response"
    (let ((path (make-temp-file)))
      (multiple-value-bind (res existed)
          (call-app (with-args *temporary-file* :header :x-delete-me)
               (lambda (env)
                 (declare (ignore env))
                 (lambda (responder)
                   (funcall responder (list 200 '(:x-delete-me "1") path)))))
        (ok existed)
        (ok (null (second res)))
        (ok (null (probe-file path))))))

  (testing "deleted even when the responder signals"
    (let ((path (make-temp-file)))
      (ok (signals
              (funcall (funcall (funcall *temporary-file*
                                         (lambda (env)
                                           (declare (ignore env))
                                           (list 200 (list +temporary-file-header+ t) path)))
                                (generate-env "/"))
                       (lambda (r) (declare (ignore r)) (error "boom")))))
      (ok (null (probe-file path)))))

  (testing "marked response without a pathname body only loses the header"
    (multiple-value-bind (res)
        (call-app *temporary-file*
             (lambda (env)
               (declare (ignore env))
               (list 200 (list +temporary-file-header+ t) '("ok"))))
      (ok (equal res '(200 () ("ok")))))))
