import SwiftUI

struct LoadingView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(25)
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MemoryListItemView: View {
    let memory: MemoryItem
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.itemName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption)
                        Text(memory.locationDescription)
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                    
                    if !memory.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(memory.tags.prefix(3), id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(memory.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if memory.isVisualMemory {
                        Image(systemName: "camera.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct SaveSuccessView: View {
    @Binding var isVisible: Bool
    
    var body: some View {
        if isVisible {
            VStack(spacing: 15) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
                
                Text("Saved Successfully!")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.green.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    )
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview("Loading") {
    LoadingView(message: "Loading memories...")
}

#Preview("Empty") {
    EmptyStateView(
        title: "No Memories",
        message: "Start by adding your first memory",
        systemImage: "brain",
        actionTitle: "Add Memory",
        action: {}
    )
}
