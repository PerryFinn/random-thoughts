import Foundation
import Testing
@testable import random_thoughts

@MainActor
struct IntelligenceIsolationTests {
    @Test func fetchUsesInjectedTransport() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let service = IntelligenceService(
            session: environment.transport.session,
            endpoint: environment.transport.endpoint
        )

        let response = try await service.fetch()

        #expect(response.points.map(\.id) == ["synthetic|max"])
        #expect(response.points.first?.iq == 42)
        let request = try #require(environment.transport.requests.first)
        #expect(environment.transport.requests.count == 1)
        #expect(request.url == environment.transport.endpoint)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func refreshUsesFixedClockWithoutStartingInInitializer() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let store = makeStore(in: environment)
        #expect(environment.transport.requests.isEmpty)
        #expect(store.points.isEmpty)

        await store.refresh()

        #expect(store.points.map(\.id) == ["synthetic|max"])
        #expect(store.lastRefreshAt == Date(timeIntervalSince1970: 1_000))
        #expect(store.errorMessage == nil)
        #expect(environment.transport.requests.count == 1)
    }

    @Test func automaticRefreshOnlyContinuesWhenControlledTimeAdvances() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let store = makeStore(in: environment)
        defer { store.stopUpdating() }

        store.startUpdating()
        store.startUpdating()
        await environment.clock.waitForSleep(number: 1)
        #expect(environment.transport.requests.count == 1)

        environment.clock.advance(by: 1_799)
        #expect(environment.transport.requests.count == 1)
        environment.clock.advance(by: 1)
        await environment.clock.waitForSleep(number: 2)

        #expect(environment.transport.requests.count == 2)
        #expect(store.lastRefreshAt == Date(timeIntervalSince1970: 2_800))
    }

    @Test func transportFailureKeepsCachedContentAndDoesNotRetry() async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        let store = makeStore(in: environment)
        await store.refresh()
        let cached = environment.defaults.data(forKey: "cachedIntelligenceResponse")

        environment.transport.fail()
        environment.clock.advance(by: 60)
        await store.refresh()

        #expect(store.points.map(\.id) == ["synthetic|max"])
        #expect(store.lastRefreshAt == Date(timeIntervalSince1970: 1_000))
        #expect(store.errorMessage != nil)
        #expect(!store.isRefreshing)
        #expect(environment.defaults.data(forKey: "cachedIntelligenceResponse") == cached)
        #expect(environment.transport.requests.count == 2)
    }

    @Test(arguments: [200, 503])
    func rejectsMalformedDataAndUnsuccessfulResponses(statusCode: Int) async throws {
        let environment = try IsolatedTestEnvironment()
        defer { environment.close() }
        environment.transport.respond(with: Data("invalid-json".utf8), statusCode: statusCode)
        let service = IntelligenceService(
            session: environment.transport.session, endpoint: environment.transport.endpoint
        )

        await #expect(throws: IntelligenceServiceError.self) { try await service.fetch() }
        #expect(environment.transport.requests.count == 1)
    }

    private func makeStore(in environment: IsolatedTestEnvironment) -> IntelligenceStore {
        IntelligenceStore(
            service: .init(session: environment.transport.session, endpoint: environment.transport.endpoint),
            defaults: environment.defaults,
            now: { environment.clock.now },
            sleep: { try await environment.clock.sleep(for: $0) }
        )
    }
}
