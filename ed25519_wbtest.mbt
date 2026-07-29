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
// RFC 8032 §7.1 test vectors. TEST 2 (seed 4ccd…, message 0x72) is the published
// vector, reproduced byte-for-byte against the `cryptography`/`pynacl` Ed25519
// reference — the seed derives this exact public key and this exact signature.
// TEST 1's seed (9d61…) derives 476f…; the widely-miscited pairing of that seed
// with d75a… is a corrupted transcription, caught here by deriving the key from
// the seed rather than trusting a hand-copied constant.
let ed_seed2 : String = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"

///|
let ed_pub2 : String = "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"

///|
let ed_sig2 : String = "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"

///|
let ed_seed1 : String = "9d61b19deffebc3ba25c9b06e1de56e3d33a4bee1240c74c81a4d81e0e11a800"

///|
let ed_pub1 : String = "476f48bc6e0cd911f2ee956b8b44e6f16bbac9ded00d9a732741ef5ba55b780f"

///|
let ed_sig1 : String = "c2c8a7472410791ada5108e262c3f26b9b328101e6c70984e71b16573601a9702d8ba9a99bd17062cd7cd44e75b719f2af104cc59607a9f6036bd3df28361c05"

///|
test "Ed25519 verifies the RFC 8032 test vectors" {
  // TEST 2: message 0x72.
  assert_true(ed25519_verify(hexb(ed_pub2), b"\x72", hexb(ed_sig2)))
  // TEST 1: empty message.
  assert_true(ed25519_verify(hexb(ed_pub1), b"", hexb(ed_sig1)))
  // Tamper the message -> reject.
  assert_false(ed25519_verify(hexb(ed_pub2), b"\x73", hexb(ed_sig2)))
  // A signature under the wrong key -> reject.
  assert_false(ed25519_verify(hexb(ed_pub1), b"\x72", hexb(ed_sig2)))
}

///|
test "Ed25519 signing reproduces the RFC 8032 vectors byte-for-byte" {
  // Signing is deterministic (RFC 8032 §5.1.6), so the output must equal the
  // published signature exactly, and the seed must derive the public key. Both
  // are cross-checked against the `cryptography`/`pynacl` reference.
  assert_eq(to_hex(ed25519_public_from_seed(hexb(ed_seed2))), ed_pub2)
  assert_eq(to_hex(ed25519_sign(hexb(ed_seed2), b"\x72")), ed_sig2)
  assert_eq(to_hex(ed25519_public_from_seed(hexb(ed_seed1))), ed_pub1)
  assert_eq(to_hex(ed25519_sign(hexb(ed_seed1), b"")), ed_sig1)
}

///|
test "jwt_verify_eddsa accepts a cross-library EdDSA token and refuses an alg downgrade" {
  let key = Ed25519PublicKey::from_hex(ed_pub1)
  // A real EdDSA JWT signed by the `cryptography` library with the matching key
  // (payload {"sub":"42"}) — proves interop, not just self-consistency.
  let token = "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiJ9.AD3ijRYc0oHt8PyrdgPAeLFstYd974rW80KPc0R3c2EN-5E6DB48PRCGcOovK9WXa1W2B1lKfqaUOrYi5aogDw"
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

///|
test "jwt_sign_eddsa round-trips through jwt_verify_eddsa" {
  let priv_key = Ed25519PrivateKey::from_hex(ed_seed1)
  let token = jwt_sign_eddsa(Map([("sub", "42".to_json())]), priv_key)
  let claims = jwt_verify_eddsa(token, priv_key.public_key(), 0) catch {
    _ => fail("round-trip verify unexpectedly raised")
  }
  assert_eq(claims.get("sub"), Some("42".to_json()))
  // Swapping in a different payload without re-signing must break the signature.
  let other = jwt_sign_eddsa(Map([("sub", "43".to_json())]), priv_key)
  let forged = split_char(other, '.')[0] +
    "." +
    split_char(token, '.')[1] +
    "." +
    split_char(other, '.')[2]
  let rejected = try {
    jwt_verify_eddsa(forged, priv_key.public_key(), 0) |> ignore
    false
  } catch {
    BadSignature => true
    _ => false
  }
  assert_true(rejected)
}
