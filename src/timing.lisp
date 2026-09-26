(defpackage #:lack-mw/timing
  (:use #:cl)
  (:import-from #:lack/util
                #:funcall-with-cb)
  (:export #:*timing*
           #:set-metric
           #:start-time
           #:end-time
           #:wrap-time
           #:with-timing))
(in-package #:lack-mw/timing)

(defstruct metric
  (headers '())   ; newest first
  (timers '()))   ; alist (name description . start), oldest first

(defun get-time ()
  "Current time in milliseconds."
  (/ (float (get-internal-real-time) 1d0)
     (/ internal-time-units-per-second 1000)))

(defun env-metric (env)
  (or (getf env :lack-mw.metric)
      (progn
        (warn "Metrics not initialized! Please add the `*timing*` middleware to this route!")
        nil)))

(defun set-metric (env name &optional value-or-description description precision)
  "Add a metric. A number value is a duration in ms; a string is a description."
  (let ((metrics (env-metric env)))
    (when metrics
      (push (if (realp value-or-description)
                (let ((dur (format nil "~,vF" (or precision 1)
                                   (float value-or-description 1d0))))
                  (if description
                      (format nil "~A;dur=~A;desc=\"~A\"" name dur description)
                      (format nil "~A;dur=~A" name dur)))
                (if value-or-description
                    (format nil "~A;desc=\"~A\"" name value-or-description)
                    (format nil "~A" name)))
            (metric-headers metrics))
      nil)))

(defun start-time (env name &optional description)
  "Start a timer."
  (let ((metrics (env-metric env)))
    (when metrics
      (setf (metric-timers metrics)
            (append (remove name (metric-timers metrics) :key #'car :test #'string=)
                    (list (list* name description (get-time)))))
      nil)))

(defun end-time (env name &optional precision)
  "End a timer and record it as a metric."
  (let ((metrics (env-metric env)))
    (when metrics
      (let ((timer (assoc name (metric-timers metrics) :test #'string=)))
        (if (null timer)
            (warn "Timer \"~A\" does not exist!" name)
            (destructuring-bind (description . start) (cdr timer)
              (set-metric env name (- (get-time) start) description precision)
              (setf (metric-timers metrics)
                    (remove timer (metric-timers metrics))))))
      nil)))

(defun wrap-time (env name fn &optional description precision)
  "Call FN, timing its duration (the timer is ended even on non-local exit)."
  (start-time env name description)
  (unwind-protect (funcall fn)
    (end-time env name precision)))

(defmacro with-timing ((env name &key description precision) &body body)
  `(wrap-time ,env ,name (lambda () ,@body) ,description ,precision))

(defun resolve (option env)
  (if (functionp option) (funcall option env) option))

(defun append-header (headers key value)
  ;; like Headers#append: join with an existing value
  (let ((existing (getf headers key)))
    (if existing
        (let ((headers (copy-list headers)))
          (setf (getf headers key) (format nil "~A, ~A" existing value))
          headers)
        (append headers (list key value)))))

(defparameter *timing*
  (lambda (app &key (total t)
                 (enabled t)
                 (total-description "Total Response Time")
                 (auto-end t)
                 (cross-origin nil))
    (lambda (env)
      (if (getf env :lack-mw.metric)
          ;; an outer *timing* is already collecting metrics
          (funcall app env)
          (let* ((metrics (make-metric))
                 (env (list* :lack-mw.metric metrics env)))
            (when total
              (start-time env "total" total-description))
            (funcall-with-cb
             app env
             (lambda (res)
               (when total
                 (end-time env "total"))
               (when auto-end
                 (loop for (name) in (metric-timers metrics)
                       do (end-time env name)))
               (if (resolve enabled env)
                   (destructuring-bind (status headers &rest body) res
                     (let ((headers (append-header headers :server-timing
                                                   (format nil "~{~A~^,~}"
                                                           (reverse (metric-headers metrics)))))
                           (origin (resolve cross-origin env)))
                       (when origin
                         (setf headers (append-header headers :timing-allow-origin
                                                      (if (stringp origin) origin "*"))))
                       (list* status headers body)))
                   res)))))))
  "Middleware that adds the Server-Timing response header (port of Hono's timing).
Use set-metric, start-time, end-time, wrap-time and with-timing with the env downstream.")
