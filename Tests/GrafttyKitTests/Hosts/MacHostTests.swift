import Foundation
import Testing
@testable import GrafttyKit

@Suite
struct MacHostTests {
    @Test
    func localHostHasStableIdentity() {
        #expect(MacHost.local.id == MacHost.localID)
        #expect(MacHost.local.label == "This Mac")
        #expect(MacHost.local.kind == .local)
    }

    @Test
    func sshHostDefaultsLabelAndPorts() {
        let host = MacHost.ssh(sshHost: "dev-mini", username: nil)

        #expect(host.label == "dev-mini")
        #expect(host.sshConfig?.sshPort == 22)
        #expect(host.sshConfig?.remoteGrafttyPort == 8799)
    }

    @Test
    func sshHostCodableRoundTrips() throws {
        let host = MacHost.ssh(
            label: "Mini",
            sshHost: "dev-mini",
            username: "btucker",
            sshPort: 2200,
            remoteGrafttyPort: 9000
        )

        let data = try JSONEncoder().encode(host)
        let decoded = try JSONDecoder().decode(MacHost.self, from: data)

        #expect(decoded == host)
    }

    @Test
    func addHostFormRejectsEmptyHost() {
        var form = AddHostFormModel()
        form.host = " "

        #expect(form.makeHost() == nil)
    }

    @Test
    func addHostFormDefaultsLabelAndTreatsEmptyUsernameAsSSHConfigDefault() {
        var form = AddHostFormModel()
        form.host = "dev-mini"
        form.username = ""

        let host = form.makeHost()

        #expect(host?.label == "dev-mini")
        #expect(host?.sshConfig?.sshUsername == nil)
    }
}
