(defpackage #:lack-mw-test/language
  (:use #:cl
        #:rove)
  (:import-from #:lack/test
                #:generate-env)
  (:import-from #:lack-mw/language
                #:*mw-language*
                #:language))
(in-package #:lack-mw-test/language)

(defparameter *echo-app*
  (lambda (env)
    `(200 (:content-type "text/plain") (,(language env)))))

(defun make-app (&rest options)
  (apply *mw-language* *echo-app* options))

(defun req (app uri &rest headers)
  "Return (values body set-cookie)."
  (let ((res (funcall app (generate-env uri :headers headers))))
    (values (first (third res))
            (getf (second res) :set-cookie))))

(deftest query
  (ok (equal (req (make-app :supported-languages '("en" "fr" "es")) "/?lang=fr") "fr"))
  (ok (equal (req (make-app :supported-languages '("en" "fr")) "/?lang=de") "en")))

(deftest cookie
  (ok (equal (req (make-app :supported-languages '("en" "fr")) "/" '("cookie" . "language=fr"))
             "fr"))
  (testing "caches detected language"
    (multiple-value-bind (body set-cookie)
        (req (make-app :supported-languages '("en" "fr") :caches '(:cookie)) "/?lang=fr")
      (ok (equal body "fr"))
      (ok (equal set-cookie
                 "language=fr; Max-Age=31536000; Path=/; HttpOnly; Secure; SameSite=Strict"))))
  (testing "cookie options are merged with defaults"
    (multiple-value-bind (body set-cookie)
        (req (make-app :supported-languages '("en" "fr")
                       :cookie-options '(:same-site "Lax" :secure nil :path "/app"))
             "/?lang=fr")
      (ok (equal body "fr"))
      (ok (equal set-cookie "language=fr; Max-Age=31536000; Path=/app; HttpOnly; SameSite=Lax"))))
  (testing "no cookie for the fallback language"
    (ok (null (nth-value 1 (req (make-app :supported-languages '("en" "fr")) "/")))))
  (testing "caches disabled"
    (ok (null (nth-value 1 (req (make-app :supported-languages '("en" "fr") :caches nil)
                                "/?lang=fr"))))))

(deftest header
  (ok (equal (req (make-app :supported-languages '("en" "fr" "es")) "/"
                  '("accept-language" . "fr-FR,fr;q=0.9,en;q=0.8"))
             "fr"))
  (ok (equal (req (make-app :supported-languages '("en" "ja") :order '(:header)) "/"
                  '("accept-language" . "ja-JP"))
             "ja"))
  (testing "q=0 is rejected"
    (ok (equal (req (make-app :supported-languages '("fr" "en") :order '(:header)) "/"
                    '("accept-language" . "fr;q=0"))
               "en"))
    (ok (equal (req (make-app :supported-languages '("fr" "en") :order '(:header)) "/"
                    '("accept-language" . "fr;q=0,de;q=0.8"))
               "en"))
    (multiple-value-bind (body set-cookie)
        (req (make-app :supported-languages '("fr" "en" "ja") :order '(:header :querystring))
             "/?lang=ja" '("accept-language" . "fr;q=0"))
      (ok (equal body "ja"))
      (ok (search "language=ja" set-cookie))))
  (testing "quality ordering"
    (ok (equal (req (make-app :supported-languages '("en" "fr" "ja") :order '(:header)) "/"
                    '("accept-language" . "fr;q=0.5,ja;q=0.8,en;q=0.1"))
               "ja")))
  (testing "truncation"
    (ok (equal (req (make-app :supported-languages '("zh-Hant" "en") :order '(:header)) "/"
                    '("accept-language" . "zh-Hant-CN"))
               "zh-Hant"))
    (ok (equal (req (make-app :supported-languages '("zh" "zh-Hant") :fallback-language "zh"
                              :order '(:header))
                    "/" '("accept-language" . "zh-Hant-CN"))
               "zh-Hant"))
    (ok (equal (req (make-app :supported-languages '("en" "ja") :order '(:header)) "/"
                    '("accept-language" . "ko-KR"))
               "en"))
    (ok (equal (req (make-app :supported-languages '("fr" "fr-CA") :fallback-language "fr"
                              :order '(:header))
                    "/" '("accept-language" . "fr-CA"))
               "fr-CA"))
    (ok (equal (req (make-app :supported-languages '("en" "ja") :order '(:header) :ignore-case t)
                    "/" '("accept-language" . "JA-JP"))
               "ja")))
  (testing "malformed header"
    (ok (equal (req (make-app :supported-languages '("en" "fr")) "/"
                    '("accept-language" . "invalid;header;;format"))
               "en")))
  (testing "invalid header lookup key"
    (ok (equal (req (make-app :supported-languages '("en" "fr") :order '(:header)
                              :lookup-from-header-key (format nil "accept~%language"))
                    "/" '("accept-language" . "fr"))
               "en"))))

(deftest normalization
  (ok (equal (lack-mw/language::normalize-language
              "zh-HANT-CN" '(:ignore-case t :supported-languages ("en" "ZH-Hant")))
             "ZH-Hant"))
  (ok (null (lack-mw/language::normalize-language
             (let ((s (with-output-to-string (o) (dotimes (i 30000) (write-string "x-" o)))))
               (subseq s 0 (1- (length s))))
             '(:ignore-case t :supported-languages ("en" "ja"))))))

(deftest path
  (ok (equal (req (make-app :order '(:path) :supported-languages '("en" "fr")) "/fr/page") "fr"))
  (ok (equal (req (make-app :order '(:path) :supported-languages '("en" "fr")
                            :lookup-from-path-index 99)
                  "/fr/page")
             "en"))
  (testing "uses the original request URI, not a rewritten path-info"
    (let ((app (make-app :order '(:path) :supported-languages '("en" "fr"))))
      (ok (equal (first (third (funcall app (list* :path-info "/home"
                                                   (generate-env "/fr/home")))))
                 "fr")))))

(deftest order
  (ok (equal (req (make-app :order '(:cookie :querystring) :supported-languages '("en" "fr" "es"))
                  "/?lang=fr" '("cookie" . "language=es"))
             "es"))
  (ok (equal (req (make-app :order '(:cookie :querystring) :supported-languages '("en" "fr"))
                  "/?lang=fr")
             "fr")))

(deftest conversion
  (ok (equal (req (make-app :supported-languages '("en" "fr")
                            :convert-detected-language
                            (lambda (lang) (subseq lang 0 (or (position #\- lang) (length lang)))))
                  "/?lang=fr-FR")
             "fr"))
  (ok (equal (req (make-app :supported-languages '("en" "fr") :ignore-case nil) "/?lang=FR")
             "en"))
  (testing "errors in convert-detected-language fall back"
    (ok (equal (req (make-app :supported-languages '("en" "fr")
                              :convert-detected-language
                              (lambda (lang) (if (string= lang "fr") (error "boom") lang)))
                    "/?lang=fr")
               "en"))))

(deftest validation
  (ok (signals (make-app :supported-languages '("fr" "es") :fallback-language "en")))
  (ok (signals (make-app :lookup-from-path-index -1)))
  (ok (signals (make-app :supported-languages '())))
  (ok (signals (make-app :order '(:invalid-detector))))
  (ok (signals (make-app :cookie-options '(:unknown 1))))
  (testing "unknown cache types are ignored"
    (multiple-value-bind (body set-cookie)
        (req (make-app :caches '(:test) :supported-languages '("en")) "/?lang=en")
      (ok (equal body "en"))
      (ok (null set-cookie)))))

(deftest debug
  (testing "logs detection"
    (let ((out (with-output-to-string (*standard-output*)
                 (req (make-app :supported-languages '("en" "fr") :debug t) "/?lang=fr"))))
      (ok (search "Language detected from querystring" out))))
  (testing "logs cookie cache errors in debug mode"
    (let* (body
           (err (with-output-to-string (*error-output*)
                  (setf body (req (make-app :supported-languages '("en" "fr")
                                            :lookup-cookie "bad cookie" :debug t)
                                  "/?lang=fr")))))
      (ok (equal body "fr"))
      (ok (search "Failed to cache language" err))))
  (testing "silent when debug is disabled"
    (let* (body set-cookie
           (err (with-output-to-string (*error-output*)
                  (multiple-value-setq (body set-cookie)
                    (req (make-app :supported-languages '("en" "fr") :lookup-cookie "bad cookie")
                         "/?lang=fr")))))
      (ok (equal body "fr"))
      (ok (null set-cookie))
      (ok (string= err "")))))
