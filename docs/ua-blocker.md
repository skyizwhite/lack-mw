# ua-blocker middleware

This middleware blocks requests by their User-Agent header, answering `403 Forbidden`. It also comes with lists of known AI bots and a robots.txt that disallows them, sourced from [ai.robots.txt](https://github.com/ai-robots-txt/ai.robots.txt).

Ported from [@hono/ua-blocker](https://github.com/honojs/middleware/tree/main/packages/ua-blocker).

## Usage

Block a custom list of user agents:

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*ua-blocker*))
(in-package #:app/main)

(defparameter *app*
  (lack:builder
   (with-args *ua-blocker* :blocklist '("ForbiddenBot" "Not You"))
   ;; or a regex matching the UPPERCASE User-Agent:
   ;; (with-args *ua-blocker* :blocklist "(FORBIDDENBOT|NOT YOU)")
   (lambda (env)
     (declare (ignore env))
     '(200 (:content-type "text/plain") ("Hello World")))))
```

Block all known AI bots:

```lisp
(lack:builder
 (with-args *ua-blocker* :blocklist +ai-bots+)
 *raw-app*)
```

Block only the bots known not to respect robots.txt, and serve a robots.txt for the others:

```lisp
(lack:builder
 (with-args *ua-blocker* :blocklist +non-respecting-ai-bots+)
 *ai-robots-txt*
 *raw-app*)
```

Extend the robots.txt with your own rules:

```lisp
(lack:builder
 (lambda (app)
   (lambda (env)
     (if (string= (getf env :path-info) "/robots.txt")
         `(200 (:content-type "text/plain; charset=UTF-8")
               (,(format nil "~aUser-agent: GoogleBot~%Allow: /~%" +ai-robots-txt+)))
         (funcall app env))))
 *raw-app*)
```

## API

### `*ua-blocker*`

| Option | Default | Description |
|---|---|---|
| `:blocklist` | `nil` | A list of user agents, matched case-insensitively anywhere in the User-Agent. Or a regex string or cl-ppcre scanner, run on the upcased User-Agent. |

A request without a User-Agent header is let through.

### `*ai-robots-txt*`

Serves `+ai-robots-txt+` as `text/plain`.

| Option | Default | Description |
|---|---|---|
| `:path` | `"/robots.txt"` | The path to serve it at. |

### Data (`lack-mw/ua-blocker/ai-bots`)

- `+ai-bots+`: the user agents of known AI bots.
- `+non-respecting-ai-bots+`: the part of `+ai-bots+` not known to respect robots.txt.
- `+ai-robots-txt+`: robots.txt content disallowing every bot in `+ai-bots+`.

## Note

- Hono exports the AI bot lists as regexes. Here they are lists of strings, matched literally, so a `.` in a name such as `bigsur.ai` is not a wildcard.
- Hono's `useAiRobotsTxt()` is a handler mounted on a path. Here `*ai-robots-txt*` is a middleware that answers on `:path` and passes every other request through.
- `src/ua-blocker/ai-bots.lisp` is generated from ai.robots.txt's `robots.json`. To update it:

  ```sh
  qlot exec ros scripts/generate-ai-bots.ros             # downloads the latest robots.json with curl
  qlot exec ros scripts/generate-ai-bots.ros robots.json # or reads a local copy
  ```
