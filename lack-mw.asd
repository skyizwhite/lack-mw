(defsystem "lack-mw"
  :description "Middleware collection for Lack"
  :author "Akira Tempaku"
  :maintainer "Akira Tempaku <paku@skyizwhite.dev>"
  :license "MIT"
  :class :package-inferred-system
  :pathname "src"
  :depends-on ("lack-mw/main")
  :in-order-to ((test-op (test-op "lack-mw-test"))))
