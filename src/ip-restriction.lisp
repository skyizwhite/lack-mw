(defpackage #:lack-mw/ip-restriction
  (:use #:cl)
  (:import-from #:cl-ppcre)
  (:export #:*mw-ip-restriction*))
(in-package #:lack-mw/ip-restriction)

;;; IP address parsing

(define-condition invalid-ip-address (error)
  ((address :initarg :address :reader invalid-ip-address-address))
  (:report (lambda (c s)
             (format s "Invalid IP address: ~a" (invalid-ip-address-address c)))))

(defparameter +ipv4-scanner+
  (ppcre:create-scanner
   "^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"))

(defun address-type (addr)
  "Return :ipv4, :ipv6 or NIL (like Hono's distinctRemoteAddr)."
  (cond ((ppcre:scan +ipv4-scanner+ addr) :ipv4)
        ((find #\: addr) :ipv6)))

(defun parse-ipv4 (str &optional (whole str))
  (unless (ppcre:scan +ipv4-scanner+ str)
    (error 'invalid-ip-address :address whole))
  (reduce (lambda (acc octet) (+ (ash acc 8) (parse-integer octet)))
          (ppcre:split "\\." str)
          :initial-value 0))

(defun parse-ipv6-groups (str whole allow-ipv4)
  "Parse colon separated hex groups (last one may be dotted IPv4) into a list of 16-bit ints."
  (if (string= str "")
      '()
      (let* ((parts (ppcre:split ":" str :limit most-positive-fixnum))
             (last-part (car (last parts))))
        (append
         (mapcar (lambda (part)
                   (unless (ppcre:scan "^[0-9a-fA-F]{1,4}$" part)
                     (error 'invalid-ip-address :address whole))
                   (parse-integer part :radix 16))
                 (butlast parts))
         (if (and allow-ipv4 (find #\. last-part))
             (let ((v4 (parse-ipv4 last-part whole)))
               (list (ldb (byte 16 16) v4) (ldb (byte 16 0) v4)))
             (progn
               (unless (ppcre:scan "^[0-9a-fA-F]{1,4}$" last-part)
                 (error 'invalid-ip-address :address whole))
               (list (parse-integer last-part :radix 16))))))))

(defun link-local-p (n)
  (= (ash n -118) #x3fa))

(defun parse-ipv6 (whole)
  (let* ((zone-pos (position #\% whole))
         (str (subseq whole 0 zone-pos))
         (compress (search "::" str)))
    (when (and zone-pos (= (1+ zone-pos) (length whole)))
      (error 'invalid-ip-address :address whole))
    (when (and compress (search "::" str :start2 (1+ compress)))
      (error 'invalid-ip-address :address whole))
    (let* ((head (parse-ipv6-groups (if compress (subseq str 0 compress) str) whole (not compress)))
           (tail (and compress (parse-ipv6-groups (subseq str (+ compress 2)) whole t)))
           (count (+ (length head) (length tail))))
      (when (if compress (>= count 8) (/= count 8))
        (error 'invalid-ip-address :address whole))
      (let ((result (reduce (lambda (acc g) (+ (ash acc 16) g))
                            (append head
                                    (make-list (- 8 count) :initial-element 0)
                                    tail)
                            :initial-value 0)))
        (when (and zone-pos (not (link-local-p result)))
          (error 'invalid-ip-address :address whole))
        result))))

(defun ipv4-mapped-p (n)
  (= (ash n -32) #xffff))

(defun mapped->ipv4 (n)
  (ldb (byte 32 0) n))

;;; Rule matcher

(defun invalid-rule (rule)
  (error "Invalid rule: ~a" rule))

(defun parse-cidr-prefix (rule prefix max)
  (unless (ppcre:scan "^[0-9]{1,3}$" prefix)
    (invalid-rule rule))
  (let ((n (parse-integer prefix)))
    (when (> n max)
      (invalid-rule rule))
    n))

(defun build-matcher (rules)
  "Compile RULES into a predicate on (addr type)."
  (let ((function-rules '())
        (static-ipv4 (make-hash-table))
        (static-ipv6 (make-hash-table))
        (cidr-rules '()))
    (flet ((register-static (rule)
             (handler-case
                 (case (address-type rule)
                   (:ipv4
                    (let ((bin (parse-ipv4 rule)))
                      (setf (gethash bin static-ipv4) t
                            (gethash (logior (ash #xffff 32) bin) static-ipv6) t)))
                   (:ipv6
                    (let ((bin (parse-ipv6 rule)))
                      (setf (gethash bin static-ipv6) t)
                      (when (ipv4-mapped-p bin)
                        (setf (gethash (mapped->ipv4 bin) static-ipv4) t))))
                   (t (invalid-rule rule)))
               (invalid-ip-address () (invalid-rule rule)))))
      (dolist (rule rules)
        (cond
          ((functionp rule) (push rule function-rules))
          ((not (stringp rule)) (invalid-rule rule))
          ((string= rule "*")
           (return-from build-matcher (constantly t)))
          ((ppcre:scan "/[^/]*$" rule)
           (let* ((slash (position #\/ rule :from-end t))
                  (addr-str (subseq rule 0 slash))
                  (type (address-type addr-str)))
             (unless type (invalid-rule rule))
             (let* ((ipv4-p (eq type :ipv4))
                    (prefix (parse-cidr-prefix rule (subseq rule (1+ slash)) (if ipv4-p 32 128))))
               (if (= prefix (if ipv4-p 32 128))
                   (register-static addr-str)
                   (let ((addr (handler-case (if ipv4-p (parse-ipv4 addr-str) (parse-ipv6 addr-str))
                                 (invalid-ip-address () (invalid-rule rule)))))
                     (when (and (not ipv4-p) (ipv4-mapped-p addr) (>= prefix 96))
                       (setf ipv4-p t
                             addr (mapped->ipv4 addr)
                             prefix (- prefix 96)))
                     (let* ((bits (if ipv4-p 32 128))
                            (mask (ash (1- (ash 1 prefix)) (- bits prefix))))
                       (push (list ipv4-p (logand addr mask) mask) cidr-rules)))))))
          (t (register-static rule)))))
    (setf function-rules (nreverse function-rules)
          cidr-rules (nreverse cidr-rules))
    (lambda (addr type)
      (let* ((remote-ipv4-p (eq type :ipv4))
             (bin (if remote-ipv4-p (parse-ipv4 addr) (parse-ipv6 addr)))
             (remote-ipv4 (cond (remote-ipv4-p bin)
                                ((ipv4-mapped-p bin) (mapped->ipv4 bin)))))
        (or (gethash bin (if remote-ipv4-p static-ipv4 static-ipv6))
            (loop for (rule-ipv4-p net mask) in cidr-rules
                  thereis (if rule-ipv4-p
                              (and remote-ipv4 (= (logand remote-ipv4 mask) net))
                              (and (not remote-ipv4-p) (= (logand bin mask) net))))
            (loop for fn in function-rules
                  thereis (funcall fn (list :addr addr :type type))))))))

;;; Middleware

(defun forbidden ()
  (list 403 (list :content-type "text/plain; charset=UTF-8") (list "Forbidden")))

(defparameter *mw-ip-restriction*
  (lambda (app &key deny-list allow-list
                 (get-ip (lambda (env) (getf env :remote-addr)))
                 on-error)
    (let ((deny-matcher (build-matcher deny-list))
          (allow-matcher (build-matcher allow-list)))
      (flet ((reject (addr type env)
               (if on-error
                   (funcall on-error (list :addr addr :type type) env)
                   (forbidden))))
        (lambda (env)
          (let ((addr (funcall get-ip env)))
            (if (or (null addr) (string= addr ""))
                (forbidden)
                (let* ((type (address-type addr))
                       (decision
                         (handler-case
                             (cond ((funcall deny-matcher addr type) :deny)
                                   ((or (null allow-list) (funcall allow-matcher addr type)) :allow)
                                   (t :deny))
                           ;; An unparsable remote address is always rejected without on-error.
                           (invalid-ip-address () :invalid))))
                  (ecase decision
                    (:allow (funcall app env))
                    (:deny (reject addr type env))
                    (:invalid (forbidden))))))))))
  "IP restriction middleware. Rejects requests by remote address using
:DENY-LIST and :ALLOW-LIST. Each rule is a static IPv4/IPv6 address, a CIDR
range, \"*\", or a function taking (:addr ADDR :type TYPE) and returning a
generalized boolean. :GET-IP is a function of ENV returning the client address
(default: :remote-addr). :ON-ERROR is a function of (REMOTE ENV) returning the
response for a rejected request (default: 403 \"Forbidden\").")
