import Foundation
import UIKit
import Vision

struct MemoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    var itemName: String
    var locationDescription: String
    var referenceFrames: [Data]
    var featureDescriptors: [Data]
    var createdAt: Date
    var updatedAt: Date
    var notes: String?
    var history: [MemoryHistory]
    var tags: [String]
    var accessCount: Int
    var isVisualMemory: Bool

    init(
        id: UUID = UUID(),
        itemName: String,
        locationDescription: String,
        referenceFrames: [UIImage] = [],
        featureDescriptors: [Data] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String? = nil,
        history: [MemoryHistory] = [],
        tags: [String] = [],
        accessCount: Int = 0,
        isVisualMemory: Bool = false
    ) {
        self.id = id
        self.itemName = itemName
        self.locationDescription = locationDescription
        self.referenceFrames = referenceFrames.map { $0.jpegData(compressionQuality: 0.8) ?? Data() }
        self.featureDescriptors = featureDescriptors
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.history = history
        self.tags = tags.isEmpty ? MemoryItem.generateTags(from: "\(itemName) \(locationDescription) \(notes ?? "")") : tags
        self.accessCount = accessCount
        self.isVisualMemory = !referenceFrames.isEmpty
    }

    var referenceImages: [UIImage] {
        referenceFrames.compactMap { UIImage(data: $0) }
    }

    var hasDescriptors: Bool {
        !featureDescriptors.isEmpty
    }

    func deserializeFeaturePrints() -> [VNFeaturePrintObservation] {
        return featureDescriptors.compactMap { data in
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
        }
    }

    mutating func addReferenceFrame(_ image: UIImage, descriptor: Data? = nil) {
        if let data = image.jpegData(compressionQuality: 0.8) {
            referenceFrames.append(data)
            if let descriptor = descriptor {
                featureDescriptors.append(descriptor)
            }
            updatedAt = Date()
        }
    }
    
    mutating func addFeaturePrint(_ featurePrint: VNFeaturePrintObservation) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: featurePrint, requiringSecureCoding: true) {
            featureDescriptors.append(data)
            updatedAt = Date()
        }
    }
    
    mutating func setFeaturePrints(_ featurePrints: [VNFeaturePrintObservation]) {
        featureDescriptors = featurePrints.compactMap { fp in
            try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
        }
        updatedAt = Date()
    }

    mutating func setFeatureDescriptors(_ descriptors: [Data]) {
        featureDescriptors = descriptors
        updatedAt = Date()
    }

    mutating func addHistoryEntry(_ entry: MemoryHistory) {
        history.append(entry)
        updatedAt = Date()
    }
    
    mutating func incrementAccessCount() {
        accessCount += 1
        updatedAt = Date()
    }
    
    mutating func updateTags() {
        tags = MemoryItem.generateTags(from: "\(itemName) \(locationDescription) \(notes ?? "")")
    }

    static func generateTags(from text: String) -> [String] {
        let stopWords = Set(["where", "is", "my", "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "up", "about", "into", "through", "during", "before", "after", "above", "below", "between", "under", "again", "further", "then", "once", "here", "there", "when", "where", "why", "how", "all", "each", "few", "more", "most", "other", "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than", "too", "very", "can", "will", "just", "should", "now", "find", "are", "was", "were", "been", "being", "have", "has", "had", "did", "does", "doing"])
        
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }
            .filter { !stopWords.contains($0) }
        
        return Array(Set(words))
    }

    static func == (lhs: MemoryItem, rhs: MemoryItem) -> Bool {
        lhs.id == rhs.id
    }
}
