import Foundation
import HostCatCore
import os.log

/// Privileged Helper 服务实现
///
/// 通过 XPC 接收主应用的写入请求，调用 HostsFileWriter 执行安全写入，
/// 并在写入成功后刷新 DNS 缓存。
final class HelperService: NSObject, HostCatHelperXPCProtocol {
    /// 启动时 realpath 解析一次的 hosts 真实路径
    private let resolvedHostsPath: String
    private let writer = HostsFileWriter()
    private let fileOps = RealFileSystemOperations()
    private let dnsRefresher = SystemDNSRefresher()
    private let logger = Logger(subsystem: "com.hostcat.helper", category: "HelperService")

    override init() {
        // 启动时解析 /etc/hosts 的真实路径并缓存
        if let resolved = try? RealFileSystemOperations().resolveRealPath(at: "/etc/hosts") {
            resolvedHostsPath = resolved
        } else {
            resolvedHostsPath = "/private/etc/hosts"
        }
        super.init()
        logger.info("HelperService 初始化, hostsPath=\(self.resolvedHostsPath)")
    }

    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        localizationIdentifier: NSString,
        withReply reply: @escaping (NSDictionary) -> Void
    ) {
        let content = contents as String
        let expectedHash = expectedCurrentHostsHash as? String
        // 仅接受主应用已解析后的具体语言标识；收到 system 或未知值时
        // 记录警告并回退到中文，避免错误文案语言不一致。
        let rawLanguage = localizationIdentifier as String
        let language: AppLanguage
        switch rawLanguage {
        case AppLanguage.english.rawValue:
            language = .english
        case AppLanguage.simplifiedChinese.rawValue:
            language = .simplifiedChinese
        default:
            logger.warning("Unexpected localizationIdentifier '\(rawLanguage)', falling back to zh-Hans")
            language = .simplifiedChinese
        }

        logger.info("收到写入请求, 内容长度=\(content.count), expectedHash=\(expectedHash?.prefix(8) ?? "nil")")

        do {
            let outcome = try writer.write(
                content: content,
                targetPath: resolvedHostsPath,
                expectedHash: expectedHash,
                fileOps: fileOps,
                dnsRefresher: dnsRefresher
            )

            let result: NSDictionary = [
                "success": true,
                "finalHash": outcome.finalHash,
                "didRefreshDNS": outcome.dnsRefreshSuccess,
                "dnsRefreshError": outcome.dnsRefreshError ?? ""
            ]

            logger.info("写入成功, hash=\(outcome.finalHash.prefix(8))..., dns=\(outcome.dnsRefreshSuccess)")
            reply(result)
        } catch {
            let errorMessage = (error as? HostsWriteError)?.description(in: language)
                ?? error.localizedDescription
            let errorCode: String
            switch error {
            case HostsWriteError.fileImmutable:
                errorCode = "fileImmutable"
            case HostsWriteError.hashMismatch:
                errorCode = "hashMismatch"
            default:
                errorCode = "writeFailed"
            }

            let result: NSDictionary = [
                "success": false,
                "errorCode": errorCode,
                "errorMessage": errorMessage
            ]

            logger.error("写入失败: \(errorMessage)")
            reply(result)
        }
    }
}
