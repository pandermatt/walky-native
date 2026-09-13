import CoreLocation
import Observation
import WalkyGeo

/// Where the phone is, once.
///
/// Deliberately one-shot rather than a stream. Both callers want the same
/// thing -- a place to hang a map on -- and neither wants the crowd sliding
/// about because somebody walked to the window. `CLLocationUpdate.liveUpdates`
/// would be the modern shape and the wrong one: it is a subscription, and this
/// is a question.
///
/// Shared between the map importer and the room scanner so the permission is
/// asked for once, by whichever comes first.
@MainActor
@Observable
final class Locator: NSObject {

  enum Failure: LocalizedError {
    case denied
    case unavailable
    case timedOut

    var errorDescription: String? {
      switch self {
      case .denied:
        "Walky needs your location for this. Turn it on in Settings > Walky."
      case .unavailable:
        "Could not work out where you are."
      case .timedOut:
        // The Simulator ships with no location at all and simply never answers,
        // which is indistinguishable from a slow fix without saying so.
        "Locating took too long. In the Simulator, set one under "
          + "Features > Location."
      }
    }
  }

  /// How long to wait for a fix. Long enough for a cold GPS start indoors,
  /// short enough that a Simulator with no location set says so rather than
  /// spinning until somebody gives up.
  private static let patience: Duration = .seconds(12)

  private let manager = CLLocationManager()
  private var fix: CheckedContinuation<Coordinate, Error>?
  private var asking: CheckedContinuation<Void, Never>?
  private var timeout: Task<Void, Never>?

  private(set) var isLocating = false

  override init() {
    super.init()
    manager.delegate = self
    // A neighbourhood import is 380m across and a scanned room hangs on the
    // building it is in: neither needs the battery cost of the best fix going.
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  /// True when asking is worth offering at all. False only where the user has
  /// said no, which is the one case a button should not be shown for.
  var isRefused: Bool {
    manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
  }

  func current() async throws -> Coordinate {
    isLocating = true
    defer { isLocating = false }

    try await authorise()

    return try await withCheckedThrowingContinuation { continuation in
      fix = continuation
      timeout = Task { [weak self] in
        try? await Task.sleep(for: Self.patience)
        self?.finish(.failure(Failure.timedOut))
      }
      manager.requestLocation()
    }
  }

  private func authorise() async throws {
    switch manager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      return
    case .denied, .restricted:
      throw Failure.denied
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
      await withCheckedContinuation { asking = $0 }
      guard !isRefused, manager.authorizationStatus != .notDetermined else {
        throw Failure.denied
      }
    @unknown default:
      throw Failure.unavailable
    }
  }

  /// Resumes the waiting call exactly once, whoever gets here first -- the
  /// delegate, or the clock. Everything that finishes a fix goes through here
  /// for that reason: a continuation resumed twice is a crash, and one never
  /// resumed is a spinner that outlives the app.
  private func finish(_ result: Result<Coordinate, Error>) {
    timeout?.cancel()
    timeout = nil
    guard let continuation = fix else { return }
    fix = nil
    continuation.resume(with: result)
  }
}

extension Locator: CLLocationManagerDelegate {
  // `CLLocationManager` calls back on the queue it was created on, which is the
  // main one here. Asserting that beats making this type non-isolated -- the
  // same trade `RoomCaptureContainer` makes with RoomPlan's delegate.
  nonisolated func locationManager(_ _unused: CLLocationManager,
                                   didUpdateLocations locations: [CLLocation]) {
    MainActor.assumeIsolated {
      guard let last = locations.last else {
        finish(.failure(Failure.unavailable))
        return
      }
      finish(.success(Coordinate(latitude: last.coordinate.latitude,
                                 longitude: last.coordinate.longitude)))
    }
  }

  nonisolated func locationManager(_ _unused: CLLocationManager,
                                   didFailWithError error: Error) {
    MainActor.assumeIsolated {
      // `kCLErrorLocationUnknown` means "not yet", not "never" -- the fix is
      // still coming and the timeout is the thing that should decide.
      if (error as? CLError)?.code == .locationUnknown { return }
      finish(.failure(error))
    }
  }

  nonisolated func locationManagerDidChangeAuthorization(_ _unused: CLLocationManager) {
    MainActor.assumeIsolated {
      // The status is read off our own `manager`, never the argument: a
      // `CLLocationManager` is not `Sendable`, so the one handed to a
      // `nonisolated` callback cannot cross into an isolated closure.
      guard self.manager.authorizationStatus != .notDetermined, let asking else { return }
      self.asking = nil
      asking.resume()
    }
  }
}
