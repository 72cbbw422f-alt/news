import Foundation
import Network
import Security
import XCTest
@testable import NEWSFLOW

final class PinnedTLSTransportIntegrationTests: XCTestCase {
    private let queue = DispatchQueue(label: "app.newsflow.tests.pinned-tls")

    func testPinnedLoopbackConnectionSendsOriginalSNIAndValidatesTrustedHostname() throws {
        try runTLSHandshake(serverName: "feeds.example.org", expectedHostname: "feeds.example.org", succeeds: true)
    }

    func testPinnedLoopbackConnectionRejectsHostnameMismatch() throws {
        try runTLSHandshake(serverName: "wrong.example.org", expectedHostname: "wrong.example.org", succeeds: false)
    }

    func testPinnedLoopbackConnectionRejectsUntrustedCertificateChain() throws {
        try runTLSHandshake(
            serverName: "feeds.example.org",
            expectedHostname: "feeds.example.org",
            succeeds: false,
            trustRoot: false
        )
    }

    private func runTLSHandshake(
        serverName: String,
        expectedHostname: String,
        succeeds: Bool,
        trustRoot: Bool = true
    ) throws {
        let fixture = try TLSFixture.load()
        let server = try TLSLoopbackServer(identity: fixture.identity, queue: queue)

        let listenerReady = expectation(description: "TLS listener ready")
        let serverObservedSNI = expectation(description: "Server observed TLS SNI")
        let clientFinished = expectation(description: "Client TLS handshake completed")
        let clientCancelled = expectation(description: "Client connection cancelled")

        var observedSNI: String?
        var observedRemoteHost: NWEndpoint.Host?
        var clientFailure: NWError?
        var listenerPort: NWEndpoint.Port?

        server.onReady = { port in
            listenerPort = port
            listenerReady.fulfill()
        }
        server.onSNI = { name in
            observedSNI = name
            serverObservedSNI.fulfill()
        }

        server.start()
        wait(for: [listenerReady], timeout: 5)
        let port = try XCTUnwrap(listenerPort)

        let pinnedAddress = try XCTUnwrap(PinnedIPAddress(literal: "127.0.0.1"))
        let connection = try PinnedTLSConnectionFactory.makeConnectionForTesting(
            serverName: serverName,
            address: pinnedAddress,
            port: port.rawValue,
            configureTLS: { options in
                sec_protocol_options_set_verify_block(
                    options.securityProtocolOptions,
                    { _, trust, complete in
                        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                        let policy = SecPolicyCreateSSL(true, expectedHostname as CFString)
                        let anchorStatus = trustRoot
                            ? SecTrustSetAnchorCertificates(secTrust, [fixture.rootCertificate] as CFArray)
                            : errSecSuccess
                        let anchorOnlyStatus = trustRoot
                            ? SecTrustSetAnchorCertificatesOnly(secTrust, true)
                            : errSecSuccess
                        let policyStatus = SecTrustSetPolicies(secTrust, policy)
                        let accepted = anchorStatus == errSecSuccess
                            && anchorOnlyStatus == errSecSuccess
                            && policyStatus == errSecSuccess
                            && SecTrustEvaluateWithError(secTrust, nil)
                        complete(accepted)
                    },
                    queue
                )
            }
        )
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                observedRemoteHost = connection.currentPath?.remoteEndpoint.flatMap(Self.host(from:))
                clientFinished.fulfill()
            case .failed(let error):
                clientFailure = error
                clientFinished.fulfill()
            default:
                break
            }
        }
        connection.start(queue: queue)

        if succeeds {
            wait(for: [clientFinished, serverObservedSNI], timeout: 8)
        } else {
            wait(for: [clientFinished], timeout: 8)
        }

        if succeeds {
            XCTAssertNil(clientFailure, "Expected valid TLS handshake, got \(String(describing: clientFailure))")
            XCTAssertEqual(observedRemoteHost, .ipv4(try XCTUnwrap(IPv4Address("127.0.0.1"))))
        } else {
            XCTAssertNotNil(clientFailure, "Expected hostname validation to reject the certificate")
        }
        if succeeds {
            XCTAssertEqual(observedSNI, serverName)
        }

        connection.stateUpdateHandler = { state in
            if case .cancelled = state {
                clientCancelled.fulfill()
            }
        }
        connection.cancel()
        wait(for: [clientCancelled], timeout: 3)
        server.stop()
    }

    private static func host(from endpoint: NWEndpoint) -> NWEndpoint.Host? {
        guard case .hostPort(let host, _) = endpoint else { return nil }
        return host
    }
}

private struct TLSFixture {
    let identity: SecIdentity
    let rootCertificate: SecCertificate

    static func load() throws -> TLSFixture {
        let bundle = Bundle(for: PinnedTLSTransportIntegrationTests.self)
        let p12URL = try XCTUnwrap(bundle.url(forResource: "server.p12", withExtension: "base64", subdirectory: "Fixtures"))
        let caURL = try XCTUnwrap(bundle.url(forResource: "ca", withExtension: "pem", subdirectory: "Fixtures"))

        let encodedPKCS12 = try String(contentsOf: p12URL, encoding: .utf8)
        let pkcs12Data = try XCTUnwrap(Data(base64Encoded: encodedPKCS12.trimmingCharacters(in: .whitespacesAndNewlines)))
        let importOptions = [kSecImportExportPassphrase as String: "newsflow-test-only"] as NSDictionary
        var importedItems: CFArray?
        let importStatus = SecPKCS12Import(pkcs12Data as CFData, importOptions, &importedItems)
        XCTAssertEqual(importStatus, errSecSuccess)
        let imported = try XCTUnwrap((importedItems as? [[String: Any]])?.first)
        let identity = try XCTUnwrap(imported[kSecImportItemIdentity as String] as? SecIdentity)

        let pem = try String(contentsOf: caURL, encoding: .utf8)
        let certificateBody = pem
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        let certificateData = try XCTUnwrap(Data(base64Encoded: certificateBody))
        let rootCertificate = try XCTUnwrap(SecCertificateCreateWithData(nil, certificateData as CFData))

        return TLSFixture(identity: identity, rootCertificate: rootCertificate)
    }
}

private final class TLSLoopbackServer {
    private let listener: NWListener
    private let queue: DispatchQueue
    var onReady: ((NWEndpoint.Port) -> Void)?
    var onSNI: ((String) -> Void)?

    init(identity: SecIdentity, queue: DispatchQueue) throws {
        self.queue = queue
        let tlsOptions = NWProtocolTLS.Options()
        guard let localIdentity = sec_identity_create(identity) else {
            throw NSError(domain: "NEWSFLOW.TLSFixture", code: 1)
        }
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, localIdentity)
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connection.stateUpdateHandler = { [weak self] state in
                guard case .ready = state,
                      let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
                      let name = sec_protocol_metadata_get_server_name(metadata.securityProtocolMetadata)
                else { return }
                self?.onSNI?(String(cString: name))
            }
            connection.start(queue: self.queue)
        }
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = self?.listener.port else { return }
            self?.onReady?(port)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }
}
