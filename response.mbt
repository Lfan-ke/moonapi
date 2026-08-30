// The response kinds that are an envelope rather than a body — FastAPI's
// `RedirectResponse` and `FileResponse`. `text` / `html` / `json` in `app.mbt`
// serialise a value; these two decide what the headers say about it.

///|
/// Whether `s` contains the ASCII code `c`.
fn holds_code(s : String, c : Int) -> Bool {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == c {
      return true
    }
  }
  false
}

///|
/// Percent-encode `s` over its UTF-8 bytes, leaving ASCII letters, digits,
/// `-._~` and anything in `safe` alone. Hex digits are upper case, as RFC 3986
/// §2.1 asks producers to emit them.
fn percent_encode(s : String, safe : String) -> String {
  let hex = "0123456789ABCDEF"
  let raw = @utf8.encode(s)
  let sb = StringBuilder()
  for i = 0; i < raw.length(); i = i + 1 {
    let b = raw[i].to_int()
    let unreserved = (b >= 0x41 && b <= 0x5A) ||
      (b >= 0x61 && b <= 0x7A) ||
      (b >= 0x30 && b <= 0x39) ||
      b == 0x2D ||
      b == 0x2E ||
      b == 0x5F ||
      b == 0x7E
    let allowed = unreserved || (b < 0x80 && holds_code(safe, b))
    if allowed {
      sb.write_char(b.unsafe_to_char())
    } else {
      sb.write_string("%")
      sb.write_char(hex[b / 16].unsafe_to_char())
      sb.write_char(hex[b % 16].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
/// A redirect to `url` (← FastAPI's `RedirectResponse`). The body is empty and
/// `Location` carries the target.
///
/// `307` is the default because it is the redirect that keeps the request's
/// method and body — the one a `POST` can safely follow, which `302` historically
/// is not. Use `303` to send a client to a `GET` after a write, and `301` / `308`
/// for a move that is permanent.
///
/// The URL is percent-encoded over the characters a URI reserves for structure,
/// so an already-encoded URL passes through unchanged and a `\r\n` smuggled into
/// one cannot open a header of its own.
pub fn redirect(url : String, status? : Int = 307) -> @moonasgi.Response {
  @moonasgi.Response::new(
    status,
    [("location", percent_encode(url, ":/%#?=@[]!$&'()*+,;"))],
    b"",
  )
}

///|
/// The media type a filename's extension implies, `application/octet-stream`
/// when nothing does. Deliberately short: this exists so `file_response` can
/// label the common downloads, not to be a copy of the IANA registry.
fn media_type_of(filename : String) -> String {
  let lower = filename.to_lower()
  let mut dot = -1
  for i = 0; i < lower.length(); i = i + 1 {
    if lower[i] == '.' {
      dot = i
    }
  }
  if dot < 0 {
    return "application/octet-stream"
  }
  match lower[dot + 1:].to_owned() {
    "txt" | "text" | "log" => "text/plain; charset=utf-8"
    "html" | "htm" => "text/html; charset=utf-8"
    "css" => "text/css; charset=utf-8"
    "csv" => "text/csv; charset=utf-8"
    "md" => "text/markdown; charset=utf-8"
    "js" | "mjs" => "text/javascript; charset=utf-8"
    "json" => "application/json"
    "xml" => "application/xml"
    "pdf" => "application/pdf"
    "zip" => "application/zip"
    "gz" => "application/gzip"
    "wasm" => "application/wasm"
    "png" => "image/png"
    "jpg" | "jpeg" => "image/jpeg"
    "gif" => "image/gif"
    "webp" => "image/webp"
    "svg" => "image/svg+xml"
    "ico" => "image/vnd.microsoft.icon"
    "woff" => "font/woff"
    "woff2" => "font/woff2"
    "mp3" => "audio/mpeg"
    "mp4" => "video/mp4"
    _ => "application/octet-stream"
  }
}

///|
/// The `Content-Disposition` value naming `filename`. A name that survives
/// percent-encoding unchanged is quoted as-is; anything else — a space, an
/// accent, a quote — is sent as RFC 6266's `filename*`, which is the only form
/// that can carry non-ASCII.
fn disposition_of(filename : String, inline : Bool) -> String {
  let kind = if inline { "inline" } else { "attachment" }
  let quoted = percent_encode(filename, "/")
  if quoted == filename {
    kind + "; filename=\"" + filename + "\""
  } else {
    kind + "; filename*=utf-8''" + quoted
  }
}

///|
/// A file download built from bytes already in hand (← FastAPI's `FileResponse`).
///
/// It takes the content rather than a path because moonapi has no filesystem of
/// its own — the same app runs on wasm, js and native, and only the server knows
/// how to read a file on any of them. What this adds is the envelope: a media
/// type guessed from `filename`'s extension unless `media_type` names one,
/// `Content-Length`, and a `Content-Disposition` that tells the browser to save
/// the file (or, with `inline`, to display it) under that name. An empty
/// `filename` leaves the disposition off entirely.
pub fn file_response(
  content : Bytes,
  filename? : String = "",
  media_type? : String = "",
  status? : Int = 200,
  inline? : Bool = false,
) -> @moonasgi.Response {
  let ct = if media_type != "" { media_type } else { media_type_of(filename) }
  let headers : Array[(String, String)] = [
    ("content-type", ct),
    ("content-length", content.length().to_string()),
  ]
  if filename != "" {
    headers.push(("content-disposition", disposition_of(filename, inline)))
  }
  @moonasgi.Response::new(status, headers, content)
}
