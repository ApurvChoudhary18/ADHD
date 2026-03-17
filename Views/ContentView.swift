import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            AddMemoryView()
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                }
            
            ScanRoomView()
                .tabItem {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
            
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
