import CommonCrypto
import CryptoKit
import Foundation

nonisolated final class Crypto: Sendable {

    enum Error: Swift.Error, Equatable {
        case invalidSaltLength
        case keyDerivationFailed
        case invalidEncryptedData
        case invalidUTF8Data
    }

    static let keyLength: Int = kCCKeySizeAES256
    static let iterations: UInt32 = 600_000

    static func generateSalt() -> Data {
        let salt = SymmetricKey(size: .bits256)
        return salt.withUnsafeBytes { Data($0) }
    }

    func encrypt(_ plain: String, pin: String, salt: Data, iterations: UInt32? = nil) throws -> Data {
        try encrypt(Data(plain.utf8), pin: pin, salt: salt, iterations: iterations)
    }

    func encrypt(_ plain: Data, pin: String, salt: Data, iterations: UInt32? = nil) throws -> Data {
        let key = try Self.deriveKey(pin: pin, salt: salt, iterations: iterations)
        let sealedBox = try AES.GCM.seal(plain, using: key)

        guard let combined = sealedBox.combined else {
            throw Error.invalidEncryptedData
        }

        return combined
    }

    func decrypt(_ encrypted: Data, pin: String, salt: Data, iterations: UInt32? = nil) throws -> Data {
        let key = try Self.deriveKey(pin: pin, salt: salt, iterations: iterations)
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        return try AES.GCM.open(sealedBox, using: key)
    }

    func decrypt(_ encrypted: Data, pin: String, salt: Data, iterations: UInt32? = nil) throws -> String {
        guard let plain = try String(data: decrypt(encrypted, pin: pin, salt: salt, iterations: iterations), encoding: .utf8) else {
            throw Error.invalidUTF8Data
        }

        return plain
    }

    func hmac(_ plain: String, pin: String, salt: Data, iterations: UInt32? = nil) throws -> String {
        try hmac(Data(plain.utf8), pin: pin, salt: salt, iterations: iterations)
    }

    func hmac(_ plain: Data, pin: String, salt: Data, iterations: UInt32? = nil) throws -> String {
        let key = try Self.deriveKey(pin: pin, salt: salt, iterations: iterations)
        let hmac = HMAC<SHA256>.authenticationCode(for: plain, using: key)
        return Data(hmac).base64EncodedString()
    }

    // MARK: - Pre-derived key variants
    //
    // PBKDF2 dominates the cost of every call above. Hot paths that perform
    // many operations under the same pin/salt should derive the key once and
    // use these.

    func encrypt(_ plain: String, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(Data(plain.utf8), using: key)
        guard let combined = sealedBox.combined else {
            throw Error.invalidEncryptedData
        }
        return combined
    }

    func decrypt(_ encrypted: Data, key: SymmetricKey) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let plain = try AES.GCM.open(sealedBox, using: key)
        guard let string = String(data: plain, encoding: .utf8) else {
            throw Error.invalidUTF8Data
        }
        return string
    }

    func hmac(_ plain: String, key: SymmetricKey) throws -> String {
        let hmac = HMAC<SHA256>.authenticationCode(for: Data(plain.utf8), using: key)
        return Data(hmac).base64EncodedString()
    }
}

nonisolated extension Crypto {

    static func deriveKey(pin: String, salt: Data, iterations: UInt32? = nil) throws -> SymmetricKey {
        guard salt.count == keyLength else {
            throw Error.invalidSaltLength
        }

        let pinData = Data(pin.utf8)
        var derivedKey = Data(count: keyLength)

        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                pinData.withUnsafeBytes { pinBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        pinData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations ?? Self.iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw Error.keyDerivationFailed
        }

        return SymmetricKey(data: derivedKey)
    }
}
