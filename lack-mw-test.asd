(defsystem "lack-mw-test"
  :class :package-inferred-system
  :pathname "tests"
  :depends-on ("rove"
               "lack-mw-test/trailing-slash"
               "lack-mw-test/composer")
  :perform (test-op (o c) (symbol-call :rove :run c :style :dot)))
