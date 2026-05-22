import Foundation

enum AppConstants {
    static let appGroupID = "BYCQP55SB3.com.yangchengjiao.plan"
    static let maxStreakDays = 365
    static let taskHorizonDays = 60

    enum DeepLink {
        static let today = URL(string: "planapp://today")!
        static let add = URL(string: "planapp://add")!
    }
}
