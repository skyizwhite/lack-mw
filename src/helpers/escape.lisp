(defpackage #:lack-mw/helpers/escape
  (:use #:cl)
  (:export #:escape-html
           #:escape-json))
(in-package #:lack-mw/helpers/escape)

;;; String escaping for the middlewares. Not re-exported from lack-mw.

(defun escape-html (string)
  "STRING with & < > \" ' replaced by character references, safe in HTML text
and quoted attribute values."
  (with-output-to-string (s)
    (loop for c across string
          do (case c
               (#\& (write-string "&amp;" s))
               (#\< (write-string "&lt;" s))
               (#\> (write-string "&gt;" s))
               (#\" (write-string "&quot;" s))
               (#\' (write-string "&#39;" s))
               (t (write-char c s))))))

(defun escape-json (string)
  "STRING escaped for use inside a JSON string literal (without the surrounding
quotes): quotes, backslashes and control characters are escaped."
  (with-output-to-string (s)
    (loop for c across string
          for code = (char-code c)
          do (case c
               (#\" (write-string "\\\"" s))
               (#\\ (write-string "\\\\" s))
               (#\Newline (write-string "\\n" s))
               (#\Return (write-string "\\r" s))
               (#\Tab (write-string "\\t" s))
               (#\Backspace (write-string "\\b" s))
               (#\Page (write-string "\\f" s))
               (t (if (< code #x20)
                      (format s "\\u~4,'0X" code)
                      (write-char c s)))))))
