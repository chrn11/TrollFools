//
//  FilterOptions.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import Foundation

struct FilterOptions: Hashable {
    private static let pinInjectedAppsStorageKey = "pinInjectedAppsV2"

    var searchKeyword = ""
    var showPatchedOnly = false
    var pinInjectedApps = (UserDefaults.standard.object(forKey: FilterOptions.pinInjectedAppsStorageKey) as? Bool) ?? false

    var isSearching: Bool { !searchKeyword.isEmpty }

    mutating func reset() {
        searchKeyword = ""
        showPatchedOnly = false
        pinInjectedApps = (UserDefaults.standard.object(forKey: FilterOptions.pinInjectedAppsStorageKey) as? Bool) ?? false
    }
}
