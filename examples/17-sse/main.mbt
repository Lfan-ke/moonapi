///|
/// Server-Sent Events framing. A `ServerSentEvent` encodes to the WHATWG
/// event-stream wire format: `ServerSentEvent::data` is the common data-only
/// frame, `new` sets `event` / `id` / `retry`, multi-line data splits into
/// several `data:` lines, and `keep_alive` emits a `:`-comment ping that
/// dispatches nothing. `sse_response` wraps a batch into a ready
/// `text/event-stream` response with the no-cache / keep-alive headers.
///
///     moon run examples/17-sse
#coverage.skip
fn main {
  let events = [
    @moonapi.ServerSentEvent::data("hello"),
    @moonapi.ServerSentEvent::new(
      "first line\nsecond line",
      event=Some("update"),
      id=Some("233"),
      retry=Some(3000),
    ),
    @moonapi.ServerSentEvent::keep_alive(comment="ping"),
  ]
  println("--- individual frames (blank line dispatches each event) ---")
  let frames = StringBuilder()
  for ev in events {
    frames.write_string(ev.encode())
  }
  println(frames.to_string())
  let resp = @moonapi.sse_response(events)
  println("--- sse_response ---")
  println(
    "status=\{resp.status} content-type=\{resp.header("content-type").unwrap_or("-")} cache-control=\{resp.header("cache-control").unwrap_or("-")}",
  )
  println("body bytes: \{resp.body.length()}")
  println(@utf8.decode_lossy(resp.body[:]))
}
