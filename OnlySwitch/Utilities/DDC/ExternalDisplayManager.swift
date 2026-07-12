//
//  ExternalDisplayManager.swift
//  OnlySwitch
//
//  Funnels all DDC/CI traffic to external monitors through a single serial
//  background queue (the I2C bus is slow and not thread-safe).
//

import Foundation

final class ExternalDisplayManager: @unchecked Sendable {
    static let shared = ExternalDisplayManager()

    private let queue = DispatchQueue(label: "com.jacklandrin.OnlySwitch.ddc", qos: .userInitiated)

    private init() {}

    /// Rediscovers connected external displays. Call after the screen layout
    /// changes. `completion` is delivered on the main queue with the new count.
    func refresh(completion: (@Sendable (Int) -> Void)? = nil) {
        queue.async {
            DDCControl.refreshExternalDisplays()
            let count = DDCControl.externalDisplayCount()
            if let completion {
                DispatchQueue.main.async { completion(count) }
            }
        }
    }

    /// Mirrors an absolute brightness (0...1) onto every external display.
    func setBrightness(percentage: Float) {
        let clamped = max(0, min(1, percentage))
        queue.async {
            DDCControl.setExternalBrightnessPercentage(clamped)
        }
    }

    /// Powers every external display on, or into DPMS off so it goes fully dark.
    func setPower(on: Bool) {
        queue.async {
            DDCControl.setExternalDisplaysPower(on)
        }
    }
}
