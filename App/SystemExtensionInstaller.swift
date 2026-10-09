import Foundation
import SystemExtensions

@MainActor
final class SystemExtensionInstaller: NSObject, @preconcurrency OSSystemExtensionRequestDelegate {
    private var request: OSSystemExtensionRequest?
    private var continuation: CheckedContinuation<Void, Error>?
    private var approvalHandler: (() -> Void)?

    func activate(onNeedsApproval: @escaping () -> Void) async throws {
        guard continuation == nil else { throw InstallerError.requestAlreadyPending }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            approvalHandler = onNeedsApproval

            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: AppConstants.tunnelBundleId,
                queue: .main
            )
            request.delegate = self
            self.request = request
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        approvalHandler?()
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension newExtension: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            finish(.success(()))
        case .willCompleteAfterReboot:
            finish(.failure(InstallerError.rebootRequired))
        @unknown default:
            finish(.failure(InstallerError.unknownResult))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        request = nil
        approvalHandler = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private enum InstallerError: LocalizedError {
        case requestAlreadyPending
        case rebootRequired
        case unknownResult

        var errorDescription: String? {
            switch self {
            case .requestAlreadyPending:
                return "A system extension request is already in progress."
            case .rebootRequired:
                return "Restart your Mac to finish updating the VPN system extension."
            case .unknownResult:
                return "The VPN system extension returned an unknown activation result."
            }
        }
    }
}
