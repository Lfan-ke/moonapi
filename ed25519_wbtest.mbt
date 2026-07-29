///|
/// Decode a hex string to bytes.
fn hexb(h : String) -> Bytes {
  let buf = Buffer()
  for i = 0; i < h.length(); i = i + 2 {
    let hi = hex_nibble(h[i].to_int())
    let lo = hex_nibble(h[i + 1].to_int())
    buf.write_byte(((hi << 4) | lo).to_byte())
  }
  buf.to_bytes()
}

///|
test "Ed25519 curve constants are self-consistent" {
  // p = 2^255 - 19, and d = -121665 / 121666 mod p — cross-checked independently
  // of their hardcoded hex, so a transcription typo cannot slip through.
  assert_true(ed_p == ed_2_255 - 19)
  assert_true(ed_d == edmod((ed_p - 121665) * edinv(121666)))
}

///|
test "Ed25519 verifies the RFC 8032 test vectors" {
  // TEST 1: empty message.
  assert_true(
    ed25519_verify(
      hexb("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"),
      b"",
      hexb(
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
      ),
    ),
  )
  // TEST 3: message 0xaf82.
  assert_true(
    ed25519_verify(
      hexb("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"),
      b"\xaf\x82",
      hexb(
        "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
      ),
    ),
  )
  // Tamper the message -> reject.
  assert_false(
    ed25519_verify(
      hexb("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"),
      b"x",
      hexb(
        "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
      ),
    ),
  )
}

///|
test "jwt_verify_eddsa accepts an Ed25519 token and refuses an alg downgrade" {
  let key = Ed25519PublicKey::from_hex(
    "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
  )
  // A real EdDSA JWT signed with the matching Ed25519 key (payload {"sub":"42"}).
  let token = "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiJ9.EitmEz7OHUvbI6btyx4HMZTnXX3mAHUohPlaegodtCruZXtWibfaE8DZTEI8Txubf5SgAiM6JxBSkmY1evpsBw"
  let claims = jwt_verify_eddsa(token, key, 0) catch {
    _ => fail("jwt_verify_eddsa unexpectedly raised")
  }
  assert_eq(claims.get("sub"), Some("42".to_json()))
  // An HS256 token is refused by the EdDSA verifier.
  let hs = jwt_sign(Map([("sub", "1".to_json())]), "secret")
  let refused = try {
    jwt_verify_eddsa(hs, key, 0) |> ignore
    false
  } catch {
    UnsupportedAlg(_) => true
    _ => false
  }
  assert_true(refused)
}
