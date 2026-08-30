///|
test "sse: a data-only event frames as one data line plus the blank line" {
  assert_eq(ServerSentEvent::data("hello").encode(), "data: hello\n\n")
}

///|
test "sse: all fields render in the canonical order" {
  let ev = ServerSentEvent::new(
    "payload",
    event=Some("update"),
    id=Some("7"),
    retry=Some(3000),
  )
  assert_eq(ev.encode(), "id: 7\nevent: update\nretry: 3000\ndata: payload\n\n")
}

///|
test "sse: multi-line data becomes one data field per line" {
  assert_eq(
    ServerSentEvent::data("a\nb\nc").encode(),
    "data: a\ndata: b\ndata: c\n\n",
  )
}

///|
test "sse: a keep-alive is a comment with no data line" {
  assert_eq(ServerSentEvent::keep_alive(comment="ping").encode(), ": ping\n\n")
}

///|
test "sse: response carries the event-stream headers and one chunk per event" {
  let resp = sse_response([
    ServerSentEvent::data("one"),
    ServerSentEvent::new("two", id=Some("2")),
  ])
  assert_eq(resp.status, 200)
  assert_eq(
    header_of(resp.headers, "content-type"),
    Some("text/event-stream; charset=utf-8"),
  )
  assert_eq(header_of(resp.headers, "cache-control"), Some("no-cache"))
  // Streamed, not buffered: two events are two chunks, and each is one whole
  // frame. Concatenated they are the body the old buffering version produced —
  // the bytes did not change, only where they are allowed to be cut.
  assert_eq(resp.chunks.length(), 2)
  assert_eq(resp.chunks[0], @utf8.encode("data: one\n\n"))
  assert_eq(resp.chunks[1], @utf8.encode("id: 2\ndata: two\n\n"))
}

///|
/// The lowered wire form: a reader gets each frame as its own body event, and
/// only the last says the stream is over.
test "sse: each frame is its own body event, only the last ends the stream" {
  let events = sse_response([
    ServerSentEvent::data("one"),
    ServerSentEvent::data("two"),
    ServerSentEvent::data("three"),
  ]).events()
  let bodies = events.filter(e => e is HttpResponseBody(_))
  assert_eq(bodies.length(), 3)
  assert_eq(
    bodies[0] ==
    @moonasgi.Event::HttpResponseBody(
      body=@utf8.encode("data: one\n\n"),
      more_body=true,
    ),
    true,
  )
  assert_eq(
    bodies[2] ==
    @moonasgi.Event::HttpResponseBody(
      body=@utf8.encode("data: three\n\n"),
      more_body=false,
    ),
    true,
  )
}
