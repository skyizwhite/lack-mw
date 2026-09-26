(defsystem "lack-mw"
  :version "0.1.0"
  :description "Middleware collection for Lack"
  :author "Akira Tempaku"
  :maintainer "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :class :package-inferred-system
  :pathname "src"
  :depends-on ("lack-mw/main")
  :in-order-to ((test-op (test-op "lack-mw-test"))))

;; packages lack defines without a system of the same name
(register-system-packages "lack-middleware-session"
                          '(#:lack/middleware/session/state/cookie
                            #:lack/middleware/session/store/memory))
(register-system-packages "lack-middleware-when" '(#:lack/middleware/when))
