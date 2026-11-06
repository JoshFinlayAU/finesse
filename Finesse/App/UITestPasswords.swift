#if DEBUG
import Foundation

/// XCTest records typed text in result bundles and the simulator log, so UI tests type a placeholder
/// and the real password arrives in the launch environment. Debug builds only.
enum UITestPasswords {
    static let placeholders = [
        "ui-test-password-1": "FINESSE_UI_TEST_PASSWORD_1",
        "ui-test-password-2": "FINESSE_UI_TEST_PASSWORD_2",
    ]

    static func resolved(
        _ typed: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        placeholders[typed].flatMap { environment[$0] } ?? typed
    }
}
#endif
