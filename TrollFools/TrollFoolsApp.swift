//
//  TrollFoolsApp.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import SwiftUI

@main
struct TrollFoolsApp: SwiftUI.App {

    @AppStorage("isDisclaimerHiddenV2")
    var isDisclaimerHidden: Bool = false

    init() {
        try? FileManager.default.removeItem(at: InjectorV3.temporaryRoot)

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "isDisclaimerHidden"),
           !defaults.bool(forKey: "isDisclaimerHiddenV2")
        {
            defaults.set(true, forKey: "isDisclaimerHiddenV2")
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isDisclaimerHidden {
                    AppListView()
                        .environmentObject(AppListModel())
                        .transition(.opacity)
                } else {
                    DisclaimerView(isDisclaimerHidden: $isDisclaimerHidden)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: isDisclaimerHidden)
        }
    }
}
