import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle URL scheme callbacks (e.g., from GameChanger wallet)
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    print("🔍 iOS AppDelegate: Received URL: \(url.absoluteString)")
    
    // Check if this is a GameChanger callback
    if url.scheme == "yuti" && url.host == "gamechanger-callback" {
      print("🔍 iOS AppDelegate: GameChanger callback detected")
      
      // Extract the result parameter
      if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
         let queryItems = components.queryItems,
         let resultItem = queryItems.first(where: { $0.name == "result" }),
         let resultValue = resultItem.value {
        
        print("🔍 iOS AppDelegate: GameChanger result data: \(resultValue)")
        
        // Send the callback data to Flutter using MethodChannel
        if let controller = window?.rootViewController as? FlutterViewController {
          let channel = FlutterMethodChannel(
            name: "com.yuti/gamechanger",
            binaryMessenger: controller.binaryMessenger
          )
          
          channel.invokeMethod("handleGameChangerCallback", arguments: resultValue)
          print("🔍 iOS AppDelegate: Sent callback data to Flutter")
        }
        
        return true
      }
    }

    // Payment success deep link: yuti://payment-success?status=success&order=...
    if url.scheme == "yuti" && url.host == "payment-success" {
      print("🔍 iOS AppDelegate: Payment success callback detected: \(url.absoluteString)")
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "com.yuti/payment",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("handlePaymentCallback", arguments: url.absoluteString)
        print("🔍 iOS AppDelegate: Sent payment callback data to Flutter")
      }
      return true
    }

    // CIP-186 deep-link signing receiver. Spec §URI format §Custom-scheme form.
    if url.scheme == "cip30dl-yuti" {
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "com.yuti/cip30",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("handleCip30DeepLink", arguments: url.absoluteString)
      }
      return true
    }

    // CIP-186 Universal-Link path. Wallet domain claim via apple-app-site-association.
    if url.scheme == "https" && url.path.hasPrefix("/cip30dl/v1/") {
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "com.yuti/cip30",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("handleCip30DeepLink", arguments: url.absoluteString)
      }
      return true
    }

    return super.application(app, open: url, options: options)
  }

  // Universal Link entry point.
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL,
       url.path.hasPrefix("/cip30dl/v1/") {
      if let controller = window?.rootViewController as? FlutterViewController {
        let channel = FlutterMethodChannel(
          name: "com.yuti/cip30",
          binaryMessenger: controller.binaryMessenger
        )
        channel.invokeMethod("handleCip30DeepLink", arguments: url.absoluteString)
      }
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}
