///|
/// NIST P-256 (secp256r1) parameters as big integers. `b` is not needed for
/// signature verification (which never evaluates the curve equation), so only the
/// field prime `p`, the coefficient `a` (= -3 mod p), the group order `n`, and the
/// generator `G` are carried. Core's `BigInt` supplies the modular arithmetic, so
/// the curve is a straight transcription with no vendored C.
/// Source: FIPS 186-4 / SEC 2.
let p256_p : BigInt = BigInt::from_string(
  "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF",
  radix=16,
)

///|
let p256_a : BigInt = BigInt::from_string(
  "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC",
  radix=16,
)

///|
let p256_n : BigInt = BigInt::from_string(
  "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551",
  radix=16,
)

///|
let p256_gx : BigInt = BigInt::from_string(
  "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296",
  radix=16,
)

///|
let p256_gy : BigInt = BigInt::from_string(
  "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5",
  radix=16,
)

///|
/// A point on P-256 in affine coordinates, plus the point at infinity (the group
/// identity).
priv struct EcPoint {
  x : BigInt
  y : BigInt
  infinity : Bool
}

///|
/// The point at infinity.
fn ec_zero() -> EcPoint {
  { x: 0, y: 0, infinity: true }
}

///|
/// Reduce mod the field prime, normalised to `[0, p)`.
fn fmod_p(a : BigInt) -> BigInt {
  let m = a % p256_p
  if m < (0 : BigInt) {
    m + p256_p
  } else {
    m
  }
}

///|
/// Reduce mod the group order, normalised to `[0, n)`.
fn fmod_n(a : BigInt) -> BigInt {
  let m = a % p256_n
  if m < (0 : BigInt) {
    m + p256_n
  } else {
    m
  }
}

///|
/// The modular inverse in the field (Fermat: a^(p-2) mod p).
fn inv_p(a : BigInt) -> BigInt {
  fmod_p(a).pow(p256_p - 2, modulus=p256_p)
}

///|
/// The modular inverse mod the group order (Fermat: a^(n-2) mod n).
fn inv_n(a : BigInt) -> BigInt {
  fmod_n(a).pow(p256_n - 2, modulus=p256_n)
}

///|
/// Double a point on P-256.
fn ec_double(pt : EcPoint) -> EcPoint {
  if pt.infinity || pt.y == (0 : BigInt) {
    return ec_zero()
  }
  let num = fmod_p(3 * pt.x * pt.x + p256_a)
  let lam = fmod_p(num * inv_p(2 * pt.y))
  let x3 = fmod_p(lam * lam - 2 * pt.x)
  let y3 = fmod_p(lam * (pt.x - x3) - pt.y)
  { x: x3, y: y3, infinity: false }
}

///|
/// Add two points on P-256.
fn ec_add(pa : EcPoint, pb : EcPoint) -> EcPoint {
  if pa.infinity {
    return pb
  }
  if pb.infinity {
    return pa
  }
  if pa.x == pb.x {
    if pa.y == pb.y {
      return ec_double(pa)
    }
    return ec_zero()
  }
  let lam = fmod_p((pb.y - pa.y) * inv_p(pb.x - pa.x))
  let x3 = fmod_p(lam * lam - pa.x - pb.x)
  let y3 = fmod_p(lam * (pa.x - x3) - pa.y)
  { x: x3, y: y3, infinity: false }
}

///|
/// Scalar multiplication `k * pt` by double-and-add.
fn ec_mul(k : BigInt, pt : EcPoint) -> EcPoint {
  let mut result = ec_zero()
  let mut addend = pt
  let mut kk = k
  while kk > (0 : BigInt) {
    if kk % 2 == (1 : BigInt) {
      result = ec_add(result, addend)
    }
    addend = ec_double(addend)
    kk = kk / 2
  }
  result
}

///|
/// An ECDSA P-256 public key: the curve point `(x, y)`. The ES256 verification
/// key.
pub(all) struct EcdsaPublicKey {
  x : BigInt
  y : BigInt
}

///|
/// Build a P-256 public key from the hex-encoded affine coordinates — e.g. the two
/// halves of openssl's uncompressed `pub` point after its `04` prefix.
pub fn EcdsaPublicKey::from_hex(
  x_hex : String,
  y_hex : String,
) -> EcdsaPublicKey {
  {
    x: BigInt::from_string(x_hex, radix=16),
    y: BigInt::from_string(y_hex, radix=16),
  }
}

///|
/// ECDSA P-256 verify with SHA-256 — the ES256 primitive (FIPS 186-4 §6.4.2).
/// `sig` is the raw `r || s` (two 32-byte big-endian integers), the encoding JWT
/// uses (not ASN.1 DER). Returns whether the signature is valid for `msg` under
/// `key`: `r`, `s` in range, then `u1·G + u2·Q` has x-coordinate `≡ r (mod n)`.
pub fn ecdsa_p256_sha256_verify(
  msg : Bytes,
  sig : Bytes,
  key : EcdsaPublicKey,
) -> Bool {
  if sig.length() != 64 {
    return false
  }
  let r = BigInt::from_octets(sig[0:32])
  let s = BigInt::from_octets(sig[32:64])
  if r < (1 : BigInt) || r >= p256_n || s < (1 : BigInt) || s >= p256_n {
    return false
  }
  let e = BigInt::from_octets(sha256(msg)[:])
  let w = inv_n(s)
  let u1 = fmod_n(e * w)
  let u2 = fmod_n(r * w)
  let g = { x: p256_gx, y: p256_gy, infinity: false }
  let q = { x: key.x, y: key.y, infinity: false }
  let point = ec_add(ec_mul(u1, g), ec_mul(u2, q))
  if point.infinity {
    return false
  }
  fmod_n(point.x) == r
}
