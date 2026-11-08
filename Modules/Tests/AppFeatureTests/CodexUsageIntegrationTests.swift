import OnlyAgent
import Testing

struct CodexUsageIntegrationTests {
    @Test(arguments: [
        (-20.0, 100),
        (0.0, 100),
        (55.4, 45),
        (130.0, 0)
    ])
    func quotaRemainingPercentIsClamped(usedPercent: Double, expected: Int) {
        #expect(CodexQuotaWindow.remainingPercent(fromUsedPercent: usedPercent) == expected)
    }

    @Test
    func resetCreditStatesDoNotConflateUnavailableWithZero() {
        #expect(CodexResetCredits.unavailable.isAvailable == false)
        #expect(CodexResetCredits.available(count: 0, expiresAt: nil).isAvailable == true)
    }

    @Test
    func creditBalanceRetainsItsReportedLimit() {
        let balance = CodexCreditBalance.available(remaining: 2_281.33, limit: 10_000, unit: "credits")

        #expect(balance == .available(remaining: 2_281.33, limit: 10_000, unit: "credits"))
    }
}
