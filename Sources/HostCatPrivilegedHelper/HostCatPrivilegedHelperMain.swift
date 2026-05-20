import Foundation
import HostCatCore

@main
struct HostCatPrivilegedHelperMain {
    static func main() {
        let defaultHash = HostsHash.sha256Hex("")
        let message = """
        HostCatPrivilegedHelper skeleton
        fixedPath=/private/etc/hosts
        emptyHash=\(defaultHash)

        """

        FileHandle.standardError.write(Data(message.utf8))
    }
}
