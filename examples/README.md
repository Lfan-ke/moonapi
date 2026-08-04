# Examples

A runnable tour of the public `@moonapi` API. Each folder is a `main` package
that builds an `App` from typed routes and uses it.

```bash
moon run examples/01-openapi
```

| # | Example | What it shows | Key API |
| --- | --- | --- | --- |
| 01 | [`openapi`](01-openapi/) | Register a text `GET`, a `:param` `GET`, and a `POST`; handle a request; emit the OpenAPI 3.1 document | `App::new`, `App::get`, `App::post`, `text`, `App::handle`, `App::openapi_json` |

The document `openapi_json(version=OpenApi31)` prints is the same one a server
([`mooncat`](https://github.com/Lfan-ke/mooncat)) serves at `/openapi.json`
after `App::to_asgi`; swap `OpenApi31` for `OpenApi30` or `Swagger20` to emit the
other spec versions off the identical routes.
