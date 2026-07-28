///|
/// A Context wrapping a POST body, no params — test helper.
fn body_ctx(payload : String) -> Context {
  {
    request: mkreq_full("POST", "/greet", body=@utf8.encode(payload)),
    params: Map([]),
  }
}

///|
test "typed body: valid payload deserialises into the struct" {
  let ctx = body_ctx("{\"name\":\"ada\"}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(req) => assert_eq(req.name, "ada")
    Err(_) => assert_eq("expected Ok", "got Err")
  }
}

///|
test "typed body: missing required field -> located 422 errors" {
  let ctx = body_ctx("{}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      assert_eq(errs.length(), 1)
      assert_eq(errs[0].kind, "missing")
      assert_eq(errs[0].loc, ["body", "name"])
    }
  }
}

///|
test "typed body: wrong field type -> located 422 before deserialisation" {
  let ctx = body_ctx("{\"name\":5}")
  let r : Result[GreetReq, _] = ctx.body_validated(GreetReq::schema())
  match r {
    Ok(_) => assert_eq("expected Err", "got Ok")
    Err(errs) => {
      assert_eq(errs.length(), 1)
      assert_eq(errs[0].kind, "string_type")
      assert_eq(errs[0].loc, ["body", "name"])
    }
  }
}

///|
test "typed body: empty body -> missing, invalid JSON -> json_invalid" {
  let empty : Context = {
    request: mkreq_full("POST", "/greet"),
    params: Map([]),
  }
  match (empty.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Err(errs) => assert_eq(errs[0].kind, "missing")
    Ok(_) => assert_eq("expected Err", "got Ok")
  }
  let junk = body_ctx("{not json")
  match (junk.body_validated(GreetReq::schema()) : Result[GreetReq, _]) {
    Err(errs) => assert_eq(errs[0].kind, "json_invalid")
    Ok(_) => assert_eq("expected Err", "got Ok")
  }
}

///|
test "typed body: unchecked extractor is total, None on bad shape" {
  let ok = body_ctx("{\"name\":\"x\"}")
  assert_eq((ok.body() : GreetReq?).unwrap().name, "x")
  let bad = body_ctx("{\"name\":5}")
  assert_eq((bad.body() : GreetReq?) is None, true)
}

///|
test "DI: container provides a request-scoped value, None when unregistered" {
  let c : Container[Dep] = Container::new()
  c.provide("greeting", () => Greeting("Hi")) |> ignore
  let scope = c.open_scope()
  assert_eq(scope.get("greeting") == Some(Greeting("Hi")), true)
  assert_eq(scope.get("absent") is None, true)
  scope.close()
}

///|
test "DI: a dependency is built once per request scope (cached)" {
  let log : Array[String] = []
  let c : Container[Dep] = Container::new()
  c.provide("greeting", () => {
    log.push("built")
    Greeting("x")
  })
  |> ignore
  let scope = c.open_scope()
  let _ = scope.get("greeting")
  let _ = scope.get("greeting")
  scope.close()
  // Two resolutions, one factory call: the value was cached for the request.
  assert_eq(log.length(), 1)
}

///|
test "DI: dependency_overrides shadow the base provider, then restore" {
  let c : Container[Dep] = Container::new()
  c.provide("greeting", () => Greeting("Hello")) |> ignore
  let s1 = c.open_scope()
  assert_eq(s1.get("greeting") == Some(Greeting("Hello")), true)
  s1.close()
  c.override_("greeting", () => Greeting("Bonjour")) |> ignore
  let s2 = c.open_scope()
  assert_eq(s2.get("greeting") == Some(Greeting("Bonjour")), true)
  s2.close()
  c.clear_overrides()
  let s3 = c.open_scope()
  assert_eq(s3.get("greeting") == Some(Greeting("Hello")), true)
  s3.close()
}

///|
test "DI: yield-style teardown runs after the handler, LIFO" {
  let log : Array[String] = []
  let c : Container[Dep] = Container::new()
  c.provide(
    "a",
    () => {
      log.push("setup a")
      Greeting("a")
    },
    teardown=_v => log.push("teardown a"),
  )
  |> ignore
  c.provide(
    "b",
    () => {
      log.push("setup b")
      Greeting("b")
    },
    teardown=_v => log.push("teardown b"),
  )
  |> ignore
  let resp = c.run(scope => {
    let _ = scope.get("a")
    let _ = scope.get("b")
    text(200, "ok")
  })
  assert_eq(resp.status, 200)
  // Setups in resolution order; teardowns strictly after, in reverse (LIFO).
  assert_eq(log == ["setup a", "setup b", "teardown b", "teardown a"], true)
}

///|
test "greet route: dependency + validated body end to end, with override" {
  let c : Container[Dep] = Container::new()
  c.provide("greeting", () => Greeting("Hello")) |> ignore
  let app = greet_app(c)
  let ok = app.handle(
    mkreq_full("POST", "/greet", body=@utf8.encode("{\"name\":\"ada\"}")),
  )
  assert_eq(ok.status, 200)
  assert_eq(json_str(resp_json(ok), "message"), "Hello, ada")
  // dependency_overrides swaps the injected value without touching the route.
  c.override_("greeting", () => Greeting("Bonjour")) |> ignore
  let ok2 = app.handle(
    mkreq_full("POST", "/greet", body=@utf8.encode("{\"name\":\"ada\"}")),
  )
  assert_eq(json_str(resp_json(ok2), "message"), "Bonjour, ada")
  // A malformed body is rejected off the same descriptor with a 422.
  let bad = app.handle(mkreq_full("POST", "/greet", body=@utf8.encode("{}")))
  assert_eq(bad.status, 422)
  assert_eq(json_str(detail0(bad), "type"), "missing")
}
