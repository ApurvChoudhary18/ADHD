import Foundation
import UIKit

struct MemoryHistory: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    var locationDescription: String
    var referenceFrames: [Data]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        locationDescription: String,
        referenceFrames: [UIImage] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.locationDescription = locationDescription
        self.referenceFrames = referenceFrames.map { $0.jpegData(compressionQuality: 0.8) ?? Data() }
    }

    var referenceImages: [UIImage] {
        referenceFrames.compactMap { UIImage(data: $0) }
    }
}
