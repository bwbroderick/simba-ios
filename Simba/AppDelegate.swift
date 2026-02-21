import UIKit
import GoogleSignIn
import BackgroundTasks
import OSLog

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.bb.simba.app.refresh",
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        scheduleAppRefresh()
        return true
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleAppRefresh()
    }

    private func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.bb.simba.app.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.sync.info("Background refresh scheduled")
        } catch {
            Logger.sync.error("Failed to schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let refreshTask = Task { @MainActor in
            let viewModel = GmailViewModel()

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                GIDSignIn.sharedInstance.restorePreviousSignIn { _, _ in
                    continuation.resume()
                }
            }

            if let count = await viewModel.fetchInboxUnreadCount() {
                UIApplication.shared.applicationIconBadgeNumber = count
                Logger.sync.info("Badge updated to \(count, privacy: .public)")
            }

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
