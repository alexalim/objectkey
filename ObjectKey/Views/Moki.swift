import SwiftUI

/// MOKI 캐릭터 에셋 이름.
enum Moki: String, CaseIterable {
    case peek, success, scan, question, key
    case reading, `break`, music, exercise, creative

    var assetName: String { "moki-\(rawValue)" }

    /// 등록할 때 물건 아이콘으로 고를 수 있는 활동형 캐릭터.
    static let activities: [Moki] = [.reading, .break, .music, .exercise, .creative]

    var label: String {
        switch self {
        case .reading: return "독서"
        case .break: return "휴식"
        case .music: return "음악"
        case .exercise: return "운동"
        case .creative: return "창작"
        default: return "MOKI"
        }
    }
}

extension Image {
    init(_ moki: Moki) { self.init(moki.assetName) }
}

/// 물건 아이콘. KeyObject.emoji에 캐릭터 에셋 이름("moki-…")이나 이모지가 들어 있다.
struct KeyBadge: View {
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        if symbol.hasPrefix("moki-") {
            Image(symbol).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(symbol.isEmpty ? "🔑" : symbol)
                .font(.system(size: size * 0.75))
                .frame(width: size, height: size)
        }
    }
}
