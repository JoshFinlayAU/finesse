import Testing
@testable import FinEsse

struct UITestPasswordsTests {
    @Test func aPlaceholderBecomesTheValueFromTheEnvironment() {
        let environment = ["FINESSE_UI_TEST_PASSWORD_2": "real"]
        #expect(UITestPasswords.resolved("ui-test-password-2", environment: environment) == "real")
    }

    @Test func anythingElseIsLeftAlone() {
        let environment = ["FINESSE_UI_TEST_PASSWORD_1": "real"]
        #expect(UITestPasswords.resolved("what a person typed", environment: environment) == "what a person typed")
        #expect(UITestPasswords.resolved("ui-test-password-2", environment: environment) == "ui-test-password-2")
    }
}
