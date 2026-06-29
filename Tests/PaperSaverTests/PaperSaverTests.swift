import Testing
@testable import PaperSaverKit

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    let paperSaver = PaperSaver()
    
    let a = paperSaver.getActiveScreensaver()
    
    print(a)
}
