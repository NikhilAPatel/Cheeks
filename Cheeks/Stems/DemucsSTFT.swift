import Accelerate

/// `HTDemucs._spec` and `_ispec` for one channel, on vDSP. Matches PyTorch to float rounding
/// (`CheeksTests/StemSeparationTests.swift` checks against numbers generated with PyTorch).
///
/// What the Python does, in terms of this type's coordinates:
/// - `_spec` reflect-pads by 1536 on the left and enough on the right to fill the last hop, runs a
///   centred STFT, then keeps `frames` frames out of the `frames + 4`. Frame `k` therefore covers
///   samples `k * 1024 - 1536 ..< k * 1024 + 2560`, reflected at both ends. The centring padding
///   of `torch.stft` is never reached, and the top (Nyquist) bin is dropped.
/// - `_ispec` puts the Nyquist bin back as zero and adds two silent frames either side, then runs
///   the inverse with the same geometry. Those silent frames still count in the window envelope,
///   so the envelope is the constant `3/2` over the whole output and the edges fade slightly.
/// - `normalized=True` divides the forward transform by `sqrt(4096)` and multiplies the inverse
///   by the same amount.
///
/// Holds scratch buffers, so an instance isn't safe to share between threads.
final class DemucsSTFT {
    static let fftSize = 4096
    static let hop = 1024
    static let bins = fftSize / 2

    private static let log2Size = vDSP_Length(12)
    private static let leftPad = hop / 2 * 3
    /// The sum of the squared Hann window at a hop of a quarter of its length.
    private static let envelope: Float = 1.5

    /// Samples per segment.
    let length: Int
    /// Spectrogram frames per segment: `ceil(length / hop)`.
    let frames: Int

    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>

    /// `length` has to be longer than the longest reflection (Demucs special-cases shorter input,
    /// which never happens here: the app always passes a whole segment).
    init(length: Int) {
        precondition(length > Self.leftPad + Self.hop, "segment too short to reflect-pad")
        self.length = length
        frames = (length + Self.hop - 1) / Self.hop
        guard let setup = vDSP_create_fftsetup(Self.log2Size, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed")
        }
        self.setup = setup
        let n = Self.fftSize
        window = .allocate(capacity: n)
        frame = .allocate(capacity: n)
        realp = .allocate(capacity: n / 2)
        imagp = .allocate(capacity: n / 2)
        // Periodic Hann, as torch.hann_window.
        for i in 0..<n {
            window[i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n)))
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        window.deallocate()
        frame.deallocate()
        realp.deallocate()
        imagp.deallocate()
    }

    /// One channel of samples to a `bins`-by-`frames` complex spectrogram. Element
    /// (`bin`, `frameIndex`) goes to `real[bin * binStride + frameIndex * frameStride]`, and the
    /// same for `imag`.
    func forward(
        _ x: UnsafePointer<Float>,
        real: UnsafeMutablePointer<Float>,
        imag: UnsafeMutablePointer<Float>,
        binStride: Int,
        frameStride: Int
    ) {
        let n = Self.fftSize
        // vDSP's forward real FFT comes out at twice the DFT.
        let scale = 0.5 / Float(n).squareRoot()
        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        for k in 0..<frames {
            let start = k * Self.hop - Self.leftPad
            if start >= 0, start + n <= length {
                vDSP_vmul(x + start, 1, window, 1, frame, 1, vDSP_Length(n))
            } else {
                for i in 0..<n {
                    var s = start + i
                    if s < 0 {
                        s = -s
                    } else if s >= length {
                        s = 2 * (length - 1) - s
                    }
                    frame[i] = x[s] * window[i]
                }
            }
            frame.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
            }
            vDSP_fft_zrip(setup, &split, 1, Self.log2Size, FFTDirection(FFT_FORWARD))

            // Packed format: imagp[0] holds the Nyquist bin, which _spec drops. DC is real.
            let base = k * frameStride
            real[base] = realp[0] * scale
            imag[base] = 0
            for bin in 1..<Self.bins {
                real[base + bin * binStride] = realp[bin] * scale
                imag[base + bin * binStride] = imagp[bin] * scale
            }
        }
    }

    /// A `bins`-by-`frames` complex spectrogram back to `length` samples, overwriting `output`.
    /// Layout as for `forward`.
    func inverse(
        real: UnsafePointer<Float>,
        imag: UnsafePointer<Float>,
        binStride: Int,
        frameStride: Int,
        output: UnsafeMutablePointer<Float>
    ) {
        let n = Self.fftSize
        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        vDSP_vclr(output, 1, vDSP_Length(length))
        for k in 0..<frames {
            // Nyquist is the zero that _ispec pads in, and irfft ignores the imaginary part of DC.
            let base = k * frameStride
            realp[0] = real[base]
            imagp[0] = 0
            for bin in 1..<Self.bins {
                realp[bin] = real[base + bin * binStride]
                imagp[bin] = imag[base + bin * binStride]
            }
            vDSP_fft_zrip(setup, &split, 1, Self.log2Size, FFTDirection(FFT_INVERSE))
            frame.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(n / 2))
            }
            vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(n))

            let start = k * Self.hop - Self.leftPad
            let from = max(0, -start)
            let to = min(n, length - start)
            if to > from {
                let destination = output + start + from
                vDSP_vadd(destination, 1, frame + from, 1, destination, 1, vDSP_Length(to - from))
            }
        }
        // vDSP's inverse real FFT of a true DFT comes out `n` times too large; with the
        // `sqrt(n)` of normalized=True, that leaves one `sqrt(n)` to divide by.
        var gain = 1 / (Float(n).squareRoot() * Self.envelope)
        vDSP_vsmul(output, 1, &gain, output, 1, vDSP_Length(length))
    }
}
