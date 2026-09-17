import Foundation
import SDKDomain

/// Writes the `package.xml` that marks a package as installed.
///
/// The `<localPackage>` body is copied verbatim from the catalog: a trimmed version
/// breaks `avdmanager`.
enum PackageXMLWriter {
    static let commonNamespace = "http://schemas.android.com/repository/android/common/02"
    static let xsiNamespace = "http://www.w3.org/2001/XMLSchema-instance"

    static func document(for package: RemotePackage) -> String {
        var namespaces = package.namespaceDeclarations
        let rootPrefix = namespaces.first { $0.value == commonNamespace }?.key ?? uniquePrefix(in: namespaces)
        namespaces[rootPrefix] = commonNamespace
        if !namespaces.values.contains(xsiNamespace) {
            namespaces["xsi"] = xsiNamespace
        }
        let declarations =
            namespaces
            .sorted { $0.key < $1.key }
            .map { " xmlns:\($0.key)=\"\(escape($0.value))\"" }
            .joined()

        var body = ""
        if let license = package.license {
            body += "<license id=\"\(escape(license.id))\" type=\"text\">\(escape(license.text))</license>"
        }
        body += "<localPackage path=\"\(escape(package.path))\" obsolete=\"false\">"
        body += package.localPackageXML
        body += "</localPackage>"

        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <\(rootPrefix):repository\(declarations)>\(body)</\(rootPrefix):repository>

            """
    }

    private static func uniquePrefix(in namespaces: [String: String]) -> String {
        var index = 2
        while namespaces["ns\(index)"] != nil {
            index += 1
        }
        return "ns\(index)"
    }

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }
}
