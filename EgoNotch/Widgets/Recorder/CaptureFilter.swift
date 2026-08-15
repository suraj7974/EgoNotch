import CoreImage
import CoreImage.CIFilterBuiltins

/// Looks you can put on the camera. Chosen to be recognisable at 40pt in a
/// chip, which rules out anything subtle.
nonisolated enum CaptureFilter: String, CaseIterable, Identifiable {
    case none, mono, sepia, vhs, thermal, pixel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .mono: "Mono"
        case .sepia: "Sepia"
        case .vhs: "VHS"
        case .thermal: "Heat"
        case .pixel: "Pixel"
        }
    }

    /// Applied to every displayed frame, and to whatever gets saved — what you
    /// see is what lands on disk.
    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image

        case .mono:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .sepia:
            let filter = CIFilter.sepiaTone()
            filter.inputImage = image
            filter.intensity = 0.9
            return filter.outputImage ?? image

        case .vhs:
            // Bleached, slightly shifted and scan-lined — the tape look comes
            // from the combination, not from any one filter.
            let colour = CIFilter.colorControls()
            colour.inputImage = image
            colour.saturation = 1.7
            colour.contrast = 1.15
            colour.brightness = 0.02
            let shifted = CIFilter.hueAdjust()
            shifted.inputImage = colour.outputImage ?? image
            shifted.angle = 0.12
            guard let base = shifted.outputImage else { return image }

            let stripes = CIFilter.stripesGenerator()
            stripes.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0.22)
            stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
            stripes.width = 2
            stripes.sharpness = 0
            guard let lines = stripes.outputImage?.cropped(to: base.extent) else { return base }
            return lines.composited(over: base)

        case .thermal:
            let filter = CIFilter.thermal()
            filter.inputImage = image
            return filter.outputImage ?? image

        case .pixel:
            let filter = CIFilter.pixellate()
            filter.inputImage = image
            filter.scale = Float(max(6, image.extent.width / 90))
            filter.center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            return filter.outputImage?.cropped(to: image.extent) ?? image
        }
    }
}
