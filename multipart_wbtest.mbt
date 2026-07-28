///|
/// A request carrying `body` under `content_type` — test helper.
fn mkreq_ct(
  verb : String,
  content_type : String,
  body : Bytes,
) -> @moonasgi.Request {
  {
    http_method: verb,
    path: "/",
    query_string: b"",
    headers: [("content-type", content_type)],
    body,
  }
}

///|
/// Append `s` as UTF-8 then CRLF to a buffer — a multipart line writer.
fn wline(buf : Buffer, s : String) -> Unit {
  buf.write_bytes(@utf8.encode(s)[:])
  buf.write_bytes(b"\r\n")
}

///|
test "urlencoded form: fields, percent-decoding, plus-as-space, bare key" {
  let body = @utf8.encode("name=Ada+Lovelace&city=M%C3%BCnchen&flag&q=a%3Db")
  let ctx : Context = {
    request: mkreq_ct("POST", "application/x-www-form-urlencoded", body),
    params: Map([]),
  }
  let form = ctx.form()
  assert_eq(form.field("name"), Some("Ada Lovelace"))
  assert_eq(form.field("city"), Some("München")) // %C3%BC -> ü (UTF-8)
  assert_eq(form.field("flag"), Some("")) // bare key -> empty value
  assert_eq(form.field("q"), Some("a=b")) // %3D -> '='
  assert_eq(form.field("absent"), None)
  assert_eq(form.files.length(), 0)
}

///|
test "urlencoded form: a repeated field is surfaced as a list" {
  let body = @utf8.encode("tag=a&tag=b&tag=c")
  let ctx : Context = {
    request: mkreq_ct("POST", "application/x-www-form-urlencoded", body),
    params: Map([]),
  }
  assert_eq(ctx.form().field_all("tag"), ["a", "b", "c"])
  // field() returns the first.
  assert_eq(ctx.form().field("tag"), Some("a"))
}

///|
/// Build a multipart/form-data body: one text field, then one file part whose
/// content is arbitrary bytes (including CRLF and a non-UTF-8 byte).
fn build_multipart(boundary : String, file_bytes : Bytes) -> Bytes {
  let buf = Buffer()
  wline(buf, "--" + boundary)
  wline(buf, "Content-Disposition: form-data; name=\"greeting\"")
  wline(buf, "")
  wline(buf, "hello world")
  wline(buf, "--" + boundary)
  wline(
    buf, "Content-Disposition: form-data; name=\"upload\"; filename=\"note.bin\"",
  )
  wline(buf, "Content-Type: application/octet-stream")
  wline(buf, "")
  buf.write_bytes(file_bytes[:])
  buf.write_bytes(b"\r\n")
  wline(buf, "--" + boundary + "--")
  buf.to_bytes()
}

///|
test "multipart round-trip: a text field and a binary file part" {
  let boundary = "----moonapiBoundaryAbc123"
  let file_bytes = b"\x00\x01line1\r\nline2\xff\xfeEND"
  let body = build_multipart(boundary, file_bytes)
  let ctx : Context = {
    request: mkreq_ct("POST", "multipart/form-data; boundary=" + boundary, body),
    params: Map([]),
  }
  let form = ctx.form()
  // The text field parsed apart from the file.
  assert_eq(form.field("greeting"), Some("hello world"))
  assert_eq(form.fields.length(), 1)
  // The file part: name, filename, content-type, and byte-exact content.
  let file = form.file("upload").unwrap()
  assert_eq(file.name, "upload")
  assert_eq(file.filename, "note.bin")
  assert_eq(file.content_type, "application/octet-stream")
  assert_eq(file.content == file_bytes, true)
  assert_eq(form.files.length(), 1)
}

///|
test "multipart: a quoted boundary in the content-type is honoured" {
  let boundary = "SimpleBoundary"
  let body = build_multipart(boundary, b"data")
  let ctx : Context = {
    request: mkreq_ct(
      "POST",
      "multipart/form-data; boundary=\"" + boundary + "\"",
      body,
    ),
    params: Map([]),
  }
  assert_eq(ctx.form().file("upload").unwrap().content == b"data", true)
}

///|
test "multipart: two file parts under distinct names both round-trip" {
  let boundary = "B0undary"
  let buf = Buffer()
  wline(buf, "--" + boundary)
  wline(buf, "Content-Disposition: form-data; name=\"a\"; filename=\"a.txt\"")
  wline(buf, "")
  buf.write_bytes(b"alpha")
  buf.write_bytes(b"\r\n")
  wline(buf, "--" + boundary)
  wline(buf, "Content-Disposition: form-data; name=\"b\"; filename=\"b.txt\"")
  wline(buf, "")
  buf.write_bytes(b"beta")
  buf.write_bytes(b"\r\n")
  wline(buf, "--" + boundary + "--")
  let ctx : Context = {
    request: mkreq_ct(
      "POST",
      "multipart/form-data; boundary=" + boundary,
      buf.to_bytes(),
    ),
    params: Map([]),
  }
  let form = ctx.form()
  assert_eq(form.files.length(), 2)
  assert_eq(form.file("a").unwrap().content == b"alpha", true)
  assert_eq(form.file("b").unwrap().content == b"beta", true)
}

///|
test "form: a non-form content type yields an empty form, no crash" {
  let ctx : Context = {
    request: mkreq_ct("POST", "application/json", b"{\"a\":1}"),
    params: Map([]),
  }
  let form = ctx.form()
  assert_eq(form.fields.length(), 0)
  assert_eq(form.files.length(), 0)
}
