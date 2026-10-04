import Testing
@testable import OnlyAgent

struct CodexUsageModelsTests {
    @Test(arguments: [
        (-20.0, 100),
        (0.0, 100),
        (55.4, 45),
        (130.0, 0)
    ])
    func remainingPercentIsClamped(value: Double, expected: Int) {
        #expect(CodexQuotaWindow.remainingPercent(fromUsedPercent: value) == expected)
    }

    @Test
    func resetCreditStatesRemainDistinct() {
        #expect(CodexResetCredits.unavailable.isAvailable == false)
        #expect(CodexResetCredits.unlimited.isAvailable == true)
        #expect(CodexResetCredits.available(count: 0, expiresAt: nil).isAvailable == true)
    }
}
