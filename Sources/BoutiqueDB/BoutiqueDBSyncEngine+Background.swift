import Foundation
#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
  import BackgroundTasks
  import UIKit
#endif
#if os(macOS)
  import AppKit
#endif

extension BoutiqueDBSyncEngine {
  /// Default background-task identifier used by ``registerBackgroundTask(_:)``
  /// and ``scheduleBackgroundSync(identifier:earliestBeginDate:)``.
  public static let defaultBackgroundTaskIdentifier = "com.boutiquedb.cloudkit-sync"

  #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    /// Registers with APNs for CloudKit remote push notifications.
    ///
    /// Call from `UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:)`
    /// after the user grants notification authorization.
    public func registerForRemoteNotifications() {
      UIApplication.shared.registerForRemoteNotifications()
    }

    /// Handles an incoming remote notification by fetching the latest CloudKit changes.
    ///
    /// Wire this to `UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
    public func handleRemoteNotification(
      userInfo: [AnyHashable: Any],
      fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
      Task { @MainActor [weak self] in
        guard let self else {
          completionHandler(.noData)
          return
        }
        do {
          try await self.fetchChanges()
          completionHandler(.newData)
        } catch {
          completionHandler(.failed)
        }
      }
    }

    /// Registers a `BGAppRefreshTask` with `BGTaskScheduler`.
    ///
    /// Add the identifier to your `Info.plist`
    /// `BGTaskSchedulerPermittedIdentifiers` array, and call this from
    /// `UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:)`.
    @discardableResult
    public func registerBackgroundTask(
      identifier: String = defaultBackgroundTaskIdentifier
    ) -> Bool {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) {
        [weak self] task in
        Task { @MainActor [weak self] in
          self?.performBackgroundTask(task)
        }
      }
    }

    /// Submits a background refresh request to the system.
    ///
    /// The system invokes the block registered with ``registerBackgroundTask(_:)``
    /// when conditions allow. Use this after local writes for an expedited outbound
    /// sync, or schedule periodically from `applicationDidEnterBackground`.
    public func scheduleBackgroundSync(
      identifier: String = defaultBackgroundTaskIdentifier,
      earliestBeginDate: Date? = nil
    ) {
      let request = BGAppRefreshTaskRequest(identifier: identifier)
      request.earliestBeginDate = earliestBeginDate
      do {
        try BGTaskScheduler.shared.submit(request)
      } catch {
        // Scheduling failures are non-fatal; the next remote notification or
        // foreground sync will still occur.
      }
    }

    private func performBackgroundTask(_ task: BGTask) {
      task.expirationHandler = { [weak self] in
        Task { @MainActor [weak self] in
          _ = try? await self?.drainCDC()
        }
        task.setTaskCompleted(success: false)
      }

      Task { @MainActor [weak self] in
        guard let self else {
          task.setTaskCompleted(success: false)
          return
        }
        do {
          _ = try await self.drainCDC()
          try await self.syncChanges()
          task.setTaskCompleted(success: true)
        } catch {
          task.setTaskCompleted(success: false)
        }
      }
    }
  #endif

  #if os(macOS)
    /// Registers with APNs for CloudKit remote push notifications on macOS.
    public func registerForRemoteNotifications() {
      NSApplication.shared.registerForRemoteNotifications()
    }

    /// Handles an incoming remote notification by fetching the latest CloudKit changes.
    ///
    /// Wire this to `NSApplicationDelegate.application(_:didReceiveRemoteNotification:)`.
    public func handleRemoteNotification(userInfo: [String: Any]) {
      Task { @MainActor [weak self] in
        guard let self else { return }
        try? await self.fetchChanges()
      }
    }

    /// Schedules a repeating background sync activity on macOS using
    /// `NSBackgroundActivityScheduler`.
    ///
    /// This is the macOS equivalent of `BGTaskScheduler` on iOS. The returned
    /// scheduler is already scheduled; keep a reference if you need to
    /// `invalidate()` it later.
    @discardableResult
    public func scheduleBackgroundSync(
      identifier: String = defaultBackgroundTaskIdentifier,
      interval: TimeInterval = 15 * 60
    ) -> NSBackgroundActivityScheduler {
      let scheduler = NSBackgroundActivityScheduler(identifier: identifier)
      scheduler.repeats = true
      scheduler.interval = interval
      scheduler.qualityOfService = .utility
      scheduler.schedule { [weak self] completion in
        Task { @MainActor [weak self] in
          guard let self else {
            completion(.finished)
            return
          }
          do {
            _ = try await self.drainCDC()
            try await self.syncChanges()
            completion(.finished)
          } catch {
            completion(.deferred)
          }
        }
      }
      return scheduler
    }
  #endif
}
