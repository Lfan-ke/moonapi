///|
/// An RSA public key: modulus `n` and public exponent `e` (RFC 8017). The RS256
/// verification key. Core's `BigInt` carries the modular arithmetic, so the
/// signature scheme is a straight transcription of PKCS#1 v1.5 with no vendored C.
pub(all) struct RsaPublicKey {
  n : BigInt
  e : BigInt
}

///|
/// An RSA private key: modulus `n`, public exponent `e`, and private exponent `d`
/// (the CRT parameters are not needed for the plain `m^d mod n` path). The RS256
/// signing key.
pub(all) struct RsaPrivateKey {
  n : BigInt
  e : BigInt
  d : BigInt
}

///|
/// Build a public key from hex-encoded modulus and exponent — e.g. openssl's
/// `rsa -modulus` output and `10001`.
pub fn RsaPublicKey::from_hex(n_hex : String, e_hex : String) -> RsaPublicKey {
  {
    n: BigInt::from_string(n_hex, radix=16),
    e: BigInt::from_string(e_hex, radix=16),
  }
}

///|
/// Build a private key from hex-encoded modulus, public exponent, and private
/// exponent.
pub fn RsaPrivateKey::from_hex(
  n_hex : String,
  e_hex : String,
  d_hex : String,
) -> RsaPrivateKey {
  {
    n: BigInt::from_string(n_hex, radix=16),
    e: BigInt::from_string(e_hex, radix=16),
    d: BigInt::from_string(d_hex, radix=16),
  }
}

///|
/// The public half of a private key — for verifying what it signs.
pub fn RsaPrivateKey::public_key(self : RsaPrivateKey) -> RsaPublicKey {
  { n: self.n, e: self.e, }
}

///|
/// The modulus size in octets: the width of an RSA signature and of the encoded
/// message block.
fn modulus_len(n : BigInt) -> Int {
  n.to_octets().length()
}

///|
/// The ASN.1 DER `DigestInfo` prefix for a SHA-256 digest (RFC 8017 §9.2): the
/// `id-sha256` `AlgorithmIdentifier` followed by the `OCTET STRING` header for the
/// 32-byte hash.
let sha256_digest_prefix : Bytes = b"\x30\x31\x30\x0d\x06\x09\x60\x86\x48\x01\x65\x03\x04\x02\x01\x05\x00\x04\x20"

///|
/// EMSA-PKCS1-v1_5 encode `msg`'s SHA-256 digest to `em_len` octets (RFC 8017
/// §9.2): `0x00 || 0x01 || PS || 0x00 || DigestInfo(H(msg))`, where `PS` is a run
/// of `0xFF` filling the block. This is the exact block RS256 signs over.
fn emsa_pkcs1_v15_sha256(msg : Bytes, em_len : Int) -> Bytes {
  let digest = sha256(msg)
  let t_len = sha256_digest_prefix.length() + digest.length()
  let ps_len = em_len - t_len - 3
  let em = Buffer()
  em.write_byte(b'\x00')
  em.write_byte(b'\x01')
  for _i in 0..<ps_len {
    em.write_byte(b'\xff')
  }
  em.write_byte(b'\x00')
  em.write_bytes(sha256_digest_prefix[:])
  em.write_bytes(digest[:])
  em.to_bytes()
}

///|
/// RSASSA-PKCS1-v1_5 sign with SHA-256 — the RS256 signing primitive (RFC 8017
/// §8.2.1): `s = EM^d mod n`, returned as a fixed-width big-endian octet string.
pub fn rsa_pkcs1_sha256_sign(msg : Bytes, key : RsaPrivateKey) -> Bytes {
  let em_len = modulus_len(key.n)
  let em = emsa_pkcs1_v15_sha256(msg, em_len)
  let m = BigInt::from_octets(em[:])
  let s = m.pow(key.d, modulus=key.n)
  s.to_octets(length=em_len)
}

///|
/// RSASSA-PKCS1-v1_5 verify with SHA-256 — the RS256 verification primitive (RFC
/// 8017 §8.2.2): recover `m = s^e mod n` and compare it, in constant time, to the
/// expected EMSA-PKCS1-v1_5 encoding of `msg`. Rejects a signature that is not the
/// modulus width or is `>= n`.
pub fn rsa_pkcs1_sha256_verify(
  msg : Bytes,
  sig : Bytes,
  key : RsaPublicKey,
) -> Bool {
  let em_len = modulus_len(key.n)
  if sig.length() != em_len {
    return false
  }
  let s = BigInt::from_octets(sig[:])
  if s >= key.n {
    return false
  }
  let m = s.pow(key.e, modulus=key.n)
  let em = m.to_octets(length=em_len)
  let expected = emsa_pkcs1_v15_sha256(msg, em_len)
  constant_time_eq(em, expected)
}
