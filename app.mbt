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
/// A background-aware handler: it additionally receives the request's
/// `BackgroundTasks` queue, so it can schedule work to run after its response is
/// sent (← declaring a `BackgroundTasks` parameter in FastAPI).
pub type BackgroundHandler = (Context, BackgroundTasks) -> @moonasgi.Response raise

///|
/// A route stores one background-aware handler; a plain `ApiHandler` is wrapped
/// to ignore the queue. `security` is the per-operation requirements (emitted as
/// OpenAPI `security` and enforced before the handler when their scheme has an
/// enforcer).
struct Route {
  verb : Method
  path : String
  run : BackgroundHandler
  summary : String
  tags : Array[String]
  deprecated : Bool
  endpoint : Endpoint?
  security : Array[SecurityRequirement]
}

///|
/// A moonapi application: routes, WebSocket routes, an outer middleware chain,
/// exception handlers, mounted sub-applications, the security schemes surfaced
/// in the OpenAPI document (with optional runtime enforcers), per-status
/// exception handlers, and the verification clock. Compiles to a moonasgi
/// `AsgiApp` any server (mooncat) can run.
pub struct App {
  routes : Array[Route]
  ws_routes : Array[WsRoute]
  middlewares : Array[@moonasgi.Middleware]
  exception_handlers : Array[ExceptionHandler]
  security_schemes : Array[(String, SecurityScheme)]
  enforcers : Map[String, SecurityEnforcer]
  status_handlers : Map[Int, (Context) -> @moonasgi.Response]
  mounts : Array[(String, App)]
  mut clock : () -> Int64
}

///|
/// Create an empty application. The verification clock defaults to `0` (Unix
/// epoch); a server sets a real one with `App::set_clock`, and tests inject a
/// fixed time so token expiry is deterministic.
pub fn App::new() -> App {
  {
    routes: [],
    ws_routes: [],
    middlewares: [],
    exception_handlers: [],
    security_schemes: [],
    enforcers: Map([]),
    status_handlers: Map([]),
    mounts: [],
    clock: () => 0L,
  }
}

///|
/// Set the clock the app reads to verify token expiry when enforcing route
/// security (Unix seconds). A native server passes the wall clock; a test passes
/// a fixed function so expiry is deterministic.
pub fn App::set_clock(self : App, clock : () -> Int64) -> Unit {
  self.clock = clock
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
/// makes the route fully typed (its parameters, request body, and responses
/// surface in the OpenAPI document and drive validation); `security` attaches
/// per-operation requirements (emitted as OpenAPI `security` and enforced before
/// the handler when their scheme has an enforcer).
pub fn App::route(
  self : App,
  verb : Method,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.routes.push({
    verb,
    path,
    run: (ctx, _bg) => handler(ctx),
    summary,
    tags,
    deprecated,
    endpoint,
    security,
  })
}

///|
/// Register a background-aware route: the handler additionally receives the
/// request's `BackgroundTasks` queue, whose thunks the app runs after the
/// response is sent (← declaring a `BackgroundTasks` parameter in FastAPI).
pub fn App::route_bg(
  self : App,
  verb : Method,
  path : String,
  handler : BackgroundHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.routes.push({
    verb,
    path,
    run: handler,
    summary,
    tags,
    deprecated,
    endpoint,
    security,
  })
}

///|
pub fn App::get(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.route(
    Get,
    path,
    handler,
    summary~,
    tags~,
    deprecated~,
    endpoint~,
    security~,
  )
}

///|
pub fn App::post(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.route(
    Post,
    path,
    handler,
    summary~,
    tags~,
    deprecated~,
    endpoint~,
    security~,
  )
}

///|
pub fn App::put(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.route(
    Put,
    path,
    handler,
    summary~,
    tags~,
    deprecated~,
    endpoint~,
    security~,
  )
}

///|
pub fn App::patch(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.route(
    Patch,
    path,
    handler,
    summary~,
    tags~,
    deprecated~,
    endpoint~,
    security~,
  )
}

///|
pub fn App::delete(
  self : App,
  path : String,
  handler : ApiHandler,
  summary? : String = "",
  tags? : Array[String] = [],
  deprecated? : Bool = false,
  endpoint? : Endpoint? = None,
  security? : Array[SecurityRequirement] = [],
) -> Unit {
  self.route(
    Delete,
    path,
    handler,
    summary~,
    tags~,
    deprecated~,
    endpoint~,
    security~,
  )
}

///|
/// Declare an OAuth2 password-bearer scheme under `name` and wire it as a
/// runtime enforcer. Like `add_security_scheme` it surfaces the scheme in the
/// OpenAPI document (with the advertised `scopes`), and additionally registers
/// the guard a route names in its `security`: the app pulls the bearer token,
/// verifies it against `bearer`'s secret at the app clock's time, and checks the
/// route's required scopes — returning 401/403 before the handler runs.
pub fn App::secure_oauth2(
  self : App,
  name : String,
  bearer : OAuth2PasswordBearer,
  scopes? : Array[(String, String)] = [],
) -> Unit {
  self.security_schemes.push((name, bearer.scheme(scopes~)))
  self.enforcers[name] = (ctx, required, now) => {
    bearer.authenticate(ctx, now, scopes=required)
  }
}

///|
/// Register a per-status exception handler (← FastAPI's `add_exception_handler`
/// keyed by an HTTP status code). Whenever an error path yields `status` — a
/// routing `404` / `405`, or a raised `HttpException` (or the fallback `500`) —
/// the handler's response replaces the default, so an app can serve a custom
/// error page. Successful handler returns are never rewritten.
pub fn App::add_status_handler(
  self : App,
  status : Int,
  handler : (Context) -> @moonasgi.Response,
) -> Unit {
  self.status_handlers[status] = handler
}

///|
/// Mount a sub-application under `prefix` (← FastAPI's `app.mount(prefix, sub)`).
/// A request whose path lies under `prefix` is routed by `subapp` with the
/// prefix stripped (its own middleware, security, and background tasks apply),
/// and the sub-app's routes appear under `prefix` in the merged OpenAPI document
/// with its security schemes folded into the parent's.
pub fn App::mount(self : App, prefix : String, subapp : App) -> Unit {
  self.mounts.push((prefix, subapp))
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
/// Rewrite an error-path response through a registered per-status handler, if one
/// is registered for its status; otherwise pass it through unchanged.
fn App::apply_status(
  self : App,
  ctx : Context,
  resp : @moonasgi.Response,
) -> @moonasgi.Response {
  match self.status_handlers.get(resp.status) {
    Some(h) => h(ctx)
    None => resp
  }
}

///|
/// Try each registered exception handler in order; the first to claim the error
/// wins outright. Otherwise fall through to the built-in mapping, which a
/// per-status handler may still rewrite (a custom `500` page, say).
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
  self.apply_status(ctx, default_exception_response(err))
}

///|
/// Enforce a route's security requirements. `None` means allow (nothing to
/// enforce, or a requirement passed); `Some(resp)` is the 401/403 to return.
/// Requirements are alternatives (OpenAPI OR-semantics): the first enforceable
/// one that passes admits the request; if every enforceable requirement fails,
/// the last failure response is returned. A requirement naming a
/// documentation-only scheme (no enforcer) grants nothing by itself.
fn App::enforce_security(
  self : App,
  ctx : Context,
  reqs : Array[SecurityRequirement],
) -> @moonasgi.Response? {
  if reqs.is_empty() {
    return None
  }
  let now = (self.clock)()
  let mut enforceable = false
  let mut last : @moonasgi.Response? = None
  for r in reqs {
    match self.enforcers.get(r.scheme) {
      Some(enf) => {
        enforceable = true
        match enf(ctx, r.scopes, now) {
          Ok(_) => return None
          Err(resp) => last = Some(resp)
        }
      }
      None => ()
    }
  }
  if enforceable {
    last
  } else {
    None
  }
}

///|
/// The routing + exception core, inside the middleware chain: match a route,
/// enforce its security, run its (possibly raising) handler, and turn any raised
/// error into a response. Falls through to mounted sub-apps, then 405 (a path
/// matched but no method) or 404 (no path). `bg` is the request's background
/// queue, handed to the matched handler and drained by the caller after the
/// response is sent.
fn App::route_and_dispatch(
  self : App,
  request : @moonasgi.Request,
  bg : BackgroundTasks,
) -> @moonasgi.Response {
  let verb = parse_method(request.http_method)
  let mut method_mismatch = false
  for route in self.routes {
    match match_path(route.path, request.path) {
      Some(params) =>
        if route.verb == verb {
          let ctx : Context = { request, params }
          match self.enforce_security(ctx, route.security) {
            Some(denied) => return self.apply_status(ctx, denied)
            None => ()
          }
          return (route.run)(ctx, bg) catch {
            e => self.dispatch_exception(ctx, e)
          }
        } else {
          method_mismatch = true
        }
      None => ()
    }
  }
  for entry in self.mounts {
    let (prefix, sub) = entry
    match strip_prefix(prefix, request.path) {
      Some(rest) => {
        let subreq : @moonasgi.Request = {
          http_method: request.http_method,
          path: rest,
          query_string: request.query_string,
          headers: request.headers,
          body: request.body,
        }
        let (resp, subbg) = sub.handle_with_background(subreq)
        bg.absorb(subbg)
        return resp
      }
      None => ()
    }
  }
  let ctx : Context = { request, params: Map([]) }
  if method_mismatch {
    self.apply_status(ctx, text(405, "Method Not Allowed"))
  } else {
    self.apply_status(ctx, text(404, "Not Found"))
  }
}

///|
/// Route a request through the middleware chain and return both the response and
/// the background queue the handler filled — the caller (`to_asgi`, or a test)
/// runs the queue after the response is sent. `handle` is the plain-response
/// wrapper over this.
pub fn App::handle_with_background(
  self : App,
  request : @moonasgi.Request,
) -> (@moonasgi.Response, BackgroundTasks) {
  let bg = BackgroundTasks::new()
  let base : @moonasgi.Handler = req => self.route_and_dispatch(req, bg)
  let resp = @moonasgi.compose(self.middlewares, base)(request)
  (resp, bg)
}

///|
/// Route a request to its handler through the middleware chain, returning 404
/// when no path matches and 405 when a path matches but no method does. Any
/// error a handler raises is mapped to a response by the exception handlers.
/// Background tasks a handler scheduled are dropped on this path; use
/// `handle_with_background` (as `to_asgi` does) to run them.
pub fn App::handle(
  self : App,
  request : @moonasgi.Request,
) -> @moonasgi.Response {
  self.handle_with_background(request).0
}

///|
/// Strip a mount `prefix` off `path` by whole segments, returning the sub-app's
/// path (`"/"` when the request hits the mount root). `None` when `path` does not
/// lie under `prefix` — the comparison is segment-wise, so `/sub` does not match
/// `/subway`.
fn strip_prefix(prefix : String, path : String) -> String? {
  let pp = segments(prefix)
  let ph = segments(path)
  if pp.length() > ph.length() {
    return None
  }
  for i = 0; i < pp.length(); i = i + 1 {
    if pp[i] != ph[i] {
      return None
    }
  }
  let sb = StringBuilder::new()
  for i = pp.length(); i < ph.length(); i = i + 1 {
    sb.write_string("/")
    sb.write_string(ph[i])
  }
  let rest = sb.to_string()
  if rest == "" {
    Some("/")
  } else {
    Some(rest)
  }
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
        let (resp, bg) = self.handle_with_background(request)
        send(
          @moonasgi.Event::HttpResponseStart(
            status=resp.status,
            headers=resp.headers,
            trailers=false,
          ),
        )
        send(@moonasgi.Event::HttpResponseBody(body=resp.body, more_body=false))
        // The response is on the wire; now drain any background tasks.
        bg.run()
      }
      WebSocket(wss) => self.serve_websocket(wss, receive, send)
      _ => ()
    }
  }
}
