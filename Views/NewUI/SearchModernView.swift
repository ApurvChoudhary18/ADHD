import SwiftUI

struct SearchModernView: View {
    @StateObject private var viewModel = SearchModernViewModel()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                
                if viewModel.displayMemories.isEmpty && viewModel.allMemories.isEmpty {
                    emptyState
                } else if viewModel.displayMemories.isEmpty && !viewModel.searchQuery.isEmpty {
                    noResultsView
                } else {
                    resultsList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Search")
            .onAppear {
                viewModel.refresh()
            }
        }
    }
    
    private var searchBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search memories...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if viewModel.isListening {
                    Button {
                        viewModel.stopListening()
                    } label: {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        viewModel.startListening()
                    } label: {
                        Image(systemName: "mic")
                            .foregroundStyle(.secondary)
                    }
                }
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if let error = viewModel.voiceError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No Memories Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add your first memory to start searching")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text("No Results")
                .font(.headline)
            
            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.displayMemories) { memory in
                    NavigationLink(destination: MemoryDetailModernView(memory: memory)) {
                        MemoryCardModernView(memory: memory)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }
}

struct MemoryCardModernView: View {
    let memory: MemoryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.itemName)
                        .font(.headline)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                        Text(memory.locationDescription)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if memory.isVisualMemory {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            
            if !memory.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(memory.tags.prefix(4), id: \.self) { tag in
                            TagChip(text: tag)
                        }
                    }
                }
            }
            
            HStack {
                Text(memory.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                Text("View")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

struct TagChip: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .clipShape(Capsule())
    }
}

struct MemoryDetailModernView: View {
    @State private var memory: MemoryItem
    
    init(memory: MemoryItem) {
        _memory = State(initialValue: memory)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                if !memory.tags.isEmpty {
                    tagsSection
                }
                
                if let notes = memory.notes, !notes.isEmpty {
                    notesSection(notes)
                }
                
                dateSection
                
                accessStatsSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Memory Details")
        .onAppear {
            recordAccess()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "brain.head.profile")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.itemName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(memory.locationDescription)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            FlowLayout(spacing: 8) {
                ForEach(memory.tags, id: \.self) { tag in
                    TagChip(text: tag)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text(notes)
                .font(.body)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Created")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(memory.createdAt, style: .date)
                        .font(.subheadline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Updated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(memory.updatedAt, style: .date)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var accessStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text("Viewed \(memory.accessCount) times")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func recordAccess() {
        MemoryManager.shared.recordMemoryAccess(memory.id)
        if let updated = MemoryManager.shared.getMemoryById(memory.id) {
            memory = updated
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX)
        }
        
        return (CGSize(width: totalWidth, height: currentY + lineHeight), positions)
    }
}

@MainActor
class SearchModernViewModel: ObservableObject {
    @Published var searchQuery = "" {
        didSet {
            performSearch()
        }
    }
    @Published var searchResults: [MemoryItem] = []
    @Published var allMemories: [MemoryItem] = []
    @Published var isListening = false
    @Published var voiceError: String?
    
    private let memoryManager = MemoryManager.shared
    private let voiceManager = VoiceInputManager.shared
    private let searchEngine = SearchEngine.shared
    
    var displayMemories: [MemoryItem] {
        if searchQuery.isEmpty {
            return allMemories
        }
        return searchResults
    }
    
    init() {
        setupVoiceCallback()
        refresh()
    }
    
    func refresh() {
        allMemories = memoryManager.memories
        performSearch()
    }
    
    private func setupVoiceCallback() {
        voiceManager.onResult = { [weak self] transcript in
            Task { @MainActor in
                self?.searchQuery = transcript
            }
        }
    }
    
    func startListening() {
        voiceError = nil
        
        Task {
            let authorized = await voiceManager.requestAuthorization()
            
            if authorized {
                do {
                    try voiceManager.startListening()
                    isListening = true
                } catch {
                    voiceError = error.localizedDescription
                    isListening = false
                }
            } else {
                voiceError = voiceManager.authorizationError ?? "Voice input not authorized"
                isListening = false
            }
        }
    }
    
    func stopListening() {
        voiceManager.stopListening()
        isListening = false
    }
    
    private func performSearch() {
        if searchQuery.isEmpty {
            searchResults = []
            return
        }
        
        searchResults = searchEngine.search(query: searchQuery, in: memoryManager.memories)
    }
}

#Preview {
    SearchModernView()
}
