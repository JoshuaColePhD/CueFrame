import Foundation
import CoreImage
import CoreGraphics

final class ShapeMaskGenerator {
    func createMask(for shape: WebcamConfiguration.Shape, size: CGSize, scaleFactor: CGFloat) -> CIImage? {
        switch shape {
        case .circle:
            return createCircleMask(size: size)
        case .roundedRectangle:
            return createRoundedRectangleMask(size: size, cornerRadius: UIConstants.Size.iconMedium * scaleFactor)
        case .squircle:
            return createSquircleMask(size: size)
        }
    }

    private func createCircleMask(size: CGSize) -> CIImage? {
        let maskRect = CGRect(origin: .zero, size: size)
        let radius = min(size.width, size.height) / 2
        let center = CIVector(x: size.width / 2, y: size.height / 2)

        return CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": center,
            "inputRadius0": radius - 1,
            "inputRadius1": radius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.clear
        ])?.outputImage?.cropped(to: maskRect)
    }

    private func createRoundedRectangleMask(size: CGSize, cornerRadius: CGFloat) -> CIImage? {
        let rect = CGRect(origin: .zero, size: size)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = Int(size.width) * 4

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(rect)
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)

        let path = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()

        guard let cgImage = context.makeImage() else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private func createSquircleMask(size: CGSize) -> CIImage? {
        let rect = CGRect(origin: .zero, size: size)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(SquircleShape.cgPath(in: rect))
        context.fillPath()
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }
}
