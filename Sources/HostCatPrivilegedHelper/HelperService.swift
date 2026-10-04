import Foundation
import HostCatCore
import os.log

/// Privileged Helper 服务实现
///
/// 通过 XPC 接收主应用的写入请求，调用 HostsFileWriter 执行安全写入，
/// 并在写入成功后刷新 DNS 缓存。
final class HelperService: NSObject, HostCatHelperXPCProtocol {
    /// 只允许写入系统 hosts 的真实路径。
    static let allowedHostsPath = "/private/etc/hosts"

    /// 启动时 realpath 解析一次；不是允许路径时为 nil，后续写入全部拒绝。
    private let resolvedHostsPath: String?
    private let writer = HostsFileWriter()
    private let fileOps = RealFileSystemOperations()
    private let dnsRefresher = SystemDNSRefresher()
    private let logger = Logger(subsystem: "com.hostcat.helper", category: "HelperService")

    override init() {
        // 启动时解析 /etc/hosts 的真实路径并缓存
        if let resolved = try? RealFileSystemOperations().resolveRealPath(at: "/etc/hosts"),
           resolved == Self.allowedHostsPath {
            resolvedHostsPath = resolved
        } else {
            resolvedHostsPath = nil
        }
        super.init()
        if let resolvedHostsPath {
            logger.info("HelperService 初始化, hostsPath=\(resolvedHostsPath, privacy: .public)")
        } else {
            logger.error("拒绝初始化写入路径：/etc/hosts 不是 \(Self.allowedHostsPath, privacy: .public)")
        }
    }

    func writeHosts(
        _ contents: NSString,
        expectedCurrentHostsHash: NSString?,
        force: Bool,
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
            logger.warning("Unexpected localizationIdentifier '\(rawLanguage, privacy: .public)', falling back to zh-Hans")
            language = .simplifiedChinese
        }

        logger.info("收到写入请求, 内容长度=\(content.count, privacy: .public), force=\(force, privacy: .public), expectedHash=\(expectedHash?.prefix(8) ?? "nil", privacy: .public)")

        guard let resolvedHostsPath else {
            replyFailure(HostsWriteError.refusedHostsPath, code: "invalidHostsPath", language: language, reply: reply)
            return
        }
        if !force, expectedHash?.isEmpty != false {
            replyFailure(HostsWriteError.missingExpectedHash, code: "hashRequired", language: language, reply: reply)
            return
        }

        do {
            let outcome = try writer.write(
                content: content,
                targetPath: resolvedHostsPath,
                expectedHash: force ? nil : expectedHash,
                fileOps: fileOps,
                dnsRefresher: dnsRefresher
            )

            let result: NSDictionary = [
                "success": true,
                "finalHash": outcome.finalHash,
                "didRefreshDNS": outcome.dnsRefreshSuccess,
                "dnsRefreshError": outcome.dnsRefreshError ?? ""
            ]

            logger.info("写入成功, hash=\(outcome.finalHash.prefix(8), privacy: .public)..., dns=\(outcome.dnsRefreshSuccess, privacy: .public)")
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
            case HostsWriteError.missingExpectedHash:
                errorCode = "hashRequired"
            case HostsWriteError.refusedHostsPath:
                errorCode = "invalidHostsPath"
            default:
                errorCode = "writeFailed"
            }

            replyFailure(message: errorMessage, code: errorCode, reply: reply)
        }
    }

    private func replyFailure(
        _ error: HostsWriteError,
        code: String,
        language: AppLanguage,
        reply: @escaping (NSDictionary) -> Void
    ) {
        replyFailure(message: error.description(in: language), code: code, reply: reply)
    }

    private func replyFailure(
        message: String,
        code: String,
        reply: @escaping (NSDictionary) -> Void
    ) {
        logger.error("写入失败: \(message, privacy: .public)")
        reply([
            "success": false,
            "errorCode": code,
            "errorMessage": message
        ])
    }
}
