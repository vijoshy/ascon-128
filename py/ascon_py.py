MASK = (1 << 64) - 1
def ror(x, n):
    return ((x >> n) | (x << (64 - n))) & MASK
RC = [0xf0, 0xe1, 0xd2, 0xc3, 0xb4, 0xa5, 0x96, 0x87, 0x78, 0x69, 0x5a, 0x4b]
def round_fn(s, C):
    x0, x1, x2, x3, x4 = s
    x2 ^= C
    x0 ^= x4
    x4 ^= x3
    x2 ^= x1
    t0 = x0 ^ ((~x1 & MASK) & x2)
    t1 = x1 ^ ((~x2 & MASK) & x3)
    t2 = x2 ^ ((~x3 & MASK) & x4)
    t3 = x3 ^ ((~x4 & MASK) & x0)
    t4 = x4 ^ ((~x0 & MASK) & x1)
    t1 ^= t0
    t0 ^= t4
    t3 ^= t2
    t2 = (~t2) & MASK
    x0 = (t0 ^ ror(t0, 19) ^ ror(t0, 28)) & MASK
    x1 = (t1 ^ ror(t1, 61) ^ ror(t1, 39)) & MASK
    x2 = (t2 ^ ror(t2, 1)  ^ ror(t2, 6))  & MASK
    x3 = (t3 ^ ror(t3, 10) ^ ror(t3, 17)) & MASK
    x4 = (t4 ^ ror(t4, 7)  ^ ror(t4, 41)) & MASK
    return [x0, x1, x2, x3, x4]
def P12(s):
    for c in RC:
        s = round_fn(s, c)
    return s
def P6(s):
    for c in RC[6:]:
        s = round_fn(s, c)
    return s
def loadbytes(b, n):
    x = 0
    for i in range(n):
        x |= b[i] << (56 - 8 * i)
    return x & MASK
def storebytes(x, n):
    return bytes((x >> (56 - 8 * i)) & 0xff for i in range(n))
def pad(i):
    return (0x80 << (56 - 8 * i)) & MASK
DSEP = 0x01 << 56  # SETBYTE(0x01,7) -> byte index7 -> shift 56-8*7=0 ... wait recompute
def encrypt(key: bytes, nonce: bytes, ad: bytes, pt: bytes, verbose=False):
    ASCON_128_IV = 0x80400c0600000000
    K0 = loadbytes(key[0:8], 8)
    K1 = loadbytes(key[8:16], 8)
    N0 = loadbytes(nonce[0:8], 8)
    N1 = loadbytes(nonce[8:16], 8)
    s = [ASCON_128_IV, K0, K1, N0, N1]
    if verbose: print("init (pre-P12):", [hex(v) for v in s])
    s = P12(s)
    s[3] ^= K0
    s[4] ^= K1
    if verbose: print("after init key xor:", [hex(v) for v in s])
    adlen = len(ad)
    if adlen:
        idx = 0
        while adlen >= 8:
            s[0] ^= loadbytes(ad[idx:idx+8], 8)
            s = P6(s)
            idx += 8
            adlen -= 8
        s[0] ^= loadbytes(ad[idx:idx+adlen], adlen)
        s[0] ^= pad(adlen)
        s = P6(s)
        if verbose: print("after AD:", [hex(v) for v in s])
    # domain separation: SETBYTE(0x01,7) = 0x01 << (56-8*7) = 0x01 << 0
    s[4] ^= 0x01
    if verbose: print("after domain sep:", [hex(v) for v in s])
    mlen = len(pt)
    ct = b""
    idx = 0
    while mlen >= 8:
        s[0] ^= loadbytes(pt[idx:idx+8], 8)
        ct += storebytes(s[0], 8)
        s = P6(s)
        idx += 8
        mlen -= 8
    s[0] ^= loadbytes(pt[idx:idx+mlen], mlen)
    ct += storebytes(s[0], mlen)
    s[0] ^= pad(mlen)
    if verbose: print("after PT pad:", [hex(v) for v in s])
    s[1] ^= K0
    s[2] ^= K1
    if verbose: print("final key xor 1:", [hex(v) for v in s])
    s = P12(s)
    s[3] ^= K0
    s[4] ^= K1
    if verbose: print("final key xor 2:", [hex(v) for v in s])
    tag = storebytes(s[3], 8) + storebytes(s[4], 8)
    return ct, tag
if __name__ == "__main__":
    key = bytes.fromhex("000102030405060708090A0B0C0D0E0F")
    nonce = bytes.fromhex("000102030405060708090A0B0C0D0E0F")
    ad = bytes.fromhex("000102030405060708090A0B0C0D0E0F")
    pt = bytes.fromhex("00010203")

    ct, tag = encrypt(key, nonce, ad, pt, verbose=True)

    print("Ciphertext =", ct.hex().upper())	
    print("Tag        =", tag.hex().upper())



