#if os(iOS)
import UIKit

/// Rotates the scene, never individual video/overlay views. Sheets share the scene.
@MainActor
final class PlaybackOrientation {
    static var supported: UIInterfaceOrientationMask = .portrait
    static func request(_ mask: UIInterfaceOrientationMask) {
        supported = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where scene.activationState == .foregroundActive {
            func invalidate(_ controller: UIViewController) {
                controller.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller.children.forEach(invalidate)
                if let presented = controller.presentedViewController { invalidate(presented) }
            }
            scene.windows.compactMap(\.rootViewController).forEach(invalidate)
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                // No fake rotation fallback: UIKit remains the sole layout authority.
                NSLog("Playback orientation request: %@", error.localizedDescription)
            }
        }
    }
}
#endif
