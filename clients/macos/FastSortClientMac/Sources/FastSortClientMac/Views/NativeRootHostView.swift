import SwiftUI

struct NativeRootHostView: View {
    @StateObject private var appState = AppState()
    @StateObject private var navigationState = NavigationState()

    var body: some View {
        RootView(navigationState: navigationState)
            .environmentObject(appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
