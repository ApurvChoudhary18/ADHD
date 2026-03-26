import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeDashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            AddMemoryModernView()
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .tag(1)
            
            ScanModernView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
                .tag(2)
            
            SearchModernView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(3)
        }
        .tint(.blue)
    }
}

#Preview {
    MainTabView()
}
