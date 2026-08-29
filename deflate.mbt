// A real DEFLATE compressor (RFC 1951) — the compression behind `gzip(...)`.
// Round 6 emitted stored (uncompressed) blocks: a valid container with no ratio.
// This is LZ77 back-reference matching (a 32 KiB window, hash-chain match finder)
// coded with DEFLATE's fixed Huffman table (§3.2.6), so the output actually
// shrinks. A companion `inflate` decodes stored and fixed-Huffman blocks, so the
// encoder is verified by round-trip on every backend, and the bytes are read by
// any conforming inflater (gzip, zlib) — checked against the system `gzip` in CI.
//
// The one step further — dynamic Huffman (§3.2.7), which fits a per-block code to
// the data for a better ratio — is the documented next increment; fixed Huffman
// already delivers a genuine ratio on real payloads.

///|
/// DEFLATE length codes 257..285: the base length each encodes (index = sym-257).
let length_base : Array[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
/// Extra bits carried after each length code 257..285.
let length_extra : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
/// DEFLATE distance codes 0..29: the base distance each encodes.
let dist_base : Array[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
/// Extra bits carried after each distance code 0..29.
let dist_extra : Array[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
/// The length code for a match length 3..258: its symbol, extra-bit count, and
/// extra-bit value.
fn length_code(len : Int) -> (Int, Int, Int) {
  let mut idx = 28
  for i = 0; i < 29; i = i + 1 {
    if length_base[i] > len {
      idx = i - 1
      break
    }
  }
  (257 + idx, length_extra[idx], len - length_base[idx])
}

///|
/// The distance code for a back-reference distance 1..32768: its symbol,
/// extra-bit count, and extra-bit value.
fn distance_code(dist : Int) -> (Int, Int, Int) {
  let mut idx = 29
  for i = 0; i < 30; i = i + 1 {
    if dist_base[i] > dist {
      idx = i - 1
      break
    }
  }
  (idx, dist_extra[idx], dist - dist_base[idx])
}

///|
/// Reverse the low `len` bits of `code` — Huffman codes travel MSB-first while
/// the bit stream is filled LSB-first, so a code is reversed before it is written.
fn reverse_bits(code : Int, len : Int) -> Int {
  let mut r = 0
  let mut c = code
  for _i = 0; _i < len; _i = _i + 1 {
    r = (r << 1) | (c & 1)
    c = c >> 1
  }
  r
}

///|
/// The fixed-Huffman literal/length code (§3.2.6) for symbol 0..287: its bit
/// pattern (MSB-first) and length.
fn fixed_litlen_code(sym : Int) -> (Int, Int) {
  if sym <= 143 {
    (0x30 + sym, 8)
  } else if sym <= 255 {
    (0x190 + (sym - 144), 9)
  } else if sym <= 279 {
    (sym - 256, 7)
  } else {
    (0xC0 + (sym - 280), 8)
  }
}

///|
/// A DEFLATE bit sink: bits accumulate LSB-first into whole bytes.
priv struct BitWriter {
  buf : Buffer
  mut acc : Int
  mut nbits : Int
}

///|
fn BitWriter::new() -> BitWriter {
  { buf: Buffer(), acc: 0, nbits: 0, }
}

///|
/// Append the low `count` bits of `value`, least-significant bit first — the raw
/// packing for block headers and Huffman extra bits.
fn BitWriter::bits(self : BitWriter, value : Int, count : Int) -> Unit {
  self.acc = self.acc | ((value & ((1 << count) - 1)) << self.nbits)
  self.nbits = self.nbits + count
  while self.nbits >= 8 {
    self.buf.write_byte((self.acc & 0xFF).to_byte())
    self.acc = self.acc >> 8
    self.nbits = self.nbits - 8
  }
}

///|
/// Write a Huffman code MSB-first (reversing it into the LSB-first stream).
fn BitWriter::huff(self : BitWriter, code : Int, len : Int) -> Unit {
  self.bits(reverse_bits(code, len), len)
}

///|
/// Flush a partial trailing byte (zero-padded) and return the packed bytes.
fn BitWriter::finish(self : BitWriter) -> Bytes {
  if self.nbits > 0 {
    self.buf.write_byte((self.acc & 0xFF).to_byte())
    self.acc = 0
    self.nbits = 0
  }
  self.buf.to_bytes()
}

///|
/// Emit a literal/length symbol under the fixed Huffman table.
fn emit_symbol(bw : BitWriter, sym : Int) -> Unit {
  let (code, len) = fixed_litlen_code(sym)
  bw.huff(code, len)
}

///|
/// Emit a match: its length code (+ extra bits) then its distance code (a fixed
/// 5-bit code + extra bits).
fn emit_match(bw : BitWriter, len : Int, dist : Int) -> Unit {
  let (lsym, lext, lval) = length_code(len)
  emit_symbol(bw, lsym)
  if lext > 0 {
    bw.bits(lval, lext)
  }
  let (dsym, dext, dval) = distance_code(dist)
  bw.huff(dsym, 5)
  if dext > 0 {
    bw.bits(dval, dext)
  }
}

///|
/// The 3-byte rolling hash keying the match-finder chains.
fn hash3(data : Bytes, i : Int) -> Int {
  let a = data[i].to_int()
  let b = data[i + 1].to_int()
  let c = data[i + 2].to_int()
  ((a << 10) ^ (b << 5) ^ c) & 0x7FFF
}

///|
/// Compress `data` into one fixed-Huffman DEFLATE block (BFINAL set). LZ77 finds
/// back-references with a hash-chain over a 32 KiB window (chain length capped so
/// the search stays linear); unmatched bytes go out as literals. The result is a
/// complete raw DEFLATE stream — the payload gzip wraps.
fn deflate_encode(data : Bytes) -> Bytes {
  let bw = BitWriter::new()
  bw.bits(1, 1) // BFINAL = 1: this is the only, final block
  bw.bits(1, 2) // BTYPE = 01: fixed Huffman codes
  let n = data.length()
  let min_match = 3
  let max_match = 258
  let window = 32768
  let max_chain = 256
  if n > 0 {
    let head = Array::make(32768, -1)
    let prev = Array::make(n, -1)
    let mut i = 0
    while i < n {
      let mut best_len = 0
      let mut best_dist = 0
      if i + min_match <= n {
        let h = hash3(data, i)
        let cap = if n - i < max_match { n - i } else { max_match }
        let mut j = head[h]
        let mut chain = max_chain
        while j >= 0 && chain > 0 {
          let dist = i - j
          if dist > window {
            break
          }
          let mut len = 0
          while len < cap && data[j + len] == data[i + len] {
            len = len + 1
          }
          if len > best_len {
            best_len = len
            best_dist = dist
            if len >= cap {
              break
            }
          }
          j = prev[j]
          chain = chain - 1
        }
      }
      if best_len >= min_match {
        emit_match(bw, best_len, best_dist)
        let end = i + best_len
        while i < end {
          if i + min_match <= n {
            let h = hash3(data, i)
            prev[i] = head[h]
            head[h] = i
          }
          i = i + 1
        }
      } else {
        emit_symbol(bw, data[i].to_int())
        if i + min_match <= n {
          let h = hash3(data, i)
          prev[i] = head[h]
          head[h] = i
        }
        i = i + 1
      }
    }
  }
  emit_symbol(bw, 256) // end-of-block
  bw.finish()
}

// -- inflate (round-trip verification) ----------------------------------------

///|
/// A DEFLATE bit source: bits are consumed LSB-first out of the byte stream.
priv struct BitReader {
  data : Bytes
  mut pos : Int
  mut acc : Int
  mut nbits : Int
}

///|
fn BitReader::new(data : Bytes) -> BitReader {
  { data, pos: 0, acc: 0, nbits: 0, }
}

///|
/// The next bit (LSB of the current byte first).
fn BitReader::bit(self : BitReader) -> Int {
  if self.nbits == 0 {
    self.acc = self.data[self.pos].to_int()
    self.pos = self.pos + 1
    self.nbits = 8
  }
  let b = self.acc & 1
  self.acc = self.acc >> 1
  self.nbits = self.nbits - 1
  b
}

///|
/// The next `count` bits as an integer, first bit read into the LSB.
fn BitReader::bits(self : BitReader, count : Int) -> Int {
  let mut v = 0
  for i = 0; i < count; i = i + 1 {
    v = v | (self.bit() << i)
  }
  v
}

///|
/// Discard the current partial byte, aligning to the next byte boundary (a stored
/// block's LEN starts there).
fn BitReader::align(self : BitReader) -> Unit {
  self.acc = 0
  self.nbits = 0
}

///|
/// Decode one fixed-Huffman literal/length symbol (0..287), reading its code
/// MSB-first and widening 7 → 8 → 9 bits across the table's length ranges.
fn decode_fixed_symbol(br : BitReader) -> Int {
  let mut code = 0
  for _i = 0; _i < 7; _i = _i + 1 {
    code = (code << 1) | br.bit()
  }
  if code <= 0x17 {
    return 256 + code
  }
  code = (code << 1) | br.bit()
  if code >= 0x30 && code <= 0xBF {
    return code - 0x30
  }
  if code >= 0xC0 && code <= 0xC7 {
    return 280 + (code - 0xC0)
  }
  code = (code << 1) | br.bit()
  144 + (code - 0x190)
}

///|
/// Decode a raw DEFLATE stream (stored and fixed-Huffman blocks). Used to
/// round-trip `deflate_encode` in the tests; back-references copy byte-by-byte so
/// overlapping (run-length) matches inflate correctly.
pub fn inflate(data : Bytes) -> Bytes {
  let br = BitReader::new(data)
  let out : Array[Byte] = []
  let mut last = false
  while !last {
    if br.bit() == 1 {
      last = true
    }
    let btype = br.bits(2)
    if btype == 0 {
      br.align()
      let len = br.data[br.pos].to_int() | (br.data[br.pos + 1].to_int() << 8)
      br.pos = br.pos + 4 // LEN + NLEN
      for _k = 0; _k < len; _k = _k + 1 {
        out.push(br.data[br.pos])
        br.pos = br.pos + 1
      }
    } else if btype == 1 {
      let mut done = false
      while !done {
        let sym = decode_fixed_symbol(br)
        if sym == 256 {
          done = true
        } else if sym < 256 {
          out.push(sym.to_byte())
        } else {
          let idx = sym - 257
          let len = length_base[idx] + br.bits(length_extra[idx])
          let mut dcode = 0
          for _i = 0; _i < 5; _i = _i + 1 {
            dcode = (dcode << 1) | br.bit()
          }
          let dist = dist_base[dcode] + br.bits(dist_extra[dcode])
          let start = out.length() - dist
          for k = 0; k < len; k = k + 1 {
            out.push(out[start + k])
          }
        }
      }
    } else {
      abort("unsupported DEFLATE block type")
    }
  }
  let buf = Buffer()
  for b in out {
    buf.write_byte(b)
  }
  buf.to_bytes()
}
