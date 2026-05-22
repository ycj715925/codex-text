import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PlanStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            TodayView()
                .tabItem {
                    Label("今天", systemImage: "checklist")
                }
                .tag(PlanTab.today)

            PlanView()
                .tabItem {
                    Label("计划", systemImage: "calendar")
                }
                .tag(PlanTab.plan)
        }
        .frame(minWidth: 820, minHeight: 560)
        .sheet(isPresented: $store.isShowingEditor) {
            TaskEditorView(task: store.editingTask)
                .environmentObject(store)
        }
    }
}
