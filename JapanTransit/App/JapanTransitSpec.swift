import Foundation
import LeeoKit

/// LeeoKit 은 아직 팁 화면에만 쓴다. 의견 보내기 · 앞으로 만들 기능은 README '다음' 2번에서 붙인다.
/// ⚠️ 여기서 bootstrap · 피드백 · 분석을 켜지 않는다 — 계약을 채우는 값일 뿐 아무것도 돌지 않는다.
enum JapanTransitSpec: LeeoAppSpec {
    static let appName = "일본길찾기"
    static let developerEmail = "leeo@kakao.com"
    static let feedback = LeeoFeedbackConfig(
        containerIdentifier: "iCloud.com.Ysoup.FeedbackHub",
        appIdentifier: "com.leeo.japantransit"
    )
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/JapanTransit/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/JapanTransit/support.html")!
    )
    static let monetization = LeeoMonetization.free

    /// 무료 앱이라 LeeoStore 가 없다 — 팁만 혼자 받는다(앱을 열 때 `startStandalone()`, → JapanTransitApp).
    /// 소모성 상품 셋, 작은 것부터. ⚠️ 기능을 여는 상품이 아니다.
    @MainActor static let tipJar = LeeoTipJar(config: LeeoTipJarConfig(productIDs: [
        "com.leeo.japantransit.tip.small",
        "com.leeo.japantransit.tip.medium",
        "com.leeo.japantransit.tip.large",
    ]))
}

/// 팁을 부탁할 만한 순간 — 카메라로 "타세요" 를 확인한 열차 수. 비출 때마다가 아니라 한 번 비추기에 한 번 센다.
enum JapanTransitTipMoments {
    static let boardedKey = "tips.boardedTrains"
    /// 확인하고 탄 열차 수. 큰 것부터.
    static let boarded = [30, 10, 3]

    /// 카메라가 "타세요" 를 처음 보여 준 때 한 번 부른다.
    static func recordBoarding() {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: boardedKey) + 1, forKey: boardedKey)
    }

    /// 넘어선 순간, 인상적인 것부터.
    static func reached(boardedCount count: Int) -> [LeeoTipMoment] {
        boarded.filter { count >= $0 }.map { threshold in
            LeeoTipMoment(id: "boarded.\(threshold)",
                          message: String(localized: "지금까지 열차 \(count)번을 카메라로 확인하고 탔어요",
                                          comment: "Tip ask card: how many trains the person confirmed with the camera before boarding"))
        }
    }
}
