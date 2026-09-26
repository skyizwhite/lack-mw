# ip-restriction middleware

This middleware limits access to resources based on the client's IP address, using a deny list and/or an allow list.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*ip-restriction*))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
    (with-args *ip-restriction*
      ;; Block a specific IP and an entire subnet
      :deny-list '("192.168.0.5" "10.0.0.0/8")
      ;; Only allow requests from localhost and a private range
      :allow-list '("127.0.0.1" "::1" "192.168.1.0/24"))
    (lambda (env)
      (declare (ignore env))
      '(200 (:content-type "text/plain") ("Hello!")))))
```

Behind a reverse proxy, get the address from a header instead:

```lisp
(with-args *ip-restriction*
  :allow-list '("203.0.113.0/24")
  :get-ip (lambda (env) (gethash "x-real-ip" (getf env :headers)))
  :on-error (lambda (remote env)
              (declare (ignore env))
              `(403 (:content-type "text/plain")
                    (,(format nil "Access denied for ~a" (getf remote :addr))))))
```

## Rules

Each rule in `:deny-list` / `:allow-list` is one of:

| Rule | Example |
| --- | --- |
| Static IPv4 | `"192.168.2.0"` |
| Static IPv6 | `"::1"`, `"2001:db8::1"` |
| IPv4 CIDR | `"192.168.2.0/24"` |
| IPv6 CIDR | `"2001:db8::/32"`, `"::ffff:192.168.1.0/120"` |
| Everything | `"*"` |
| Function | `(lambda (remote) ...)` — `remote` is `(:addr "1.2.3.4" :type :ipv4)`; return true to match |

IPv4-mapped IPv6 addresses (`::ffff:127.0.0.1`, `::ffff:7f00:1`) are matched against IPv4 rules and vice versa. An invalid rule signals an error when the middleware is built.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `:deny-list` | `nil` | Rules for rejected addresses. Checked first. |
| `:allow-list` | `nil` | Rules for allowed addresses. When non-empty, any address not matching it is rejected. |
| `:get-ip` | `(getf env :remote-addr)` | Function of `env` returning the client address string. |
| `:on-error` | `nil` | Function of `(remote env)` returning the response for a rejected request. Defaults to `403` with body `Forbidden`. |

## Notes

- Hono takes `getIP` as a required argument (usually `getConnInfo`); here it is the `:get-ip` option defaulting to Lack's `:remote-addr`. It returns a plain string; the address type is always inferred from it.
- A missing/empty address or an address that cannot be parsed (e.g. `999.999.999.999`, `1234:::5678`, a zone id on a non link-local address) is always rejected with `403 Forbidden`, without calling `:on-error` (same as Hono).
- Hono throws an `HTTPException`; here the `403` response is returned directly.
