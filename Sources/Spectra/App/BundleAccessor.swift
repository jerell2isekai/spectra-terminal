import Foundation

extension Bundle {
    /// Resource bundle accessor that works in both SPM development builds
    /// and packaged .app bundles.
    ///
    /// SPM's auto-generated `Bundle.module` uses `Bundle.main.bundleURL`
    /// which resolves to the `.app/` root — but build scripts place the
    /// resource bundle at `.app/Contents/Resources/`. This accessor
    /// checks `resourceURL` first (correct for .app), then falls back
    /// to `bundleURL` (correct for `swift run`).
    static let spectraResources: Bundle = {
        let bundleName = "Spectra_Spectra"
        let candidates = [
            Bundle.main.resourceURL,  // .app/Contents/Resources/
            Bundle.main.bundleURL,    // .build/.../release/ (swift run)
        ]
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundlePath, let bundle = Bundle(path: bundlePath.path) {
                return bundle
            }
        }
        fatalError("unable to find resource bundle \(bundleName), searched: \(candidates.compactMap { $0?.path })")
    }()
}
