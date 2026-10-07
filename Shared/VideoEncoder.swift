import Foundation

enum VideoEncoder: String, CaseIterable, Codable {
    case fast
    case slowHighQuality
    case visuallyLossless

    var name: String {
        switch self {
        case .fast: "快速省电,文件较大"
        case .slowHighQuality: "慢速高画质,文件更小"
        case .visuallyLossless: "Visually lossless"
        }
    }

    var description: String {
        switch self {
        case .fast:
            #if arch(arm64)
                "Uses the hardware encoder for quick, low-power optimisation"
            #else
                "Uses the default encoder preset for a good balance of speed and quality"
            #endif
        case .slowHighQuality:
            "Uses a slow software encoder preset for smaller files with better quality"
        case .visuallyLossless:
            "生成无可感知画质损失的文件(CRF 17)"
        }
    }
}
