// A real P-256 key and an ES256 (raw r||s) signature generated with OpenSSL
// 3.2.4, so these tests prove interoperability with a reference implementation.
// Generated: openssl ecparam -name prime256v1 -genkey, dgst -sha256 -sign, DER
// r/s converted to the raw 64-byte JWS encoding.

///|
let es256_qx : String = "5972f45e5118f3fb52b7dd7c7873092a92ab6837685f77b23355263ba36aca8a"

///|
let es256_qy : String = "dc50f04477e9225c4ebe98779ce74e7e7e65f855d90ed6729b819e02df22e69e"

///|
let es256_signing_input : String = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Im1vb25hcGkifQ"

///|
let es256_sig : String = "sPjSolSY_WYT1wKOFp4qEpMaiiGYMcKDN-uVa91nxGejScyY5ZMSV9iICzO1fdYqzrA8cwQEAFmHuvYT2ClKMg"

///|
test "ES256 verifies an OpenSSL-produced signature (interop)" {
  let key = EcdsaPublicKey::from_hex(es256_qx, es256_qy)
  let sig = base64url_decode(es256_sig)
  assert_true(
    ecdsa_p256_sha256_verify(@utf8.encode(es256_signing_input), sig, key),
  )
}

///|
test "ES256 rejects a tampered message and a tampered signature" {
  let key = EcdsaPublicKey::from_hex(es256_qx, es256_qy)
  let sig = base64url_decode(es256_sig)
  assert_false(
    ecdsa_p256_sha256_verify(@utf8.encode(es256_signing_input + "x"), sig, key),
  )
  // Flip the last byte of s -> no longer a valid signature.
  let buf = Buffer()
  buf.write_bytes(sig[:sig.length() - 1])
  buf.write_byte((sig[sig.length() - 1].to_int() ^ 1).to_byte())
  assert_false(
    ecdsa_p256_sha256_verify(
      @utf8.encode(es256_signing_input),
      buf.to_bytes(),
      key,
    ),
  )
}

///|
test "jwt_verify_es256 accepts a real ES256 token and refuses an alg downgrade" {
  let token = es256_signing_input + "." + es256_sig
  let key = EcdsaPublicKey::from_hex(es256_qx, es256_qy)
  let claims = jwt_verify_es256(token, key, 0) catch {
    _ => fail("jwt_verify_es256 unexpectedly raised")
  }
  assert_eq(claims.get("name"), Some("moonapi".to_json()))
  // An HS256 token is refused by the ES256 verifier.
  let hs = jwt_sign(Map([("sub", "1".to_json())]), "secret")
  let refused = try {
    jwt_verify_es256(hs, key, 0) |> ignore
    false
  } catch {
    UnsupportedAlg(_) => true
    _ => false
  }
  assert_true(refused)
}
