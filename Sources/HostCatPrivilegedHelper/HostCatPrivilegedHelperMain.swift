import Foundation
import HostCatCore

@main
struct HostCatPrivilegedHelperMain {
    static func main() {
        let delegate = HelperDelegate()
        let listener = NSXPCListener(machServiceName: "com.hostcat.helper")
        listener.delegate = delegate
        listener.resume()

        // 保持 RunLoop 运行，Helper 作为 LaunchDaemon 常驻
        RunLoop.current.run()
    }
}
