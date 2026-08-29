///|
/// Edwards25519 curve parameters as big integers (RFC 8032). `p = 2^255 - 19` is
/// the field prime, `d` the curve coefficient, `l` the group order, `sqrt_m1` a
/// square root of -1 (for point decompression, since `p ≡ 5 (mod 8)`), and
/// `(bx, by)` the base point. Core's `BigInt` supplies the arithmetic; the values
/// were computed from the definition, not transcribed.
let ed_p : BigInt = BigInt::from_string(
  "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED",
  radix=16,
)

///|
let ed_d : BigInt = BigInt::from_string(
  "52036CEE2B6FFE738CC740797779E89800700A4D4141D8AB75EB4DCA135978A3",
  radix=16,
)

///|
let ed_l : BigInt = BigInt::from_string(
  "1000000000000000000000000000000014DEF9DEA2F79CD65812631A5CF5D3ED",
  radix=16,
)

///|
let ed_sqrt_m1 : BigInt = BigInt::from_string(
  "2B8324804FC1DF0B2B4D00993DFBD7A72F431806AD2FE478C4EE1B274A0EA0B0",
  radix=16,
)

///|
let ed_bx : BigInt = BigInt::from_string(
  "216936D3CD6E53FEC0A4E231FDD6DC5C692CC7609525A7B2C9562D608F25D51A",
  radix=16,
)

///|
let ed_by : BigInt = BigInt::from_string(
  "6666666666666666666666666666666666666666666666666666666666666658",
  radix=16,
)

///|
/// 2^255, for masking off a compressed point's sign bit.
let ed_2_255 : BigInt = BigInt::from_string(
  "8000000000000000000000000000000000000000000000000000000000000000",
  radix=16,
)

///|
/// A point on Edwards25519 in affine coordinates. The addition law is complete
/// (identity `(0, 1)`, no special cases), so no infinity flag is needed.
priv struct EdPoint {
  x : BigInt
  y : BigInt
}

///|
/// Reduce mod the field prime, normalised to `[0, p)`.
fn edmod(a : BigInt) -> BigInt {
  let m = a % ed_p
  if m < (0 : BigInt) {
    m + ed_p
  } else {
    m
  }
}

///|
/// Reduce mod the group order, normalised to `[0, l)`.
fn edmod_l(a : BigInt) -> BigInt {
  let m = a % ed_l
  if m < (0 : BigInt) {
    m + ed_l
  } else {
    m
  }
}

///|
/// Field inverse (Fermat: a^(p-2) mod p).
fn edinv(a : BigInt) -> BigInt {
  edmod(a).pow(ed_p - 2, modulus=ed_p)
}

///|
/// Recover the `x` coordinate from `y` on Edwards25519: `x² = (y²-1)/(d·y²+1)`,
/// with the `p ≡ 5 (mod 8)` square root and the even root chosen.
fn ed_xrecover(y : BigInt) -> BigInt {
  let yy = edmod(y * y)
  let xx = edmod((yy - 1) * edinv(edmod(ed_d * yy + 1)))
  let mut x = xx.pow((ed_p + 3) / 8, modulus=ed_p)
  if edmod(x * x - xx) != (0 : BigInt) {
    x = edmod(x * ed_sqrt_m1)
  }
  if x % 2 != (0 : BigInt) {
    x = ed_p - x
  }
  x
}

///|
/// Edwards25519 point addition (complete twisted-Edwards law, a = -1).
fn ed_add(pp : EdPoint, qq : EdPoint) -> EdPoint {
  let x1 = pp.x
  let y1 = pp.y
  let x2 = qq.x
  let y2 = qq.y
  let dxy = edmod(ed_d * x1 * x2 * y1 * y2)
  let x3 = edmod((x1 * y2 + x2 * y1) * edinv(edmod(1 + dxy)))
  let y3 = edmod((y1 * y2 + x1 * x2) * edinv(edmod(1 - dxy)))
  { x: x3, y: y3, }
}

///|
/// Scalar multiplication `e · pt` by double-and-add.
fn ed_mul(e : BigInt, pt : EdPoint) -> EdPoint {
  let mut result : EdPoint = { x: 0, y: 1, }
  let mut addend = pt
  let mut k = e
  while k > (0 : BigInt) {
    if k % 2 == (1 : BigInt) {
      result = ed_add(result, addend)
    }
    addend = ed_add(addend, addend)
    k = k / 2
  }
  result
}

///|
/// Interpret `b` as a little-endian unsigned integer (Ed25519's byte order).
fn ed_le_int(b : BytesView) -> BigInt {
  let buf = Buffer()
  for i = b.length() - 1; i >= 0; i = i - 1 {
    buf.write_byte(b[i])
  }
  BigInt::from_octets(buf.to_bytes()[:])
}

///|
/// Decompress a 32-byte little-endian Edwards25519 point: `y` is the low 255
/// bits, and the top bit selects the sign (parity) of `x`.
fn ed_decode_point(s : BytesView) -> EdPoint {
  let y = ed_le_int(s) % ed_2_255
  let mut x = ed_xrecover(y)
  let sign = (s[31].to_int() >> 7) & 1
  let parity = if x % 2 == (1 : BigInt) { 1 } else { 0 }
  if parity != sign {
    x = ed_p - x
  }
  { x, y, }
}

///|
/// Ed25519 signature verification (RFC 8032 §5.1.7). `sig` is the 64-byte
/// `R || S`, `pub_key` the 32-byte compressed public point. Checks `[S]B = R +
/// [k]A` with `k = SHA-512(R || A || M) mod l`.
pub fn ed25519_verify(pub_key : Bytes, msg : Bytes, sig : Bytes) -> Bool {
  if pub_key.length() != 32 || sig.length() != 64 {
    return false
  }
  let a_pt = ed_decode_point(pub_key[:])
  let r_pt = ed_decode_point(sig[0:32])
  let s = ed_le_int(sig[32:64])
  if s >= ed_l {
    return false
  }
  let hbuf = Buffer()
  hbuf.write_bytes(sig[0:32])
  hbuf.write_bytes(pub_key[:])
  hbuf.write_bytes(msg[:])
  let k = edmod_l(ed_le_int(sha512(hbuf.to_bytes())[:]))
  let lhs = ed_mul(s, { x: ed_bx, y: ed_by, })
  let rhs = ed_add(r_pt, ed_mul(k, a_pt))
  lhs.x == rhs.x && lhs.y == rhs.y
}

///|
/// Encode a point as its 32-byte little-endian compressed form (RFC 8032
/// §5.1.2): `y` in the low 255 bits, the parity of `x` in the top bit. The
/// inverse of `ed_decode_point`.
fn ed_encode_point(pt : EdPoint) -> Bytes {
  let be = edmod(pt.y).to_octets(length=32)
  let buf = Buffer()
  for i = 31; i >= 1; i = i - 1 {
    buf.write_byte(be[i])
  }
  let parity = if edmod(pt.x) % 2 == (1 : BigInt) { 0x80 } else { 0 }
  buf.write_byte((be[0].to_int() | parity).to_byte())
  buf.to_bytes()
}

///|
/// A big integer as `length` little-endian bytes (Ed25519's byte order for the
/// signature scalar `S`).
fn ed_int_to_le(n : BigInt, length : Int) -> Bytes {
  let be = n.to_octets(length~)
  let buf = Buffer()
  for i = length - 1; i >= 0; i = i - 1 {
    buf.write_byte(be[i])
  }
  buf.to_bytes()
}

///|
/// Expand a 32-byte Ed25519 seed into its secret scalar and PRF prefix (RFC 8032
/// §5.1.5): `SHA-512(seed)`, the low 32 bytes clamped (`&= 0xF8`, top two bits
/// forced) as the little-endian scalar, the high 32 bytes as the prefix.
fn ed_expand_seed(seed : Bytes) -> (BigInt, Bytes) {
  let h = sha512(seed)
  let abuf = Buffer()
  abuf.write_byte((h[0].to_int() & 0xF8).to_byte())
  for i = 1; i < 31; i = i + 1 {
    abuf.write_byte(h[i])
  }
  abuf.write_byte(((h[31].to_int() & 0x7F) | 0x40).to_byte())
  let s = ed_le_int(abuf.to_bytes()[:])
  let pbuf = Buffer()
  for i = 32; i < 64; i = i + 1 {
    pbuf.write_byte(h[i])
  }
  (s, pbuf.to_bytes())
}

///|
/// Derive the 32-byte compressed public key `A = [s]B` from a 32-byte Ed25519
/// seed.
pub fn ed25519_public_from_seed(seed : Bytes) -> Bytes {
  let (s, _) = ed_expand_seed(seed)
  ed_encode_point(ed_mul(s, { x: ed_bx, y: ed_by, }))
}

///|
/// Ed25519 signing (RFC 8032 §5.1.6), deterministic. `seed` is the 32-byte
/// secret key. Returns the 64-byte `R || S` signature: `r = SHA-512(prefix || M)
/// mod l`, `R = [r]B`, `k = SHA-512(R || A || M) mod l`, `S = (r + k·s) mod l`.
pub fn ed25519_sign(seed : Bytes, msg : Bytes) -> Bytes {
  let (s, prefix) = ed_expand_seed(seed)
  let big_a = ed_encode_point(ed_mul(s, { x: ed_bx, y: ed_by, }))
  let rbuf = Buffer()
  rbuf.write_bytes(prefix)
  rbuf.write_bytes(msg)
  let r = edmod_l(ed_le_int(sha512(rbuf.to_bytes())[:]))
  let big_r = ed_encode_point(ed_mul(r, { x: ed_bx, y: ed_by, }))
  let kbuf = Buffer()
  kbuf.write_bytes(big_r)
  kbuf.write_bytes(big_a)
  kbuf.write_bytes(msg)
  let k = edmod_l(ed_le_int(sha512(kbuf.to_bytes())[:]))
  let s_scalar = edmod_l(r + k * s)
  let out = Buffer()
  out.write_bytes(big_r)
  out.write_bytes(ed_int_to_le(s_scalar, 32))
  out.to_bytes()
}

///|
/// An Ed25519 (EdDSA) public key: the 32-byte compressed point. The verification
/// key for the JWT `EdDSA` algorithm (RFC 8037).
pub(all) struct Ed25519PublicKey {
  key : Bytes
}

///|
/// Build an Ed25519 public key from its 32-byte hex encoding.
pub fn Ed25519PublicKey::from_hex(hex : String) -> Ed25519PublicKey {
  let buf = Buffer()
  for i = 0; i < hex.length(); i = i + 2 {
    let hi = hex_nibble(hex[i].to_int())
    let lo = hex_nibble(hex[i + 1].to_int())
    buf.write_byte(((hi << 4) | lo).to_byte())
  }
  { key: buf.to_bytes(), }
}

///|
/// An Ed25519 (EdDSA) private key: the 32-byte secret seed. The signing key for
/// the JWT `EdDSA` algorithm (RFC 8037).
pub(all) struct Ed25519PrivateKey {
  seed : Bytes
}

///|
/// Build an Ed25519 private key from its 32-byte seed in hex.
pub fn Ed25519PrivateKey::from_hex(hex : String) -> Ed25519PrivateKey {
  let buf = Buffer()
  for i = 0; i < hex.length(); i = i + 2 {
    let hi = hex_nibble(hex[i].to_int())
    let lo = hex_nibble(hex[i + 1].to_int())
    buf.write_byte(((hi << 4) | lo).to_byte())
  }
  { seed: buf.to_bytes(), }
}

///|
/// The public key matching this private key: `A = [s]B`.
pub fn Ed25519PrivateKey::public_key(
  self : Ed25519PrivateKey,
) -> Ed25519PublicKey {
  { key: ed25519_public_from_seed(self.seed), }
}

///|
/// A single hex digit's value, from its character code.
fn hex_nibble(v : Int) -> Int {
  if v >= 0x30 && v <= 0x39 {
    v - 0x30
  } else if v >= 0x61 && v <= 0x66 {
    v - 0x61 + 10
  } else if v >= 0x41 && v <= 0x46 {
    v - 0x41 + 10
  } else {
    0
  }
}
