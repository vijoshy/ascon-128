# ascon-aead128
Ascon-AEAD128 is a lightweight authenticated-encryption algorithm standardized by NIST in **SP 800-232 (final, August 2025)**. It uses a 128-bit key, a 128-bit nonce, a 128-bit rate, a 128-bit authentication tag, and a 320-bit internal permutation state.

Ascon-AEAD128 is based on a sponge-like construction rather than a conventional block cipher. The parameters implemented by this repository are:

• Key Length (k): 128 bits
• Nonce Length: 128 bits
• Rate or Block Size (r): 128 bits
• Number of rounds (a, b): 12 and 8 rounds respectively
• Authentication Tag Length: 128 bits

---

## Features

- Ascon-AEAD128 implementation compliant with NIST SP 800-232
- 320-bit permutation state
- 12-round (`P12`) initialization/finalization and 8-round (`P8`) processing support
- Hardware 10* padding for final associated-data and plaintext blocks
- Hardware masking of partial final ciphertext blocks
- FSM-based controller
- Datapath/controller separation
- SystemVerilog RTL implementation
- Python reference/golden model
- Vivado/XSim simulation support

The current implementation targets **Ascon-AEAD128 from the final NIST SP 800-232 specification**, rather than the older Ascon submission/v1.2 parameter set.
---

## Architecture

The design is divided into two major blocks:

- **Controller (FSM)**
  - Controls initialization
  - Associated-data absorption
  - Plaintext absorption
  - Finalization
  - Selects P8/P12 permutations
  - Tracks the final associated-data and plaintext blocks

---

- **Datapath**
  - 320-bit Ascon state
  - Round permutation engine
  - Key/nonce loading
  - Hardware 10* padding
  - Partial-block ciphertext masking
  - Ciphertext generation
  - Authentication-tag generation

The RTL accepts raw, unpadded data blocks. The caller supplies the number of valid bytes in the final block through `data_bytes`; the hardware inserts the `0x01` padding byte and zeroes the remaining bytes. For messages whose length is an exact multiple of 16 bytes, an additional final padding block is required.

---

## Interface

The top-level RTL module is `ascon_core`.

| Signal | Direction | Width | Description |
|---|---:|---:|---|
| `clk` | Input | 1 | Active clock. |
| `rst` | Input | 1 | Active-high reset. |
| `start_cipher` | Input | 1 | Starts a new encryption operation. Assert for one cycle while the core is idle. |
| `has_ad` | Input | 1 | Indicates that associated data is present. |
| `has_pt` | Input | 1 | Indicates that plaintext is present. The current testbench supplies one final padding block when plaintext is empty. |
| `ad_last` | Input | 1 | Marks the currently supplied associated-data block as the final AD block. |
| `pt_last` | Input | 1 | Marks the currently supplied plaintext block as the final plaintext block. |
| `key` | Input | 128 | 128-bit Ascon key. |
| `nonce` | Input | 128 | 128-bit unique nonce. Do not reuse a nonce with the same key. |
| `data_in` | Input | 128 | Raw, unpadded AD or plaintext block. The block is supplied as `{block_word0[127:64], block_word1[63:0]}`. |
| `data_bytes` | Input | 5 | Number of valid bytes in the final AD or plaintext block, from 0 to 15. Non-final blocks use 16. |
| `ciphertext_out` | Output | 128 | Ciphertext block produced for the current plaintext block. Only the valid bytes of a partial final block are meaningful. |
| `tag_out` | Output | 128 | 128-bit authentication tag, available after finalization. |
| `cipher_done` | Output | 1 | Indicates that the encryption operation has completed and the outputs are valid. |

### Input and block-handling notes

- Inputs must be presented in the byte order expected by the RTL and testbench.
- The hardware performs 10* padding on final AD and plaintext blocks; callers must not add the padding byte themselves.
- For an input whose length is an exact multiple of 16 bytes, provide one additional final block with `data_bytes = 0`.
- For empty plaintext, provide one final all-padding plaintext block with `pt_last = 1` and `data_bytes = 0`.
- The core is an encryption-only datapath; decryption and tag verification are not currently implemented.

---

## Block Diagram



---

## Verification

A Python reference implementation is included alongside the RTL to verify the Ascon-AEAD128 initialization, permutation, associated-data processing, plaintext processing, ciphertext, and authentication tag.

The repository also includes:

- A SystemVerilog simulation testbench in `tb/ascon_tb.sv`
- A reference KAT file in `docs/ascon128_kat.txt`
- A sample waveform in `docs/waveform.png`

The supplied testbench currently runs a manually configured test vector and prints the resulting ciphertext and tag for comparison with the Python reference model. It is not yet an automated self-checking KAT testbench.

---

## Development Environment

- SystemVerilog RTL
- AMD Vivado with XSim
- Python 3 reference model
- Any simulator supporting the SystemVerilog constructs used by the testbench

To run the Python reference model:

```bash
python3 py/ascon_py.py
```

The RTL testbench can be run by adding the files in `rtl/` and `tb/ascon_tb.sv` to a Vivado/XSim simulation project. Configure the test vector in the `EDIT ME` section of `tb/ascon_tb.sv` before starting the simulation.

---

## References

- NIST SP 800-232, *Ascon-Based Lightweight Cryptography Standards for Constrained Devices* (final, August 2025)
- Official Ascon-AEAD128 specification and Known Answer Tests
- Ascon permutation specification

---

## Security Disclaimer

This repository is intended for research, education, and hardware-design experimentation. Although the implementation is based on the Ascon-AEAD128 specification, functional verification does not constitute a formal security evaluation.

The RTL has not necessarily been reviewed for side-channel leakage, fault-injection resistance, timing leakage, glitch behavior, fault attacks, key erasure, or other implementation-level security properties. It should not be used to protect sensitive data in production without independent cryptographic review, extensive verification, and appropriate physical-security countermeasures.

Nonce uniqueness is required when using the same key. Never reuse a nonce with the same key. The implementation currently provides encryption and tag generation only; decryption and authentication-tag verification are not included.

---

## License

This project is released under the MIT License.

---

## Author

Personal cryptographic hardware accelerator by vijoshy
