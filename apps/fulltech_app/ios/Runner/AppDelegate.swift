import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pendingBackupPath: String?
  private var backupOpenChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      backupOpenChannel = FlutterMethodChannel(
        name: "com.daleventa.pos/backup_open",
        binaryMessenger: controller.binaryMessenger
      )
      backupOpenChannel?.setMethodCallHandler { [weak self] call, result in
        if call.method == "takeInitialBackupPath" {
          let path = self?.pendingBackupPath
          self?.pendingBackupPath = nil
          result(path)
          return
        }
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if url.pathExtension.lowercased() == "dvbackup" || url.pathExtension.lowercased() == "zip" {
      pendingBackupPath = url.path
      backupOpenChannel?.invokeMethod("backupOpened", arguments: url.path)
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
