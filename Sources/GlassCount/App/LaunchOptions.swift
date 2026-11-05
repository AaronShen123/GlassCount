import Foundation

/// Developer/test switches (all optional):
///   --data-dir <path>         use a separate data directory (keeps real data untouched)
///   --seed-demo               add sample events when the store is empty
///   --seed-background <path>  import this image as the window background at launch
///   --no-system-notifications never talk to UNUserNotificationCenter
struct LaunchOptions {
    var dataDirectory: URL = AppPaths.defaultDirectory()
    var seedDemo = false
    var seedBackground: URL?
    var systemNotifications = true

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--data-dir" where i + 1 < args.count: o.dataDirectory = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 1
            case "--seed-demo": o.seedDemo = true
            case "--seed-background" where i + 1 < args.count: o.seedBackground = URL(fileURLWithPath: args[i + 1]); i += 1
            case "--no-system-notifications": o.systemNotifications = false
            default: break
            }
            i += 1
        }
        return o
    }
}
