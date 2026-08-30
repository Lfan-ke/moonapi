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
  let form = ctx.form().unwrap()
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
  assert_eq(ctx.form().unwrap().field_all("tag"), ["a", "b", "c"])
  // field() returns the first.
  assert_eq(ctx.form().unwrap().field("tag"), Some("a"))
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
  let form = ctx.form().unwrap()
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
  assert_eq(
    ctx.form().unwrap().file("upload").unwrap().content == b"data",
    true,
  )
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
  let form = ctx.form().unwrap()
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
  // An empty form, not a refusal: nothing was submitted, and nothing was denied.
  let form = ctx.form().unwrap()
  assert_eq(form.fields.length(), 0)
  assert_eq(form.files.length(), 0)
}

// -- limits and part metadata -------------------------------------------------

///|
/// A multipart body of `n` one-byte text fields — test helper.
fn multipart_fields(boundary : String, n : Int) -> Bytes {
  let buf = Buffer()
  for i = 0; i < n; i = i + 1 {
    wline(buf, "--" + boundary)
    wline(
      buf,
      "Content-Disposition: form-data; name=\"f" + i.to_string() + "\"",
    )
    wline(buf, "")
    wline(buf, "v")
  }
  wline(buf, "--" + boundary + "--")
  buf.to_bytes()
}

///|
/// A context over a multipart body under `boundary` — test helper.
fn multipart_ctx(boundary : String, body : Bytes) -> Context {
  {
    request: mkreq_ct("POST", "multipart/form-data; boundary=" + boundary, body),
    params: Map([]),
  }
}

///|
/// A context over an urlencoded body — test helper.
fn urlencoded_ctx(body : String) -> Context {
  {
    request: mkreq_ct(
      "POST",
      "application/x-www-form-urlencoded",
      @utf8.encode(body),
    ),
    params: Map([]),
  }
}

///|
/// The bound that matters: a body is refused for having too many parts, and the
/// refusal is `None` rather than a truncated form, so nothing downstream can act
/// on half a request.
test "multipart: a body over the part limit is refused" {
  let boundary = "qwq233"
  let limits = FormLimits::new(max_parts=3)
  let ctx = multipart_ctx(boundary, multipart_fields(boundary, 4))
  assert_eq(ctx.form(limits~) is None, true)
}

///|
/// Refused means over, not at: the limit is the number of parts allowed, so a
/// body of exactly that many still parses.
test "multipart: exactly the part limit is allowed" {
  let boundary = "qwq233"
  let limits = FormLimits::new(max_parts=3)
  let ctx = multipart_ctx(boundary, multipart_fields(boundary, 3))
  let form = ctx.form(limits~).unwrap()
  assert_eq(form.fields.length(), 3)
  assert_eq(form.field("f0"), Some("v"))
  assert_eq(form.field("f2"), Some("v"))
}

///|
/// A multipart body of one file part carrying exactly `content` — test helper,
/// so a size bound has only one part to be measured against.
fn multipart_one_file(boundary : String, content : Bytes) -> Bytes {
  let buf = Buffer()
  wline(buf, "--" + boundary)
  wline(buf, "Content-Disposition: form-data; name=\"up\"; filename=\"f.bin\"")
  wline(buf, "")
  buf.write_bytes(content[:])
  buf.write_bytes(b"\r\n")
  wline(buf, "--" + boundary + "--")
  buf.to_bytes()
}

///|
/// The other bound: one part may not be arbitrarily large, however few there
/// are. The part here is ten bytes, so nine refuses it and ten does not.
test "multipart: a part over the size limit is refused, at the limit is not" {
  let boundary = "hhh"
  let body = multipart_one_file(boundary, b"0123456789")
  assert_eq(
    multipart_ctx(boundary, body).form(limits=FormLimits::new(max_part_size=9))
    is None,
    true,
  )
  let form = multipart_ctx(boundary, body)
    .form(limits=FormLimits::new(max_part_size=10))
    .unwrap()
  assert_eq(form.file("up").unwrap().content, b"0123456789")
}

///|
/// A urlencoded pair costs a part the same way a multipart section does, and is
/// bounded the same way — otherwise the cheaper carrier would be the unbounded
/// one.
test "urlencoded: over the pair limit is refused, at the limit is not" {
  let limits = FormLimits::new(max_parts=2)
  assert_eq(urlencoded_ctx("a=1&b=2&c=3").form(limits~) is None, true)
  let form = urlencoded_ctx("a=1&b=2").form(limits~).unwrap()
  assert_eq(form.field("a"), Some("1"))
  assert_eq(form.field("b"), Some("2"))
}

///|
/// And a single enormous pair is refused on size, not only on count.
test "urlencoded: a pair over the size limit is refused" {
  let limits = FormLimits::new(max_part_size=8)
  assert_eq(urlencoded_ctx("name=heke1228").form(limits~) is None, true)
  assert_eq(urlencoded_ctx("name=qwq").form(limits~) is Some(_), true)
}

///|
/// The defaults are Starlette's, and they let an ordinary form through — a limit
/// that refused normal traffic would be a bug, not a defence.
test "form limits default to 1000 parts of 1 MiB" {
  let limits = FormLimits::new()
  assert_eq(limits.max_parts, 1000)
  assert_eq(limits.max_part_size, 1024 * 1024)
  let boundary = "emm"
  let ctx = multipart_ctx(boundary, multipart_fields(boundary, 50))
  assert_eq(ctx.form().unwrap().fields.length(), 50)
}

///|
/// `size` is derived from the bytes rather than stored beside them, so it cannot
/// disagree with what was uploaded.
test "UploadFile::size is the length of the content" {
  let boundary = "----moonapiBoundaryAbc123"
  let file_bytes = b"\x00\x01line1\r\nline2\xff\xfeEND"
  let ctx = multipart_ctx(boundary, build_multipart(boundary, file_bytes))
  let file = ctx.form().unwrap().file("upload").unwrap()
  assert_eq(file.size(), file_bytes.length())
  assert_eq(file.size(), file.content.length())
}

///|
/// A part carries headers beyond the two that are promoted to fields, and they
/// have to be readable — lowercased, in body order, and looked up by any casing.
test "UploadFile keeps the part's own headers" {
  let boundary = "B0undary"
  let buf = Buffer()
  wline(buf, "--" + boundary)
  wline(buf, "Content-Disposition: form-data; name=\"a\"; filename=\"a.txt\"")
  wline(buf, "Content-Type: text/plain")
  wline(buf, "X-Checksum: 23333")
  wline(buf, "")
  buf.write_bytes(b"alpha")
  buf.write_bytes(b"\r\n")
  wline(buf, "--" + boundary + "--")
  let ctx = multipart_ctx(boundary, buf.to_bytes())
  let file = ctx.form().unwrap().file("a").unwrap()
  assert_eq(file.headers.length(), 3)
  assert_eq(file.headers[0].0, "content-disposition")
  assert_eq(file.headers[1], ("content-type", "text/plain"))
  assert_eq(file.headers[2], ("x-checksum", "23333"))
  // Looked up by any casing, like every other header in the stack.
  assert_eq(file.header("X-Checksum"), Some("23333"))
  assert_eq(file.header("x-checksum"), Some("23333"))
  assert_eq(file.header("x-absent"), None)
}
