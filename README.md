# Automatic-Gain-Control-Analog-to-Digital-Converter


**Status: Under Active Development**

## Overview

This repository houses a modular, object-oriented digital signal processing (DSP) block implemented in MATLAB. It acts as a complete hardware-equivalent frontend pipeline, integrating a signal generator, high-pass filter (HPF), anti-aliasing filter (AAF), time-varying automatic gain control (AGC), noise gate, analog-to-digital converter (ADC), and ADC encoder. It explores two main areas:

**1. Digital Signal Processing (DSP) Paradigms:** Sinusoidal signal generation, multi-stage filtering, automatic gain control, sampling, quantization, fixed-point representation, frame-based processing.

**2. Software Engineering Paradigms:** Object-oriented programming (OOP), unit testing, integration testing, code reusability, and modularity.

## How to Run

This repository contains the reusable implementation and verification codebase. The primary standalone execution path is the automated test suite.

### Requirements

- MATLAB
- Signal Processing Toolbox

### 1. Clone the Repository

```bash
git clone https://github.com/DamiProject/Automatic-Gain-Control-Analog-to-Digital-Converter.git
cd Automatic-Gain-Control-Analog-to-Digital-Converter
```

### 2. Run the Test Suite

Open MATLAB and navigate to the repository root, then run:

```matlab
ADCRunTests
```

`ADCRunTests.m` automatically adds the `Design` directory and its subdirectories to the MATLAB path, then executes all unit and integration tests contained in the `Tests` directory.

The test suite verifies the individual ADC signal-chain modules as well as their interaction across the processing chain.

The repository structure is:

```text
Automatic-Gain-Control-Analog-to-Digital-Converter/
├── Design/
│   ├── SignalGenerator.m
│   ├── ADCFilter.m
│   ├── AGC.m
│   ├── ADC.m
│   ├── ADCEncoder.m
│   ├── ADCParameters.m
│   └── ADCMeta.m
│
├── Tests/
│   ├── Unit Tests/
│   └── Integration Tests/
│
└── ADCRunTests.m
```

A successful run completes all tests without an assertion failure.

---

## Module Implementations

 **1. Signal Generator Object:** This module generates an instance of the analog input signal to be digitized, consisting of a sinusoidal baseband signal (core data), high-frequency interference signal, DC offset, and AWGN noise floor.

**Key Implementation Features:**

- **Non-Stationary Envelope Generation:** Rather than generating a static, continuous sine wave, the baseband signal is amplitude-modulated using a custom envelope i.e. a Gaussian pulse followed by an exponential fade.

- **Real-World Transient Simulation:** This envelope creates a dynamic "burst and decay" profile, simulating the transient nature of real-world physical sources (such as human speech). This non-stationary behavior provides the necessary amplitude variance to rigorously test the downstream Automatic Gain Control (AGC) and quantization stages.

 **2. DC Removal (HPF) Object:** This module generates an instance of an N-order Butterworth High-Pass Filter (HPF) to attenuate unwanted DC offset from the incoming signal. In DSP, DC offsets are not universally detrimental; for example, unipolar quantizers rely on an injected DC offset to lift the analog signal entirely above zero. However, this simulation implements a bipolar midtread quantizer, which requires the signal to swing symmetrically across its zero-crossing. In this architecture, a residual DC offset restricts the dynamic range and severely degrades the quantizer's operational accuracy, making this HPF stage critical.
   
**Key Implementation Features:**

- **Numerically Robust ZPK Formulation:** To prevent numerical instability and floating-point roundoff errors common in high-order filter calculations, the coefficients are mathematically derived using a cascaded second-order section (SoS) Zero-Pole-Gain (ZPK) formulation.

**3. Anti-Aliasing Filter (LPF):** This module generates an instance of an N-order Butterworth Low-Pass Filter (LPF) to band-limit the incoming analog signal before it reaches the sampler. According to the Nyquist-Shannon sampling theorem, a system must sample at a rate at least twice the highest frequency present in the signal to prevent distortion. If frequencies exceeding the Nyquist limit ($f_s / 2$) enter the sampler, they "fold" back into the baseband, masquerading as lower frequencies. This phenomenon, known as aliasing, introduces irreversible inharmonic distortion that cannot be mathematically removed post-conversion.

**Key Implementation Features:**

- **Numerically Robust ZPK Formulation:** Just like the DC removal stage, to prevent numerical instability and floating-point roundoff errors common in high-order filter calculations, the coefficients are mathematically derived using a cascaded second-order section (SoS) Zero-Pole-Gain (ZPK) formulation.
- **Oversampling Operation:**  By operating at an oversampled rate relative to a target signal's bandwidth, the transition band leading up to the Nyquist limit ($f_s / 2$) is significantly widened. This eliminates the need for an aggressive, high-order "brick-wall" filter with a steep cutoff, reducing filter complexity, computational load, and in-band phase distortion while maintaining anti-aliasing protection.

**4. Feedforward Time-Varying Automatic Gain Control (AGC) With Noise Gate:** This module generates an AGC instance to dynamically adjust the gain of the incoming analog signal over time. Its primary function is to drive the conditioned waveform toward a defined operating region within the bipolar midtread quantizer’s full-scale range. This improves dynamic-range utilization while reducing the likelihood of quantizer clipping and saturation. To prevent the system from amplifying the noise floor during quiet periods (such as a fading audio message), the module integrates a Noise Gate. The noise gate dictates the AGC's behavior under low Signal-to-Noise Ratio (SNR) conditions:

- **Signal Detection:** When the target signal drops below a defined threshold and is barely present amidst the white noise, the gate activates.

- **Gain Suspension:** Suspends the AGC's gain updates to prevent unwanted amplification of the noise floor. By freezing the gain during quiet periods, the noise gate prevents noticeable "noise pumping" and preserves the signal's fidelity at the quantizer's output.

**Key Implementation Features:**

- **Smoothed Peak Envelope Detector:** The AGC uses an absolute-value envelope detector with independent leaky integrator attack and release smoothing. Compared with RMS-based level detection, this structure responds more directly to extreme amplitude transients and allows the gain controller to preserve quantizer headroom while avoiding abrupt gain changes.
- **Dynamic Thresholding:** Rather than using a hardcoded gate threshold, the model derives it from the configured AWGN standard deviation. This keeps the noise gate operating point consistent with the noise level selected for each simulation scenario.
- **Leaky Integrator Smoothing:** The AGC utilizes leaky integrators for envelope detection and gain application. This ensures smooth transitions during signal conditioning and prevents the abrupt, unnatural "clicking" artifacts that can occur when a noise gate opens or closes.
- **Dynamic Headroom Mapping:** The upper and lower gain limits are parameterized to 75% and 30% of the subsequent quantizer stage's peak voltage, respectively, ensuring improved gain scaling prior to quantization.
  
**5. ADC (Sampler + Quantizer):** This module combines a uniform sampler and a bipolar midtread quantizer to convert the continuous analog signal into a discrete digital output. The midtread architecture is prioritized over a midrise approach because it provides a true "zero" representation level. When the analog input is zero or contains negligible noise, the digital output remains exactly zero, effectively preventing idle channel noise and limit cycle oscillations.

**Key Implementation Features:**
- **Dynamic Parameterization:** Avoids hardcoded values by injecting key hardware specifications (Sampling frequency ($F_s$), full scale voltage ($V_{fs}$), downsampling factor ($DF$), and bit resolution ($B$)) upon instantiation. These parameters dynamically calculate the precise quantization step size ($\Delta = V_{fs} / 2^B$), ADC sampling frequency, and bipolar full-scale range.
- **Clip Protection:** Integrates strict saturation logic aligned with the full-scale voltage range. This accurately simulates real-world hardware overflow and underflow scenarios, preventing erroneous out-of-bounds indexing during extreme signal peaks.
- **Explicit Quantization Error Extraction:** Isolates the quantization noise alongside the digitized signal. This is critical for evaluating the system's noise floor and calculating the Signal-to-Quantization-Noise Ratio (SQNR).

**6. ADC Encoder:** Takes raw analog-to-digital quantizer indices and converts them into a fixed-point representation.

**Key Implementation Features:**

**- Dual Numerical Encoding:** It simultaneously calculates and outputs both Offset-Binary (unsigned integer) and Two's-Complement (signed integer) representations for the provided ADC quantizer indices.

**- Dynamic Type Casting:** To optimize memory usage, the class automatically casts the encoded outputs into the smallest appropriate MATLAB integer data type (uint8/int8, uint16/int16, uint32/int32, or uint64/int64) based on the configured ADC bit width.

**- Rigorous Input Validation:** It ensures that all input indices are valid, finite, and non-negative integers that fall strictly within the bounds of the ADC's resolution ($0$ to $2^{NumBits} - 1$). It specifically enforces the use of uint64 data types for widths greater than 53 bits to prevent floating-point precision loss.

**- Specialized 64-bit Handling:**  Calculating Two's-Complement typically involves subtracting a half-scale value. To prevent arithmetic overflow at the maximum 64-bit resolution, the code handles this special case using bitwise XOR operations (bitxor) and memory typecasting.

**- Bit-Accurate Binary Display:** It includes a Binary method that extracts the exact string representation of the logical bits (e.g., returning "1011" for a 4-bit ADC), ignoring any extra padded zeros that MATLAB adds when storing odd bit-widths inside standard 8, 16, 32, or 64-bit memory blocks.

**- Downstream Formatting:** The encoder outputs an input format structure that defines the Word Length (WL), Integer Word Length (IWL), and Fractional Word Length (FWL = 0), passing crucial fixed-point metadata to the next stage of processing.

---

## Author

**Damilola Ibukun Awotunde**

MEng, Communications & Signal Processing - Western University | [LinkedIn](https://www.linkedin.com/in/damilola-awotunde) 
