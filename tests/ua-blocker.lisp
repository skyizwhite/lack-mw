(defpackage #:lack-mw-test/ua-blocker
  (:use #:cl
        #:rove)
  (:import-from #:lack)
  (:import-from #:lack/test
                #:testing-app
                #:request)
  (:import-from #:lack-mw/utils
                #:with-args)
  (:import-from #:lack-mw/ua-blocker
                #:*ua-blocker*
                #:*ai-robots-txt*)
  (:import-from #:lack-mw/ua-blocker/ai-bots
                #:+ai-bots+
                #:+non-respecting-ai-bots+
                #:+ai-robots-txt+))
(in-package #:lack-mw-test/ua-blocker)

(defun text-app (text)
  (lambda (env)
    (declare (ignore env))
    `(200 (:content-type "text/plain") (,text))))

(defun blocked-p (app user-agent)
  (testing-app app
    (multiple-value-bind (body status)
        (request "/" :headers (and user-agent `(("user-agent" . ,user-agent))))
      (cond ((and (eql status 403) (string= body "Forbidden")) t)
            ((eql status 200) nil)
            (t (error "Unexpected response: ~a ~a" status body))))))

(defun blocker (blocklist)
  (lack:builder (with-args *ua-blocker* :blocklist blocklist) (text-app "ok")))

(deftest custom-blocklist
  (let ((app (blocker '("BadBot" "EvilCrawler" "SpamBot"))))
    (ok (blocked-p app "BadBot/1.0"))
    (ok (blocked-p app "badbot/2.0") "case insensitive")
    (ok (blocked-p app "EvilCrawler/3.0 (compatible; MSIE 6.0)"))
    (ng (blocked-p app "GoodBot/1.0"))
    (ng (blocked-p app "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"))
    (ng (blocked-p app nil) "no User-Agent")))

(deftest literal-matching
  (let ((app (blocker '("bigsur.ai" "iaskspider/2.0"))))
    (ok (blocked-p app "bigsur.ai"))
    (ng (blocked-p app "bigsurXai") "a dot is not a wildcard")
    (ok (blocked-p app "iaskspider/2.0"))))

(deftest ai-bots
  (let ((app (blocker +ai-bots+)))
    (ok (blocked-p app "GPTBot/1.0"))
    (ok (blocked-p app "Bytespider"))
    (ok (blocked-p app "ClaudeBot/1.0"))
    (ng (blocked-p app "UnknownBot/1.0"))))

(deftest non-respecting-ai-bots
  (let ((app (blocker +non-respecting-ai-bots+)))
    (ok (blocked-p app "Bytespider"))
    (ng (blocked-p app "GPTBot/1.0") "GPTBot respects robots.txt"))
  (ok (subsetp +non-respecting-ai-bots+ +ai-bots+ :test #'string=)))

(deftest empty-and-default
  (ng (blocked-p (blocker '()) "BadBot/1.0"))
  (ng (blocked-p (lack:builder *ua-blocker* (text-app "ok")) "BadBot/1.0")))

(deftest regex-blocklist
  (let ((app (blocker "BADREGEXBOT|EVILREGEXBOT")))
    (ok (blocked-p app "BadRegexBot/1.0"))
    (ok (blocked-p app "evilregexbot"))
    (ng (blocked-p app "GoodBot/1.0")))
  (ok (blocked-p (blocker (ppcre:create-scanner "^CURL/")) "curl/8.0")))

(deftest ai-robots-txt
  (testing-app (lack:builder *ai-robots-txt* (text-app "ok"))
    (multiple-value-bind (body status headers) (request "/robots.txt")
      (ok (eql status 200))
      (ok (string= body +ai-robots-txt+))
      (ok (search "text/plain" (gethash "content-type" headers))))
    (ok (string= (request "/other") "ok")))
  (ok (search "User-agent: GPTBot" +ai-robots-txt+))
  (let ((end (- (length +ai-robots-txt+) (length "Disallow: /
"))))
    (ok (string= "Disallow: /
" +ai-robots-txt+ :start2 end)))
  (testing-app (lack:builder (with-args *ai-robots-txt* :path "/ai-robots.txt") (text-app "ok"))
    (ok (string= (request "/ai-robots.txt") +ai-robots-txt+))
    (ok (string= (request "/robots.txt") "ok"))))
