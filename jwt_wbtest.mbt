///|
/// A claims map from `(key, json)` pairs — test helper.
fn claims(pairs : Array[(String, Json)]) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  for p in pairs {
    m[p.0] = p.1
  }
  m
}

///|
test "base64url round-trips arbitrary bytes without padding" {
  let raw = b"\x00\x01\x02hello\xff\xfe"
  assert_eq(base64url_decode(base64url_encode(raw)) == raw, true)
  // No '+' '/' '=' in the alphabet.
  let enc = base64url_encode(b"\xfb\xff\xbf")
  for i = 0; i < enc.length(); i = i + 1 {
    let c = enc[i]
    assert_eq(c == '+' || c == '/' || c == '=', false)
  }
}

///|
test "jwt sign then verify returns the claims" {
  let secret = "s3cr3t"
  let token = jwt_sign(claims([("sub", "alice".to_json())]), secret)
  let got = jwt_verify(token, secret, 0L)
  assert_eq(got.get("sub"), Some("alice".to_json()))
}

///|
test "jwt verify rejects a tampered payload with BadSignature" {
  let secret = "s3cr3t"
  let token = jwt_sign(claims([("sub", "alice".to_json())]), secret)
  // Flip the payload segment to another value; the signature no longer matches.
  let parts = split_char(token, '.')
  let forged_payload = base64url_encode(@utf8.encode("{\"sub\":\"attacker\"}"))
  let forged = parts[0] + "." + forged_payload + "." + parts[2]
  let outcome = try {
    let _ = jwt_verify(forged, secret, 0L)
    "accepted"
  } catch {
    BadSignature => "bad_signature"
    _ => "other_error"
  }
  assert_eq(outcome, "bad_signature")
}

///|
test "jwt verify rejects the wrong secret" {
  let token = jwt_sign(claims([("sub", "alice".to_json())]), "right")
  let outcome = try {
    let _ = jwt_verify(token, "wrong", 0L)
    "accepted"
  } catch {
    BadSignature => "bad_signature"
    _ => "other"
  }
  assert_eq(outcome, "bad_signature")
}

///|
test "jwt verify enforces exp (expired) and nbf (not yet valid)" {
  let secret = "k"
  let expiring = jwt_sign(
    claims([("sub", "a".to_json()), ("exp", 100L.to_json())]),
    secret,
  )
  // exp is 100; at t=100 it's expired (>=), at t=99 it's still valid.
  assert_eq(jwt_verify(expiring, secret, 99L).get("sub"), Some("a".to_json()))
  let exp_outcome = try {
    let _ = jwt_verify(expiring, secret, 100L)
    "accepted"
  } catch {
    Expired => "expired"
    _ => "other"
  }
  assert_eq(exp_outcome, "expired")
  let future = jwt_sign(
    claims([("sub", "a".to_json()), ("nbf", 50L.to_json())]),
    secret,
  )
  let nbf_outcome = try {
    let _ = jwt_verify(future, secret, 49L)
    "accepted"
  } catch {
    NotYetValid => "not_yet"
    _ => "other"
  }
  assert_eq(nbf_outcome, "not_yet")
  assert_eq(jwt_verify(future, secret, 50L).get("sub"), Some("a".to_json()))
}

///|
test "jwt verify refuses the alg:none downgrade" {
  let header = base64url_encode(
    @utf8.encode("{\"alg\":\"none\",\"typ\":\"JWT\"}"),
  )
  let payload = base64url_encode(@utf8.encode("{\"sub\":\"alice\"}"))
  let token = header + "." + payload + "."
  let outcome = try {
    let _ = jwt_verify(token, "k", 0L)
    "accepted"
  } catch {
    UnsupportedAlg(_) => "unsupported_alg"
    _ => "other"
  }
  assert_eq(outcome, "unsupported_alg")
}

///|
test "jwt verify rejects a token without three segments" {
  let outcome = try {
    let _ = jwt_verify("only.two", "k", 0L)
    "accepted"
  } catch {
    MalformedToken(_) => "malformed"
    _ => "other"
  }
  assert_eq(outcome, "malformed")
}
