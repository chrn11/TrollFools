//
//  App.swift
//  TrollFools
//
//  Created by 82Flex on 2024/10/30.
//

import Combine
import Foundation

final class App: ObservableObject {
    let bid: String
    let name: String
    let latinName: String
    let type: String
    let teamID: String
    let url: URL
    let version: String?
    let isAdvertisement: Bool

    @Published var isDetached: Bool
    @Published var isAllowedToAttachOrDetach: Bool
    @Published var isInjected: Bool
    @Published var hasPersistedAssets: Bool
    @Published var enabledPlugInCount: Int
    @Published var disabledPlugInCount: Int

    lazy var icon: UIImage? = UIImage._applicationIconImage(forBundleIdentifier: bid, format: 0, scale: 3.0)
    var alternateIcon: UIImage?

    lazy var isUser: Bool = type == "User"
    lazy var isSystem: Bool = !isUser
    lazy var isFromApple: Bool = bid.hasPrefix("com.apple.")
    lazy var isFromTroll: Bool = isSystem && !isFromApple
    lazy var isRemovable: Bool = url.path.contains("/var/containers/Bundle/Application/")

    weak var appList: AppListModel?
    private var cancellables: Set<AnyCancellable> = []
    private static let reloadSubject = PassthroughSubject<String, Never>()

    init(
        bid: String,
        name: String,
        type: String,
        teamID: String,
        url: URL,
        version: String? = nil,
        alternateIcon: UIImage? = nil,
        isAdvertisement: Bool = false
    ) {
        self.bid = bid
        self.name = name
        self.type = type
        self.teamID = teamID
        self.url = url
        self.version = version
        let injected = InjectorV3.main.checkIsInjectedAppBundle(url)
        let persisted = InjectorV3.main.hasPersistedAssets(bid: bid)
        let plugInCounts = Self.plugInCounts(url: url, bid: bid, isInjected: injected, hasPersistedAssets: persisted)
        self.isDetached = InjectorV3.main.isMetadataDetachedInBundle(url)
        self.isAllowedToAttachOrDetach = type == "User" && InjectorV3.main.isAllowedToAttachOrDetachMetadataInBundle(url)
        self.isInjected = injected
        self.hasPersistedAssets = persisted
        self.enabledPlugInCount = plugInCounts.enabled
        self.disabledPlugInCount = plugInCounts.disabled
        self.alternateIcon = alternateIcon
        self.isAdvertisement = isAdvertisement
        self.latinName = name
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)?
            .components(separatedBy: .whitespaces)
            .joined() ?? ""
        Self.reloadSubject
            .filter { $0 == bid }
            .sink { [weak self] _ in
                self?._reload()
            }
            .store(in: &cancellables)
    }

    func reload() {
        Self.reloadSubject.send(bid)
    }

    private func _reload() {
        reloadDetachedStatus()
        reloadInjectedStatus()
    }

    private func reloadDetachedStatus() {
        self.isDetached = InjectorV3.main.isMetadataDetachedInBundle(url)
        self.isAllowedToAttachOrDetach = isUser && InjectorV3.main.isAllowedToAttachOrDetachMetadataInBundle(url)
    }

    private func reloadInjectedStatus() {
        self.isInjected = InjectorV3.main.checkIsInjectedAppBundle(url)
        self.hasPersistedAssets = InjectorV3.main.hasPersistedAssets(bid: bid)
        let plugInCounts = Self.plugInCounts(
            url: url,
            bid: bid,
            isInjected: isInjected,
            hasPersistedAssets: hasPersistedAssets
        )
        self.enabledPlugInCount = plugInCounts.enabled
        self.disabledPlugInCount = plugInCounts.disabled
    }

    private static func plugInCounts(url: URL, bid: String, isInjected: Bool, hasPersistedAssets: Bool) -> PlugInCounts {
        guard isInjected || hasPersistedAssets else {
            return .zero
        }
        return InjectorV3.main.plugInCounts(in: url, bid: bid)
    }
}
