///|
/// Lowercase hex of a byte string — test helper for comparing digests to the
/// published NIST / RFC vectors.
fn to_hex(b : Bytes) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for i = 0; i < b.length(); i = i + 1 {
    let v = b[i].to_int()
    sb.write_char(digits[v / 16].unsafe_to_char())
    sb.write_char(digits[v % 16].unsafe_to_char())
  }
  sb.to_string()
}

///|
test "sha256 matches the NIST vectors" {
  assert_eq(
    to_hex(sha256(@utf8.encode(""))),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    to_hex(sha256(@utf8.encode("abc"))),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  // A message spanning two 512-bit blocks (56 bytes forces a second block).
  assert_eq(
    to_hex(
      sha256(
        @utf8.encode("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      ),
    ),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
test "hmac_sha256 matches RFC 4231 test case 2" {
  // key = "Jefe", data = "what do ya want for nothing?"
  let mac = hmac_sha256(
    @utf8.encode("Jefe"),
    @utf8.encode("what do ya want for nothing?"),
  )
  assert_eq(
    to_hex(mac),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  )
}

///|
test "hmac_sha256 with a key longer than the block is hashed first" {
  // RFC 4231 test case 3 uses a 131-byte key; here just assert stability +
  // that the long-key branch produces a 32-byte digest distinct from a short one.
  let long_key = Bytes::make(131, b'\xaa')
  let mac = hmac_sha256(
    long_key,
    @utf8.encode("Test Using Larger Than Block-Size Key - Hash Key First"),
  )
  assert_eq(mac.length(), 32)
  assert_eq(
    to_hex(mac),
    "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
  )
}

///|
test "constant_time_eq: equal, differing, and length-mismatched" {
  assert_eq(constant_time_eq(b"secret", b"secret"), true)
  assert_eq(constant_time_eq(b"secret", b"secreu"), false)
  assert_eq(constant_time_eq(b"secret", b"secre"), false)
  assert_eq(constant_time_eq(b"", b""), true)
}
