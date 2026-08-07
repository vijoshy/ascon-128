# ascon-128
Ascon-128 is a lightweight encryption algorithm selected by the NIST as the lightweight cryptography standard algorithm. It features a 128 bit key, 128 bit nonce and a 320 bit internal state.

Based on a sponge construction than a block cipher. Suggested parameters are as follows:

•	Key Length (k): 128 bits
•	Rate or Block Size (r): 64 bits
•	Number of rounds (a, b): 12 and 6 bits respectively

---

## Features

- ASCON-128 v1.2 implementation
- 320-bit permutation state
- 12-round (`P12`) and 6-round (`P6`) permutation support
- Finite State Machine (FSM) based controller
- Datapath/controller separation
- Verilog-2001 implementation
- Vivado/XSim simulation support

---

## Architecture

The design is divided into two major blocks:

- **Controller (FSM)**
  - Controls initialization
  - Associated Data absorption
  - Plaintext absorption
  - Finalization
  - Selects P6/P12 permutations

---

- **Datapath**
  - 320-bit ASCON state
  - Round permutation engine
  - Key/nonce loading
  - Ciphertext generation
  - Authentication tag generation

---

##Block Diagram 
<img width="2156" height="4625" alt="ascon128_corrected_flow" src="https://github.com/user-attachments/assets/27ad4b03-ee49-45d1-9859-73f84d218994" />

---

## Verification

A Python reference implementation was written alongside the RTL to verify intermediate state values and final outputs.

The implementation has been validated against the official ASCON Known Answer Tests (KATs)

---

## Development Environment

- Verilog HDL
- AMD Vivado (XSim)
- Python 3 (Reference Model)

---

## References

- ASCON Specification v1.2
- NIST Lightweight Cryptography Standard
- Official ASCON Known Answer Tests (KAT)

---

## License

This project is released under the MIT License.

---

## Author

 Personal Cryptographic Hardware Accelerator by vijoshy 
