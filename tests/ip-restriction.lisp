(defpackage #:lack-mw-test/ip-restriction
  (:use #:cl
        #:rove)
  (:import-from #:lack/test
                #:generate-env)
  (:import-from #:lack-mw/ip-restriction
                #:*ip-restriction*))
(in-package #:lack-mw-test/ip-restriction)

(defparameter *ok-app*
  (lambda (env)
    (declare (ignore env))
    '(200 (:content-type "text/plain") ("Hello World!"))))

(defun call (app ip)
  (funcall app (list* :remote-addr ip (generate-env "/"))))

(defun status-for (app ip)
  (first (call app ip)))

(defun match-p (addr rule)
  (let ((app (funcall *ip-restriction* *ok-app*
                      :allow-list (list rule)
                      :get-ip (constantly addr))))
    (= (first (funcall app (generate-env "/"))) 200)))

(deftest restrict
  (testing "basic"
    (let ((app (funcall *ip-restriction* *ok-app*
                        :allow-list '("192.168.1.0" "192.168.2.0/24")
                        :deny-list '("192.168.2.10"))))
      (ok (= (status-for app "0.0.0.0") 403))
      (ok (= (status-for app "192.168.1.0") 200))
      (ok (= (status-for app "192.168.2.5") 200))
      (ok (= (status-for app "192.168.2.10") 403))
      (ok (equal (third (call app "0.0.0.0")) '("Forbidden")))))
  (testing "allow-empty"
    (let ((app (funcall *ip-restriction* *ok-app* :deny-list '("192.168.1.0"))))
      (ok (= (status-for app "0.0.0.0") 200))
      (ok (= (status-for app "192.168.1.0") 403))
      (ok (= (status-for app "192.168.2.5") 200))
      (ok (= (status-for app "192.168.2.10") 200))))
  (testing "no address"
    (let ((app (funcall *ip-restriction* *ok-app*)))
      (ok (= (status-for app nil) 403))
      (ok (= (status-for app "127.0.0.1") 200))))
  (testing "custom on-error"
    (let ((app (funcall *ip-restriction* *ok-app*
                        :get-ip (constantly "0.0.0.0")
                        :deny-list '("0.0.0.0")
                        :on-error (lambda (remote env)
                                    (declare (ignore env))
                                    `(418 () (,(getf remote :addr) ,(string (getf remote :type))))))))
      (ok (equal (funcall app (generate-env "/")) '(418 () ("0.0.0.0" "IPV4"))))))
  (testing "invalid remote address"
    (dolist (ip '("999.999.999.999" "2001:db8::1%eth0" "1234:::5678"))
      (let ((app (funcall *ip-restriction* *ok-app* :allow-list '("127.0.0.1"))))
        (ok (= (status-for app ip) 403) ip))))
  (testing "on-error is not called for invalid remote addresses"
    (let* ((app (funcall *ip-restriction* *ok-app*
                         :allow-list '("127.0.0.1")
                         :on-error (lambda (remote env)
                                     (declare (ignore remote env))
                                     '(418 () ("custom error")))))
           (res (call app "1234:::5678")))
      (ok (= (first res) 403))
      (ok (equal (third res) '("Forbidden")))))
  (testing "link-local zone id is accepted"
    (let ((app (funcall *ip-restriction* *ok-app* :allow-list '("fe80::1"))))
      (ok (= (status-for app "fe80::1%eth0") 200)))))

(deftest rules
  (testing "invalid CIDR rules signal at build time"
    (dolist (rule '("192.168.0.0/33" "::/129" "127.0.0.1/" "::ffff:127.0.0.1/129"))
      (ok (signals (funcall *ip-restriction* *ok-app* :allow-list (list rule))) rule)))
  (testing "star"
    (ok (match-p "192.168.2.0" "*"))
    (ok (match-p "192.168.2.1" "*"))
    (ok (match-p "::0" "*")))
  (testing "CIDR notation"
    (ok (match-p "192.168.2.0" "192.168.2.0/24"))
    (ok (match-p "192.168.2.1" "192.168.2.0/24"))
    (ok (match-p "192.168.2.1" "192.168.2.1/32"))
    (ng (match-p "192.168.2.1" "192.168.2.2/32"))
    (ok (match-p "::0" "::0/1"))
    (ng (match-p "::1" "0.0.0.0/24"))
    (ng (match-p "::abcd:1" "127.0.0.0/8"))
    (ng (match-p "::1" "::ffff:1.0.0.0/96"))
    (ok (match-p "::ffff:192.168.1.1" "::ffff:192.168.1.0/120"))
    (ok (match-p "192.168.1.1" "::ffff:192.168.1.0/120"))
    (ok (match-p "::ffff:192.168.1.1" "192.168.1.0/24"))
    (ng (match-p "::ffff:10.0.0.1" "192.168.1.0/24"))
    (ok (match-p "::ffff:192.168.1.1" "::/0"))
    (ok (match-p "::ffff:192.168.1.1" "::ffff:0:0/95")))
  (testing "static rules"
    (ok (match-p "192.168.2.1" "192.168.2.1"))
    (ok (match-p "1234::5678" "1234::5678"))
    (ok (match-p "::ffff:127.0.0.1" "::ffff:127.0.0.1"))
    (ok (match-p "::ffff:127.0.0.1" "::ffff:7f00:1"))
    (ok (match-p "127.0.0.1" "::ffff:127.0.0.1"))
    (ok (match-p "::ffff:127.0.0.1" "127.0.0.1"))
    (ng (match-p "::ffff:127.0.0.1" "127.0.0.2"))
    (ok (match-p "::ffff:7f00:1" "127.0.0.1"))
    (ok (match-p "0:0:0:0:0:ffff:7f00:1" "127.0.0.1"))
    (ok (match-p "::1" "::1"))
    (ok (match-p "2001:db8:0:0:0:0:0:1" "2001:db8::1"))
    (ok (match-p "2001:db8::1" "2001:db8:0:0:0:0:0:1"))
    (ng (match-p "::ffff:127.0.0.2" "127.0.0.1"))
    (ng (match-p "::7f00:1" "127.0.0.1")))
  (testing "function rules"
    (ok (match-p "0.0.0.0" (constantly t)))
    (ng (match-p "0.0.0.0" (constantly nil)))
    (let (seen)
      (match-p "93.184.216.34" (lambda (remote) (setf seen remote) nil))
      (ok (equal seen '(:addr "93.184.216.34" :type :ipv4))))))
