import Foundation

final class SearchEngine {
    static let shared = SearchEngine()
    
    private let stopWords = Set(["where", "is", "my", "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "from", "find", "find", "are", "was", "were", "can", "will", "this", "that", "have", "had", "did", "does", "doing"])
    
    private init() {}
    
    func search(query: String, in memories: [MemoryItem]) -> [MemoryItem] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return memories
        }
        
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        let searchKeywords = extractKeywords(from: normalizedQuery)
        
        guard !searchKeywords.isEmpty else {
            return []
        }
        
        var results: [(MemoryItem, Double)] = []
        
        for memory in memories {
            let score = calculateRelevanceScore(keywords: searchKeywords, memory: memory)
            if score > 0 {
                results.append((memory, score))
            }
        }
        
        return results
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }
    
    private func extractKeywords(from query: String) -> [String] {
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 1 }
            .filter { !stopWords.contains($0) }
        
        return words
    }
    
    private func calculateRelevanceScore(keywords: [String], memory: MemoryItem) -> Double {
        var score: Double = 0
        
        let itemName = memory.itemName.lowercased()
        let locationDescription = memory.locationDescription.lowercased()
        let notes = memory.notes?.lowercased() ?? ""
        let tags = memory.tags.map { $0.lowercased() }
        
        for keyword in keywords {
            if itemName == keyword {
                score += 100
            } else if itemName.hasPrefix(keyword) {
                score += 80
            } else if itemName.contains(keyword) {
                score += 60
            } else {
                let fuzzyScore = fuzzyMatch(query: keyword, target: itemName)
                score += fuzzyScore * 50
            }
            
            if locationDescription.contains(keyword) {
                score += 30
            } else {
                let fuzzyScore = fuzzyMatch(query: keyword, target: locationDescription)
                score += fuzzyScore * 20
            }
            
            if notes.contains(keyword) {
                score += 15
            }
            
            if tags.contains(keyword) {
                score += 40
            }
            
            for tag in tags {
                if tag.contains(keyword) || keyword.contains(tag) {
                    score += 35
                }
            }
            
            for word in itemName.split(separator: " ").map(String.init) {
                if word == keyword {
                    score += 25
                }
            }
            
            for word in locationDescription.split(separator: " ").map(String.init) {
                if word == keyword {
                    score += 10
                }
            }
        }
        
        return score
    }
    
    private func fuzzyMatch(query: String, target: String) -> Double {
        let queryChars = Array(query)
        let targetChars = Array(target)
        
        if queryChars.isEmpty || targetChars.isEmpty {
            return 0
        }
        
        var queryIndex = 0
        var matchCount = 0
        
        for char in targetChars {
            if queryIndex < queryChars.count && char == queryChars[queryIndex] {
                matchCount += 1
                queryIndex += 1
            }
        }
        
        let matchRatio = Double(matchCount) / Double(queryChars.count)
        let lengthPenalty = 1.0 - (Double(targetChars.count - queryChars.count) / Double(max(targetChars.count, queryChars.count)))
        
        return matchRatio * 0.7 + max(0, lengthPenalty) * 0.3
    }
    
    func suggestCompletions(for prefix: String, in memories: [MemoryItem]) -> [String] {
        guard !prefix.isEmpty else { return [] }
        
        let normalizedPrefix = prefix.lowercased()
        
        var suggestions = Set<String>()
        
        for memory in memories {
            let itemName = memory.itemName.lowercased()
            if itemName.hasPrefix(normalizedPrefix) {
                suggestions.insert(memory.itemName)
            }
            
            for word in itemName.split(separator: " ") {
                if String(word).hasPrefix(normalizedPrefix) {
                    suggestions.insert(String(word))
                }
            }
        }
        
        return Array(suggestions).sorted().prefix(5).map { $0 }
    }
}
