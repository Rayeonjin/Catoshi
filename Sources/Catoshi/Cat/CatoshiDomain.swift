import Foundation

enum DisplayPalette: String, CaseIterable, Identifiable {
    case color
    case monochrome

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .color: return language.pick("컬러", "Color")
        case .monochrome: return language.pick("모노크롬", "Monochrome")
        }
    }
}

enum SocketConnectionState: Equatable {
    case connecting
    case connected
    case disconnected

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .connecting: return language.pick("복구 중", "Recovering")
        case .connected: return language.pick("실시간", "Live")
        case .disconnected: return language.pick("오프라인", "Offline")
        }
    }
}

enum CatoshiCoat: String, CaseIterable, Identifiable {
    case calico
    case cheese
    case gray
    case tuxedo
    case cream

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .calico: return language.pick("삼색이", "Calico")
        case .cheese: return language.pick("치즈", "Cheese")
        case .gray: return language.pick("회색", "Gray")
        case .tuxedo: return language.pick("턱시도", "Tuxedo")
        case .cream: return language.pick("크림", "Cream")
        }
    }


    var atlasResourceName: String {
        "CatoshiAtlas_\(rawValue)"
    }
}


enum CatoshiSensitivity: String, CaseIterable, Identifiable {
    case sensitive
    case normal
    case calm

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .sensitive: return language.pick("민감", "Sensitive")
        case .normal: return language.pick("보통", "Normal")
        case .calm: return language.pick("차분", "Calm")
        }
    }

    var happyThreshold: Double {
        switch self {
        case .sensitive: return 0.20
        case .normal: return 0.30
        case .calm: return 0.40
        }
    }

    var zoomiesThreshold: Double {
        switch self {
        case .sensitive: return 0.40
        case .normal: return 0.60
        case .calm: return 0.80
        }
    }

    var rocketThreshold: Double {
        switch self {
        case .sensitive: return 0.80
        case .normal: return 1.00
        case .calm: return 1.20
        }
    }


    var dipThreshold: Double { -happyThreshold }
    var crashThreshold: Double { -zoomiesThreshold }
    var panicThreshold: Double { -rocketThreshold }

    func detailedSummary(_ language: AppLanguage) -> String {
        String(
            format: language.pick(
                "상승 +%.2f / +%.2f / +%.2f%% · 하락 %.2f / %.2f / %.2f%%",
                "Rise +%.2f / +%.2f / +%.2f%% · Drop %.2f / %.2f / %.2f%%"
            ),
            happyThreshold, zoomiesThreshold, rocketThreshold,
            dipThreshold, crashThreshold, panicThreshold
        )
    }
}

enum CatoshiActivity: String, CaseIterable, Identifiable {
    case quiet
    case normal
    case playful

    var id: String { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .quiet: return language.pick("조용", "Quiet")
        case .normal: return language.pick("보통", "Normal")
        case .playful: return language.pick("활발", "Playful")
        }
    }

    var nextActionDelay: ClosedRange<Double> {
        switch self {
        case .quiet: return 45...120
        case .normal: return 20...60
        case .playful: return 10...35
        }
    }
}

enum CatoshiCooldown: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .oneMinute: return language.pick("1분", "1 minute")
        case .twoMinutes: return language.pick("2분", "2 minutes")
        case .fiveMinutes: return language.pick("5분", "5 minutes")
        case .tenMinutes: return language.pick("10분", "10 minutes")
        }
    }
}

enum CatoshiState: String {
    case idle
    case walk
    case turn
    case standUp
    case sitDown
    case sit
    case loaf
    case stretch
    case groom
    case sleep
    case happy
    case zoomies
    case rocket
    case alert
    case scared
    case flee

    var severity: Int {
        switch self {
        case .idle, .walk, .turn, .standUp, .sitDown, .sit, .loaf, .stretch, .groom, .sleep: return 0
        case .happy, .alert: return 1
        case .zoomies, .scared: return 2
        case .rocket, .flee: return 3
        }
    }

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .idle: return language.pick("조용히 지켜보는 중", "Watching quietly")
        case .walk: return language.pick("산책 중", "Taking a stroll")
        case .turn: return language.pick("방향을 바꾸는 중", "Turning around")
        case .standUp: return language.pick("일어나는 중", "Getting up")
        case .sitDown: return language.pick("자리 잡는 중", "Settling down")
        case .sit: return language.pick("앉아 있는 중", "Sitting")
        case .loaf: return language.pick("식빵 굽는 중", "Loaf mode")
        case .stretch: return language.pick("기지개 중", "Stretching")
        case .groom: return language.pick("그루밍 중", "Grooming")
        case .sleep: return language.pick("낮잠 중", "Napping")
        case .happy: return language.pick("신난 상태", "Excited")
        case .zoomies: return language.pick("우다다", "Zoomies")
        case .rocket: return language.pick("달나라 모드", "Moon mode")
        case .alert: return language.pick("하락 감시 중", "Watching the dip")
        case .scared: return language.pick("깜짝 놀람", "Spooked")
        case .flee: return language.pick("도망가는 중", "Running away")
        }
    }

    var isMoving: Bool {
        switch self {
        case .walk, .happy, .zoomies, .rocket, .flee: return true
        default: return false
        }
    }

    /// Compact frame sequences tuned for a ~20 pt menu bar. Ordinary walking uses a
    /// dedicated four-phase gait; sit/stand transitions provide visual grammar between
    /// locomotion and resting poses instead of snapping directly between them.
    var frameSequence: [String] {
        switch self {
        case .idle: return ["idle"]
        case .walk: return ["walk1", "walk2", "walk3", "walk4"]
        case .turn: return ["turn1", "turn2", "turn3"]
        case .standUp: return ["sit", "turn3", "idle"]
        case .sitDown: return ["idle", "turn3", "sit"]
        case .sit: return ["sit"]
        case .loaf: return ["loaf"]
        case .stretch: return ["sit", "stretch", "stretch", "idle"]
        case .groom: return ["groom", "sit", "groom", "groom", "sit"]
        case .sleep: return ["sleep"]
        case .happy: return ["happy", "walk2", "happy", "walk4"]
        case .zoomies: return ["run1", "zoom1", "run2", "zoom2", "run1", "zoom1"]
        case .rocket: return ["zoom1", "zoom2", "run1", "zoom2", "zoom1", "run2"]
        case .alert: return ["sit", "idle", "sit"]
        case .scared: return ["sit", "scared", "scared", "loaf"]
        case .flee: return ["scared", "flee", "run1", "flee", "run2"]
        }
    }

    var framesPerSecond: Double {
        switch self {
        case .walk: return 7.5
        case .turn: return 8.0
        case .standUp, .sitDown: return 7.0
        case .stretch: return 3.5
        case .groom: return 3.2
        case .happy: return 5.5
        case .zoomies: return 9.0
        case .rocket: return 10.0
        case .alert: return 1.8
        case .scared: return 4.0
        case .flee: return 8.5
        default: return 0
        }
    }

    /// Distance advanced for one rendered locomotion frame. Ordinary walking uses
    /// small pixel-art steps; the menu-bar view derives its gait phase from these
    /// position steps instead of running a second animation clock.
    var travelPointsPerFrame: Double {
        switch self {
        case .walk: return 2.2
        case .happy: return 3.4
        case .zoomies: return 5.4
        case .rocket: return 6.2
        case .flee: return 5.6
        default: return 0
        }
    }

    var travelFrameInterval: Double {
        guard framesPerSecond > 0 else { return 0.18 }
        return 1.0 / framesPerSecond
    }

    var needsTimeline: Bool {
        animationEnabledByState && (frameSequence.count > 1 || isMoving)
    }

    /// Static representative art for non-animated contexts such as the popover header.
    var representativeFrameName: String {
        switch self {
        case .idle: return "idle"
        case .walk: return "walk2"
        case .turn: return "turn2"
        case .standUp: return "turn3"
        case .sitDown, .sit, .alert: return "sit"
        case .loaf: return "loaf"
        case .stretch: return "stretch"
        case .groom: return "groom"
        case .sleep: return "sleep"
        case .happy: return "happy"
        case .zoomies: return "zoom1"
        case .rocket: return "zoom2"
        case .scared: return "scared"
        case .flee: return "flee"
        }
    }

    private var animationEnabledByState: Bool {
        switch self {
        case .idle, .sit, .loaf, .sleep: return false
        default: return true
        }
    }
}

enum CatoshiMicroMotion: Equatable {
    case none
    case breathe
    case blink
    case earTwitch
    case tailFlick
    case settle
}
