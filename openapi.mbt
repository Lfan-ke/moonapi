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
/// Build the OpenAPI / Swagger document for the app as a `Json` value, walking
/// the registered routes once into paths → methods → operations.
pub fn App::openapi(
  self : App,
  version? : OpenApiVersion = OpenApi31,
  title? : String = "moonapi",
  api_version? : String = "0.1.0",
) -> Json {
  let paths : Map[String, Json] = Map([])
  for route in self.routes {
    let op : Map[String, Json] = Map([])
    if route.summary != "" {
      op["summary"] = route.summary.to_json()
    }
    let ok : Map[String, Json] = Map([("description", "OK".to_json())])
    let responses : Map[String, Json] = Map([("200", ok.to_json())])
    op["responses"] = responses.to_json()
    let item = match paths.get(route.path) {
      Some(Object(m)) => m
      _ => Map([])
    }
    item[method_lower(route.verb)] = op.to_json()
    paths[route.path] = item.to_json()
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
  doc.to_json()
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
