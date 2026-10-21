import Foundation
import CoreGraphics

struct QuotaWindow: Codable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    var remaining: Int { Int((100 - min(100, max(0, usedPercent))).rounded()) }
    var resetDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }
}

private struct QuotaBucket: Decodable {
    let limitId: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
}

private struct QuotaResponse: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?
}

struct QuotaSnapshot: Codable {
    let fiveHour: QuotaWindow?
    let weekly: QuotaWindow?
    let fetchedAt: Date

    static func parse(_ object: [String: Any], now: Date = Date()) throws -> QuotaSnapshot {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = try JSONDecoder().decode(QuotaResponse.self, from: data)
        guard let bucket = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits,
              bucket.limitId == nil || bucket.limitId == "codex" else {
            throw QuotaError.unavailable
        }
        let windows = [bucket.primary, bucket.secondary].compactMap { $0 }
        return QuotaSnapshot(
            fiveHour: windows.first { $0.windowDurationMins == 300 },
            weekly: windows.first { $0.windowDurationMins == 10080 },
            fetchedAt: now
        )
    }
}

enum QuotaError: Error { case unavailable }

enum BarGeometry {
    static func origin(in host: CGRect, size: CGSize, x: Double, y: Double) -> CGPoint {
        let inset: CGFloat = 10
        let horizontal = max(0, host.width - size.width - 2 * inset)
        let vertical = max(0, host.height - size.height - 2 * inset)
        return CGPoint(x: host.minX + inset + horizontal * min(1, max(0, x)),
                       y: host.minY + inset + vertical * min(1, max(0, y)))
    }

    static func relative(_ origin: CGPoint, in host: CGRect, size: CGSize) -> CGPoint {
        let horizontal = max(1, host.width - size.width - 20)
        let vertical = max(1, host.height - size.height - 20)
        return CGPoint(x: min(1, max(0, (origin.x - host.minX - 10) / horizontal)),
                       y: min(1, max(0, (origin.y - host.minY - 10) / vertical)))
    }
}
