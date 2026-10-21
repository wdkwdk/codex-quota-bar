import Foundation
import CoreGraphics

@main
struct ModelTests {
    static func main() throws {
        let five: [String: Any] = ["usedPercent": 23, "windowDurationMins": 300, "resetsAt": 1800000000]
        let week: [String: Any] = ["usedPercent": 41, "windowDurationMins": 10080, "resetsAt": 1800100000]
        let reversed = try QuotaSnapshot.parse(["rateLimits": ["limitId": "codex", "primary": week, "secondary": five]])
        assert(reversed.fiveHour?.remaining == 77 && reversed.weekly?.remaining == 59, "按窗口时长识别，不能依赖 primary 的顺序")
        assert(reversed.fiveHour?.resetDate?.timeIntervalSince1970 == 1800000000, "重置时间单位是秒")
        let buckets = try QuotaSnapshot.parse(["rateLimits": ["primary": week], "rateLimitsByLimitId": ["codex": ["primary": five]]])
        assert(buckets.fiveHour?.remaining == 77 && buckets.weekly == nil, "优先使用 codex 桶，不拼接其他桶的数据")
        let missing = try QuotaSnapshot.parse(["rateLimits": ["primary": NSNull(), "secondary": NSNull()]])
        assert(missing.fiveHour == nil && missing.weekly == nil, "未知不能显示成零或满额")
        let wrongDuration = try QuotaSnapshot.parse(["rateLimits": ["primary": ["usedPercent": 10, "windowDurationMins": 15]]])
        assert(wrongDuration.fiveHour == nil, "不能将 15 分钟窗口误标为 5 小时")
        do {
            _ = try QuotaSnapshot.parse(["rateLimits": ["limitId": "other", "primary": five]])
            assertionFailure("不能将其他桶显示成 Codex 额度")
        } catch QuotaError.unavailable { }
        assert(QuotaWindow(usedPercent: 120, windowDurationMins: nil, resetsAt: nil).remaining == 0)
        assert(QuotaWindow(usedPercent: -10, windowDurationMins: nil, resetsAt: nil).remaining == 100)
        let host = CGRect(x: -900, y: 100, width: 900, height: 700)
        let size = CGSize(width: 560, height: 32)
        let point = BarGeometry.origin(in: host, size: size, x: 1, y: 0)
        assert(point.x == -570 && point.y == 110, "支持负坐标的副屏")
        let relative = BarGeometry.relative(point, in: host, size: size)
        assert(relative.x == 1 && relative.y == 0)
        let resized = CGRect(x: 0, y: 0, width: 700, height: 500)
        let moved = BarGeometry.origin(in: resized, size: size, x: relative.x, y: relative.y)
        assert(moved.x + size.width <= resized.maxX - 10 && moved.y == 10, "缩放后位置仍在窗口内")
        let clamped = BarGeometry.origin(in: resized, size: size, x: -9, y: 99)
        assert(clamped.x == 10 && clamped.y == resized.maxY - size.height - 10)
        print("通过：额度解析、窗口识别、缺失数据、百分比、时间戳、位置记忆与边界。")
    }
}
