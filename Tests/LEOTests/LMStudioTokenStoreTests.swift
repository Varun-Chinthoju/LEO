import XCTest
@testable import LEO

final class LMStudioTokenStoreTests: XCTestCase {
    func testRetrievesTokenFromTheConfiguredKeychainService() throws {
        let keychain = FakeLMStudioKeychain(result: .success(Data("sk-local-token".utf8)))
        let store = LMStudioTokenStore(account: "default", keychain: keychain)

        XCTAssertEqual(try store.retrieveToken(), "sk-local-token")
        XCTAssertEqual(keychain.services, [LMStudioTokenStore.serviceName])
        XCTAssertEqual(keychain.accounts, ["default"])
    }

    func testMissingKeychainItemFailsClosedWithoutReturningAToken() throws {
        let keychain = FakeLMStudioKeychain(result: .success(nil))
        let store = LMStudioTokenStore(keychain: keychain)

        XCTAssertNil(try store.retrieveToken())
    }

    func testEmptyOrMalformedKeychainDataFailsClosed() throws {
        let empty = LMStudioTokenStore(
            keychain: FakeLMStudioKeychain(result: .success(Data()))
        )
        let malformed = LMStudioTokenStore(
            keychain: FakeLMStudioKeychain(result: .success(Data([0xFF, 0xFE])))
        )

        XCTAssertNil(try empty.retrieveToken())
        XCTAssertNil(try malformed.retrieveToken())
    }

    func testKeychainFailureIsPropagatedAndNoFallbackIsAttempted() {
        let keychain = FakeLMStudioKeychain(result: .failure(.status(-25300)))
        let store = LMStudioTokenStore(keychain: keychain)

        XCTAssertThrowsError(try store.retrieveToken()) { error in
            XCTAssertEqual(error as? LMStudioTokenStoreError, .keychainFailure(.status(-25300)))
        }
        XCTAssertEqual(keychain.readCount, 1)
    }
}

private final class FakeLMStudioKeychain: LMStudioKeychainClient, @unchecked Sendable {
    let result: Result<Data?, LMStudioKeychainError>
    private(set) var services: [String] = []
    private(set) var accounts: [String] = []
    private(set) var readCount = 0

    init(result: Result<Data?, LMStudioKeychainError>) {
        self.result = result
    }

    func read(service: String, account: String) throws -> Data? {
        readCount += 1
        services.append(service)
        accounts.append(account)
        return try result.get()
    }
}
