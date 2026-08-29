///|
/// The self-built cryptographic primitives under the JWT layer. `sha256` and
/// `sha512` hash, `hmac_sha256` keys a MAC (both checked here against published
/// vectors), `constant_time_eq` compares digests without an early-exit timing
/// leak, and `base64url_encode` / `base64url_decode` are the no-padding alphabet
/// JWT segments use — shown round-tripping a digest.
///
///     moon run examples/19-crypto
#coverage.skip
fn main {
  // SHA-256 against the NIST "abc" vector.
  let d256 = @moonapi.sha256(b"abc")
  println("sha256(\"abc\")   = \{to_hex(d256)}")
  println(
    "  matches NIST vector: \{to_hex(d256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"}",
  )

  // SHA-512 against the NIST "abc" vector.
  let d512 = @moonapi.sha512(b"abc")
  println("sha512(\"abc\")   = \{to_hex(d512)}")
  println(
    "  matches NIST vector: \{to_hex(d512) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"}",
  )

  // HMAC-SHA256 against RFC 4231 test case 1 (key = 20 * 0x0b, "Hi There").
  let key = b"\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b\x0b"
  let mac = @moonapi.hmac_sha256(key, b"Hi There")
  println("hmac_sha256     = \{to_hex(mac)}")
  println(
    "  matches RFC 4231 case 1: \{to_hex(mac) == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"}",
  )

  // Constant-time comparison: equal to itself, unequal to a different digest.
  println(
    "constant_time_eq(sha256 abc, sha256 abc) = \{@moonapi.constant_time_eq(d256, @moonapi.sha256(b"abc"))}",
  )
  println(
    "constant_time_eq(sha256 abc, sha256 abd) = \{@moonapi.constant_time_eq(d256, @moonapi.sha256(b"abd"))}",
  )

  // base64url round-trip (no padding), the JWT segment alphabet.
  let encoded = @moonapi.base64url_encode(d256)
  let decoded = @moonapi.base64url_decode(encoded)
  println("base64url(sha256 abc) = \{encoded}")
  println(
    "  decodes back to the digest: \{@moonapi.constant_time_eq(decoded, d256)}",
  )
}

///|
/// Lower-case hex of a byte string.
fn to_hex(b : Bytes) -> String {
  let hex = "0123456789abcdef"
  let sb = StringBuilder()
  for i = 0; i < b.length(); i = i + 1 {
    let v = b[i].to_int()
    sb.write_char(hex[v >> 4].unsafe_to_char())
    sb.write_char(hex[v & 0xF].unsafe_to_char())
  }
  sb.to_string()
}
