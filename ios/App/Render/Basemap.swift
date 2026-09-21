import Foundation
import MapKit
import SwiftUI
import WalkyGeo
import WalkySim

/// Apple's map, as an image the canvas draws rather than a view behind it.
///
/// `MapCanvas` is `Canvas(opaque: true, …)` over an unconditional ground fill,
/// so nothing placed behind it is ever visible, and making it transparent costs
/// a real amount on the Core Graphics path -- every frame, for a feature that
/// is off on a blank map. A snapshot costs nothing per frame: it is drawn in
/// world space after the existing transform, so it pans and zooms with the
/// world for free and a stale one simply scales in place.
///
/// One snapshot per import, of the imported area plus a margin round it (see
/// `MapImporter.groundMarginMetres`). Zoom well past the import and it goes
/// soft, which is the honest cost of not yet having a settle-and-resnapshot
/// rule. See `ios/README.md`.
///
/// It *is* retaken when the lighting changes, which is why `taken` is kept:
/// Apple's map is drawn light or dark by the snapshotter, so a sheet shot on
/// the Classic ground and then looked at on Paper is a dark photograph under a
/// near-white floor. See `refresh(dark:)`.
@MainActor
@Observable
final class Basemap {
  struct Sheet {
    let image: CGImage
    /// Where the image belongs in world units.
    let worldRect: CGRect
  }

  private(set) var sheet: Sheet?
  private var task: Task<Void, Never>?
  /// What the last snapshot was of, so it can be taken again in a different
  /// light without the caller having to remember any of it.
  private var taken: (anchor: GeoAnchor, worldRect: CGRect, dark: Bool)?

  func clear() {
    task?.cancel()
    task = nil
    sheet = nil
    taken = nil
  }

  /// Retake the last snapshot in a different light, if the light has changed.
  ///
  /// Cheap to call on every appearance change: it answers immediately unless
  /// there is a sheet and its lighting is now wrong.
  func refresh(dark: Bool) {
    guard let taken, taken.dark != dark else { return }
    snapshot(anchor: taken.anchor, worldRect: taken.worldRect, dark: dark) { _ in }
  }

  /// Snapshot `worldRect`, and place the result by asking the snapshot itself
  /// where two known coordinates landed.
  ///
  /// MapKit adjusts a region to the aspect of the size it is given, so the
  /// image is not necessarily the box that was asked for. Deriving the
  /// placement from `point(for:)` is exact whatever it decided, where assuming
  /// the requested region would put every building off by the adjustment.
  func snapshot(anchor: GeoAnchor, worldRect: CGRect, dark: Bool,
                pixels: CGFloat = 1024, onDone: @escaping (String?) -> Void) {
    task?.cancel()
    taken = (anchor, worldRect, dark)

    let box = anchor.boundingBox(worldMinX: worldRect.minX, worldMinY: worldRect.minY,
                                 worldMaxX: worldRect.maxX, worldMaxY: worldRect.maxY)
    let centre = box.centre
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: centre.latitude, longitude: centre.longitude),
      span: MKCoordinateSpan(latitudeDelta: box.north - box.south,
                             longitudeDelta: box.east - box.west))
    // The crowd is the subject; the map is the ground it stands on.
    let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
    configuration.pointOfInterestFilter = .excludingAll
    options.preferredConfiguration = configuration
    options.showsBuildings = false
    // The snapshotter is told which way to draw its own map; each platform
    // has its own word for that.
    #if os(iOS)
    options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
    #else
    options.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    #endif

    let aspect = worldRect.height / max(worldRect.width, 1)
    options.size = CGSize(width: pixels, height: max(1, pixels * aspect))

    let topLeft = anchor.coordinate(Point(worldRect.minX, worldRect.minY))
    let bottomRight = anchor.coordinate(Point(worldRect.maxX, worldRect.maxY))

    task = Task { [weak self] in
      let snapshotter = MKMapSnapshotter(options: options)
      do {
        let shot = try await snapshotter.start()
        if Task.isCancelled { return }
        // The snapshot's image is the platform's, and only one of the two
        // hands over a `CGImage` as a property -- an `NSImage` is a list of
        // representations, so it has to be asked to pick one.
        #if os(iOS)
        let picked = shot.image.cgImage
        #else
        let picked = shot.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let cgImage = picked else {
          onDone("The map came back without an image."); return
        }

        // Which way up the answers are is the platform's, and the two do not
        // agree: UIKit measures an image from its top left, AppKit from its
        // bottom left. Measured on a 400x300 snapshot of the same region, a
        // Mac puts the north-west corner at y 225 and the south-east at y 75 --
        // so `spanY` came out **negative**, `scaleY` with it, and the sheet
        // was placed with a negative height, which draws nothing at all. That
        // is the whole of why the basemap was missing on macOS.
        //
        // Flipped once, here, so everything below this line -- and the canvas
        // the sheet is drawn on, which is top-left on both -- reads the same
        // on both platforms.
        let a = imagePoint(shot.point(for: CLLocationCoordinate2D(latitude: topLeft.latitude,
                                                               longitude: topLeft.longitude)),
                        height: shot.image.size.height)
        let b = imagePoint(shot.point(for: CLLocationCoordinate2D(latitude: bottomRight.latitude,
                                                               longitude: bottomRight.longitude)),
                        height: shot.image.size.height)
        let spanX = b.x - a.x, spanY = b.y - a.y
        guard abs(spanX) > 0.5, abs(spanY) > 0.5 else {
          onDone("The map placed those two corners on top of each other."); return
        }

        let scaleX = worldRect.width / spanX
        let scaleY = worldRect.height / spanY
        let size = shot.image.size
        self?.sheet = Sheet(image: cgImage, worldRect: CGRect(
          x: worldRect.minX - a.x * scaleX,
          y: worldRect.minY - a.y * scaleY,
          width: size.width * scaleX,
          height: size.height * scaleY))
        onDone(nil)
      } catch {
        if !Task.isCancelled { onDone("The map service declined: \(error.localizedDescription)") }
      }
    }
  }
}

/// A point out of `MKMapSnapshotter.Snapshot.point(for:)`, in the top-left
/// space the rest of this app measures in.
private func imagePoint(_ point: CGPoint, height: CGFloat) -> CGPoint {
  #if os(iOS)
  point
  #else
  CGPoint(x: point.x, y: height - point.y)
  #endif
}
