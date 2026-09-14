import SwiftUI
import UIKit

/// The map on a second screen -- AirPlay to a TV, or a cable -- with every
/// control left on the phone.
///
/// Without this iOS mirrors, and a mirrored portrait phone is a thin strip in
/// the middle of a 16:9 TV with a toolbar in it. Declaring a scene for the
/// external display role is what Photos and Keynote do: while Walky is in the
/// foreground the TV is handed a scene of its own instead of a copy, and the
/// phone goes on being the remote.
///
/// Non-interactive by definition -- nobody touches a TV -- so there is no
/// `TouchCanvas` here and no chrome to hide.
///
/// Named by `UIApplicationSceneManifest` in project.yml, which is the only
/// place it is wired up. Returning the same configuration from an app
/// delegate's `configurationForConnecting` is not enough: iOS offers an
/// external display session only to an app whose manifest lists the role.
@MainActor
final class ExternalDisplayDelegate: NSObject, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let model = AppModel.shared
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIHostingController(rootView: ExternalMapView(model: model))
    window.isHidden = false
    self.window = window
    model.externalDisplays += 1
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    // Only a scene that got a window was counted, so only one of those uncounts.
    guard window != nil else { return }
    window = nil
    AppModel.shared.externalDisplays -= 1
  }
}

/// The same world, drawn a second time at the TV's size.
///
/// Its own `Redraw`, so the TV keeps moving while a sheet covers the phone's
/// map -- which is exactly when somebody presenting is in Settings -- without
/// that also repainting the map hidden behind the sheet.
struct ExternalMapView: View {
  let model: AppModel

  var body: some View {
    MapCanvas(world: model.world, redraw: model.externalRedraw, basemap: model.basemap,
              stats: { DebugStats(fps: model.fps, tps: model.tps) }, mirroring: true)
  }
}
