import Foundation

public struct DiagnosticPipeline {
    private let bundleInspector: BundleInspector

    public init(bundleInspector: BundleInspector = BundleInspector()) {
        self.bundleInspector = bundleInspector
    }

    public func diagnose(path: String) -> DiagnosticReport {
        bundleInspector.inspect(pathString: path)
    }
}
