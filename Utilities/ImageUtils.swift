import Foundation
import UIKit

final class ImageUtils {
    static let shared = ImageUtils()
    
    private init() {}
    
    func compressImage(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }
    
    func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        let widthRatio = targetSize.width / image.size.width
        let heightRatio = targetSize.height / image.size.height
        
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: image.size.width * ratio,
            height: image.size.height * ratio
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    func resizeForStorage(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage? {
        let size = image.size
        
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        let ratio = size.width > size.height
            ? maxDimension / size.width
            : maxDimension / size.height
        
        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )
        
        return resizeImage(image, targetSize: newSize)
    }
    
    func createThumbnail(_ image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage? {
        return resizeImage(image, targetSize: size)
    }
    
    func saveImage(_ image: UIImage, to url: URL, quality: CGFloat = 0.8) throws {
        guard let data = compressImage(image, quality: quality) else {
            throw ImageUtilsError.compressionFailed
        }
        
        try data.write(to: url)
    }
    
    func loadImage(from url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }
    
    func createGridImage(from images: [UIImage], columns: Int = 3, cellSize: CGSize = CGSize(width: 100, height: 100)) -> UIImage? {
        guard !images.isEmpty else { return nil }
        
        let rows = (images.count + columns - 1) / columns
        
        let width = CGFloat(columns) * cellSize.width
        let height = CGFloat(rows) * cellSize.height
        
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
            
            for (index, image) in images.enumerated() {
                let row = index / columns
                let col = index % columns
                
                let x = CGFloat(col) * cellSize.width
                let y = CGFloat(row) * cellSize.height
                
                let rect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
                
                let thumbnail = createThumbnail(image, size: cellSize) ?? image
                thumbnail.draw(in: rect)
            }
        }
    }
    
    func detectBrightness(_ image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.5 }
        
        let width = 50
        let height = 50
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0.5 }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalBrightness: Double = 0
        let pixelCount = Double(width * height)
        
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = Double(rawData[i])
            let g = Double(rawData[i + 1])
            let b = Double(rawData[i + 2])
            
            let brightness = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
            totalBrightness += brightness
        }
        
        return totalBrightness / pixelCount
    }
    
    func isImageTooDark(_ image: UIImage, threshold: Double = 0.2) -> Bool {
        return detectBrightness(image) < threshold
    }
    
    func isImageTooBlurry(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }
        
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        guard let filter = CIFilter(name: "CILaplacian") else { return false }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let outputImage = filter.outputImage else { return false }
        
        var bitmap = [UInt8](repeating: 0, count: 1)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 1,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        return bitmap[0] < 10
    }
}

enum ImageUtilsError: LocalizedError {
    case compressionFailed
    case saveFailed
    case loadFailed
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress image"
        case .saveFailed:
            return "Failed to save image"
        case .loadFailed:
            return "Failed to load image"
        }
    }
}
