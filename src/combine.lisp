(defpackage #:lack-mw/combine
  (:use #:cl)
  (:import-from #:cl-ppcre)
  (:export #:mw-some
           #:mw-every
           #:mw-except
           #:mw-condition
           #:unmet-condition))
(in-package #:lack-mw/combine)

(define-condition unmet-condition (error)
  ()
  (:report "Unmet condition"))

(defun mw-condition (predicate)
  "Turn PREDICATE (a function of ENV) into a middleware that calls the wrapped
app when PREDICATE returns true, and signals UNMET-CONDITION otherwise."
  (lambda (app)
    (lambda (env)
      (if (funcall predicate env)
          (funcall app env)
          (error 'unmet-condition)))))

(defun mw-every (&rest middlewares)
  "Compose MIDDLEWARES into one middleware; the first one is the outermost."
  (lambda (app)
    (reduce #'funcall middlewares :from-end t :initial-value app)))

(defun mw-some (&rest middlewares)
  "Return a middleware that tries MIDDLEWARES in order and uses the first one
that passes, i.e. calls the wrapped app. A middleware fails when it returns
without calling the app, or signals an error before calling it; the next one
is then tried. The last middleware's outcome (response or error) is final."
  (lambda (app)
    (let* ((flag (gensym "NEXT-CALLED"))
           (tracked-app (lambda (env)
                          (setf (symbol-value flag) t)
                          (funcall app env)))
           (wrapped (mapcar (lambda (mw) (funcall mw tracked-app)) middlewares)))
      (lambda (env)
        ;; A fresh binding per request; the gensym keeps nested MW-SOMEs apart
        ;; and the dynamic binding is thread-local.
        (progv (list flag) (list nil)
          (loop for (handler . rest) on wrapped
                do (setf (symbol-value flag) nil)
                   (if (null rest)
                       (return (funcall handler env))
                       (let ((res (block attempt
                                    (handler-bind
                                        ((error (lambda (e)
                                                  (declare (ignore e))
                                                  (unless (symbol-value flag)
                                                    (return-from attempt '%failed)))))
                                      (let ((res (funcall handler env)))
                                        (if (symbol-value flag) res '%failed))))))
                         (unless (eq res '%failed)
                           (return res))))
                finally (return (funcall app env))))))))

(defun segment-regex (segment)
  (flet ((literal (str)
           (format nil "~{~a~^.*~}"
                   (mapcar #'ppcre:quote-meta-chars
                           (ppcre:split "\\*" str :limit most-positive-fixnum)))))
    (multiple-value-bind (match groups)
        (ppcre:scan-to-strings "^:[A-Za-z0-9_]+(?:\\{(.+)\\})?(\\?)?$" segment)
      (if match
          (let ((re (if (aref groups 0) (format nil "(?:~a)" (aref groups 0)) "[^/]+")))
            (if (aref groups 1)
                (format nil "(?:/~a)?" re)
                (format nil "/~a" re)))
          (format nil "/~a" (literal segment))))))

(defun path-pattern-scanner (pattern)
  "Compile a Hono style path PATTERN such as \"/api/*\", \"/users/:id\",
\"/posts/:id{[0-9]+}\" or \"/animal/:type?\" into a scanner."
  (if (string= pattern "*")
      (ppcre:create-scanner "")
      (let* ((tail-wildcard (and (> (length pattern) 1)
                                 (string= "/*" pattern :start2 (- (length pattern) 2))))
             (body (if tail-wildcard (subseq pattern 0 (- (length pattern) 2)) pattern))
             (segments (rest (ppcre:split "/" body :limit most-positive-fixnum))))
        (ppcre:create-scanner
         ;; when every segment is optional the pattern also matches the root "/"
         (format nil "^(?:~:[~;/~]~{~a~}~:[~;|/~])~:[~;(?:/.*)?~]$"
                 (and (null segments) (not tail-wildcard))
                 (mapcar #'segment-regex segments)
                 (and segments
                      (every (lambda (segment) (ppcre:scan "^:.*\\?$" segment)) segments))
                 tail-wildcard)))))

(defun condition->predicate (condition)
  (etypecase condition
    (string (let ((scanner (path-pattern-scanner condition)))
              (lambda (env) (ppcre:scan scanner (or (getf env :path-info) "")))))
    (function condition)))

(defun mw-except (condition &rest middlewares)
  "Return a middleware that applies MIDDLEWARES (composed like MW-EVERY)
except when CONDITION matches. CONDITION is a path pattern string, a predicate
on ENV, or a list of those (any match skips the middlewares)."
  (let* ((conditions (if (listp condition) condition (list condition)))
         (predicates (mapcar #'condition->predicate conditions))
         (composed (apply #'mw-every middlewares)))
    (lambda (app)
      (let ((wrapped (funcall composed app)))
        (lambda (env)
          (if (some (lambda (p) (funcall p env)) predicates)
              (funcall app env)
              (funcall wrapped env)))))))
