import Foundation
import Testing
@testable import GrafttyKit

@Suite
struct SSHLocalForwardTests {
    @Test
    func buildsSSHArgumentsUsingConfigAlias() {
        let config = SSHHostConfig(sshHost: "dev-mini")

        let args = SSHLocalForwardCommand.arguments(
            config: config,
            localPort: 49152
        )

        #expect(args.contains("-N"))
        #expect(args.contains("-L"))
        #expect(args.contains("127.0.0.1:49152:127.0.0.1:8799"))
        #expect(args.last == "dev-mini")
    }

    @Test
    func buildsSSHArgumentsWithUserAndNonDefaultPort() {
        let config = SSHHostConfig(
            sshHost: "192.168.1.42",
            sshUsername: "btucker",
            sshPort: 2200
        )

        let args = SSHLocalForwardCommand.arguments(config: config, localPort: 49152)

        #expect(args.contains("-p"))
        #expect(args.contains("2200"))
        #expect(args.last == "btucker@192.168.1.42")
    }

    @Test
    func localPortAllocatorReturnsBindablePort() throws {
        let port = try LocalPortAllocator.ephemeralLoopbackPort()

        #expect(port > 0)
    }
}
