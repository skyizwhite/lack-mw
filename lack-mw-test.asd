(defsystem "lack-mw-test"
  :class :package-inferred-system
  :pathname "tests"
  :depends-on ("rove")
  :perform (test-op (o c) (symbol-call :rove :run c :style :dot)))
