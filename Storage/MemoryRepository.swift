import Foundation

protocol MemoryRepositoryProtocol {
    func saveMemory(_ memory: MemoryItem) async throws
    func fetchAllMemories() async throws -> [MemoryItem]
    func searchMemory(query: String) async throws -> [MemoryItem]
    func updateMemory(_ memory: MemoryItem) async throws
    func deleteMemory(id: UUID) async throws
    func fetchMemory(id: UUID) async throws -> MemoryItem?
    
    func saveDescriptors(_ descriptors: [Data], for memoryId: UUID) async throws
    func loadDescriptors(for memoryId: UUID) async throws -> [Data]
    func deleteDescriptors(for memoryId: UUID) async throws
}

final class MemoryRepository: MemoryRepositoryProtocol {
    static let shared = MemoryRepository()
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let memoriesFileName = "memories.json"
    
    private let ioQueue = DispatchQueue(label: "com.memorycam.repository.io", qos: .utility)
    
    private var memoriesDirectory: URL {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let memoriesDir = documentsDirectory.appendingPathComponent("Memories", isDirectory: true)
        
        if !fileManager.fileExists(atPath: memoriesDir.path) {
            try? fileManager.createDirectory(at: memoriesDir, withIntermediateDirectories: true)
        }
        
        return memoriesDir
    }
    
    private var memoriesFileURL: URL {
        memoriesDirectory.appendingPathComponent(memoriesFileName)
    }
    
    private var referenceImagesDirectory: URL {
        let dir = memoriesDirectory.appendingPathComponent("ReferenceImages", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private var descriptorsDirectory: URL {
        let dir = memoriesDirectory.appendingPathComponent("Descriptors", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func saveMemory(_ memory: MemoryItem) async throws {
        var memories = try await fetchAllMemories()
        memories.append(memory)
        try await saveAllMemories(memories)
        
        if !memory.featureDescriptors.isEmpty {
            try await saveDescriptors(memory.featureDescriptors, for: memory.id)
        }
    }
    
    func fetchAllMemories() async throws -> [MemoryItem] {
        guard fileManager.fileExists(atPath: memoriesFileURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: memoriesFileURL)
        return try decoder.decode([MemoryItem].self, from: data)
    }
    
    func searchMemory(query: String) async throws -> [MemoryItem] {
        let memories = try await fetchAllMemories()
        let lowercasedQuery = query.lowercased()
        
        return memories.filter { memory in
            memory.itemName.lowercased().contains(lowercasedQuery) ||
            memory.locationDescription.lowercased().contains(lowercasedQuery) ||
            (memory.notes?.lowercased().contains(lowercasedQuery) ?? false)
        }
    }
    
    func updateMemory(_ memory: MemoryItem) async throws {
        var memories = try await fetchAllMemories()
        
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
            try await saveAllMemories(memories)
            
            try await saveDescriptors(memory.featureDescriptors, for: memory.id)
        } else {
            throw MemoryRepositoryError.memoryNotFound
        }
    }
    
    func deleteMemory(id: UUID) async throws {
        var memories = try await fetchAllMemories()
        memories.removeAll { $0.id == id }
        try await saveAllMemories(memories)
        
        let imageDir = referenceImagesDirectory.appendingPathComponent(id.uuidString)
        try? fileManager.removeItem(at: imageDir)
        
        try await deleteDescriptors(for: id)
    }
    
    func fetchMemory(id: UUID) async throws -> MemoryItem? {
        let memories = try await fetchAllMemories()
        return memories.first { $0.id == id }
    }
    
    func saveReferenceImage(_ imageData: Data, memoryId: UUID, index: Int) throws -> URL {
        let imageDir = referenceImagesDirectory.appendingPathComponent(memoryId.uuidString, isDirectory: true)
        
        if !fileManager.fileExists(atPath: imageDir.path) {
            try fileManager.createDirectory(at: imageDir, withIntermediateDirectories: true)
        }
        
        let imageURL = imageDir.appendingPathComponent("frame_\(index).jpg")
        try imageData.write(to: imageURL)
        return imageURL
    }
    
    func saveDescriptors(_ descriptors: [Data], for memoryId: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: ())
                    return
                }
                
                do {
                    let descriptorFile = self.descriptorsDirectory.appendingPathComponent("\(memoryId.uuidString).data")
                    
                    var container = DescriptorContainer(descriptors: descriptors)
                    let data = try NSKeyedArchiver.archivedData(withRootObject: container, requiringSecureCoding: false)
                    try data.write(to: descriptorFile, options: .atomic)
                    
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func loadDescriptors(for memoryId: UUID) async throws -> [Data] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Data], Error>) in
            ioQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                
                let descriptorFile = self.descriptorsDirectory.appendingPathComponent("\(memoryId.uuidString).data")
                
                guard self.fileManager.fileExists(atPath: descriptorFile.path) else {
                    continuation.resume(returning: [])
                    return
                }
                
                do {
                    let data = try Data(contentsOf: descriptorFile)
                    
                    if let container = try NSKeyedUnarchiver.unarchivedObject(ofClass: DescriptorContainer.self, from: data) {
                        continuation.resume(returning: container.descriptors)
                    } else {
                        continuation.resume(returning: [])
                    }
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func deleteDescriptors(for memoryId: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: ())
                    return
                }
                
                let descriptorFile = self.descriptorsDirectory.appendingPathComponent("\(memoryId.uuidString).data")
                try? self.fileManager.removeItem(at: descriptorFile)
                
                continuation.resume(returning: ())
            }
        }
    }
    
    private func saveAllMemories(_ memories: [MemoryItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ioQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: ())
                    return
                }
                
                do {
                    let data = try self.encoder.encode(memories)
                    try data.write(to: self.memoriesFileURL, options: .atomic)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@objc(DescriptorContainer)
final class DescriptorContainer: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    
    let descriptors: [Data]
    
    init(descriptors: [Data]) {
        self.descriptors = descriptors
        super.init()
    }
    
    required init?(coder: NSCoder) {
        guard let dataArray = coder.decodeObject(of: [NSArray.self, NSData.self], forKey: "descriptors") as? [NSData] else {
            self.descriptors = []
            super.init()
            return
        }
        self.descriptors = dataArray.map { $0 as Data }
        super.init()
    }
    
    func encode(with coder: NSCoder) {
        let dataArray = descriptors.map { NSData(data: $0) }
        coder.encode(dataArray, forKey: "descriptors")
    }
}

enum MemoryRepositoryError: LocalizedError {
    case memoryNotFound
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .memoryNotFound:
            return "Memory not found"
        case .encodingFailed:
            return "Failed to encode memory"
        case .decodingFailed:
            return "Failed to decode memory"
        }
    }
}
