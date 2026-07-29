// A real RSA-2048 key and an RS256 signature generated with OpenSSL 3.2.4
// (`openssl genrsa 2048` + `dgst -sha256 -sign`), so these tests prove
// interoperability with a reference implementation, not just internal
// self-consistency. RSASSA-PKCS1-v1_5 is deterministic, so a correct signer
// reproduces OpenSSL's signature byte for byte.

///|
let rsa_n : String = "9245436da53d54a3b5730ca5813f4fa59ca3a706abaad3e8262f5cc7f96eda451945c10324bccc7f9c40f7510154d8133fbc5cffa2f46b0276674b5f9d6a22dd5371a11468f9f0b54c38025d14cb1124bdb0fbc8bb59cabc6adf784eb7879ddd375e86ae9cd4dca5a8365d7505f28e9382cfe8762efb248e9a2cc113753c37aea7eb72fe6e5004a72b4f28bf8b43f92e7fba3a84882ec3bba2f71e180d110e33d668e5c08dbb35db9f73e70430fec32a6fcb05b793e49f69509e9a4b84e355182fa355fb70fd5504fe7b46a6b7159a2f3f5c1ba2375499ad734c4e0b752a0cabdd860d9701ea232cd0cf038198b284096cf7b0cb30e2e00f13db9c520f7fcabf"

///|
let rsa_e : String = "10001"

///|
let rsa_d : String = "2991979d1485be851bef0b5c09c4355d6a8bb3cf18805ee2addf6dedc2fc76f9863a25a5400e8bcb845b8e2dae442f7820f7e6321c5c7c00e2276eeb48703e6249f1940699e2d63e9fdf97045f016ae8d723f21a54ec2acaab50c0ff15f76baccfac84782147f940f6f224533a927964809b9783e6cc26d2840c4dfebaa59769145ac67739eada17fac461791fabf4694ecb3efeb781c50530ff999f28608bb9a9f1a31da1cad07920fbb72c4fe843301003b694059c8edf443f23f50c1e9804e44693547beead7ec512f064f7b266fd4cfff5e65d940b9839a2f30e6532657e67d1c8e405f20385b21c3dacce582027310ceb085db0382866961906a2c9b8d9"

///|
let rsa_signing_input : String = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Im1vb25hcGkiLCJhZG1pbiI6dHJ1ZX0"

///|
let rsa_openssl_sig : String = "ht-aWm8mVHKSBIFcbe0MkguhBlL842jKhzgG_s77SoPnjLaUsnqYKBgn7MW5p9QkqrTJrEB2kC-7Q6LNF8125DdS81MgUJ50UDHrlDhZXLZRQfFm7196DxJQsTvHX7flytMuwBSQZrr7FL45QSBzJBJlLcSQqokqBMecdbbCAuCQpte3Q-hdzukVAADtHT6aGz00wGUyd9AV8SFeGwiQy_1sxiUv1CGzWJyUZmHOBCE1wml6HHo_ZS56rW7pgCTA9MDd9u2xGTfghafTfhmPHaj_D--6dA7ZwbBsiFDEeXr_nxA5f4qsNP-f9nUbLSeAj1aEhPKQbIfKIewjJn4nzQ"

///|
test "RS256 verifies an OpenSSL-produced signature (interop)" {
  let pub_key = RsaPublicKey::from_hex(rsa_n, rsa_e)
  let sig = base64url_decode(rsa_openssl_sig)
  assert_true(
    rsa_pkcs1_sha256_verify(@utf8.encode(rsa_signing_input), sig, pub_key),
  )
}

///|
test "RS256 reproduces OpenSSL's exact signature (deterministic PKCS#1 v1.5)" {
  let priv_key = RsaPrivateKey::from_hex(rsa_n, rsa_e, rsa_d)
  let sig = rsa_pkcs1_sha256_sign(@utf8.encode(rsa_signing_input), priv_key)
  assert_eq(base64url_encode(sig), rsa_openssl_sig)
}

///|
test "RS256 rejects a tampered message and a tampered signature" {
  let pub_key = RsaPublicKey::from_hex(rsa_n, rsa_e)
  let sig = base64url_decode(rsa_openssl_sig)
  // The signature is valid only for the exact signing input.
  assert_false(
    rsa_pkcs1_sha256_verify(@utf8.encode(rsa_signing_input + "x"), sig, pub_key),
  )
  // Flip the last signature byte -> no longer verifies.
  let buf = Buffer()
  buf.write_bytes(sig[:sig.length() - 1])
  buf.write_byte((sig[sig.length() - 1].to_int() ^ 1).to_byte())
  assert_false(
    rsa_pkcs1_sha256_verify(
      @utf8.encode(rsa_signing_input),
      buf.to_bytes(),
      pub_key,
    ),
  )
}

///|
test "jwt_sign_rs256 / jwt_verify_rs256 round-trip, and reject tampering + alg downgrade" {
  let priv_key = RsaPrivateKey::from_hex(rsa_n, rsa_e, rsa_d)
  let claims : Map[String, Json] = Map([
    ("sub", "42".to_json()),
    ("scope", "admin".to_json()),
  ])
  let token = jwt_sign_rs256(claims, priv_key)
  let got = jwt_verify_rs256(token, priv_key.public_key(), 0) catch {
    _ => fail("jwt_verify_rs256 unexpectedly raised")
  }
  assert_eq(got.get("sub"), Some("42".to_json()))

  // A tampered token fails at BadSignature.
  let tampered_rejected = try {
    jwt_verify_rs256(token + "x", priv_key.public_key(), 0) |> ignore
    false
  } catch {
    BadSignature => true
    _ => false
  }
  assert_true(tampered_rejected)

  // An HS256 token is refused by the RS256 verifier (no alg downgrade).
  let hs = jwt_sign(claims, "secret")
  let downgrade_refused = try {
    jwt_verify_rs256(hs, priv_key.public_key(), 0) |> ignore
    false
  } catch {
    UnsupportedAlg(_) => true
    _ => false
  }
  assert_true(downgrade_refused)
}
