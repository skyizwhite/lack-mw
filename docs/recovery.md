# recovery middleware

This middleware is the last line of defense: it catches any error left unhandled by the middlewares and the app further in, logs it, and answers `500 Internal Server Error` as HTML, JSON or plain text.

## Usage

Place it outermost, before the other middlewares, so it catches errors from all of them:

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*recovery*))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
   (with-args *recovery* :format :json)
   ;; other middlewares...
   (lambda (env)
     (declare (ignore env))
     (error "Something went wrong"))))
```

To have the 500 responses logged by an access log, put the access log outside it:

```lisp
(lack:builder
 *accesslog*
 *recovery*
 *raw-app*)
```

Show the error details while developing:

```lisp
(lack:builder
 (with-args *recovery* :dev-mode (equal (uiop:getenv "DEV") "1"))
 *raw-app*)
```

Answer with your own response:

```lisp
(lack:builder
 (with-args *recovery*
   :on-error (lambda (condition env)
               (declare (ignore condition env))
               '(503 (:content-type "text/plain") ("Try again later"))))
 *raw-app*)
```

## API

### `*recovery*`

| Option | Default | Description |
|---|---|---|
| `:format` | `:html` | `:html`, `:json` or `:text`. The body is a minimal page saying "Internal Server Error", `{"error":{"message":"Internal Server Error"}}` or `Internal Server Error`, with a `charset=utf-8` Content-Type. |
| `:dev-mode` | `nil` | When true, the body also shows the condition's type, its message and the backtrace: escaped inside `<pre>` in HTML, as the `"type"`, `"detail"` and `"backtrace"` fields in JSON, as plain lines in text. |
| `:logger` | writes to `*error-output*` | A function of `(condition backtrace env)` called for each caught error, `backtrace` being a string. The default writes the method, the request URI and the condition, then the backtrace. `nil` disables logging. |
| `:on-error` | `nil` | A function of `(condition env)` returning a whole Lack response, used instead of the built-in one. The error is still logged. |

## Note

- Unlike clack-errors' `*clack-error-middleware*`, which only answers HTML, this middleware can answer JSON or plain text, takes a logger and a custom response, and never shows error details unless `:dev-mode` is on.
- Only unhandled conditions of type `error` are caught; a `handler-case` further in still wins, and warnings pass through. The backtrace is captured with `handler-bind` at the point of the error, before unwinding.
- As with clack-errors, a condition of type `error` that is merely `signal`ed, which `signal` would otherwise let return, is caught as well and answered with a 500.
- Delayed responses (`(lambda (responder) ...)`): an error signalled before the responder is called is answered with a 500 through the responder. Once the responder has been called the response has started and can't be replaced, so the error is logged and re-signalled for the server to handle (usually by closing the connection). Errors signalled after the delayed response function returns, e.g. by a streaming writer called later, are not caught.
- A failing logger is ignored, and a failing `:on-error` or renderer falls back to a static `text/plain` 500. A responder that fails while sending the 500 of a delayed response, e.g. on a closed connection, is logged and nothing more is sent.
- `:dev-mode` exposes internals (messages, source paths, the backtrace) to clients. Never enable it in production.
