# combine middleware

`mw-some`, `mw-every` and `mw-except` combine several middlewares into one, e.g. to build access control rules.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:mw-some
                #:mw-every
                #:mw-except
                #:mw-condition
                #:*mw-ip-restriction*))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    ;; Public pages need nothing. Everything else: clients in the local network
    ;; pass directly, others must pass authentication and rate limiting.
    (mw-except '("/" "/public/*")
      (mw-some
        (with-args *mw-ip-restriction* :allow-list '("192.168.0.0/16"))
        (mw-every *my-auth* *my-rate-limit*)))
    *raw-app*))
```

## API

| Function | Description |
| --- | --- |
| `(mw-some &rest middlewares)` | Tries each middleware in order and uses the first one that **passes**. |
| `(mw-every &rest middlewares)` | Applies all middlewares in order (plain composition, first one outermost). |
| `(mw-except condition &rest middlewares)` | Applies the middlewares (composed like `mw-every`) unless `condition` matches, in which case the app is called directly. |
| `(mw-condition predicate)` | Turns a predicate on `env` into a middleware usable in `mw-some` / `mw-every`: calls the app when true, signals `unmet-condition` when false. |

All of them are functions returning a middleware (not `defparameter`s), so use them directly in `lack:builder`.

### `mw-some` semantics

A middleware **passes** when it calls the wrapped app (Hono: calls `next`). It **fails** when it returns a response without calling the app (e.g. an auth middleware answering `401`) or signals an error before calling the app; the next middleware is then tried. The last middleware's outcome is final: if every middleware fails, its response is returned or its error is signaled. Errors signaled after the app was called (i.e. by the app or by later middlewares) propagate and never cause other middlewares to be tried.

### `mw-except` conditions

`condition` is a path pattern string, a predicate on `env`, or a list of them (any match skips the middlewares). Path patterns are matched against `:path-info` and follow Hono's router syntax:

| Pattern | Matches |
| --- | --- |
| `"/maintenance"` | exactly `/maintenance` |
| `"/api/public/*"` | `/api/public` and everything below it |
| `"*"` | every path |
| `"/files/*.png"` | `*` anywhere else matches any characters |
| `"/users/:id"` | one path segment |
| `"/posts/:id{[0-9]+}"` | one segment matching the regex |
| `"/animal/:type?"` | `/animal` and `/animal/dog` |

## Notes

- Names are prefixed with `mw-` because `some` and `every` are standard CL functions: exporting shadowing symbols would break any package that `:use`s both `cl` and `lack-mw`. `mw-condition` is prefixed for the same reason (`condition` is a CL type) and for consistency.
- Hono tells conditions apart from middlewares by their boolean return value. In Lack both are functions of one argument, so conditions must be wrapped in `mw-condition` for `mw-some` / `mw-every`. `mw-except` takes predicates directly.
- In Hono, a middleware that returns a response without calling `next` counts as passing in `some`; here it counts as failing, because Lack middlewares reject requests by returning a response instead of throwing. Conversely, a middleware that returns a delayed response `(lambda (responder) ...)` passes only if it has called the app by the time it returns.
- Hono throws `Error('Unmet condition')` in `every` for a false condition; here `mw-condition` signals `unmet-condition`, which ends up as a server error unless handled.
- Lack has the builtin `lack/middleware/when` (`(:when test middleware)` in `lack:builder`), which applies one middleware when a predicate on `env` is true. `mw-except` is its inverse with path-pattern support and multiple middlewares.
- Path patterns only support the syntax above; a `{regex}` must not contain `/`.
