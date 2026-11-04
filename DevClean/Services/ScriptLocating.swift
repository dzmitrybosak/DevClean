import Foundation

enum ScriptLocationError: LocalizedError {
    case missingFromBundle(name: String, fileExtension: String)
    case unavailable(URL)

    var errorDescription: String? {
        switch self {
        case .missingFromBundle(let name, let fileExtension):
            String(localized: "The script \(name).\(fileExtension) was not found in the app bundle.")
        case .unavailable(let url):
            String(
                localized: """
                The script file is unavailable:
                \(url.path)
                The app bundle was removed (most likely because DerivedData was cleaned, where it lives). Rebuild the project (⌘R).
                """
            )
        }
    }
}

protocol ScriptLocating {
    func locateScript() throws -> URL
}

/// Resolves the bundled cleanup script and validates that it still exists on disk.
struct BundleScriptLocator: ScriptLocating {
    private let bundle: Bundle
    private let name: String
    private let fileExtension: String

    init(
        bundle: Bundle = .main,
        name: String = "clean-dev-cache",
        fileExtension: String = "sh"
    ) {
        self.bundle = bundle
        self.name = name
        self.fileExtension = fileExtension
    }

    func locateScript() throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            throw ScriptLocationError.missingFromBundle(name: name, fileExtension: fileExtension)
        }

        // The bundle can disappear while the app is running — for example, if a
        // previous cleanup removed ~/Library/Developer/Xcode/DerivedData where
        // Xcode placed this very app. Fail with a clear message instead of
        // letting zsh report "no such file or directory".
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScriptLocationError.unavailable(url)
        }

        return url
    }
}
