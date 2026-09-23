import Foundation
import SwiftUI

@MainActor
final class OnboardingState: ObservableObject {
    static let shared = OnboardingState()

    private let key = "hasCompletedOnboarding"
    private let menuBarHintPendingKey = "menuBarHintPending"
    private let userDefaults: UserDefaults

    @Published private(set) var hasCompletedOnboarding: Bool

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.hasCompletedOnboarding = userDefaults.bool(forKey: key)
    }

    func complete() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: key)
        userDefaults.set(true, forKey: menuBarHintPendingKey)
    }

    func consumeMenuBarHintIfNeeded() -> Bool {
        guard userDefaults.bool(forKey: menuBarHintPendingKey) else { return false }
        userDefaults.set(false, forKey: menuBarHintPendingKey)
        return true
    }

    #if DEBUG
    func reset() {
        hasCompletedOnboarding = false
        userDefaults.set(false, forKey: key)
        userDefaults.set(false, forKey: menuBarHintPendingKey)
    }
    #endif
}
