<div align="center">

# moonapi

**A typed web framework for MoonBit — `← FastAPI`.**

[![Check and Test](https://github.com/Lfan-ke/moonapi/actions/workflows/ci.yml/badge.svg)](https://github.com/Lfan-ke/moonapi/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)
[![mooncakes](https://img.shields.io/badge/mooncakes-Lfan--ke%2Fmoonapi-brightgreen)](https://mooncakes.io/docs/Lfan-ke/moonapi)

</div>

`moonapi` builds an [`AsgiApp`](https://github.com/Lfan-ke/moonasgi) from typed routes and generates its own **OpenAPI / Swagger** document — the role FastAPI plays for Python. It depends only on `moonasgi`, so it's backend-agnostic (routing and OpenAPI run in-process on every backend); a server such as [`mooncat`](https://github.com/Lfan-ke/mooncat) runs the resulting app.

```mermaid
flowchart LR
  routes["typed routes<br/>App::get / post / …"] --> app["**moonapi** App"]
  app -->|"App::to_asgi()"| asgi(["moonasgi AsgiApp"])
  app -->|"App::openapi()"| spec["OpenAPI 2.0 / 3.0 / 3.1"]
  asgi --> cat["mooncat serves it"]
```

## Quickstart

```moonbit
let app = @moonapi.App::new()
app.get("/", _ctx => @moonapi.text(200, "Hello from moonapi!"))
app.get("/users/:id", ctx => @moonapi.text(200, "user " + ctx.param("id").unwrap()),
        summary="fetch a user")
app.post("/users", _ctx => @moonapi.text(201, "created"))

// One set of routes → every mainstream spec version:
let v31 = app.openapi_json(version=OpenApi31)   // OpenAPI 3.1.0
let v30 = app.openapi_json(version=OpenApi30)   // OpenAPI 3.0.3
let v20 = app.openapi_json(version=Swagger20)   // Swagger 2.0
let docs_page = @moonapi.swagger_ui()           // a Swagger UI page

// Serve it (native, via mooncat):
@mooncat.serve(app.to_asgi(), port=8000)
```

## What's here (`v0`)

- **Routing** — `App::get/post/put/patch/delete/route`, `:param` path segments extracted into `Context::param`, correct `404` (no path) vs `405` (path but not method).
- **Descriptor tree** — a runtime `Schema` / `Param` / `Endpoint` tree (a one-first-class-value substitute for FastAPI's from-signature reflection) that a typed route carries. Walked **once** to (a) emit **complete** OpenAPI request/response body schemas — objects, arrays, scalars, `required`, with named models hoisted under `components/schemas` and referenced by `$ref` — and (b) drive request validation off the same tree. User structs describe themselves with `derive(ToJson)` + a `T::schema()` associated function + a one-line `ToSchema` bridge (the mctl-friendly shape).
- **Multi-version OpenAPI** — `App::openapi` / `openapi_json` emit **Swagger 2.0, OpenAPI 3.0.3, and OpenAPI 3.1.0** from the same routes and descriptors (3.x `requestBody` + `components/schemas`; 2.0 body-parameter + `definitions`), because a good FastAPI is not pinned to one spec version.
- **Typed body extractors** — `Context::body[T]` deserialises the JSON body into a `derive(FromJson)` struct; `Context::body_validated[T]` first checks it against the endpoint descriptor and returns either the built value or a FastAPI-shaped `422` error list — schema emission, validation, and deserialisation all off one descriptor.
- **Dependency injection** — a `Container` (provider registry + `dependency_overrides`) with request-scoped, one-shot resolution (per-request caching) and `yield`-style teardown run LIFO around the handler — the explicit MoonBit equivalent of FastAPI's `Depends`.
- **OAuth2 + JWT security** — a `/token` password-grant endpoint issues an HS256 JWT (`create_access_token`), and an `OAuth2PasswordBearer` reads the `Authorization: Bearer` header, verifies the token, and enforces scopes: `401` on a missing or invalid/expired token, `403` when a valid token lacks a required scope. The SHA-256 / HMAC-SHA256 pair is self-built (`crypto.mbt`), checked against the NIST and RFC 4231 vectors; the `alg: "none"` downgrade is refused and signatures compare in constant time.
- **Form & file extractors** — `Context::form` parses both an `application/x-www-form-urlencoded` body (percent- and `+`-decoded) and a `multipart/form-data` body, splitting the boundary stream into `FormField`s and byte-exact `UploadFile`s (filename + content-type + raw bytes). `Context::oauth2_password_form` reads the OAuth2 password form off it.
- **response_model** — `filter_response` / `json_model` validate a handler's return value against a declared `Schema` and project it down to exactly the model's fields, so a route can hold a richer object internally than it exposes (an id, a password hash) and still emit only what it promised.
- **Swagger UI** — `swagger_ui()` returns a ready-to-serve documentation page.
- **Responses** — `text` and `json` helpers over `moonasgi.Response`.

Verified across all backends (`wasm`, `wasm-gc`, `js`, `native`) in CI, 0 warnings under `--deny-warn`.

## Roadmap (transliterating FastAPI)

The descriptor tree (`Endpoint` / `Param` / `Schema`) is in place — walked once for full OpenAPI 3.1 body schemas and validation — with the typed `derive(FromJson)` body extractors (`Context::body` / `body_validated`) and the dependency-injection container on top. This release adds the security and form layers: OAuth2 password-bearer with self-built HS256 JWT and scopes, the `Form` / `File` extractors over a self-built urlencoded + multipart parser, and `response_model` filtering. Next: RS256 / ES256 signing; exception handlers; CORS / GZip middleware; background tasks; streaming / SSE; WS routes; sub-app mounting; and codegen'd request schemas via `moonctl`. Security scheme objects in the emitted OpenAPI document are still to come.

## License

Apache-2.0.
