# oauth-providers middleware

Social login with OAuth 2.0. A provider's middleware redirects a request without a `code` to the provider's sign-in page, with a `state` kept in a cookie. Back with a `code`, it checks the state, fetches the token and the user, puts them in env and calls the app.

Ported from [@hono/oauth-providers](https://github.com/honojs/middleware/tree/main/packages/oauth-providers). Providers: GitHub and Google.

These middlewares need an HTTP client (dexador, and so OpenSSL through cl+ssl), so they are not re-exported from `lack-mw`. Import them from their own packages.

## Usage

```lisp
(defpackage #:app/main
  (:use #:cl)
  (:import-from #:lack)
  (:import-from #:lack-mw
                #:with-args
                #:*mount*)
  (:import-from #:lack-mw/oauth-providers
                #:oauth-token
                #:oauth-granted-scopes)
  (:import-from #:lack-mw/oauth-providers/github
                #:*github-auth*
                #:github-user)
  (:import-from #:lack-mw/oauth-providers/google
                #:*google-auth*
                #:google-user))
(in-package #:app/main)

(defun signed-in (user-fn)
  (lambda (env)
    (let ((user (funcall user-fn env)))
      ;; keep what you need in your session here
      `(200 (:content-type "text/plain")
            (,(format nil "Hello, ~a (~{~a~^ ~})"
                      (gethash "name" user) (oauth-granted-scopes env)))))))

(defparameter *app*
  (lack:builder
   (with-args *mount* "/auth/github"
     (lack:builder
      (with-args *github-auth*
        :client-id "..." :client-secret "..."
        :scope '("read:user" "user:email")
        :oauth-app t)
      (signed-in #'github-user)))
   (with-args *mount* "/auth/google"
     (lack:builder
      (with-args *google-auth*
        :client-id "..." :client-secret "..."
        :scope '("openid" "email" "profile"))
      (signed-in #'google-user)))
   *raw-app*))
```

## Values in env

From `lack-mw/oauth-providers`:

| Accessor | Value |
|---|---|
| `(oauth-token env)` | `(:token "..." :expires-in seconds)` |
| `(oauth-refresh-token env)` | `(:token "..." :expires-in seconds)`, or `nil` when the provider gave none |
| `(oauth-granted-scopes env)` | list of strings |

The user, a hash table of the provider's JSON (parsed by [jzon](https://github.com/Zulu-Inuoe/jzon)):

| Accessor | Provider |
|---|---|
| `(github-user env)` | GitHub's `/user`, with `"email"` set to the primary address from `/user/emails` |
| `(google-user env)` | Google's `/oauth2/v2/userinfo` |

## GitHub (`lack-mw/oauth-providers/github`)

### `*github-auth*`

| Option | Default | Description |
|---|---|---|
| `:client-id` | `$GITHUB_ID` | Client ID. |
| `:client-secret` | `$GITHUB_SECRET` | Client secret. |
| `:scope` | `nil` | List of scopes. Sent for an OAuth app only: a GitHub App sets its scopes in its settings. |
| `:oauth-app` | `nil` | True for an OAuth app, false for a GitHub App. |
| `:redirect-uri` | the request URL | For a GitHub App, where GitHub comes back to. An OAuth app always comes back to its one callback URL. |

## Google (`lack-mw/oauth-providers/google`)

### `*google-auth*`

| Option | Default | Description |
|---|---|---|
| `:scope` | (required) | List of scopes, such as `'("openid" "email" "profile")`. |
| `:client-id` | `$GOOGLE_ID` | Client ID. |
| `:client-secret` | `$GOOGLE_SECRET` | Client secret. |
| `:redirect-uri` | the request URL without its query | Where Google comes back to. |
| `:state` | a random one | A fixed state. |
| `:login-hint` | `nil` | An email address or `sub` to preselect the account. |
| `:prompt` | `nil` | `:none`, `:consent` or `:select-account`. |
| `:access-type` | `nil` | `:online` or `:offline`. `:offline` gets a refresh token. |

### `(google-revoke-token token)`

Revokes an access or refresh token. True when Google accepted it.

## Errors

- A `code` whose `state` query parameter is missing or differs from the cookie is answered with `401 Unauthorized`, without asking the provider.
- When the provider refuses the code or the token, the answer is `400` with the provider's message.

## Testing your app

`lack-mw/oauth-providers:*http-client*` is the function the providers call HTTP with: `(method url &key headers content)`, returning the body as a string and the status. Rebind it to stub the providers.

## Note

- Behind a reverse proxy the request URL may not be the public one (`http` for `https`, an internal host). Pass `:redirect-uri` then.
- The state cookie is named `state`, lasts 10 minutes and is `HttpOnly`, `Secure` and `SameSite=Lax`, as in Hono.
- Differences from Hono:
  - Google's token request is form-encoded with `client_id` and `client_secret`, as Google documents it. Hono sends JSON with `clientId` and `clientSecret`.
  - GitHub's `redirect_uri` is URL-encoded. Hono appends it to the URL as it is.
  - Hono's Google middleware also reads `access_token` and `expires-in` from the query, but always replaces them with the token it fetches. They are not read here.
  - Errors are answered directly rather than thrown as `HTTPException`.
- Other providers of @hono/oauth-providers (Discord, Facebook, LinkedIn, Microsoft Entra, OpenStreetMap, Twitch, X) are not ported yet. A provider is a package under `lack-mw/oauth-providers/` that calls `oauth-middleware` with its authorize URL and its fetch function.
