///|
test "sha512 matches the NIST vectors" {
  assert_eq(
    to_hex(sha512(@utf8.encode(""))),
    "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
  )
  assert_eq(
    to_hex(sha512(@utf8.encode("abc"))),
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
  )
}

///|
test "sha512 handles a multi-block message (over 112 bytes)" {
  // 200 'a's crosses the 128-byte block boundary and the 112-byte pad threshold;
  // the expected digest is from a reference SHA-512 (openssl/hashlib).
  let s = "a".repeat(200)
  assert_eq(
    to_hex(sha512(@utf8.encode(s))),
    "4b11459c33f52a22ee8236782714c150a3b2c60994e9acee17fe68947a3e6789f31e7668394592da7bef827cddca88c4e6f86e4df7ed1ae6cba71f3e98faee9f",
  )
}
