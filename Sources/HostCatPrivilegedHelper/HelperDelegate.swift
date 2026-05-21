import Foundation
import HostCatCore

/// XPC Listener Delegate，负责验证调用方签名并分发请求
final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    // TODO: 部署前替换为真实 Team ID
    // 格式："anchor apple generic and identifier \"com.hostcat.app\" and certificate leaf[subject.OU] = \"TEAM_ID\""
    private let callerRequirement = "identifier \"com.hostcat.app\""

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // 验证调用方 code signing requirement
        connection.setCodeSigningRequirement(callerRequirement)

        // 配置导出接口
        let interface = NSXPCInterface(with: HostCatHelperXPCProtocol.self)
        connection.exportedInterface = interface
        connection.exportedObject = HelperService()

        // 连接中断和失效处理
        connection.interruptionHandler = {
            // 连接临时中断（可自动恢复）
        }
        connection.invalidationHandler = {
            // 连接永久失效
        }

        connection.resume()
        return true
    }
}
