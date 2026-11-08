import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var backgroundCompletion: (() -> Void)?
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Self.backgroundCompletion = completionHandler
    }
}

@main struct CloudPlayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .onOpenURL { url in store.playback = nil; store.handle(url) }
        }
    }
}
