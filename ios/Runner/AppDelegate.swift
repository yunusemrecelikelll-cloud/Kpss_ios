import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // "Günlük Çalışma Planı" hatırlatmaları (flutter_local_notifications).
    // Bu satır olmadan, uygulama ÖN PLANDAYKEN gelen yerel bildirimler
    // gösterilmez — kullanıcı uygulamayı açık unuttuğunda hatırlatmayı hiç
    // görmez. FlutterAppDelegate zaten UNUserNotificationCenterDelegate'i
    // uyguladığı için delegate olarak kendisini vermek yeterli.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
