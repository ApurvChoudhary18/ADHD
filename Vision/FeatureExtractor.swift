import Foundation
import Vision
import UIKit
import CoreImage

final class FeatureExtractor: @unchecked Sendable {
    static let shared = FeatureExtractor()
    
    private let context: CIContext
    private var descriptorCache: [String: VNFeaturePrintObservation] = [:]
    private let cacheQueue = DispatchQueue(label: "com.memorycam.featureextractor.cache")
    
    static var debugMode: Bool = false
    
    private init() {
        context = CIContext(options: [.useSoftwareRenderer: false])
    }
    
    func extractFeaturePrint(from image: UIImage) async throws -> VNFeaturePrintObservation {
        let processedImage = preprocessFrame(image) ?? image
        
        guard let cgImage = processedImage.cgImage else {
            throw FeatureExtractionError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision1
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request]) { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let featurePrint = request.results?.first as? VNFeaturePrintObservation else {
                        continuation.resume(throwing: FeatureExtractionError.noFeaturesFound)
                        return
                    }
                    
                    continuation.resume(returning: featurePrint)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func extractFeaturePrints(from image: UIImage) async throws -> [VNFeaturePrintObservation] {
        let featurePrint = try await extractFeaturePrint(from: image)
        return [featurePrint]
    }
    
    func computeSimilarity(between observationA: VNFeaturePrintObservation, and observationB: VNFeaturePrintObservation) throws -> Float {
        var distance: Float = 0
        try observationA.computeDistance(&distance, to: observationB)
        let similarity = 1.0 / (1.0 + distance)
        return similarity
    }
    
    func computeBatchSimilarity(live: [VNFeaturePrintObservation], reference: [VNFeaturePrintObservation]) -> Float {
        guard !live.isEmpty && !reference.isEmpty else {
            return 0.0
        }
        
        var maxSimilarity: Float = 0.0
        
        for liveFP in live {
            for refFP in reference {
                do {
                    let similarity = try computeSimilarity(between: liveFP, and: refFP)
                    maxSimilarity = max(maxSimilarity, similarity)
                } catch {
                    continue
                }
            }
        }
        
        return maxSimilarity
    }
    
    private func preprocessFrame(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        var ciImage = CIImage(cgImage: cgImage)
        
        let metrics = analyzeFrameQuality(image)
        
        if metrics.isTooDark {
            ciImage = applyBrightnessCorrection(ciImage, targetBrightness: 0.4)
        }
        
        let currentContrast = metrics.contrast
        if currentContrast < 0.5 {
            ciImage = applyContrastAdjustment(ciImage, factor: 1.5)
        }
        
        ciImage = applySharpening(ciImage, intensity: 0.3)
        
        guard let outputCGImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: outputCGImage)
    }
    
    private func analyzeFrameQuality(_ image: UIImage) -> FrameQualityMetrics {
        guard let cgImage = image.cgImage else {
            return FrameQualityMetrics(brightness: 0.5, contrast: 0.5, sharpness: 50.0)
        }
        
        let width = min(cgImage.width, 100)
        let height = min(cgImage.height, 100)
        
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
        ) else {
            return FrameQualityMetrics(brightness: 0.5, contrast: 0.5, sharpness: 50.0)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalBrightness: Double = 0
        var minBrightness: Double = 255
        var maxBrightness: Double = 0
        
        for i in stride(from: 0, to: rawData.count, by: 4) {
            let r = Double(rawData[i])
            let g = Double(rawData[i + 1])
            let b = Double(rawData[i + 2])
            
            let brightness = (r * 0.299 + g * 0.587 + b * 0.114)
            totalBrightness += brightness
            minBrightness = min(minBrightness, brightness)
            maxBrightness = max(maxBrightness, brightness)
        }
        
        let pixelCount = Double(width * height)
        let avgBrightness = totalBrightness / pixelCount / 255.0
        let contrast = (maxBrightness - minBrightness) / 255.0
        
        let sharpness = computeSharpness(cgImage: cgImage)
        
        return FrameQualityMetrics(
            brightness: avgBrightness,
            contrast: contrast,
            sharpness: sharpness
        )
    }
    
    private func computeSharpness(cgImage: CGImage) -> Double {
        let width = min(cgImage.width, 50)
        let height = min(cgImage.height, 50)
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 50.0 }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var laplacianSum: Double = 0
        var count: Double = 0
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let current = Double(pixels[y * width + x])
                let top = Double(pixels[(y - 1) * width + x])
                let bottom = Double(pixels[(y + 1) * width + x])
                let left = Double(pixels[y * width + (x - 1)])
                let right = Double(pixels[y * width + (x + 1)])
                
                let laplacian = abs(4 * current - top - bottom - left - right)
                laplacianSum += laplacian
                count += 1
            }
        }
        
        return count > 0 ? laplacianSum / count : 50.0
    }
    
    private func applyBrightnessCorrection(_ image: CIImage, targetBrightness: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(targetBrightness - 0.5, forKey: kCIInputBrightnessKey)
        
        return filter.outputImage ?? image
    }
    
    private func applyContrastAdjustment(_ image: CIImage, factor: Double) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputContrastKey)
        
        return filter.outputImage ?? image
    }
    
    private func applySharpening(_ image: CIImage, intensity: Double) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else { return image }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputSharpnessKey)
        
        return filter.outputImage ?? image
    }
    
    func extractFeatures(from image: UIImage) async throws -> VNFeaturePrintObservation {
        return try await extractFeaturePrint(from: image)
    }
    
    func clearCache() {
        cacheQueue.async { [weak self] in
            self?.descriptorCache.removeAll()
        }
    }
}

struct FrameQualityMetrics {
    let brightness: Double
    let contrast: Double
    let sharpness: Double
    let isTooDark: Bool
    let isTooBlurry: Bool
    let isGoodQuality: Bool
    
    static let minimumBrightness: Double = 0.15
    static let minimumSharpness: Double = 10.0
    static let minimumContrast: Double = 0.2
    
    init(brightness: Double, contrast: Double, sharpness: Double) {
        self.brightness = brightness
        self.contrast = contrast
        self.sharpness = sharpness
        self.isTooDark = brightness < FrameQualityMetrics.minimumBrightness
        self.isTooBlurry = sharpness < FrameQualityMetrics.minimumSharpness
        self.isGoodQuality = !isTooDark && !isTooBlurry && contrast >= FrameQualityMetrics.minimumContrast
    }
}

enum FeatureExtractionError: LocalizedError {
    case invalidImage
    case noFeaturesFound
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image provided"
        case .noFeaturesFound:
            return "No features found in image"
        case .processingFailed:
            return "Failed to process image"
        }
    }
}
