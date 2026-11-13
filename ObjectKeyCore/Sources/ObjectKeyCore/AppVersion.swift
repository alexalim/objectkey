import Foundation

/// 앱 버전 문자열 비교. "1.0.10"이 "1.0.9"보다 새 버전이라는 걸 글자 비교로는 알 수 없어 숫자로 나눠 본다.
public enum AppVersion {
    /// latest가 current보다 새 버전인가. 자리 수가 다르면 빈 자리는 0으로 본다("1.1" == "1.1.0").
    /// 숫자로 읽을 수 없는 문자열이면 비교하지 않는다(false).
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let a = parts(latest), let b = parts(current) else { return false }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int]? {
        let pieces = version.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty else { return nil }
        var result: [Int] = []
        for piece in pieces {
            guard let n = Int(piece) else { return nil }
            result.append(n)
        }
        return result
    }
}
