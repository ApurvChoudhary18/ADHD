import Foundation
import UIKit
import Vision
import Combine

final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()
    
    @Published var memories: [MemoryItem] = []
    @Published var searchResults: [MemoryItem] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let repository: MemoryRepositoryProtocol
    private let searchEngine: SearchEngine
    private let featureExtractor: FeatureExtractor
    
    private init(
        repository: MemoryRepositoryProtocol = MemoryRepository.shared,
        searchEngine: SearchEngine = SearchEngine.shared,
        featureExtractor: FeatureExtractor = FeatureExtractor.shared
    ) {
        self.repository = repository
        self.searchEngine = searchEngine
        self.featureExtractor = featureExtractor
    }
    
    func loadMemories() async {
        await MainActor.run { isLoading = true }
        
        do {
            var fetchedMemories = try await repository.fetchAllMemories()
            
            for index in fetchedMemories.indices {
                if !fetchedMemories[index].hasDescriptors {
                    let persistedDescriptors = try await repository.loadDescriptors(for: fetchedMemories[index].id)
                    if !persistedDescriptors.isEmpty {
                        fetchedMemories[index].setFeatureDescriptors(persistedDescriptors)
                    } else if !fetchedMemories[index].referenceFrames.isEmpty {
                        let images = fetchedMemories[index].referenceImages
                        let newDescriptors = await extractFeaturePrints(from: images)
                        if !newDescriptors.isEmpty {
                            let serialized = newDescriptors.compactMap { fp -> Data? in
                                try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
                            }
                            fetchedMemories[index].setFeatureDescriptors(serialized)
                            try? await repository.saveDescriptors(serialized, for: fetchedMemories[index].id)
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.memories = fetchedMemories
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func saveMemory(
        itemName: String,
        locationDescription: String,
        capturedFrames: [UIImage] = [],
        notes: String? = nil,
        enableDiversityFilter: Bool = true
    ) async throws -> MemoryItem {
        let framesToUse: [UIImage]
        var serializedDescriptors: [Data] = []
        
        if !capturedFrames.isEmpty {
            if enableDiversityFilter && capturedFrames.count > 3 {
                framesToUse = Array(capturedFrames.prefix(8))
            } else {
                framesToUse = capturedFrames
            }
            
            let featurePrints = await extractFeaturePrints(from: framesToUse)
            
            serializedDescriptors = featurePrints.compactMap { fp -> Data? in
                try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
            }
        } else {
            framesToUse = []
        }
        
        let memory = MemoryItem(
            itemName: itemName,
            locationDescription: locationDescription,
            referenceFrames: framesToUse,
            featureDescriptors: serializedDescriptors,
            notes: notes,
            isVisualMemory: !capturedFrames.isEmpty
        )
        
        try await repository.saveMemory(memory)
        
        await MainActor.run {
            self.memories.append(memory)
        }
        
        return memory
    }
    
    private func extractFeaturePrints(from images: [UIImage]) async -> [VNFeaturePrintObservation] {
        var allFeaturePrints: [VNFeaturePrintObservation] = []
        
        for image in images {
            do {
                let fp = try await featureExtractor.extractFeaturePrint(from: image)
                allFeaturePrints.append(fp)
            } catch {
                print("[MemoryManager] Failed to extract feature print: \(error)")
            }
        }
        
        return allFeaturePrints
    }
    
    func saveMemoryWithDescriptors(
        itemName: String,
        locationDescription: String,
        capturedFrames: [UIImage],
        precomputedDescriptors: [Data],
        notes: String? = nil
    ) async throws -> MemoryItem {
        let memory = MemoryItem(
            itemName: itemName,
            locationDescription: locationDescription,
            referenceFrames: capturedFrames,
            featureDescriptors: precomputedDescriptors,
            notes: notes
        )
        
        try await repository.saveMemory(memory)
        
        await MainActor.run {
            self.memories.append(memory)
        }
        
        return memory
    }
    
    func updateMemory(_ memory: MemoryItem) async throws {
        var updatedMemory = memory
        updatedMemory.updatedAt = Date()
        
        try await repository.updateMemory(updatedMemory)
        
        await MainActor.run {
            if let index = self.memories.firstIndex(where: { $0.id == memory.id }) {
                self.memories[index] = updatedMemory
            }
        }
    }
    
    func regenerateDescriptors(for memoryId: UUID) async throws {
        guard let index = memories.firstIndex(where: { $0.id == memoryId }) else {
            throw MemoryManagerError.memoryNotFound
        }
        
        var memory = memories[index]
        let images = memory.referenceImages
        
        guard !images.isEmpty else { return }
        
        let featurePrints = await extractFeaturePrints(from: images)
        let serialized = featurePrints.compactMap { fp -> Data? in
            try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
        }
        
        memory.setFeatureDescriptors(serialized)
        
        try await repository.saveDescriptors(serialized, for: memoryId)
        try await updateMemory(memory)
    }
    
    func deleteMemory(id: UUID) async throws {
        try await repository.deleteMemory(id: id)
        
        await MainActor.run {
            self.memories.removeAll { $0.id == id }
            self.searchResults.removeAll { $0.id == id }
        }
    }
    
    func search(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        
        searchResults = searchEngine.search(query: query, in: memories)
    }
    
    func fuzzySearch(query: String) -> [MemoryItem] {
        return searchEngine.search(query: query, in: memories)
    }
    
    func getMemory(id: UUID) async throws -> MemoryItem? {
        return try await repository.fetchMemory(id: id)
    }
    
    func getMemoryById(_ id: UUID) -> MemoryItem? {
        return memories.first { $0.id == id }
    }
    
    func addReferenceFrame(_ image: UIImage, to memoryId: UUID) async throws {
        guard var memory = memories.first(where: { $0.id == memoryId }) else {
            throw MemoryManagerError.memoryNotFound
        }
        
        memory.addReferenceFrame(image)
        
        if let fp = try? await featureExtractor.extractFeaturePrint(from: image) {
            memory.addFeaturePrint(fp)
        }
        
        let serialized = memory.featureDescriptors
        try await repository.saveDescriptors(serialized, for: memoryId)
        try await updateMemory(memory)
    }
    
    func addHistoryEntry(to memoryId: UUID, entry: MemoryHistory) async throws {
        guard var memory = memories.first(where: { $0.id == memoryId }) else {
            throw MemoryManagerError.memoryNotFound
        }
        
        memory.addHistoryEntry(entry)
        
        try await updateMemory(memory)
    }
    
    func getRecentMemories(limit: Int = 10) -> [MemoryItem] {
        return Array(memories.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
    
    func getSuggestedMemories(limit: Int = 5) -> [MemoryItem] {
        let sortedByAccess = memories.sorted { $0.accessCount > $1.accessCount }
        let sortedByRecent = memories.sorted { $0.createdAt > $1.createdAt }
        
        var combined: [UUID: Double] = [:]
        
        for (index, memory) in sortedByAccess.enumerated() {
            let score = Double(sortedByAccess.count - index)
            combined[memory.id] = (combined[memory.id] ?? 0) + score
        }
        
        for (index, memory) in sortedByRecent.enumerated() {
            let score = Double(sortedByRecent.count - index) * 0.5
            combined[memory.id] = (combined[memory.id] ?? 0) + score
        }
        
        return memories
            .sorted { (combined[$0.id] ?? 0) > (combined[$1.id] ?? 0) }
            .prefix(limit)
            .map { $0 }
    }
    
    func recordMemoryAccess(_ memoryId: UUID) {
        if let index = memories.firstIndex(where: { $0.id == memoryId }) {
            memories[index].incrementAccessCount()
        }
    }
    
    func getMemoriesByDate(from startDate: Date, to endDate: Date) -> [MemoryItem] {
        return memories.filter { memory in
            memory.createdAt >= startDate && memory.createdAt <= endDate
        }
    }
    
    func suggestCompletions(for prefix: String) -> [String] {
        return searchEngine.suggestCompletions(for: prefix, in: memories)
    }
    
    func getMemoriesWithDescriptors() -> [MemoryItem] {
        return memories.filter { $0.hasDescriptors }
    }
    
    func getMemoriesMissingDescriptors() -> [MemoryItem] {
        return memories.filter { !$0.hasDescriptors }
    }
}

enum MemoryManagerError: LocalizedError {
    case memoryNotFound
    case saveFailed
    case updateFailed
    
    var errorDescription: String? {
        switch self {
        case .memoryNotFound:
            return "Memory not found"
        case .saveFailed:
            return "Failed to save memory"
        case .updateFailed:
            return "Failed to update memory"
        }
    }
}
