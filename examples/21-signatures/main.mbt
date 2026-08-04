///|
/// The raw asymmetric signature primitives under the JWT `alg` families — the
/// self-built RSA / ECDSA / Ed25519 stack. Each key is built from hex
/// (`*PrivateKey::from_hex`, `*PublicKey::from_hex`), a message is signed
/// (`rsa_pkcs1_sha256_sign` / `ecdsa_p256_sha256_sign` / `ed25519_sign`) and
/// verified (`..._verify`), and a tampered message is rejected. The ECDSA leg
/// also checks the published RFC 7515 A.3 vector, so the verifier is pinned to a
/// known-good signature, not just its own output.
///
///     moon run examples/21-signatures
#coverage.skip
fn main {
  let msg = b"moonapi signs this payload"

  // Ed25519 (RFC 8032 TEST 1 seed and its derived public key).
  let ed_priv = @moonapi.Ed25519PrivateKey::from_hex(
    "9d61b19deffebc3ba25c9b06e1de56e3d33a4bee1240c74c81a4d81e0e11a800",
  )
  let ed_pub = @moonapi.Ed25519PublicKey::from_hex(
    "476f48bc6e0cd911f2ee956b8b44e6f16bbac9ded00d9a732741ef5ba55b780f",
  )
  // The public key derives from the seed two ways; they agree.
  let derived = @moonapi.ed25519_public_from_seed(ed_priv.seed)
  println("Ed25519: derived pubkey matches from_hex: \{derived == ed_pub.key}")
  let ed_sig = @moonapi.ed25519_sign(ed_priv.seed, msg)
  println(
    "Ed25519: verify=\{@moonapi.ed25519_verify(ed_pub.key, msg, ed_sig)} tamper=\{@moonapi.ed25519_verify(ed_pub.key, b"other", ed_sig)}",
  )

  // RSA (RSASSA-PKCS1-v1_5 + SHA-256) with a matched 2048-bit key pair.
  let rsa_n = "9245436da53d54a3b5730ca5813f4fa59ca3a706abaad3e8262f5cc7f96eda451945c10324bccc7f9c40f7510154d8133fbc5cffa2f46b0276674b5f9d6a22dd5371a11468f9f0b54c38025d14cb1124bdb0fbc8bb59cabc6adf784eb7879ddd375e86ae9cd4dca5a8365d7505f28e9382cfe8762efb248e9a2cc113753c37aea7eb72fe6e5004a72b4f28bf8b43f92e7fba3a84882ec3bba2f71e180d110e33d668e5c08dbb35db9f73e70430fec32a6fcb05b793e49f69509e9a4b84e355182fa355fb70fd5504fe7b46a6b7159a2f3f5c1ba2375499ad734c4e0b752a0cabdd860d9701ea232cd0cf038198b284096cf7b0cb30e2e00f13db9c520f7fcabf"
  let rsa_e = "10001"
  let rsa_d = "2991979d1485be851bef0b5c09c4355d6a8bb3cf18805ee2addf6dedc2fc76f9863a25a5400e8bcb845b8e2dae442f7820f7e6321c5c7c00e2276eeb48703e6249f1940699e2d63e9fdf97045f016ae8d723f21a54ec2acaab50c0ff15f76baccfac84782147f940f6f224533a927964809b9783e6cc26d2840c4dfebaa59769145ac67739eada17fac461791fabf4694ecb3efeb781c50530ff999f28608bb9a9f1a31da1cad07920fbb72c4fe843301003b694059c8edf443f23f50c1e9804e44693547beead7ec512f064f7b266fd4cfff5e65d940b9839a2f30e6532657e67d1c8e405f20385b21c3dacce582027310ceb085db0382866961906a2c9b8d9"
  let rsa_priv = @moonapi.RsaPrivateKey::from_hex(rsa_n, rsa_e, rsa_d)
  let rsa_pub = @moonapi.RsaPublicKey::from_hex(rsa_n, rsa_e)
  let rsa_sig = @moonapi.rsa_pkcs1_sha256_sign(msg, rsa_priv)
  println(
    "RSA:     verify=\{@moonapi.rsa_pkcs1_sha256_verify(msg, rsa_sig, rsa_pub)} tamper=\{@moonapi.rsa_pkcs1_sha256_verify(b"other", rsa_sig, rsa_pub)}",
  )

  // ECDSA P-256 + SHA-256, a self round-trip on the RFC 6979 test scalar.
  let ec_priv = @moonapi.EcdsaPrivateKey::from_hex(
    "C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721",
  )
  let ec_sig = @moonapi.ecdsa_p256_sha256_sign(msg, ec_priv)
  println(
    "ECDSA:   verify=\{@moonapi.ecdsa_p256_sha256_verify(msg, ec_sig, ec_priv.public_key())} tamper=\{@moonapi.ecdsa_p256_sha256_verify(b"other", ec_sig, ec_priv.public_key())}",
  )

  // And the published RFC 7515 A.3 ES256 vector, verified via a from_hex key.
  let a3_key = @moonapi.EcdsaPublicKey::from_hex(
    "5972f45e5118f3fb52b7dd7c7873092a92ab6837685f77b23355263ba36aca8a", "dc50f04477e9225c4ebe98779ce74e7e7e65f855d90ed6729b819e02df22e69e",
  )
  let a3_input = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Im1vb25hcGkifQ"
  let a3_sig = @moonapi.base64url_decode(
    "sPjSolSY_WYT1wKOFp4qEpMaiiGYMcKDN-uVa91nxGejScyY5ZMSV9iICzO1fdYqzrA8cwQEAFmHuvYT2ClKMg",
  )
  println(
    "ECDSA:   RFC 7515 A.3 vector verifies: \{@moonapi.ecdsa_p256_sha256_verify(@utf8.encode(a3_input), a3_sig, a3_key)}",
  )
}
