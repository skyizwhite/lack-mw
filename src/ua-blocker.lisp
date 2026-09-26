(defpackage #:lack-mw/ua-blocker
  (:use #:cl)
  (:import-from #:cl-ppcre)
  (:import-from #:lack-mw/ua-blocker/ai-bots
                #:+ai-robots-txt+)
  (:export #:*mw-ua-blocker*
           #:*mw-ai-robots-txt*))
(in-package #:lack-mw/ua-blocker)

(defun blocklist-scanner (blocklist)
  "A scanner for BLOCKLIST: a list of user agents, matched literally anywhere in
the upcased User-Agent, or a regex string or scanner run on it as is."
  (etypecase blocklist
    (null nil)
    (list (ppcre:create-scanner
           (format nil "(~{~a~^|~})"
                   (mapcar (lambda (ua) (ppcre:quote-meta-chars (string-upcase ua)))
                           blocklist))))
    ((or string function) (ppcre:create-scanner blocklist))))

(defparameter *mw-ua-blocker*
  (lambda (app &key blocklist)
    (let ((scanner (blocklist-scanner blocklist)))
      (lambda (env)
        (let ((user-agent (gethash "user-agent" (getf env :headers))))
          (if (and scanner user-agent
                   (ppcre:scan scanner (string-upcase user-agent)))
              '(403 (:content-type "text/plain; charset=UTF-8") ("Forbidden"))
              (funcall app env))))))
  "Middleware answering 403 to requests whose User-Agent matches :BLOCKLIST.
A regex blocklist should match on UPPERCASE user agents.")

(defparameter *mw-ai-robots-txt*
  (lambda (app &key (path "/robots.txt"))
    (lambda (env)
      (if (string= (getf env :path-info) path)
          `(200 (:content-type "text/plain; charset=UTF-8") (,+ai-robots-txt+))
          (funcall app env))))
  "Middleware serving +AI-ROBOTS-TXT+ at :PATH.")
