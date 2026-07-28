// Server-Sent Events (← FastAPI's `EventSourceResponse` / `StreamingResponse`
// with `media_type="text/event-stream"`). One `ServerSentEvent` frames per the
// WHATWG event-stream format; `sse_response` concatenates a batch into a ready
// `text/event-stream` body. The framing is the value here — a server (mooncat)
// pushes frames over time; this builds each one and the response envelope.

///|
/// One Server-Sent Event. `data` is the payload (multi-line data is split into
/// several `data:` lines per the spec); `event` names the type an
/// `EventSource.addEventListener` binds to; `id` sets `lastEventId` for
/// reconnection; `retry` is the client's reconnection delay in milliseconds;
/// `comment` emits `:`-prefixed lines (a keep-alive ping carries only this).
pub(all) struct ServerSentEvent {
  data : String
  event : String?
  id : String?
  retry : Int?
  comment : String?
}

///|
/// A data-only event — the common case (`data: ...\n\n`).
pub fn ServerSentEvent::data(data : String) -> ServerSentEvent {
  { data, event: None, id: None, retry: None, comment: None }
}

///|
/// A fully-specified event. Any field left `None` is omitted from the frame.
pub fn ServerSentEvent::new(
  data : String,
  event? : String? = None,
  id? : String? = None,
  retry? : Int? = None,
  comment? : String? = None,
) -> ServerSentEvent {
  { data, event, id, retry, comment }
}

///|
/// A comment-only keep-alive frame (`: <text>\n\n`) — no event is dispatched,
/// but the bytes keep the connection warm through proxies.
pub fn ServerSentEvent::keep_alive(comment? : String = "") -> ServerSentEvent {
  { data: "", event: None, id: None, retry: None, comment: Some(comment) }
}

///|
/// Split `s` on `\n` into its lines (core has no `String::split`). A trailing
/// newline yields a trailing empty line, matching how each is re-emitted as its
/// own `data:` field.
fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == 0x0A {
      out.push(sb.to_string())
      sb.reset()
    } else if s[i].to_int() != 0x0D {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  out.push(sb.to_string())
  out
}

///|
/// Encode this event as its wire frame: optional `comment` / `id` / `event` /
/// `retry` fields, then one `data:` line per line of `data`, terminated by the
/// blank line that dispatches the event.
pub fn ServerSentEvent::encode(self : ServerSentEvent) -> String {
  let sb = StringBuilder::new()
  match self.comment {
    Some(c) =>
      for line in split_lines(c) {
        sb.write_string(": ")
        sb.write_string(line)
        sb.write_string("\n")
      }
    None => ()
  }
  match self.id {
    Some(id) => {
      sb.write_string("id: ")
      sb.write_string(id)
      sb.write_string("\n")
    }
    None => ()
  }
  match self.event {
    Some(ev) => {
      sb.write_string("event: ")
      sb.write_string(ev)
      sb.write_string("\n")
    }
    None => ()
  }
  match self.retry {
    Some(ms) => {
      sb.write_string("retry: ")
      sb.write_string(ms.to_string())
      sb.write_string("\n")
    }
    None => ()
  }
  if self.data != "" ||
    (
      self.comment is None &&
      self.id is None &&
      self.event is None &&
      self.retry is None
    ) {
    for line in split_lines(self.data) {
      sb.write_string("data: ")
      sb.write_string(line)
      sb.write_string("\n")
    }
  }
  sb.write_string("\n")
  sb.to_string()
}

///|
/// A `text/event-stream` response whose body is the framed `events`. Sets
/// `Cache-Control: no-cache` and `Connection: keep-alive`, the headers an SSE
/// endpoint sends so intermediaries don't buffer or close the stream.
pub fn sse_response(
  events : Array[ServerSentEvent],
  status? : Int = 200,
  headers? : Array[(String, String)] = [],
) -> @moonasgi.Response {
  let sb = StringBuilder::new()
  for ev in events {
    sb.write_string(ev.encode())
  }
  let hs : Array[(String, String)] = [
    ("content-type", "text/event-stream; charset=utf-8"),
    ("cache-control", "no-cache"),
    ("connection", "keep-alive"),
  ]
  for h in headers {
    hs.push(h)
  }
  @moonasgi.Response::new(status, hs, @utf8.encode(sb.to_string()))
}
