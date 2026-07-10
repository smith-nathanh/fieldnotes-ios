import Foundation
import FieldnotesCore

nonisolated enum ResourceLocator {
    static func url(
        named name: String,
        extension ext: String,
        bundle: Bundle = .main
    ) throws -> URL {
        let candidateSubdirectories = [
            nil,
            "Resources/Models",
            "Resources/Labels",
            "Resources/TestFixtures",
            "Resources/BioCAP",
            "Resources/BioCAP/Models",
            "Resources/BioCAP/TestFixtures",
        ]

        for subdirectory in candidateSubdirectories {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
        }

        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw ResourceError.missing("\(name).\(ext)")
        }
        return url
    }

    static func labels(named name: String) throws -> [String] {
        let url = try url(named: name, extension: "txt")
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    static func commonNames(named name: String = "labels_en") throws -> [String: String] {
        let url = try url(named: name, extension: "json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    static func taxa(named name: String = "taxa") throws -> [String: Taxon] {
        let url = try url(named: name, extension: "json")
        let data = try Data(contentsOf: url)
        let rawTaxa = try JSONDecoder().decode([String: String].self, from: data)
        return rawTaxa.reduce(into: [:]) { result, entry in
            result[entry.key] = Taxon(rawValue: entry.value) ?? .unknown
        }
    }
}

enum ResourceError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case .missing(let name):
            return "Missing bundled resource: \(name)"
        }
    }
}
