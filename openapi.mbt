///|
/// Target OpenAPI / Swagger document version. moonapi emits every mainstream
/// version from the same route descriptors — a "good FastAPI" is not pinned to
/// one spec version.
pub(all) enum OpenApiVersion {
  Swagger20
  OpenApi30
  OpenApi31
} derive(Eq)

///|
/// (root document key, version string) for each spec version.
fn version_field(v : OpenApiVersion) -> (String, String) {
  match v {
    Swagger20 => ("swagger", "2.0")
    OpenApi30 => ("openapi", "3.0.3")
    OpenApi31 => ("openapi", "3.1.0")
  }
}

///|
/// A `:name` path parameter as an OpenAPI parameter object for `version`. In
/// Swagger 2.0 the type sits inline; in OpenAPI 3.x it lives under `schema`,
/// which is the one structural difference between the two shapes.
fn path_parameter(name : String, version : OpenApiVersion) -> Json {
  let param : Map[String, Json] = Map([
    ("name", name.to_json()),
    ("in", "path".to_json()),
    ("required", true.to_json()),
  ])
  match version {
    Swagger20 => param["type"] = "string".to_json()
    _ => {
      let schema : Map[String, Json] = Map([("type", "string".to_json())])
      param["schema"] = schema.to_json()
    }
  }
  param.to_json()
}

///|
/// The `:name` parameters of a route path, in order, as OpenAPI parameter
/// objects — the faithful equivalent of FastAPI reading them off the signature.
fn path_parameters(path : String, version : OpenApiVersion) -> Array[Json] {
  let out : Array[Json] = []
  for seg in segments(path) {
    if seg.length() > 0 && seg[0] == ':' {
      out.push(path_parameter(seg[1:].to_owned(), version))
    }
  }
  out
}

///|
/// Build the OpenAPI / Swagger document for the app as a `Json` value, walking
/// the registered routes once into paths → methods → operations.
pub fn App::openapi(
  self : App,
  version? : OpenApiVersion = OpenApi31,
  title? : String = "moonapi",
  api_version? : String = "0.1.0",
) -> Json {
  let paths : Map[String, Json] = Map([])
  let defs : Map[String, Json] = Map([])
  // Own routes plus every mounted sub-app's routes, each under its prefix.
  let all_routes : Array[(String, Route)] = []
  self.collect_routes("", all_routes)
  for entry in all_routes {
    let (full_path, route) = entry
    let op : Map[String, Json] = Map([])
    if route.summary != "" {
      op["summary"] = route.summary.to_json()
    }
    match route.endpoint {
      // A typed route: walk its descriptor once for parameters, request body,
      // responses, and any hoisted component schemas.
      Some(ep) => emit_endpoint(op, ep, defs, version)
      // An untyped route: the `:name` path params and a default 200 response.
      None => {
        let params = path_parameters(full_path, version)
        if params.length() > 0 {
          op["parameters"] = params.to_json()
        }
        let ok : Map[String, Json] = Map([("description", "OK".to_json())])
        let responses : Map[String, Json] = Map([("200", ok.to_json())])
        op["responses"] = responses.to_json()
      }
    }
    // Per-operation security requirements (← FastAPI's `Security(...)`).
    match security_json(route.security) {
      Some(s) => op["security"] = s
      None => ()
    }
    let item = match paths.get(full_path) {
      Some(Object(m)) => m
      _ => Map([])
    }
    item[method_lower(route.verb)] = op.to_json()
    paths[full_path] = item.to_json()
  }
  let info : Map[String, Json] = Map([
    ("title", title.to_json()),
    ("version", api_version.to_json()),
  ])
  let (root_key, version_str) = version_field(version)
  let doc : Map[String, Json] = Map([
    (root_key, version_str.to_json()),
    ("info", info.to_json()),
    ("paths", paths.to_json()),
  ])
  // Hoisted named object schemas and the declared security schemes (the app's
  // own plus every mounted sub-app's): under `components` (`schemas` /
  // `securitySchemes`) in 3.x, or the top-level `definitions` /
  // `securityDefinitions` in Swagger 2.0.
  let schemes : Array[(String, SecurityScheme)] = []
  let seen : Map[String, Bool] = Map([])
  self.collect_security_schemes(schemes, seen)
  let has_schemes = schemes.length() > 0
  match version {
    Swagger20 => {
      if !defs.is_empty() {
        doc["definitions"] = defs.to_json()
      }
      if has_schemes {
        doc["securityDefinitions"] = security_schemes_json(schemes, version)
      }
    }
    _ =>
      if !defs.is_empty() || has_schemes {
        let comp : Map[String, Json] = Map([])
        if !defs.is_empty() {
          comp["schemas"] = defs.to_json()
        }
        if has_schemes {
          comp["securitySchemes"] = security_schemes_json(schemes, version)
        }
        doc["components"] = comp.to_json()
      }
  }
  doc.to_json()
}

///|
/// Collect this app's routes and every mounted sub-app's routes into `out`, each
/// paired with its full path (the mount prefixes joined on). Recursive, so
/// nested mounts flatten into one path space for the merged OpenAPI document.
fn App::collect_routes(
  self : App,
  prefix : String,
  out : Array[(String, Route)],
) -> Unit {
  for route in self.routes {
    out.push((join_prefix(prefix, route.path), route))
  }
  for entry in self.mounts {
    let (mp, sub) = entry
    sub.collect_routes(join_prefix(prefix, mp), out)
  }
}

///|
/// Collect this app's security schemes and every mounted sub-app's, first-writer
/// wins (a parent's scheme shadows a sub-app's same-named one). `seen` tracks
/// names already taken.
fn App::collect_security_schemes(
  self : App,
  out : Array[(String, SecurityScheme)],
  seen : Map[String, Bool],
) -> Unit {
  for pair in self.security_schemes {
    if !seen.contains(pair.0) {
      seen[pair.0] = true
      out.push(pair)
    }
  }
  for entry in self.mounts {
    entry.1.collect_security_schemes(out, seen)
  }
}

///|
/// Join a mount `prefix` and a route `path` into one path by concatenating their
/// segments, so `("/sub", "/items")` becomes `/sub/items` and a root path stays
/// under the prefix. An all-empty result is the root `"/"`.
fn join_prefix(prefix : String, path : String) -> String {
  let segs = segments(prefix)
  for s in segments(path) {
    segs.push(s)
  }
  if segs.is_empty() {
    return "/"
  }
  let sb = StringBuilder::new()
  for s in segs {
    sb.write_string("/")
    sb.write_string(s)
  }
  sb.to_string()
}

///|
/// The app's OpenAPI / Swagger document for `version`, stringified.
pub fn App::openapi_json(
  self : App,
  version? : OpenApiVersion = OpenApi31,
) -> String {
  self.openapi(version~).stringify(indent=2)
}

///|
/// A self-contained Swagger UI page rendering the document served at `spec_url`.
pub fn swagger_ui(
  spec_url? : String = "/openapi.json",
  title? : String = "moonapi",
) -> String {
  "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>\{title}</title>\n<link rel=\"stylesheet\" href=\"https://unpkg.com/swagger-ui-dist/swagger-ui.css\">\n</head>\n<body>\n<div id=\"swagger-ui\"></div>\n<script src=\"https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js\"></script>\n<script>\nwindow.onload = () => { window.ui = SwaggerUIBundle({ url: \"\{spec_url}\", dom_id: \"#swagger-ui\" }); };\n</script>\n</body>\n</html>\n"
}
