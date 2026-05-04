import Testing
@testable import Graftty

@Suite("Pending CI indicator policy")
struct PendingCIIndicatorPolicyTests {
    @Test("""
@spec PERF-1.8: While a PR/MR's latest checks verdict is pending, the application shall render pending-CI motion without updating SwiftUI state on a continuous timer. A live timer in every visible pending badge makes otherwise-idle CPU scale with the number of pending PR rows; compositor-backed layer animation is allowed because it does not rebuild the SwiftUI sidebar tree on every frame.
""")
    func pendingCIMotionAvoidsSwiftUIStateLoop() {
        #expect(PendingCIIndicatorMotion.usesContinuousSwiftUIStateLoop == false)
        #expect(PendingCIIndicatorMotion.usesCompositorLayerAnimation == true)
        #expect(PendingCIIndicatorMotion.opacity(isPending: true) == 0.9)
        #expect(PendingCIIndicatorMotion.opacity(isPending: false) == 1.0)
    }
}
