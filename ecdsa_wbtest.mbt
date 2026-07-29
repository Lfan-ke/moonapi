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

///|
/// The RFC 6979 Appendix A.2.5 P-256 key.
let rfc6979_d : String = "C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721"

///|
fn hexint(h : String) -> BigInt {
  BigInt::from_string(h, radix=16)
}

///|
test "ECDSA public key derivation d*G matches RFC 6979 A.2.5" {
  let pk = EcdsaPrivateKey::from_hex(rfc6979_d).public_key()
  assert_true(
    pk.x ==
    hexint("60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6"),
  )
  assert_true(
    pk.y ==
    hexint("7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299"),
  )
}

///|
test "ES256 deterministic signing reproduces the RFC 6979 A.2.5 vectors" {
  let key = EcdsaPrivateKey::from_hex(rfc6979_d)
  // message "sample"
  let s1 = ecdsa_p256_sha256_sign(b"sample", key)
  assert_true(
    BigInt::from_octets(s1[0:32]) ==
    hexint("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"),
  )
  assert_true(
    BigInt::from_octets(s1[32:64]) ==
    hexint("F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8"),
  )
  // message "test"
  let s2 = ecdsa_p256_sha256_sign(b"test", key)
  assert_true(
    BigInt::from_octets(s2[0:32]) ==
    hexint("F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367"),
  )
  assert_true(
    BigInt::from_octets(s2[32:64]) ==
    hexint("019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083"),
  )
}

///|
test "jwt_sign_es256 / jwt_verify_es256 round-trip through moonapi's own verifier" {
  let key = EcdsaPrivateKey::from_hex(rfc6979_d)
  let claims : Map[String, Json] = Map([("sub", "42".to_json())])
  let token = jwt_sign_es256(claims, key)
  let got = jwt_verify_es256(token, key.public_key(), 0) catch {
    _ => fail("round-trip verify raised")
  }
  assert_eq(got.get("sub"), Some("42".to_json()))
}
