"""
Ascon-AEAD128 golden model -- NIST SP 800-232 (final standard, 2025).

Ported from meichlseder/pyascon (ascon.py), trimmed to the AEAD128 encrypt path
that the RTL in this folder implements. Little-endian byte order throughout.

This is the reference the Verilog testbench (ascon_tb.v) is checked against.
Run directly to execute the self-test.
"""

MASK = (1 << 64) - 1
RATE = 16          # bytes (128-bit rate)
A_ROUNDS = 12      # initialization / finalization
B_ROUNDS = 8       # associated-data / plaintext processing
ASCON_AEAD128_IV = 0x00001000808C0001   # LE-loaded IV word (version=1, b=8,a=12, taglen=128, rate=16)


def rotr(x, n):
    return ((x >> n) | (x << (64 - n))) & MASK


def bytes_to_int(b):
    return int.from_bytes(b, "little")


def int_to_bytes(x, n):
    return int(x).to_bytes(n, "little")


def bytes_to_state(b):
    return [bytes_to_int(b[8 * w:8 * (w + 1)]) for w in range(5)]


def permutation(S, rounds):
    assert rounds <= 12
    for r in range(12 - rounds, 12):
        # p_C : round constant into x2 (RC = 0xf0 - 15*r ; r = 0..11 -> f0..4b)
        S[2] ^= (0xF0 - r * 0x10 + r * 0x01)
        # p_S : substitution layer
        S[0] ^= S[4]
        S[4] ^= S[3]
        S[2] ^= S[1]
        T = [(S[i] ^ MASK) & S[(i + 1) % 5] for i in range(5)]
        for i in range(5):
            S[i] ^= T[(i + 1) % 5]
        S[1] ^= S[0]
        S[0] ^= S[4]
        S[3] ^= S[2]
        S[2] ^= MASK
        # p_L : linear diffusion layer
        S[0] ^= rotr(S[0], 19) ^ rotr(S[0], 28)
        S[1] ^= rotr(S[1], 61) ^ rotr(S[1], 39)
        S[2] ^= rotr(S[2], 1) ^ rotr(S[2], 6)
        S[3] ^= rotr(S[3], 10) ^ rotr(S[3], 17)
        S[4] ^= rotr(S[4], 7) ^ rotr(S[4], 41)
        for i in range(5):
            S[i] &= MASK


def initialize(S, key, nonce):
    iv = bytes([1, 0, (B_ROUNDS << 4) + A_ROUNDS]) + int_to_bytes(128, 2) + bytes([RATE, 0, 0])
    assert bytes_to_int(iv) == ASCON_AEAD128_IV, hex(bytes_to_int(iv))
    S[0], S[1], S[2], S[3], S[4] = bytes_to_state(iv + key + nonce)
    permutation(S, A_ROUNDS)
    zk = bytes_to_state(b"\x00" * (40 - len(key)) + key)   # -> [0,0,0,K0,K1]
    for i in range(5):
        S[i] ^= zk[i]


def process_associated_data(S, ad):
    if len(ad) > 0:
        pad = b"\x01" + b"\x00" * (RATE - (len(ad) % RATE) - 1)
        ad_p = ad + pad
        for blk in range(0, len(ad_p), RATE):
            S[0] ^= bytes_to_int(ad_p[blk:blk + 8])
            S[1] ^= bytes_to_int(ad_p[blk + 8:blk + 16])
            permutation(S, B_ROUNDS)
    S[4] ^= 1 << 63          # domain separation (always, even for empty AD)


def process_plaintext(S, pt):
    last = len(pt) % RATE
    pad = b"\x01" + b"\x00" * (RATE - last - 1)
    pt_p = pt + pad
    ct = b""
    # full blocks (all but the final rate-sized block)
    for blk in range(0, len(pt_p) - RATE, RATE):
        S[0] ^= bytes_to_int(pt_p[blk:blk + 8])
        S[1] ^= bytes_to_int(pt_p[blk + 8:blk + 16])
        ct += int_to_bytes(S[0], 8) + int_to_bytes(S[1], 8)
        permutation(S, B_ROUNDS)
    # final block -- absorb, squeeze, NO permutation
    blk = len(pt_p) - RATE
    S[0] ^= bytes_to_int(pt_p[blk:blk + 8])
    S[1] ^= bytes_to_int(pt_p[blk + 8:blk + 16])
    ct += (int_to_bytes(S[0], 8)[:min(8, last)] + int_to_bytes(S[1], 8)[:max(0, last - 8)])
    return ct


def finalize(S, key):
    S[2] ^= bytes_to_int(key[0:8])       # rate//8 + 0 = 2
    S[3] ^= bytes_to_int(key[8:16])      # rate//8 + 1 = 3
    permutation(S, A_ROUNDS)
    S[3] ^= bytes_to_int(key[0:8])
    S[4] ^= bytes_to_int(key[8:16])
    return int_to_bytes(S[3], 8) + int_to_bytes(S[4], 8)


def encrypt(key, nonce, ad, pt):
    assert len(key) == 16 and len(nonce) == 16
    S = [0, 0, 0, 0, 0]
    initialize(S, key, nonce)
    process_associated_data(S, ad)
    ct = process_plaintext(S, pt)
    tag = finalize(S, key)
    return ct, tag


def _pad_blocks(data):
    """SP 800-232 padding -> list of 16-byte blocks. Always >= 1 block."""
    pad = b"\x01" + b"\x00" * (RATE - (len(data) % RATE) - 1)
    d = data + pad
    return [d[i:i + RATE] for i in range(0, len(d), RATE)]


def encrypt_hw(key, nonce, ad, pt):
    """
    Block-level view for the Verilog testbench.

    Returns a dict with the padded AD/PT blocks the DUT must be fed, the
    *untruncated* 16-byte ciphertext blocks the DUT registers per PT block,
    the real ciphertext byte length, and the tag. All bytes little-endian
    exactly as loaded into the 64-bit state words.
    """
    S = [0, 0, 0, 0, 0]
    initialize(S, key, nonce)

    ad_blocks = _pad_blocks(ad) if len(ad) > 0 else []
    for blk in ad_blocks:
        S[0] ^= bytes_to_int(blk[0:8])
        S[1] ^= bytes_to_int(blk[8:16])
        permutation(S, B_ROUNDS)
    S[4] ^= 1 << 63

    pt_blocks = _pad_blocks(pt)
    ct_blocks = []
    for i, blk in enumerate(pt_blocks):
        S[0] ^= bytes_to_int(blk[0:8])
        S[1] ^= bytes_to_int(blk[8:16])
        ct_blocks.append(int_to_bytes(S[0], 8) + int_to_bytes(S[1], 8))
        if i != len(pt_blocks) - 1:
            permutation(S, B_ROUNDS)

    S[2] ^= bytes_to_int(key[0:8])
    S[3] ^= bytes_to_int(key[8:16])
    permutation(S, A_ROUNDS)
    S[3] ^= bytes_to_int(key[0:8])
    S[4] ^= bytes_to_int(key[8:16])
    tag = int_to_bytes(S[3], 8) + int_to_bytes(S[4], 8)

    return {
        "ad_blocks": ad_blocks,
        "pt_blocks": pt_blocks,
        "ct_blocks": ct_blocks,
        "ct_len": len(pt),
        "tag": tag,
    }


if __name__ == "__main__":
    key   = bytes.fromhex("000102030405060708090A0B0C0D0E0F")
    nonce = bytes.fromhex("101112131415161718191A1B1C1D1E1F")
    ad    = bytes.fromhex("30") 
    pt    = bytes.fromhex("202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C")  

    # Run encryption
    ct, tag = encrypt(key, nonce, ad, pt)

    # Print results for manual verification
    print("PT:       ", pt.hex().upper())
    print("CT:       ", ct.hex().upper())
    print("Tag:      ", tag.hex().upper())
    print("CT || Tag:", (ct + tag).hex().upper())
    print("for reference this is count 959");

