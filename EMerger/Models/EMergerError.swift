//
//  EMergerError.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

enum EMergerError: LocalizedError, Sendable {
    case invalidServerURL(String)
    case missingCredential(accountLabel: String)
    case unauthorized(accountLabel: String)
    case http(status: Int, message: String)
    case outOfDate(currentVersion: Int?)
    case vetoed([String])
    case decoding(String)
    case keychain(OSStatus)
    case network(String)
    case noActingAccount
    case ciTriggerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL(let url):
            return "Geçersiz sunucu adresi: \(url)"
        case .missingCredential(let label):
            return "\(label) hesabı için Keychain'de token bulunamadı. Ayarlar'dan yeniden girin."
        case .unauthorized(let label):
            return "\(label) hesabının token'ı reddedildi (401). Token süresi dolmuş veya yetkisi eksik olabilir."
        case .http(let status, let message):
            return "Sunucu hatası (HTTP \(status)): \(message)"
        case .outOfDate(let v):
            if let v { return "PR bu arada değişti (güncel sürüm \(v)). Liste yenilendi; tekrar deneyin." }
            return "PR bu arada değişti. Liste yenilendi; tekrar deneyin."
        case .vetoed(let reasons):
            return "Merge engellendi: " + reasons.joined(separator: " · ")
        case .decoding(let detail):
            return "Sunucu yanıtı çözümlenemedi: \(detail)"
        case .keychain(let status):
            return "Keychain hatası (\(status))."
        case .network(let detail):
            return "Ağ hatası: \(detail)"
        case .noActingAccount:
            return "Bu işlemi yapabilecek bir hesap yok (PR'ın yazarı kendini onaylayamaz)."
        case .ciTriggerFailed(let detail):
            return "CI tetiklenemedi: \(detail)"
        }
    }
}
