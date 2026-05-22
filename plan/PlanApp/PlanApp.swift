import SwiftUI

@main
struct PlanMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PlanStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
                .onOpenURL { url in
                    store.handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refresh()
                    }
                }
        }
        .windowStyle(.titleBar)
    }
}
