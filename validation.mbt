///|
/// Decode a `Bytes` request field to text, replacing any malformed UTF-8 rather
/// than raising — inbound bytes are attacker-controlled, so extraction stays
/// total.
fn decode_field(raw : Bytes) -> String {
  @utf8.decode_lossy(raw[:])
}

///|
/// Look up a query-string parameter by name, e.g. `?limit=10&q=cat`. The query
/// string is split on `&` into `key=value` pairs (first `=` wins; a bare key
/// yields `""`). Percent-decoding is intentionally out of scope for v0.2.
pub fn Context::query(self : Context, name : String) -> String? {
  let s = decode_field(self.request.query_string)
  let n = s.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || s[i] == '&' {
      if i > start {
        let pair = s[start:i].to_owned()
        let m = pair.length()
        let mut eq = -1
        for j = 0; j < m; j = j + 1 {
          if pair[j] == '=' {
            eq = j
            break
          }
        }
        let (k, v) = if eq < 0 {
          (pair, "")
        } else {
          (pair[0:eq].to_owned(), pair[eq + 1:m].to_owned())
        }
        if k == name {
          return Some(v)
        }
      }
      start = i + 1
    }
  }
  None
}

///|
/// Parse the request body as JSON, returning `None` for an empty body or one
/// that does not parse — the total counterpart of FastAPI reading a JSON body.
pub fn Context::body_json(self : Context) -> Json? {
  let s = decode_field(self.request.body)
  if s == "" {
    return None
  }
  Some(@json.parse(s)) catch {
    _ => None
  }
}

///|
/// Pull a single field out of a JSON object body by name, `None` if the body is
/// absent, not an object, or lacks the field.
pub fn Context::json_field(self : Context, name : String) -> Json? {
  match self.body_json() {
    Some(Object(m)) => m.get(name)
    _ => None
  }
}

///|
/// One entry in a `422` response's `detail` array, mirroring FastAPI /
/// pydantic v2: where the error is (`loc`, e.g. `["query", "q"]`), a human
/// `msg`, and a machine `kind` (serialised as the JSON key `type`).
pub(all) struct ValidationError {
  loc : Array[String]
  msg : String
  kind : String
}

///|
/// The canonical "a required parameter was not supplied" error located at
/// `loc`, matching FastAPI's `{"type": "missing", "msg": "Field required"}`.
pub fn ValidationError::missing(loc : Array[String]) -> ValidationError {
  { loc, msg: "Field required", kind: "missing" }
}

///|
/// Render one validation error as its JSON object.
fn ValidationError::to_json(self : ValidationError) -> Json {
  let m : Map[String, Json] = Map([
    ("type", self.kind.to_json()),
    ("loc", self.loc.to_json()),
    ("msg", self.msg.to_json()),
  ])
  m.to_json()
}

///|
/// The `{"detail": [ ... ]}` body FastAPI returns when request validation
/// fails, built from a list of `ValidationError`s.
pub fn validation_error_body(errors : Array[ValidationError]) -> Json {
  let detail : Array[Json] = []
  for e in errors {
    detail.push(e.to_json())
  }
  let doc : Map[String, Json] = Map([("detail", detail.to_json())])
  doc.to_json()
}

///|
/// A `422 Unprocessable Entity` response whose `application/json` body lists the
/// validation `errors`, exactly as FastAPI reports a failed request.
pub fn unprocessable(errors : Array[ValidationError]) -> @moonasgi.Response {
  json(422, validation_error_body(errors))
}
