import Foundation
import UIKit

final class MemoryCamTestHarness {
    static let shared = MemoryCamTestHarness()
    
    private let memoryManager = MemoryManager.shared
    private let sceneMatcher = SceneMatcher.shared
    private let searchEngine = SearchEngine.shared
    private let featureExtractor = FeatureExtractor.shared
    
    private init() {}
    
    func testMemoryFlow() async {
        print("========================================")
        print("Starting MemoryCam Test Flow")
        print("========================================")
        
        do {
            print("\n[TEST] Step 1: Load existing memories")
            await memoryManager.loadMemories()
            print("[TEST] Loaded \(memoryManager.memories.count) existing memories")
            
            print("\n[TEST] Step 2: Create test images")
            let testImages = generateTestImages(count: 5)
            print("[TEST] Generated \(testImages.count) test images")
            
            print("\n[TEST] Step 3: Save a new memory")
            let testMemory = try await memoryManager.saveMemory(
                itemName: "test_passport",
                locationDescription: "red drawer",
                capturedFrames: testImages,
                notes: "Test memory for validation"
            )
            print("[TEST] Saved memory: \(testMemory.id)")
            print("[TEST] Item: \(testMemory.itemName)")
            print("[TEST] Location: \(testMemory.locationDescription)")
            print("[TEST] Reference frames: \(testMemory.referenceFrames.count)")
            print("[TEST] Feature descriptors: \(testMemory.featureDescriptors.count)")
            
            print("\n[TEST] Step 4: Search for memory")
            let searchResults = searchEngine.search(query: "passport", in: memoryManager.memories)
            print("[TEST] Search results: \(searchResults.count) found")
            if let first = searchResults.first {
                print("[TEST] First result: \(first.itemName)")
            }
            
            print("\n[TEST] Step 5: Fuzzy search")
            let fuzzyResults = searchEngine.search(query: "pasprt", in: memoryManager.memories)
            print("[TEST] Fuzzy search results: \(fuzzyResults.count) found")
            
            print("\n[TEST] Step 6: Test scene matching with reference frames")
            await sceneMatcher.loadReferenceDescriptors(for: memoryManager.memories)
            
            if let referenceImage = testMemory.referenceImages.first {
                let matchResult = try await sceneMatcher.findBestMatch(
                    referenceImage,
                    againstMemories: [testMemory]
                )
                
                if let result = matchResult {
                    print("[TEST] Match result:")
                    print("[TEST]   Memory ID: \(result.memoryId)")
                    print("[TEST]   Similarity: \(result.similarityScore)")
                    print("[TEST]   State: \(result.matchState.rawValue)")
                    print("[TEST]   Bounding box: \(result.boundingBox?.description ?? "nil")")
                }
            }
            
            print("\n[TEST] Step 7: Test scene matching with different image")
            let differentImage = testImages.last!
            let differentMatchResult = try await sceneMatcher.findBestMatch(
                differentImage,
                againstMemories: [testMemory]
            )
            
            if let result = differentMatchResult {
                print("[TEST] Different image match:")
                print("[TEST]   Similarity: \(result.similarityScore)")
                print("[TEST]   State: \(result.matchState.rawValue)")
            }
            
            print("\n[TEST] Step 8: Test suggestions")
            let suggestions = searchEngine.suggestCompletions(for: "test", in: memoryManager.memories)
            print("[TEST] Suggestions: \(suggestions)")
            
            print("\n[TEST] Step 9: Get recent memories")
            let recentMemories = memoryManager.getRecentMemories(limit: 5)
            print("[TEST] Recent memories: \(recentMemories.count)")
            
            print("\n[TEST] Step 10: Clean up test memory")
            try await memoryManager.deleteMemory(id: testMemory.id)
            print("[TEST] Deleted test memory")
            
            print("\n========================================")
            print("MemoryCam Test Flow Completed Successfully!")
            print("========================================")
            
        } catch {
            print("[TEST] Error during test flow: \(error)")
        }
    }
    
    func testFeaturePrintExtraction() async {
        print("\n========================================")
        print("Testing Feature Print Extraction")
        print("========================================")
        
        let testImages = generateTestImages(count: 3)
        
        print("\n[TEST] Extracting feature prints from \(testImages.count) images")
        
        for (index, image) in testImages.enumerated() {
            do {
                let featurePrint = try await featureExtractor.extractFeaturePrint(from: image)
                print("[TEST] Image \(index + 1): Extracted feature print successfully")
            } catch {
                print("[TEST] Image \(index + 1): Failed - \(error)")
            }
        }
        
        if testImages.count >= 2 {
            print("\n[TEST] Testing similarity computation")
            do {
                let fp1 = try await featureExtractor.extractFeaturePrint(from: testImages[0])
                let fp2 = try await featureExtractor.extractFeaturePrint(from: testImages[1])
                let similarity = try featureExtractor.computeSimilarity(between: fp1, and: fp2)
                print("[TEST] Similarity between first two images: \(similarity)")
            } catch {
                print("[TEST] Similarity computation failed: \(error)")
            }
        }
        
        print("\n========================================")
        print("Feature Print Extraction Test Completed")
        print("========================================")
    }
    
    func testSceneMatchingWithMultipleMemories() async {
        print("\n========================================")
        print("Testing Scene Matching with Multiple Memories")
        print("========================================")
        
        let images1 = generateTestImages(count: 3)
        let images2 = generateTestImages(count: 3)
        
        do {
            let memory1 = try await memoryManager.saveMemory(
                itemName: "wallet",
                locationDescription: "front pocket",
                capturedFrames: images1
            )
            
            let memory2 = try await memoryManager.saveMemory(
                itemName: "keys",
                locationDescription: "bowl on table",
                capturedFrames: images2
            )
            
            print("\n[TEST] Created 2 test memories")
            
            await sceneMatcher.loadReferenceDescriptors(for: memoryManager.memories)
            
            let testFrame = images1.first!
            let results = try await sceneMatcher.matchFrame(testFrame, againstMemories: [memory1, memory2])
            
            print("\n[TEST] Matching results:")
            for result in results {
                let memory = memoryManager.memories.first { $0.id == result.memoryId }
                print("[TEST]   \(memory?.itemName ?? "unknown"): \(result.similarityScore) - \(result.matchState.rawValue)")
            }
            
            try await memoryManager.deleteMemory(id: memory1.id)
            try await memoryManager.deleteMemory(id: memory2.id)
            
            print("\n========================================")
            print("Multiple Memories Test Completed")
            print("========================================")
            
        } catch {
            print("[TEST] Error: \(error)")
        }
    }
    
    func testSearchEngine() {
        print("\n========================================")
        print("Testing Search Engine")
        print("========================================")
        
        let testMemories: [MemoryItem] = [
            MemoryItem(itemName: "Passport", locationDescription: "Red drawer"),
            MemoryItem(itemName: "Laptop", locationDescription: "Office desk"),
            MemoryItem(itemName: "Car Keys", locationDescription: "Kitchen bowl"),
            MemoryItem(itemName: "Wallet", locationDescription: "Back pocket"),
            MemoryItem(itemName: "Passport Photos", locationDescription: "Blue folder")
        ]
        
        let queries = ["passport", "key", "desk", "xyz123", "car"]
        
        for query in queries {
            let results = searchEngine.search(query: query, in: testMemories)
            print("\n[TEST] Query: '\(query)'")
            print("[TEST] Results: \(results.count)")
            for result in results {
                print("  - \(result.itemName) (\(result.locationDescription))")
            }
        }
        
        print("\n========================================")
        print("Search Engine Test Completed")
        print("========================================")
    }
    
    private func generateTestImages(count: Int) -> [UIImage] {
        var images: [UIImage] = []
        
        let size = CGSize(width: 640, height: 480)
        
        for i in 0..<count {
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
                let hue = CGFloat(i) / CGFloat(count)
                let color = UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)
                
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                
                let rectSize: CGFloat = 100
                let x = CGFloat(i) * (size.width / CGFloat(count + 1))
                let y = size.height / 2 - rectSize / 2
                
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: rectSize, height: rectSize))
            }
            
            images.append(image)
        }
        
        return images
    }
}

extension CGRect {
    var description: String {
        return "CGRect(x: \(origin.x), y: \(origin.y), width: \(size.width), height: \(size.height))"
    }
}
