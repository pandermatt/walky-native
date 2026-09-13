import SwiftUI
import WalkyCore
import WalkyGeo

/// Put the crowd somewhere real.
///
/// One explicit import rather than a layer that follows the camera: the
/// navigation graph is rebuilt from scratch whenever the walls change, and it
/// is superquadratic in their corners, so footprints streaming in on every pan
/// would be a rebuild on every pan. This asks once.
///
/// **Two sections, because there are two questions.** It used to be one, with a
/// text field, a location button, an area slider, a scale picker, a caution and
/// a progress line all in a stack, and the thing you had to do first was the
/// hardest to find. Where you want the map is a decision; how big and at what
/// ratio is a setting you touch once and forget. Splitting them means the first
/// section is two obvious ways to say *where* and nothing else.
struct RealMapSection: View {
  let world: WalkyWorld
  let basemap: Basemap
  @Bindable var importer: MapImporter
  let locator: Locator
  let dark: Bool

  var body: some View {
    Group {
      where_
      settings
    }
  }

  // MARK: - Where

  private var where_: some View {
    Section {
      HStack {
        TextField("Place or address", text: $importer.query)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .onSubmit(search)
        // Named for what it does rather than for what it starts. "Import" is
        // the machine's word for the whole operation; "Search" is the word for
        // this button, and the difference is whether anybody knows to press it.
        Button("Search", action: search)
          .disabled(importer.isBusy
                    || importer.query.trimmingCharacters(in: .whitespaces).isEmpty)
      }

      // Being somewhere is the other way of saying where, and on a phone it is
      // usually the shorter one. Hidden rather than disabled once location has
      // been refused: a button that can only ever apologise is worse than no
      // button, and Settings is where that gets undone, not here.
      if !locator.isRefused {
        Button {
          importer.importHere(locator, into: world, basemap: basemap, dark: dark)
        } label: {
          Label("Use my location", systemImage: "location.fill")
        }
        .disabled(importer.isBusy)
      }

      if importer.isBusy {
        // Determinate where the work can be counted, indeterminate where it
        // cannot -- `MapImporter.fraction` says which is which, and the nil it
        // returns for the rebuild is this initialiser's own indeterminate form.
        ProgressView(value: importer.progress, total: 1)
          .progressViewStyle(.linear)
      }

      status

      // Offered rather than imposed: see `MapImporter.isSlow`. Neither half of
      // an import has a length that can be known in advance, so nothing is
      // cancelled on a timer -- after twenty seconds this simply stops being a
      // wait with no way out.
      if importer.isSlow {
        Button {
          importer.retry(locator, into: world, basemap: basemap, dark: dark)
        } label: {
          Label("Try again", systemImage: "arrow.clockwise")
        }
        .font(.footnote)
      }
    } footer: {
      // Say where each half comes from. Apple has no building outline to give
      // -- no MapKit or Maps Server API returns one -- so the ground is
      // Apple's and the walls are OpenStreetMap's, and both want crediting.
      //
      // Two lines like every other footer in this sheet, but shortened around
      // the credit rather than through it: "© OpenStreetMap contributors" is
      // the wording the ODbL guidelines ask for, so it got more canonical on
      // the way down, not less.
      Text("© OpenStreetMap contributors (ODbL); ground by Apple. Importing "
         + "replaces your map.")
    }
  }

  /// What the import is doing, or what it did.
  @ViewBuilder private var status: some View {
    switch importer.phase {
    case .idle:
      EmptyView()
    case .searching:
      line("Finding the place…")
    case .fetching:
      line("Asking OpenStreetMap for its buildings…")
    case .merging:
      line("Merging what overlaps…")
    case .placing:
      line("Placing the buildings…")
    case .routing:
      line("Building the navigation graph…")
    case .done(let what):
      line(what)
    case .failed(let why):
      Text(why).font(.footnote).foregroundStyle(.red)
    case .refused(let why, let ready):
      // Not `.failed`: the buildings are already here. Overpass is a free
      // service on a fair-use policy, so the one thing this must not do is
      // ask it again for an answer it has already given.
      Text(why).font(.footnote).foregroundStyle(.red)
      Button("Import \(ready.corners) corners anyway") {
        importer.importAnyway(ready, into: world, basemap: basemap, dark: dark)
      }
      .font(.footnote)
    }
  }

  private func line(_ text: String) -> some View {
    Text(text).font(.footnote).foregroundStyle(.secondary)
  }

  // MARK: - How big, and at what ratio

  private var settings: some View {
    Section {
      LabeledContent("Area") {
        Text("\(Int(importer.sideMetres)) m across")
          .foregroundStyle(.secondary)
      }
      Slider(value: $importer.sideMetres, in: 120...600, step: 20)
        // Dragging it mid-import changed the basemap's crop without changing
        // the buildings under it.
        .disabled(importer.isBusy)

      LabeledContent("Scale") {
        Text("1:\(Int(importer.scale))").foregroundStyle(.secondary)
      }
      // Stops rather than a range: the interesting ratios are a handful and
      // between them is nothing anybody wants.
      Picker("Scale", selection: $importer.scale) {
        ForEach(MapImporter.scaleStops, id: \.self) { Text("1:\(Int($0))").tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(importer.isBusy)

      if let caution = importer.scaleCaution {
        Label(caution, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote).foregroundStyle(.orange)
      }
    } header: {
      Text("Area and scale")
    } footer: {
      Text("How much ground to import, and how big it is drawn. 1:10 keeps the "
         + "crowd watchable; 1:1 is life size.")
    }
  }

  private func search() {
    importer.importPlace(into: world, basemap: basemap, dark: dark)
  }
}
