//
//  AppListView.swift
//  TrollFools
//
//  Created by Lessica on 2024/7/19.
//

import CocoaLumberjackSwift
import OrderedCollections
import SwiftUI
import SwiftUIIntrospect

typealias Scope = AppListModel.Scope

struct AppListView: View {
    let isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad

    private struct RestoreDisabledPlugInsSummary {
        let appCount: Int
        let plugInCount: Int
        let failedAppCount: Int
    }

    @StateObject var searchViewModel = AppListSearchModel()
    @EnvironmentObject var appList: AppListModel
    @Environment(\.verticalSizeClass) var verticalSizeClass

    @State var selectorOpenedURL: URLIdentifiable? = nil
    @State var selectedIndex: String? = nil

    @State var isWarningPresented = false
    @State var temporaryOpenedURL: URLIdentifiable? = nil

    @State var latestVersionString: String?
    @State var isRestoringDisabledPlugIns = false
    @State var isRestoreResultPresented = false
    @State var restoreResultTitle = ""
    @State var restoreResultMessage = ""

    @AppStorage("isWarningHidden")
    var isWarningHidden: Bool = false

    var shouldDisableToolbarActions: Bool {
        isRestoringDisabledPlugIns
    }

    var appString: String {
        let appNameString = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "TrollFools"
        let appVersionString = String(
            format: "v%@ (%@)",
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        )

        let appStringFormat = """
        %@ %@
        %@ © 2024-%d %@
        """

        return String(
            format: appStringFormat,
            appNameString, appVersionString,
            NSLocalizedString("Copyright", comment: ""),
            Calendar.current.component(.year, from: Date()),
            NSLocalizedString("Lessica, huami1314, iosdump and other contributors", comment: "")
        )
    }

    var body: some View {
        if #available(iOS 15, *) {
            content
                .alert(
                    NSLocalizedString("Notice", comment: ""),
                    isPresented: $isWarningPresented,
                    presenting: temporaryOpenedURL
                ) { result in
                    Button {
                        selectorOpenedURL = result
                    } label: {
                        Text(NSLocalizedString("Continue", comment: ""))
                    }
                    Button(role: .destructive) {
                        selectorOpenedURL = result
                        isWarningHidden = true
                    } label: {
                        Text(NSLocalizedString("Continue and Don’t Show Again", comment: ""))
                    }
                    Button(role: .cancel) {
                        temporaryOpenedURL = nil
                        isWarningPresented = false
                    } label: {
                        Text(NSLocalizedString("Cancel", comment: ""))
                    }
                } message: {
                    Text(OptionView.warningMessage([$0.url]))
                }
                .alert(restoreResultTitle, isPresented: $isRestoreResultPresented) {
                    Button(NSLocalizedString("Done", comment: ""), role: .cancel) { }
                } message: {
                    Text(restoreResultMessage)
                }
        } else {
            content
                .alert(isPresented: $isRestoreResultPresented) {
                    Alert(
                        title: Text(restoreResultTitle),
                        message: Text(restoreResultMessage),
                        dismissButton: .default(Text(NSLocalizedString("Done", comment: "")))
                    )
                }
        }
    }

    var content: some View {
        styledNavigationView
            .animation(.easeOut, value: appList.activeScopeApps.keys)
            .sheet(item: $selectorOpenedURL) { urlWrapper in
                AppListView()
                    .environmentObject(AppListModel(selectorURL: urlWrapper.url))
            }
            .onOpenURL { url in
                let ext = url.pathExtension.lowercased()
                guard url.isFileURL,
                      ext == "dylib" || ext == "deb" || ext == "zip"
                else {
                    return
                }

                let urlIdent = URLIdentifiable(url: preprocessURL(url))
                if #available(iOS 15, *) {
                    if !isWarningHidden && ext == "deb" {
                        temporaryOpenedURL = urlIdent
                        isWarningPresented = true
                        return
                    }
                }

                selectorOpenedURL = urlIdent
            }
            .onAppear {
                CheckUpdateManager.shared.checkUpdateIfNeeded { latestVersion, _ in
                    DispatchQueue.main.async {
                        withAnimation {
                            latestVersionString = latestVersion?.tagName
                        }
                    }
                }
            }
    }

    @ViewBuilder
    var styledNavigationView: some View {
        if isPad {
            navigationView
                .navigationViewStyle(.automatic)
        } else {
            navigationView
                .navigationViewStyle(.stack)
        }
    }

    var navigationView: some View {
        NavigationView {
            ScrollViewReader { reader in
                ZStack {
                    refreshableListView

                    if verticalSizeClass == .regular && appList.activeScopeApps.keys.count > 1 {
                        IndexableScroller(
                            indexes: appList.activeScopeApps.keys.elements,
                            currentIndex: $selectedIndex
                        )
                        .accessibilityHidden(true)
                    }
                }
                .onChange(of: selectedIndex) { index in
                    if let index {
                        reader.scrollTo("AppSection-\(index)", anchor: .center)
                    }
                }
            }

            // Detail view shown when nothing has been selected
            if !appList.isSelectorMode {
                PlaceholderView()
            }
        }
    }

    @ViewBuilder
    var refreshableListView: some View {
        if #available(iOS 15, *) {
            searchableListView
                .refreshable {
                    guard !isRestoringDisabledPlugIns else {
                        return
                    }
                    appList.reload()
                }
        } else {
            searchableListView
                .introspect(.list, on: .iOS(.v14)) { tableView in
                    if tableView.refreshControl == nil {
                        tableView.refreshControl = {
                            let refreshControl = UIRefreshControl()
                            refreshControl.addAction(UIAction { action in
                                if !isRestoringDisabledPlugIns {
                                    appList.reload()
                                }
                                if let control = action.sender as? UIRefreshControl {
                                    control.endRefreshing()
                                }
                            }, for: .valueChanged)
                            return refreshControl
                        }()
                    }
                }
        }
    }

    var searchableListView: some View {
        listView
            .onChange(of: appList.filter.showPatchedOnly) { showPatchedOnly in
                if let searchBar = searchViewModel.searchController?.searchBar {
                    reloadSearchBarPlaceholder(searchBar, showPatchedOnly: showPatchedOnly)
                }
            }
            .onReceive(searchViewModel.$searchKeyword) {
                appList.filter.searchKeyword = $0
            }
            .onReceive(searchViewModel.$searchScopeIndex) {
                appList.activeScope = Scope(rawValue: $0) ?? .all
            }
            .introspect(.viewController, on: .iOS(.v14, .v15, .v16, .v17, .v18)) { viewController in
                viewController.navigationItem.hidesSearchBarWhenScrolling = true
                if searchViewModel.searchController == nil {
                    viewController.navigationItem.searchController = {
                        let searchController = UISearchController(searchResultsController: nil)
                        searchController.searchResultsUpdater = searchViewModel
                        searchController.obscuresBackgroundDuringPresentation = false
                        searchController.hidesNavigationBarDuringPresentation = true
                        searchController.automaticallyShowsScopeBar = false
                        if #available(iOS 16, *) {
                            searchController.scopeBarActivation = .manual
                        }
                        setupSearchBar(searchController: searchController)
                        return searchController
                    }()
                    searchViewModel.searchController = viewController.navigationItem.searchController
                }
            }
    }

    var listView: some View {
        List {
            topSection

            appSections
        }
        .animation(.easeOut, value: combines(
            appList.isRebuildNeeded,
            appList.activeScope,
            appList.filter,
            appList.unsupportedCount
        ))
        .listStyle(.insetGrouped)
        .disabled(isRestoringDisabledPlugIns)
        .navigationTitle(appList.isSelectorMode ?
            NSLocalizedString("Select Application to Inject", comment: "") :
            NSLocalizedString("TrollFools", comment: "")
        )
        .navigationBarTitleDisplayMode((AppListModel.isLegacyDevice || appList.isSelectorMode) ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if appList.isSelectorMode, let selectorURL = appList.selectorURL {
                    VStack {
                        Text(selectorURL.lastPathComponent).font(.headline)
                        Text(NSLocalizedString("Select Application to Inject", comment: "")).font(.caption)
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !appList.isSelectorMode {
                    Button {
                        reEnableAllDisabledPlugIns()
                    } label: {
                        if isRestoringDisabledPlugIns {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise.circle")
                        }
                    }
                    .disabled(shouldDisableToolbarActions)
                    .accessibilityLabel(NSLocalizedString("Re-Enable Disabled Plug-Ins", comment: ""))
                }

                Button {
                    appList.filter.pinInjectedApps.toggle()
                } label: {
                    if #available(iOS 15, *) {
                        Image(systemName: appList.filter.pinInjectedApps
                            ? "pin.fill"
                            : "pin")
                    } else {
                        Image(systemName: appList.filter.pinInjectedApps
                            ? "star.fill"
                            : "star")
                    }
                }
                .disabled(shouldDisableToolbarActions)
                .accessibilityLabel(NSLocalizedString("Pin Injected Apps", comment: ""))

                Button {
                    appList.filter.showPatchedOnly.toggle()
                } label: {
                    if #available(iOS 15, *) {
                        Image(systemName: appList.filter.showPatchedOnly
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    } else {
                        Image(systemName: appList.filter.showPatchedOnly
                            ? "eject.circle.fill"
                            : "eject.circle")
                    }
                }
                .disabled(shouldDisableToolbarActions)
                .accessibilityLabel(NSLocalizedString("Show Patched Only", comment: ""))
            }
        }
    }

    var topSection: some View {
        Section {
            if AppListModel.hasTrollStore && appList.isRebuildNeeded {
                rebuildButton
                    .transition(.opacity)
            }
        } header: {
            if AppListModel.hasTrollStore && appList.isRebuildNeeded {
                Text("")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if appList.activeScope == .all && latestVersionString != nil {
                    upgradeButton
                        .transition(.opacity)
                }

                if !appList.filter.isSearching && !appList.filter.showPatchedOnly && !appList.isRebuildNeeded {
                    paddedHeaderFooterText(
                        appList.activeScope == .system
                            ? NSLocalizedString("Only removable system applications are eligible and listed.", comment: "")
                            : (appList.activeScope != .troll && appList.unsupportedCount > 0
                                ? String(format: NSLocalizedString("And %d more unsupported user applications.", comment: ""), appList.unsupportedCount)
                                : "")
                    )
                    .transition(.opacity)
                }
            }
        }
        .id("TopSection")
    }

    var rebuildButton: some View {
        Button {
            appList.rebuildIconCache()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Rebuild Icon Cache", comment: ""))
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("You need to rebuild the icon cache in TrollStore to apply changes.", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "timelapse")
                    .font(.title)
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 4)
        }
    }

    var upgradeButton: some View {
        Button {
            CheckUpdateManager.shared.executeUpgrade()
        } label: {
            Text(String(format: NSLocalizedString("New version %@ available!", comment: ""), latestVersionString ?? "(null)"))
                .font(.footnote)
        }
    }

    var appSections: some View {
        ForEach(appList.activeScopeApps.isEmpty ? ["_"] : Array(appList.activeScopeApps.keys), id: \.self) { sectionKey in
            appSection(forKey: sectionKey)
        }
    }

    func appSection(forKey sectionKey: String) -> some View {
        Section {
            ForEach(appList.activeScopeApps[sectionKey] ?? [], id: \.bid) { app in
                NavigationLink {
                    if appList.isSelectorMode, let selectorURL = appList.selectorURL {
                        InjectView(app, urlList: [selectorURL])
                    } else {
                        OptionView(app)
                    }
                } label: {
                    if #available(iOS 16, *) {
                        AppListCell(app: app)
                    } else {
                        AppListCell(app: app)
                            .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            if sectionKey == "_" {
                paddedHeaderFooterText(NSLocalizedString("No Applications", comment: ""))
                    .textCase(.none)
            } else {
                paddedHeaderFooterText(sectionKey == selectedIndex ? "→ \(sectionKey)" : sectionKey)
            }
        } footer: {
            if (sectionKey == "_" || sectionKey == appList.activeScopeApps.keys.last) && !appList.isSelectorMode && !appList.filter.isSearching {
                footer
            }
        }
        .id("AppSection-\(sectionKey)")
    }

    @ViewBuilder
    var footer: some View {
        if #available(iOS 16, *) {
            footerContent
                .padding(.vertical, 16)
        } else if #available(iOS 15, *) {
            footerContent
                .padding(.top, 10)
                .padding(.bottom, 16)
        } else {
            footerContent
                .padding(.all, 16)
        }
    }

    var footerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appString)
                .font(.footnote)

            Button {
                UIApplication.shared.open(URL(string: "https://github.com/Lessica/TrollFools")!)
            } label: {
                Text(NSLocalizedString("Source Code", comment: ""))
                    .font(.footnote)
            }
        }
    }

    private func preprocessURL(_ url: URL) -> URL {
        let isInbox = url.path.contains("/Documents/Inbox/")
        guard isInbox else {
            return url
        }
        let fileNameNoExt = url.deletingPathExtension().lastPathComponent
        let fileNameComps = fileNameNoExt.components(separatedBy: CharacterSet(charactersIn: "._- "))
        guard let lastComp = fileNameComps.last, fileNameComps.count > 1, lastComp.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil else {
            return url
        }
        let newURL = url.deletingLastPathComponent()
            .appendingPathComponent(String(fileNameNoExt.prefix(fileNameNoExt.count - lastComp.count - 1)))
            .appendingPathExtension(url.pathExtension)
        do {
            try? FileManager.default.removeItem(at: newURL)
            try FileManager.default.copyItem(at: url, to: newURL)
            return newURL
        } catch {
            return url
        }
    }

    private func setupSearchBar(searchController: UISearchController) {
        if let searchBarDelegate = searchController.searchBar.delegate, (searchBarDelegate as? NSObject) != searchViewModel {
            searchViewModel.forwardSearchBarDelegate = searchBarDelegate
        }

        searchController.searchBar.delegate = searchViewModel
        searchController.searchBar.showsScopeBar = true
        searchController.searchBar.scopeButtonTitles = Scope.allCases.map { $0.localizedShortName }
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no

        reloadSearchBarPlaceholder(searchController.searchBar, showPatchedOnly: appList.filter.showPatchedOnly)
    }

    private func reloadSearchBarPlaceholder(_ searchBar: UISearchBar, showPatchedOnly: Bool) {
        searchBar.placeholder = (showPatchedOnly
            ? NSLocalizedString("Search Patched…", comment: "")
            : NSLocalizedString("Search…", comment: ""))
    }

    private func reEnableAllDisabledPlugIns() {
        guard !isRestoringDisabledPlugIns else {
            return
        }

        isRestoringDisabledPlugIns = true

        let apps = appList.allApplications

        DispatchQueue.global(qos: .userInitiated).async {
            let summary = restoreDisabledPlugInsForAllApps(apps)

            DispatchQueue.main.async {
                isRestoringDisabledPlugIns = false
                appList.reload()
                presentRestoreSummary(summary)
            }
        }
    }

    private func presentRestoreSummary(_ summary: RestoreDisabledPlugInsSummary) {
        if summary.failedAppCount == 0 {
            restoreResultTitle = NSLocalizedString("Completed", comment: "")
            if summary.plugInCount == 0 {
                restoreResultMessage = NSLocalizedString("No disabled plug-ins found in patched apps.", comment: "")
            } else {
                restoreResultMessage = String(
                    format: NSLocalizedString("Re-enabled %d plug-ins in %d apps.", comment: ""),
                    summary.plugInCount,
                    summary.appCount
                )
            }
        } else if summary.plugInCount == 0 {
            restoreResultTitle = NSLocalizedString("Failed", comment: "")
            restoreResultMessage = String(
                format: NSLocalizedString("Failed to re-enable plug-ins in %d apps.", comment: ""),
                summary.failedAppCount
            )
        } else {
            restoreResultTitle = NSLocalizedString("Completed with Errors", comment: "")
            restoreResultMessage = String(
                format: NSLocalizedString("Re-enabled %d plug-ins in %d apps, %d apps failed.", comment: ""),
                summary.plugInCount,
                summary.appCount,
                summary.failedAppCount
            )
        }

        isRestoreResultPresented = true
    }

    private func restoreDisabledPlugInsForAllApps(_ apps: [App]) -> RestoreDisabledPlugInsSummary {
        var recoveredAppCount = 0
        var recoveredPlugInCount = 0
        var failedAppCount = 0
        let defaults = UserDefaults.standard

        for app in apps {
            let persistedPlugIns = InjectorV3.main.persistedAssetURLs(bid: app.bid)
            guard !persistedPlugIns.isEmpty else {
                continue
            }

            let enabledPlugInNames = Set(InjectorV3.main.injectedAssetURLsInBundle(app.url).map(\.lastPathComponent))
            let disabledPlugIns = persistedPlugIns.filter {
                !enabledPlugInNames.contains($0.lastPathComponent)
            }

            guard !disabledPlugIns.isEmpty else {
                continue
            }

            do {
                let injector = try InjectorV3(app.url)

                if injector.appID.isEmpty {
                    injector.appID = app.bid
                }

                if injector.teamID.isEmpty {
                    injector.teamID = app.teamID
                }

                injector.useWeakReference = (defaults.object(forKey: "UseWeakReference-\(app.bid)") as? Bool) ?? true
                injector.preferMainExecutable = (defaults.object(forKey: "PreferMainExecutable-\(app.bid)") as? Bool) ?? false
                injector.injectStrategy = defaults
                    .string(forKey: "InjectStrategy-\(app.bid)")
                    .flatMap(InjectorV3.Strategy.init(rawValue:)) ?? .lexicographic

                try injector.inject(disabledPlugIns, shouldPersist: false)
                recoveredPlugInCount += disabledPlugIns.count
                recoveredAppCount += 1
            } catch {
                DDLogError("\(error)", ddlog: InjectorV3.main.logger)
                failedAppCount += 1
            }
        }

        return .init(appCount: recoveredAppCount, plugInCount: recoveredPlugInCount, failedAppCount: failedAppCount)
    }

    @ViewBuilder
    private func paddedHeaderFooterText(_ content: String) -> some View {
        if #available(iOS 15, *) {
            Text(content)
                .font(.footnote)
        } else {
            Text(content)
                .font(.footnote)
                .padding(.horizontal, 16)
        }
    }
}

struct URLIdentifiable: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
