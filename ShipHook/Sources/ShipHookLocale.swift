import Foundation

enum ShipHookLocale {
    static var usesCommonwealthSpelling: Bool {
        let regionCode: String?
        if #available(macOS 13.0, *) {
            regionCode = Locale.current.region?.identifier
        } else {
            regionCode = Locale.current.regionCode
        }

        guard let region = regionCode?.uppercased() else {
            return false
        }

        return ["AU", "NZ", "GB", "IE", "ZA"].contains(region)
    }

    static var notarising: String {
        usesCommonwealthSpelling ? "Notarising" : "Notarizing"
    }

    static var notariseLowercase: String {
        usesCommonwealthSpelling ? "notarising" : "notarizing"
    }
}
