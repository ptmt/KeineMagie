import SwiftUI
import AuthenticationServices
import KeineMagieCore

/// Async coordinator fetches a fresh server challenge BEFORE presenting Apple's native sheet.
@MainActor @Observable
final class AppleLoginCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var controller: ASAuthorizationController?
    private var attempt: SessionController.LoginAttempt?
    private var session: SessionController?
    private var anchor: ASPresentationAnchor?

    func signIn(session: SessionController) async {
        guard controller == nil else { return }
        guard let attempt = await session.prepareLogin() else { return }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else {
            session.failLogin(attempt: attempt, cancelled: false)
            return
        }
        self.session = session
        self.attempt = attempt
        anchor = window
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.nonce = attempt.challenge.nonce // Server-supplied nonce, exactly; NO additional hashing.
        request.state = attempt.challenge.state
        request.requestedScopes = [] // No name, email, or authorization code sent to our server.
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Set before performRequests; kept alive through completion.
        anchor ?? ASPresentationAnchor()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let session, let attempt else { clear(); return }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            session.failLogin(attempt: attempt, cancelled: false); clear(); return
        }
        let returnedState = credential.state
        clear()
        Task { await session.completeLogin(attempt: attempt, identityToken: token, state: returnedState) }
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let session, let attempt {
            session.failLogin(attempt: attempt, cancelled: (error as? ASAuthorizationError)?.code == .canceled)
        }
        clear()
    }
    private func clear() { controller = nil; attempt = nil; session = nil; anchor = nil }
}

/// Apple's own branded control; coordinator handles the asynchronous challenge before authorization.
struct NativeAppleButton: UIViewRepresentable {
    let action: () -> Void
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 10
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
}
