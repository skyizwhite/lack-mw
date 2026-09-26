# timing middleware

This middleware adds a [Server-Timing](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Server-Timing) header to the response. Handlers can record their own metrics and timers through the env.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*timing*
                #:set-metric
                #:start-time
                #:end-time
                #:with-timing))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *timing* :cross-origin t)
    (lambda (env)
      ;; value-less metric
      (set-metric env "region" "europe-west3")
      ;; metric with a duration in milliseconds
      (set-metric env "custom" 23.8 "My custom Metric")
      ;; timer
      (start-time env "db")
      (sleep 0.01)
      (end-time env "db")
      ;; timing a body of code (the timer ends even on a non-local exit)
      (with-timing (env "render" :description "Render")
        (sleep 0.01))
      '(200 (:content-type "text/plain") ("Hello")))))
;; Server-Timing: region;desc="europe-west3",custom;dur=23.8;desc="My custom Metric",db;dur=10.1,render;dur=10.1;desc="Render",total;dur=20.4;desc="Total Response Time"
```

## Options

| Option               | Default                 | Description |
|----------------------|-------------------------|-------------|
| `:total`             | `t`                     | Adds a `total` metric for the whole response time. |
| `:enabled`           | `t`                     | Whether the headers are added. Can also be a function `(env) -> boolean`, called after the app runs. |
| `:total-description` | `"Total Response Time"` | The description of the `total` metric. |
| `:auto-end`          | `t`                     | Ends any timers still running when the request finishes. |
| `:cross-origin`      | `nil`                   | Sets `Timing-Allow-Origin`. `t` sends `*`, a string sends that origin, and a function `(env) -> boolean-or-string` decides per request. |

## API

All functions take the request env.

- `(set-metric env name &optional value-or-description description precision)`: if the second argument is a number, it is a duration in ms (`name;dur=V;desc="D"`). If it is a string, it is a description (`name;desc="D"`). `precision` is the number of decimals (default 1).
- `(start-time env name &optional description)`
- `(end-time env name &optional precision)`
- `(wrap-time env name fn &optional description precision)`: calls `fn` and times it.
- `(with-timing (env name &key description precision) &body body)`: the macro form of `wrap-time`.

The metric state is stored in the env under `:lack-mw.metric`.

## Note

- Ported from Hono's `timing`. If an outer `*timing*` is already collecting metrics, an inner one only passes the request through.
- If the response already has a `Server-Timing` or `Timing-Allow-Origin` header, the new value is joined to it with `", "`, like `Headers#append`.
- Hono's `console.warn` becomes `cl:warn`. You get a warning when the timing middleware is missing, or when you end a timer that does not exist.
- `wrapTime` takes a Promise in Hono. Here it takes a function (`wrap-time`) or a body (`with-timing`).
- Times come from `get-internal-real-time`. Hono uses `performance.now()`, with `Date.now()` as its fallback.
