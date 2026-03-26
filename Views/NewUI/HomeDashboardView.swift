import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject private var memoryManager = MemoryManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    actionCardsSection
                    
                    if !memoryManager.memories.isEmpty {
                        recentMemoriesSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("MemoryCam")
            .refreshable {
                await memoryManager.loadMemories()
            }
            .onAppear {
                loadData()
            }
        }
    }
    
    private func loadData() {
        if memoryManager.memories.isEmpty {
            Task {
                await memoryManager.loadMemories()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Your AI Memory Assistant")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            NavigationLink(destination: AddMemoryModernView()) {
                ActionCardView(
                    icon: "plus.circle.fill",
                    title: "Add Memory",
                    subtitle: "Save a new item location",
                    color: .blue
                )
            }
            
            NavigationLink(destination: ScanModernView()) {
                ActionCardView(
                    icon: "camera.viewfinder",
                    title: "Find Object",
                    subtitle: "Scan your surroundings",
                    color: .green
                )
            }
            
            NavigationLink(destination: SearchModernView()) {
                ActionCardView(
                    icon: "magnifyingglass",
                    title: "Search Memories",
                    subtitle: "Find saved items",
                    color: .orange
                )
            }
        }
    }
    
    @ViewBuilder
    private var recentMemoriesSection: some View {
        let recentMemories = memoryManager.getRecentMemories(limit: 3)
        if !recentMemories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Memories")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                ForEach(recentMemories) { memory in
                    NavigationLink(destination: MemoryDetailModernView(memory: memory)) {
                        MemoryRowView(memory: memory)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ActionCardView: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}

struct MemoryRowView: View {
    let memory: MemoryItem
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.blue)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.itemName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text(memory.locationDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(memory.createdAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeDashboardView()
}
