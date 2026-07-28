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
test "sse: response carries the event-stream headers and framed body" {
  let resp = sse_response([
    ServerSentEvent::data("one"),
    ServerSentEvent::new("two", id=Some("2")),
  ])
  assert_eq(resp.status, 200)
  assert_eq(
    resp.header("content-type"),
    Some("text/event-stream; charset=utf-8"),
  )
  assert_eq(resp.header("cache-control"), Some("no-cache"))
  assert_eq(resp.body, @utf8.encode("data: one\n\nid: 2\ndata: two\n\n"))
}
