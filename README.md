# lack-mw

Middleware collection for [Lack](https://github.com/fukamachi/lack).

These middlewares were ported from [Hono](https://github.com/honojs/hono).

## Middlewares

- **trailing-slash**  
  Handles trailing slashes in URLs for GET requests.  
  If the requested resource isn’t found, it redirects to the correct URL accordingly.
  - `*append-trailing-slash*`  
    Redirects to the URL **with** a trailing slash.
  - `*trim-trailing-slash*`  
    Redirects to the URL **without** a trailing slash.
- Coming soon...

## License

Licensed under the MIT License.

© 2024 skyizwhite

© 2021 - present, Yusuke Wada and Hono contributors