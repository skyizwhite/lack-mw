(defpackage #:lack-mw/helpers/url
  (:use #:cl)
  (:export #:request-url))
(in-package #:lack-mw/helpers/url)

;;; URL helpers for the middlewares. Not re-exported from lack-mw.

(defun request-url (env)
  "The URL of the request in ENV: its scheme, the Host header (or the server name
and port) and the request URI with its query."
  (format nil "~A://~A~A"
          (or (getf env :url-scheme) "http")
          (or (gethash "host" (getf env :headers))
              (format nil "~A~@[:~A~]" (getf env :server-name)
                      (let ((port (getf env :server-port)))
                        (unless (member port '(nil 80 443)) port))))
          (getf env :request-uri)))
