import Foundation

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable {
        /// 上传成功
        case success
        /// 中性提示，比如「之前传过了」
        case info
        /// 没传上去
        case error
    }

    let id = UUID()
    let text: String
    let kind: Kind
}
