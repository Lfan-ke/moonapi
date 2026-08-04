///|
/// The form and file extractors — FastAPI's `Form(...)` / `File(...)`. One
/// `Context::form` parses both carriers: an `application/x-www-form-urlencoded`
/// body (percent- and `+`-decoded) and a `multipart/form-data` body split on its
/// boundary. `FormData::field` reads the first value, `field_all` every value a
/// repeated field submitted, and `file` an `UploadFile` — filename, content-type,
/// and the raw bytes byte-for-byte, so a binary upload survives untouched.
///
///     moon run examples/13-forms-files
#coverage.skip
fn main {
  let app = @moonapi.App::new()
  app.post("/upload", ctx => {
    let form = ctx.form()
    let title = form.field("title").unwrap_or("-")
    let tags = form.field_all("tag")
    match form.file("doc") {
      Some(f) =>
        @moonapi.text(
          200,
          "title=\{title} tags=[\{join_csv(tags)}] file=\{f.filename} type=\{f.content_type} bytes=\{f.content.length()} body=\{@utf8.decode_lossy(f.content[:])}",
        )
      None =>
        @moonapi.text(200, "title=\{title} tags=[\{join_csv(tags)}] (no file)")
    }
  })
  let post = (label : String, ct : String, body : Bytes) => {
    let req : @moonasgi.Request = {
      http_method: "POST",
      path: "/upload",
      query_string: b"",
      headers: [("content-type", ct)],
      body,
    }
    let r = app.handle(req)
    println("\{label} -> \{r.status} \{@utf8.decode_lossy(r.body[:])}")
  }

  // 1. urlencoded: a repeated `tag` becomes a list; `+` decodes to a space.
  post(
    "urlencoded",
    "application/x-www-form-urlencoded",
    @utf8.encode("title=hello+world&tag=a&tag=b&tag=c"),
  )

  // 2. multipart: a text field plus an uploaded file with its own content-type.
  let boundary = "boundaryqwq233"
  let multipart =
    #|--boundaryqwq233
    #|Content-Disposition: form-data; name="title"
    #|
    #|greetings
    #|--boundaryqwq233
    #|Content-Disposition: form-data; name="doc"; filename="hello.txt"
    #|Content-Type: text/plain
    #|
    #|qwq file bytes 23333
    #|--boundaryqwq233--
    #|
  // The multipart grammar is CRLF-delimited; the raw string above is LF-only.
  let crlf_body = @utf8.encode(to_crlf(multipart))
  post("multipart", "multipart/form-data; boundary=" + boundary, crlf_body)
}

///|
/// Join strings with commas — a repeated form field surfaces as a list.
fn join_csv(xs : Array[String]) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < xs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(xs[i])
  }
  sb.to_string()
}

///|
/// Rewrite LF line endings as CRLF — the multipart wire grammar is CRLF, but a
/// MoonBit multi-line string literal carries bare LFs.
fn to_crlf(s : String) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == 0x0A {
      sb.write_string("\r\n")
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  sb.to_string()
}
