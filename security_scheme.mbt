// OpenAPI security scheme objects (← FastAPI surfacing `OAuth2PasswordBearer`,
// `HTTPBearer`, `APIKeyHeader`, etc. under `components/securitySchemes`). A
// `SecurityScheme` is declared on the `App` and emitted into the generated spec
// so the OAuth2 / JWT layer from the security module is described to clients.
// Both spec shapes are produced: OpenAPI 3.x `securitySchemes`, and the Swagger
// 2.0 `securityDefinitions` shape (a flat OAuth2 flow, no `http` type).

///|
/// A security scheme describing how a client authenticates. Mirrors the OpenAPI
/// scheme types: an OAuth2 password flow (its token URL and named scopes), an
/// HTTP bearer scheme (with a `bearerFormat` such as `JWT`), an API key in a
/// header / query / cookie, and HTTP Basic.
pub(all) enum SecurityScheme {
  OAuth2Password(token_url~ : String, scopes~ : Array[(String, String)])
  HttpBearer(bearer_format~ : String)
  ApiKeyHeader(name~ : String)
  ApiKeyQuery(name~ : String)
  ApiKeyCookie(name~ : String)
  HttpBasic
}

///|
/// Build the security scheme that describes this password-bearer flow (← the
/// object FastAPI derives from `OAuth2PasswordBearer`). `scopes` are the
/// `(name, description)` pairs advertised in the OpenAPI document.
pub fn OAuth2PasswordBearer::scheme(
  self : OAuth2PasswordBearer,
  scopes? : Array[(String, String)] = [],
) -> SecurityScheme {
  OAuth2Password(token_url=self.token_url, scopes~)
}

///|
/// A `{name: description, ...}` JSON object from scope pairs.
fn scopes_object(scopes : Array[(String, String)]) -> Json {
  let m : Map[String, Json] = Map([])
  for pair in scopes {
    m[pair.0] = pair.1.to_json()
  }
  m.to_json()
}

///|
/// This scheme as an OpenAPI 3.0 / 3.1 security scheme object.
fn SecurityScheme::to_openapi_3x(self : SecurityScheme) -> Json {
  match self {
    OAuth2Password(token_url~, scopes~) => {
      let flow : Map[String, Json] = Map([
        ("tokenUrl", token_url.to_json()),
        ("scopes", scopes_object(scopes)),
      ])
      let flows : Map[String, Json] = Map([("password", flow.to_json())])
      let m : Map[String, Json] = Map([
        ("type", "oauth2".to_json()),
        ("flows", flows.to_json()),
      ])
      m.to_json()
    }
    HttpBearer(bearer_format~) => {
      let m : Map[String, Json] = Map([
        ("type", "http".to_json()),
        ("scheme", "bearer".to_json()),
        ("bearerFormat", bearer_format.to_json()),
      ])
      m.to_json()
    }
    ApiKeyHeader(name~) => api_key_json("header", name)
    ApiKeyQuery(name~) => api_key_json("query", name)
    ApiKeyCookie(name~) => api_key_json("cookie", name)
    HttpBasic => {
      let m : Map[String, Json] = Map([
        ("type", "http".to_json()),
        ("scheme", "basic".to_json()),
      ])
      m.to_json()
    }
  }
}

///|
/// An `apiKey` scheme object for `in`/`name`.
fn api_key_json(in_ : String, name : String) -> Json {
  let m : Map[String, Json] = Map([
    ("type", "apiKey".to_json()),
    ("in", in_.to_json()),
    ("name", name.to_json()),
  ])
  m.to_json()
}

///|
/// This scheme as a Swagger 2.0 security definition. Swagger 2.0 has no `http`
/// type: an HTTP bearer is expressed as an `apiKey` in the `Authorization`
/// header (the standard 2.0 workaround), Basic uses the `basic` type, and the
/// OAuth2 flow is the flat 2.0 form (`flow` + `tokenUrl` at top level). Swagger
/// 2.0 `apiKey` only allows `header`/`query`, so a cookie key maps to a header.
fn SecurityScheme::to_openapi_20(self : SecurityScheme) -> Json {
  match self {
    OAuth2Password(token_url~, scopes~) => {
      let m : Map[String, Json] = Map([
        ("type", "oauth2".to_json()),
        ("flow", "password".to_json()),
        ("tokenUrl", token_url.to_json()),
        ("scopes", scopes_object(scopes)),
      ])
      m.to_json()
    }
    HttpBearer(_) => api_key_json("header", "Authorization")
    ApiKeyHeader(name~) => api_key_json("header", name)
    ApiKeyQuery(name~) => api_key_json("query", name)
    ApiKeyCookie(name~) => api_key_json("header", name)
    HttpBasic => {
      let m : Map[String, Json] = Map([("type", "basic".to_json())])
      m.to_json()
    }
  }
}

///|
/// The `{name: scheme, ...}` object for the app's declared schemes, rendered in
/// the shape `version` uses.
fn security_schemes_json(
  schemes : Array[(String, SecurityScheme)],
  version : OpenApiVersion,
) -> Json {
  let m : Map[String, Json] = Map([])
  for pair in schemes {
    m[pair.0] = match version {
      Swagger20 => pair.1.to_openapi_20()
      _ => pair.1.to_openapi_3x()
    }
  }
  m.to_json()
}
