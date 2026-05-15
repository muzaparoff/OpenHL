// SPDX-License-Identifier: MIT

import Foundation

/// Loads JSON fixture files bundled with the test target.
///
/// Fixtures live in `Tests/HyperliquidAPITests/Fixtures/` and are declared
/// as `.process("Fixtures")` resources in the test target's `Package.swift`.
/// `Bundle.module` resolves to the test bundle at runtime.
enum FixtureLoader {

    enum Error: Swift.Error {
        case fileNotFound(String)
        case readFailed(String, underlying: Swift.Error)
    }

    /// Loads `<name>.json` from the `Fixtures` subdirectory of the test bundle.
    static func load(_ name: String) throws -> Data {
        let fileName = name.hasSuffix(".json") ? name : "\(name).json"
        guard
            let url = Bundle.module.url(
                forResource: fileName,
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        else {
            throw Error.fileNotFound(fileName)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw Error.readFailed(fileName, underlying: error)
        }
    }
}
