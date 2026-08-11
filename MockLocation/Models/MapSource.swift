import Foundation

enum MapSource: Hashable {
    case amap
    case baidu

    var title: String {
        switch self {
        case .amap:
            return "高德地图"
        case .baidu:
            return "百度地图"
        }
    }
}
