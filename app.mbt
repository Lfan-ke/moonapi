///|
/// HTTP methods a moonapi route can bind to.
pub(all) enum Method {
  Get
  Post
  Put
  Patch
  Delete
  Head
  Options
} derive(Eq)

///|
fn parse_method(s : String) -> Method {
  match s {
    "GET" => Get
    "POST" => Post
    "PUT" => Put
    "PATCH" => Patch
    "DELETE" => Delete
    "HEAD" => Head
    "OPTIONS" => Options
    _ => Get
  }
}

///|
fn method_lower(m : Method) -> String {
  match m {
    Get => "get"
    Post => "post"
    Put => "put"
    Patch => "patch"
    Delete => "delete"
    Head => "head"
    Options => "options"
  }
}

///|
/// The per-request context handed to a handler: the raw request plus the path
/// parameters extracted from the matched route (`:name` segments).
pub(all) struct Context {
  request : @moonasgi.Request
  params : Map[String, String]
}

///|
/// Look up a path parameter by name.
pub fn Context::param(self : Context, name : String) -> String? {
  self.params.get(name)
}

///|
/// A moonapi route handler: request context in, response out. It may `raise` an
/// `HttpException` (or any error) instead of returning — the app catches it and
/// maps it to a response through the registered exception handlers, so handlers
/// read like FastAPI's `raise HTTPException(...)` rather than threading a
/// `Result` back by hand. A plain non-raising closure is still a valid handler.
pub type ApiHandler = (Context) -> @moonasgi.Response raise

///|
struct Route {
  verb : Method
  path : String
  handler : ApiHandler
  summary : String
  endpoint : Endpoint?
}

///|
/// A moonapi application: routes, WebSocket routes, an outer middleware chain,
/// exception handlers, and the security schemes surfaced in the OpenAPI
/// document. Compiles to a moonasgi `AsgiApp` any server (mooncat) can run.
pub struct App {
  routes : Array[Route]
  ws_routes : Array[WsRoute]
  middlewares : Array[@moonasgi.Middleware]
  exception_handlers : Array[ExceptionHandler]
  security_schemes : Array[(String, SecurityScheme)]
}

///|
/// Create an empty application.
pub fn App::new() -> App {
  {
    routes: [],
    ws_routes: [],
    middlewares: [],
    exception_handlers: [],
    security_schemes: [],
  }
}

///|
/// Add an outer middleware. Middlewares wrap the router as an onion; the first
/// registered is the outermost (it sees the request first and the response
/// last). `cors(...)` and `gzip(...)` are middlewares.
pub fn App::middleware(self : App, mw : @moonasgi.Middleware) -> Unit {
  self.middlewares.push(mw)
}

///|
/// Register an exception handler. On a raised error the handlers are tried in
/// registration order; the first to return `Some(response)` wins. An
/// unhandled error falls through to the built-in mapping — an `HttpException`
/// becomes its own `status` / `detail`, anything else a `500`.
pub fn App::exception_handler(self : App, h : ExceptionHandler) -> Unit {
  self.exception_handlers.push(h)
}

///|
/// Declare a security scheme under `name`, surfaced in the emitted OpenAPI
/// document (`components/securitySchemes` in 3.x, `securityDefinitions` in
/// Swagger 2.0) so the generated spec describes how to authenticate.
pub fn App::add_security_scheme(
  self : App,
  name : String,
  scheme : SecurityScheme,
) -> Unit {
  self.security_schemes.push((name, scheme))
}

///|
/// Register a route for an explicit method. An optional `endpoint` descriptor
/// makes the route fully typed: its parameters, request body, and responses
/// surface in the OpenAPI document and drive validation.
pub fn App::route(
  self : App,
  verb : Method,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  endpoint? : Endpoint? = None,
) -> Unit {
  self.routes.push({ verb, path, handler, summary, endpoint })
}

///|
pub fn App::get(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  endpoint? : Endpoint? = None,
) -> Unit {
  self.route(Get, path, handler, summary~, endpoint~)
}

///|
pub fn App::post(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  endpoint? : Endpoint? = None,
) -> Unit {
  self.route(Post, path, handler, summary~, endpoint~)
}

///|
pub fn App::put(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  endpoint? : Endpoint? = None,
) -> Unit {
  self.route(Put, path, handler, summary~, endpoint~)
}

///|
pub fn App::patch(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  endpoint? : Endpoint? = None,
) -> Unit {
  self.route(Patch, path, handler, summary~, endpoint~)
}

///|
pub fn App::delete(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  endpoint? : Endpoint? = None,
) -> Unit {
  self.route(Delete, path, handler, summary~, endpoint~)
}

///|
/// Split a path into its non-empty segments.
fn segments(path : String) -> Array[String] {
  let out : Array[String] = []
  let n = path.length()
  let mut start = 0
  for i = 0; i <= n; i = i + 1 {
    if i == n || path[i] == '/' {
      if i > start {
        out.push(path[start:i].to_owned())
      }
      start = i + 1
    }
  }
  out
}

///|
/// Match a route pattern against a request path, extracting `:name` params.
fn match_path(pattern : String, path : String) -> Map[String, String]? {
  let pp = segments(pattern)
  let ph = segments(path)
  if pp.length() != ph.length() {
    return None
  }
  let params : Map[String, String] = Map([])
  for i = 0; i < pp.length(); i = i + 1 {
    let seg = pp[i]
    if seg.length() > 0 && seg[0] == ':' {
      params[seg[1:].to_owned()] = ph[i]
    } else if seg != ph[i] {
      return None
    }
  }
  Some(params)
}

///|
/// A plain-text response.
pub fn text(status : Int, body : String) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "text/plain; charset=utf-8")],
    @utf8.encode(body),
  )
}

///|
/// A JSON response serialised from a `Json` value.
pub fn json(status : Int, value : Json) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("content-type", "application/json")],
    @utf8.encode(value.stringify()),
  )
}

///|
/// Try each registered exception handler in order, then the built-in mapping.
fn App::dispatch_exception(
  self : App,
  ctx : Context,
  err : Error,
) -> @moonasgi.Response {
  for h in self.exception_handlers {
    match h(ctx, err) {
      Some(resp) => return resp
      None => ()
    }
  }
  default_exception_response(err)
}

///|
/// The routing + exception core, inside the middleware chain: match a route,
/// run its (possibly raising) handler, and turn any raised error into a
/// response. 404 when no path matches, 405 when a path matches but no method.
fn App::route_and_dispatch(
  self : App,
  request : @moonasgi.Request,
) -> @moonasgi.Response {
  let verb = parse_method(request.http_method)
  let mut method_mismatch = false
  for route in self.routes {
    match match_path(route.path, request.path) {
      Some(params) =>
        if route.verb == verb {
          let ctx : Context = { request, params }
          return (route.handler)(ctx) catch {
            e => self.dispatch_exception(ctx, e)
          }
        } else {
          method_mismatch = true
        }
      None => ()
    }
  }
  if method_mismatch {
    text(405, "Method Not Allowed")
  } else {
    text(404, "Not Found")
  }
}

///|
/// Route a request to its handler through the middleware chain, returning 404
/// when no path matches and 405 when a path matches but no method does. Any
/// error a handler raises is mapped to a response by the exception handlers.
pub fn App::handle(
  self : App,
  request : @moonasgi.Request,
) -> @moonasgi.Response {
  let base : @moonasgi.Handler = req => self.route_and_dispatch(req)
  @moonasgi.compose(self.middlewares, base)(request)
}

///|
async fn drain_body(receive : @moonasgi.Receive) -> Bytes {
  let buf = Buffer()
  let mut more = true
  while more {
    match receive() {
      HttpRequest(body~, more_body~) => {
        buf.write_bytes(body)
        more = more_body
      }
      _ => more = false
    }
  }
  buf.to_bytes()
}

///|
/// Compile the app to a moonasgi `AsgiApp` a server can run: drain the request
/// body, route it, and stream the response back over the SEAM.
pub fn App::to_asgi(self : App) -> @moonasgi.AsgiApp {
  (scope, receive, send) => {
    match scope {
      Http(hs) => {
        let body = drain_body(receive)
        let request : @moonasgi.Request = {
          http_method: hs.http_method,
          path: hs.path,
          query_string: hs.query_string,
          headers: hs.headers,
          body,
        }
        let resp = self.handle(request)
        send(
          @moonasgi.Event::HttpResponseStart(
            status=resp.status,
            headers=resp.headers,
          ),
        )
        send(@moonasgi.Event::HttpResponseBody(body=resp.body, more_body=false))
      }
      WebSocket(wss) => self.serve_websocket(wss, receive, send)
      _ => ()
    }
  }
}
