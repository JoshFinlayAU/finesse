import Testing
@testable import FinEsse

@Test func appModuleIsTestable() {
    #expect(String(describing: FinesseApp.self) == "FinesseApp")
}
