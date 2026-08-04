///|
/// Read the `sub` claim as a string.
fn sub_of(claims : Map[String, Json]) -> String {
  match claims.get("sub") {
    Some(String(s)) => s
    _ => "?"
  }
}

///|
/// JWT signing across all four algorithm families the library ships:
/// `jwt_sign` / `jwt_verify` (HS256, symmetric) plus the asymmetric
/// `jwt_sign_rs256` (RSA), `jwt_sign_es256` (ECDSA P-256), and `jwt_sign_eddsa`
/// (Ed25519), each round-tripped through its own verifier with keys built from
/// hex. It also shows the two rejections that make a verifier safe: a tampered
/// token fails at `BadSignature`, and presenting an HS256 token to the RS256
/// verifier is refused as an `alg` downgrade (`UnsupportedAlg`).
///
///     moon run examples/20-jwt-signing
#coverage.skip
fn main {
  let claims : Map[String, Json] = Map([
    ("sub", "lfanke".to_json()),
    ("name", "heke1228".to_json()),
  ])

  // HS256 — the symmetric, shared-secret path.
  let secret = "moonapi-hs256-secret"
  let hs = @moonapi.jwt_sign(claims, secret)
  let hs_claims = @moonapi.jwt_verify(hs, secret, 0L) catch { _ => Map([]) }
  println(
    "HS256:  verified sub=\{sub_of(hs_claims)} (token \{hs.length()} chars)",
  )

  // A tampered token fails the signature check.
  let tampered = try {
    @moonapi.jwt_verify(hs + "x", secret, 0L) |> ignore
    "accepted (bug!)"
  } catch {
    BadSignature => "BadSignature"
    _ => "other JwtError"
  }
  println("HS256:  tampered token -> \{tampered}")

  // RS256 — RSASSA-PKCS1-v1_5 over a 2048-bit RSA key.
  let rsa_n = "9245436da53d54a3b5730ca5813f4fa59ca3a706abaad3e8262f5cc7f96eda451945c10324bccc7f9c40f7510154d8133fbc5cffa2f46b0276674b5f9d6a22dd5371a11468f9f0b54c38025d14cb1124bdb0fbc8bb59cabc6adf784eb7879ddd375e86ae9cd4dca5a8365d7505f28e9382cfe8762efb248e9a2cc113753c37aea7eb72fe6e5004a72b4f28bf8b43f92e7fba3a84882ec3bba2f71e180d110e33d668e5c08dbb35db9f73e70430fec32a6fcb05b793e49f69509e9a4b84e355182fa355fb70fd5504fe7b46a6b7159a2f3f5c1ba2375499ad734c4e0b752a0cabdd860d9701ea232cd0cf038198b284096cf7b0cb30e2e00f13db9c520f7fcabf"
  let rsa_e = "10001"
  let rsa_d = "2991979d1485be851bef0b5c09c4355d6a8bb3cf18805ee2addf6dedc2fc76f9863a25a5400e8bcb845b8e2dae442f7820f7e6321c5c7c00e2276eeb48703e6249f1940699e2d63e9fdf97045f016ae8d723f21a54ec2acaab50c0ff15f76baccfac84782147f940f6f224533a927964809b9783e6cc26d2840c4dfebaa59769145ac67739eada17fac461791fabf4694ecb3efeb781c50530ff999f28608bb9a9f1a31da1cad07920fbb72c4fe843301003b694059c8edf443f23f50c1e9804e44693547beead7ec512f064f7b266fd4cfff5e65d940b9839a2f30e6532657e67d1c8e405f20385b21c3dacce582027310ceb085db0382866961906a2c9b8d9"
  let rsa_priv = @moonapi.RsaPrivateKey::from_hex(rsa_n, rsa_e, rsa_d)
  let rs = @moonapi.jwt_sign_rs256(claims, rsa_priv)
  let rs_claims = @moonapi.jwt_verify_rs256(rs, rsa_priv.public_key(), 0L) catch {
    _ => Map([])
  }
  println("RS256:  verified sub=\{sub_of(rs_claims)}")

  // ES256 — ECDSA on P-256 with the deterministic RFC 6979 nonce.
  let ec_priv = @moonapi.EcdsaPrivateKey::from_hex(
    "C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721",
  )
  let es = @moonapi.jwt_sign_es256(claims, ec_priv)
  let es_claims = @moonapi.jwt_verify_es256(es, ec_priv.public_key(), 0L) catch {
    _ => Map([])
  }
  println("ES256:  verified sub=\{sub_of(es_claims)}")

  // EdDSA — Ed25519 (RFC 8032 TEST 1 seed).
  let ed_priv = @moonapi.Ed25519PrivateKey::from_hex(
    "9d61b19deffebc3ba25c9b06e1de56e3d33a4bee1240c74c81a4d81e0e11a800",
  )
  let ed = @moonapi.jwt_sign_eddsa(claims, ed_priv)
  let ed_claims = @moonapi.jwt_verify_eddsa(ed, ed_priv.public_key(), 0L) catch {
    _ => Map([])
  }
  println("EdDSA:  verified sub=\{sub_of(ed_claims)}")

  // The alg-downgrade refusal: an HS256 token handed to the RS256 verifier.
  let downgrade = try {
    @moonapi.jwt_verify_rs256(hs, rsa_priv.public_key(), 0L) |> ignore
    "accepted (bug!)"
  } catch {
    UnsupportedAlg(a) => "refused: UnsupportedAlg(\{a})"
    _ => "refused: other JwtError"
  }
  println("cross:  HS256 token via RS256 verifier -> \{downgrade}")
}
