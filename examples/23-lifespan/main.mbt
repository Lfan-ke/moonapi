/// Startup and shutdown hooks (← FastAPI's `on_event`). A server drives them over
/// the ASGI lifespan protocol; here the same synchronous core runs in-process, so
/// the order is visible without a socket: startup in registration order, shutdown
/// in reverse, so a resource is released before whatever it was opened from.
///
///     moon run examples/23-lifespan

///|
fn main {
  let log : Array[String] = []
  let app = @moonapi.App::new()
  app.on_startup(() => log.push("connect db"))
  app.on_startup(() => log.push("warm cache"))
  app.on_shutdown(() => log.push("drop cache"))
  app.on_shutdown(() => log.push("close db"))
  let scope = @moonasgi.Scope::Lifespan(@moonasgi.LifespanScope::new())
  let replies = @moonasgi.run_lifespan(app.lifespan_handler(), scope, [
    @moonasgi.Event::LifespanStartup,
    @moonasgi.Event::LifespanShutdown,
  ])
  for r in replies {
    let name = match r {
      LifespanStartupComplete => "startup.complete"
      LifespanShutdownComplete => "shutdown.complete"
      LifespanStartupFailed(message~) => "startup.failed: " + message
      LifespanShutdownFailed(message~) => "shutdown.failed: " + message
      _ => "?"
    }
    println(name)
  }
  println(log.join(" -> "))
}
