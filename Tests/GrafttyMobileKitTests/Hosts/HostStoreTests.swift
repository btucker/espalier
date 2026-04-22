#if canImport(UIKit)
import Foundation
import Testing
@testable import GrafttyMobileKit

@Suite
@MainActor
struct HostStoreTests {

    private func makeStore() -> HostStore {
        HostStore(keychainService: "test.graftty.\(UUID().uuidString)")
    }

    @Test
    func startsEmpty() throws {
        let store = makeStore()
        #expect(store.hosts.isEmpty)
    }

    @Test
    func addPersistsAcrossInstances() throws {
        let service = "test.graftty.\(UUID().uuidString)"
        let h = Host(label: "mac", baseURL: URL(string: "http://mac.ts.net:8799/")!)
        do {
            let store = HostStore(keychainService: service)
            try store.add(h)
            #expect(store.hosts.count == 1)
            #expect(store.hosts.first == h)
        }
        // New instance reads the same items back.
        let other = HostStore(keychainService: service)
        #expect(other.hosts.count == 1)
        #expect(other.hosts.first == h)
        try other.deleteAll()
    }

    @Test
    func updateReplacesMatchingId() throws {
        let store = makeStore()
        var h = Host(label: "mac", baseURL: URL(string: "http://mac:8799/")!)
        try store.add(h)
        h.label = "renamed"
        try store.update(h)
        #expect(store.hosts.first?.label == "renamed")
        try store.deleteAll()
    }

    @Test
    func deleteRemovesById() throws {
        let store = makeStore()
        let a = Host(label: "a", baseURL: URL(string: "http://a:8799/")!)
        let b = Host(label: "b", baseURL: URL(string: "http://b:8799/")!)
        try store.add(a)
        try store.add(b)
        try store.delete(a.id)
        #expect(store.hosts.map(\.id) == [b.id])
        try store.deleteAll()
    }
}
#endif
