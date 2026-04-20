import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @StateObject private var viewModel = BMusicViewModel()
    @State private var selectedTab: BMusicTab = .search
    @State private var libraryEditMode: EditMode = .inactive
    @State private var showQuickSearch = false
    @State private var quickSearchText = ""

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack {
                SearchScreen(viewModel: viewModel)
                    .navigationTitle("首页")
            }
            .miniPlayerInset(viewModel: viewModel)
            .tabItem {
                Label("首页", systemImage: "house.fill")
            }
            .tag(BMusicTab.search)

            NavigationStack {
                LibraryScreen(viewModel: viewModel) { query in
                    libraryEditMode = .inactive
                    viewModel.searchText = query
                    selectedTab = .search
                    Task { await viewModel.search(reset: true) }
                }
                .navigationTitle("资料库")
            }
            .environment(\.editMode, $libraryEditMode)
            .miniPlayerInset(viewModel: viewModel)
            .tabItem {
                Label("资料库", systemImage: "music.note.list")
            }
            .tag(BMusicTab.library)

            NavigationStack {
                SettingsScreen(viewModel: viewModel)
                    .navigationTitle("设置")
            }
            .miniPlayerInset(viewModel: viewModel)
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
            .tag(BMusicTab.settings)

            Color.clear
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(BMusicTab.quickSearch)
        }
        .overlay(alignment: .bottom) {
            if showQuickSearch {
                QuickSearchDock {
                    QuickSearchBar(
                        text: $quickSearchText,
                        isSearching: viewModel.isSearching
                    ) {
                        performQuickSearch()
                    } close: {
                        withAnimation(.snappy) {
                            showQuickSearch = false
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $viewModel.showLogin) {
            NavigationStack {
                LoginScreen(viewModel: viewModel)
                    .navigationTitle("B 站登录")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                viewModel.showLogin = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $viewModel.showWebLogin) {
            NavigationStack {
                WebLoginScreen(viewModel: viewModel)
                    .navigationTitle("网页登录")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") {
                                viewModel.showWebLogin = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $viewModel.showPlaylistPicker) {
            NavigationStack {
                PlaylistPickerScreen(viewModel: viewModel)
                    .navigationTitle("加入播放列表")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") {
                                viewModel.showPlaylistPicker = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.clear)
        }
        .sheet(isPresented: $viewModel.showPlayer) {
            PlayerScreen(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .task {
            await viewModel.refreshUser()
        }
    }

    private var tabSelection: Binding<BMusicTab> {
        Binding {
            selectedTab
        } set: { newValue in
            if newValue == .quickSearch {
                quickSearchText = viewModel.searchText
                withAnimation(.snappy) {
                    showQuickSearch = true
                }
            } else {
                selectedTab = newValue
                withAnimation(.snappy) {
                    showQuickSearch = false
                }
            }
        }
    }

    private func performQuickSearch() {
        let keyword = quickSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return
        }

        viewModel.searchText = keyword
        selectedTab = .search
        withAnimation(.snappy) {
            showQuickSearch = false
        }
        Task { await viewModel.search(reset: true) }
    }
}

private enum BMusicTab: Hashable {
    case search
    case library
    case settings
    case quickSearch
}

private struct QuickSearchDock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.regularMaterial)
                .frame(height: 10)
                .offset(y: 10)
        }
    }
}

private extension View {
    func miniPlayerInset(viewModel: BMusicViewModel) -> some View {
        safeAreaInset(edge: .bottom, spacing: 8) {
            MiniPlayer(viewModel: viewModel)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }
}

private struct SearchScreen: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        List {
            if !viewModel.errorMessage.isEmpty {
                Section {
                    Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索 B 站音乐、歌手、视频", text: $viewModel.searchText)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await viewModel.search(reset: true) }
                        }
                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    Task { await viewModel.search(reset: true) }
                } label: {
                    if viewModel.isSearching {
                        ProgressView()
                    } else {
                        Label("搜索", systemImage: "arrow.right.circle.fill")
                    }
                }
                .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
            }

            Section {
                if viewModel.results.isEmpty {
                    RecommendationCloudView(recommendations: viewModel.displayRecommendations) { keyword in
                        viewModel.searchText = keyword
                        Task { await viewModel.search(reset: true) }
                    }

                    Button {
                        viewModel.shuffleRecommendations()
                        Task { await viewModel.refreshRecommendedKeywords(force: true) }
                    } label: {
                        if viewModel.isLoadingRecommendedKeywords {
                            ProgressView()
                        } else {
                            Label("换一换", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(viewModel.isLoadingRecommendedKeywords)
                } else {
                    ForEach(viewModel.results) { item in
                        MusicRow(viewModel: viewModel, item: item)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if let artist = item.artist {
                                Button {
                                    viewModel.toggleFavoriteArtist(artist)
                                } label: {
                                    Label(viewModel.isFavoriteArtist(artist) ? "取消 UP" : "收藏 UP", systemImage: viewModel.isFavoriteArtist(artist) ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                                }
                                .tint(.teal)
                            }
                        }
                        .task {
                            await viewModel.loadMoreIfNeeded(current: item)
                        }
                    }

                    if viewModel.isSearching {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            } header: {
                Text(viewModel.results.isEmpty ? "推荐关键词" : "结果")
            }
        }
        .listStyle(.insetGrouped)
        .task {
            await viewModel.refreshRecommendedKeywords()
        }
    }
}

private struct QuickSearchBar: View {
    @Binding var text: String
    let isSearching: Bool
    let submit: () -> Void
    let close: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索 B 站音乐", text: $text)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit(submit)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.bar, in: Capsule())

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
        }
        .onAppear {
            isFocused = true
        }
    }
}

private struct RecommendationCloudView: View {
    let recommendations: [BMusicRecommendation]
    let select: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 9, rowSpacing: 10) {
            ForEach(recommendations) { recommendation in
                Button {
                    select(recommendation.keyword)
                } label: {
                    Text(recommendation.keyword)
                        .font(.system(size: fontSize(for: recommendation), weight: fontWeight(for: recommendation)))
                        .lineLimit(1)
                        .foregroundStyle(styleColor(for: recommendation).opacity(0.92))
                        .padding(.horizontal, horizontalPadding(for: recommendation))
                        .padding(.vertical, verticalPadding(for: recommendation))
                        .background(styleColor(for: recommendation).opacity(0.12), in: Capsule())
                        .background(.ultraThinMaterial, in: Capsule())
                        .rotationEffect(.degrees(rotation(for: recommendation)))
                        .offset(y: yOffset(for: recommendation))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
    }

    private func fontSize(for recommendation: BMusicRecommendation) -> CGFloat {
        let scores = recommendations.map(\.score)
        let minScore = scores.min() ?? recommendation.score
        let maxScore = scores.max() ?? recommendation.score
        guard maxScore > minScore else {
            return 18
        }
        let ratio = CGFloat(recommendation.score - minScore) / CGFloat(maxScore - minScore)
        return 14 + ratio * 18
    }

    private func fontWeight(for recommendation: BMusicRecommendation) -> Font.Weight {
        recommendation.score >= (recommendations.map(\.score).max() ?? recommendation.score) - 1 ? .semibold : .regular
    }

    private func horizontalPadding(for recommendation: BMusicRecommendation) -> CGFloat {
        fontSize(for: recommendation) > 24 ? 16 : 11
    }

    private func verticalPadding(for recommendation: BMusicRecommendation) -> CGFloat {
        fontSize(for: recommendation) > 24 ? 9 : 7
    }

    private func styleColor(for recommendation: BMusicRecommendation) -> Color {
        let colors: [Color] = [.pink, .teal, .indigo, .orange, .green, .cyan]
        return colors[abs(recommendation.keyword.stableHash) % colors.count]
    }

    private func rotation(for recommendation: BMusicRecommendation) -> Double {
        Double((abs(recommendation.keyword.stableHash) % 9) - 4) * 0.8
    }

    private func yOffset(for recommendation: BMusicRecommendation) -> CGFloat {
        CGFloat((abs(recommendation.keyword.stableHash / 7) % 7) - 3)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = computeLayout(proposal: proposal, subviews: subviews)
        return layout.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = computeLayout(proposal: proposal, subviews: subviews)
        for (index, origin) in layout.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(layout.sizes[index])
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint], sizes: [CGSize]) {
        let maxWidth = proposal.width ?? 320
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }

        return (
            CGSize(width: min(maxWidth, usedWidth), height: y + rowHeight),
            origins,
            sizes
        )
    }
}

private struct LibraryScreen: View {
    @ObservedObject var viewModel: BMusicViewModel
    let searchBilibili: (String) -> Void
    @Environment(\.editMode) private var editMode
    @State private var librarySearchText = ""
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var searchQuery: String {
        librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var librarySearchResults: [BMusicVideo] {
        viewModel.librarySearchResults(matching: searchQuery)
    }

    private var libraryArtistResults: [BMusicArtist] {
        viewModel.libraryArtistSearchResults(matching: searchQuery)
    }

    var body: some View {
        List {
            if searchQuery.isEmpty {
                LibraryHomeContent(viewModel: viewModel)
            } else {
                LibrarySearchContent(
                    viewModel: viewModel,
                    query: searchQuery,
                    results: librarySearchResults,
                    artists: libraryArtistResults,
                    searchBilibili: searchBilibili
                )
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $librarySearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索资料库音乐和 UP 主")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.recentlyPlayed.isEmpty || !viewModel.playlists.isEmpty || !viewModel.favoriteArtists.isEmpty {
                    Button(isEditing ? "完成" : "编辑") {
                        withAnimation {
                            editMode?.wrappedValue = isEditing ? .inactive : .active
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newPlaylistName = ""
                    showNewPlaylist = true
                } label: {
                    Label("新建播放列表", systemImage: "plus")
                }
            }
        }
        .alert("新建播放列表", isPresented: $showNewPlaylist) {
            TextField("名称", text: $newPlaylistName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                viewModel.createPlaylist(named: newPlaylistName)
            }
        } message: {
            Text("给这个列表起个名字。")
        }
    }
}

private struct LibraryHomeContent: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        if !viewModel.favoriteArtists.isEmpty {
            Section("收藏 UP 主") {
                ForEach(viewModel.favoriteArtists) { artist in
                    NavigationLink {
                        ArtistDetailScreen(viewModel: viewModel, artist: artist)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name)
                                .font(.body)
                            Text("UID \(artist.id)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.removeFavoriteArtists(at: offsets)
                }
            }
        }

        Section("播放列表") {
            NavigationLink {
                FavoritePlaylistDetailScreen(viewModel: viewModel)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的收藏")
                        .font(.body)
                    Text("\(viewModel.favorites.count) 首")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.playlists.isEmpty {
                ForEach(viewModel.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailScreen(viewModel: viewModel, playlistID: playlist.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                                .font(.body)
                            Text("\(playlist.items.count) 首")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    viewModel.deletePlaylists(at: offsets)
                }
            }
        }

        if !viewModel.recentlyPlayed.isEmpty {
            Section("最近播放") {
                ForEach(viewModel.recentlyPlayed) { item in
                    MusicRow(viewModel: viewModel, item: item, queueContext: viewModel.recentlyPlayed)
                }
                .onDelete { offsets in
                    viewModel.removeRecentlyPlayed(at: offsets)
                }
            }
        }
    }
}

private struct LibrarySearchContent: View {
    @ObservedObject var viewModel: BMusicViewModel
    let query: String
    let results: [BMusicVideo]
    let artists: [BMusicArtist]
    let searchBilibili: (String) -> Void

    var body: some View {
        if results.isEmpty && artists.isEmpty {
            ContentUnavailableView("资料库里没有找到", systemImage: "music.magnifyingglass", description: Text("可以继续搜索 B 站音乐。"))
        }

        if !artists.isEmpty {
            Section("UP 主") {
                ForEach(artists) { artist in
                    NavigationLink {
                        ArtistDetailScreen(viewModel: viewModel, artist: artist)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name)
                                .font(.body)
                            Text("UID \(artist.id)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if !results.isEmpty {
            Section("音乐") {
                ForEach(results) { item in
                    MusicRow(viewModel: viewModel, item: item)
                }
            }
        }

        Section {
            Button {
                searchBilibili(query)
            } label: {
                Label("在 B 站搜索更多“\(query)”", systemImage: "globe")
            }
        } footer: {
            Text("默认先搜索资料库里的音乐和 UP 主；点这里可以切到首页，显示 B 站搜索内容。")
        }
    }
}

private struct ArtistDetailScreen: View {
    @ObservedObject var viewModel: BMusicViewModel
    let artist: BMusicArtist

    var body: some View {
        List {
            if viewModel.loadingArtistID == artist.id {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            if let message = viewModel.artistErrorMessages[artist.id] {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            let videos = viewModel.artistVideos[artist.id] ?? []
            if videos.isEmpty && viewModel.loadingArtistID != artist.id {
                ContentUnavailableView("还没有视频", systemImage: "person.crop.circle", description: Text("下拉刷新或稍后再试。"))
            } else {
                ForEach(videos) { item in
                    MusicRow(viewModel: viewModel, item: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(artist.name)
        .refreshable {
            await viewModel.loadArtistVideos(artist, force: true)
        }
        .task {
            await viewModel.loadArtistVideos(artist)
        }
        .toolbar {
            Button("取消收藏", role: .destructive) {
                viewModel.removeFavoriteArtist(artist)
            }
        }
    }
}

private struct PlaylistDetailScreen: View {
    @ObservedObject var viewModel: BMusicViewModel
    let playlistID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var detailEditMode: EditMode = .inactive
    @State private var showRename = false
    @State private var renamedPlaylistName = ""

    private var playlist: BMusicPlaylist? {
        viewModel.playlist(id: playlistID)
    }

    private var isEditing: Bool {
        detailEditMode.isEditing
    }

    var body: some View {
        List {
            if let playlist {
                if playlist.items.isEmpty {
                    ContentUnavailableView("列表为空", systemImage: "music.note.list", description: Text("在歌曲右侧点加号，选择加入这个列表。"))
                } else {
                    ForEach(playlist.items) { item in
                        MusicRow(viewModel: viewModel, item: item, queueContext: playlist.items)
                    }
                    .onDelete { offsets in
                        viewModel.removeItems(fromPlaylist: playlist.id, at: offsets)
                    }
                    .onMove { source, destination in
                        viewModel.moveItems(inPlaylist: playlist.id, from: source, to: destination)
                    }
                }
            } else {
                ContentUnavailableView("播放列表不存在", systemImage: "exclamationmark.triangle", description: Text("它可能已经被删除。"))
            }
        }
        .environment(\.editMode, $detailEditMode)
        .listStyle(.insetGrouped)
        .navigationTitle(playlist?.name ?? "播放列表")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if playlist?.items.isEmpty == false {
                    Button(isEditing ? "取消" : "编辑") {
                        withAnimation {
                            detailEditMode = isEditing ? .inactive : .active
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    detailEditMode = .inactive
                    dismiss()
                }
            }
        }
        .alert("重命名播放列表", isPresented: $showRename) {
            TextField("名称", text: $renamedPlaylistName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                viewModel.renamePlaylist(playlistID, to: renamedPlaylistName)
            }
        }
    }
}

private struct FavoritePlaylistDetailScreen: View {
    @ObservedObject var viewModel: BMusicViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var detailEditMode: EditMode = .inactive
    @State private var visibleItems: [BMusicVideo] = []

    private var isEditing: Bool {
        detailEditMode.isEditing
    }

    var body: some View {
        List {
            if visibleItems.isEmpty {
                ContentUnavailableView("列表为空", systemImage: "heart", description: Text("在搜索结果里点心形按钮，就会加入这里。"))
            } else {
                ForEach(visibleItems) { item in
                    MusicRow(viewModel: viewModel, item: item, queueContext: visibleItems)
                }
                .onDelete { offsets in
                    let removedItems = offsets.compactMap { visibleItems.indices.contains($0) ? visibleItems[$0] : nil }
                    visibleItems.remove(atOffsets: offsets)
                    removedItems.forEach { viewModel.removeFavorite($0) }
                }
                .onMove { source, destination in
                    visibleItems.move(fromOffsets: source, toOffset: destination)
                    viewModel.reorderFavorites(toMatch: visibleItems)
                }
            }
        }
        .environment(\.editMode, $detailEditMode)
        .listStyle(.insetGrouped)
        .navigationTitle("我的收藏")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !visibleItems.isEmpty {
                    Button(isEditing ? "取消" : "编辑") {
                        withAnimation {
                            detailEditMode = isEditing ? .inactive : .active
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    detailEditMode = .inactive
                    dismiss()
                }
            }
        }
        .onAppear {
            visibleItems = viewModel.favorites
        }
    }
}

private struct PlaylistPickerScreen: View {
    @ObservedObject var viewModel: BMusicViewModel
    @State private var newPlaylistName = ""

    var body: some View {
        ZStack {
            PlayerDynamicBackground(item: viewModel.playlistPickerItem ?? viewModel.currentItem)

            List {
                if let item = viewModel.playlistPickerItem {
                    Section {
                        VideoRow(item: item, isCurrent: viewModel.currentItem?.id == item.id, showsPlayButton: false, showsActionButton: false) {
                            Task { await viewModel.play(item) }
                        } addAction: {
                            viewModel.showPlaylistPicker = false
                        }
                    }
                    .listRowBackground(PlaylistPickerRowBackground())
                }

                Section("已有播放列表") {
                    Button {
                        if let item = viewModel.playlistPickerItem {
                            viewModel.addFavorite(item)
                        }
                        viewModel.showPlaylistPicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("我的收藏")
                                Text("\(viewModel.favorites.count) 首")
                                    .font(.footnote)
                                    .foregroundStyle(.primary.opacity(0.72))
                            }
                            Spacer()
                            Image(systemName: "heart")
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(PlaylistPickerRowBackground())

                    ForEach(viewModel.playlists) { playlist in
                        Button {
                            if let item = viewModel.playlistPickerItem {
                                viewModel.add(item, toPlaylist: playlist.id)
                            }
                            viewModel.showPlaylistPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name)
                                    Text("\(playlist.items.count) 首")
                                        .font(.footnote)
                                        .foregroundStyle(.primary.opacity(0.72))
                                }
                                Spacer()
                                Image(systemName: "plus")
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(PlaylistPickerRowBackground())
                    }
                }

                Section("新建") {
                    HStack {
                        TextField("播放列表名称", text: $newPlaylistName)
                        Button("创建并加入") {
                            viewModel.createPlaylist(named: newPlaylistName, adding: viewModel.playlistPickerItem)
                            newPlaylistName = ""
                            viewModel.showPlaylistPicker = false
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .listRowBackground(PlaylistPickerRowBackground())
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct PlaylistPickerRowBackground: View {
    var body: some View {
        Color.white
            .opacity(0.14)
            .background(.ultraThinMaterial)
    }
}

private struct SettingsScreen: View {
    @ObservedObject var viewModel: BMusicViewModel
    @State private var showListExporter = false
    @State private var showListImporter = false
    @State private var listExportURLs: [URL] = []
    @State private var backupMessage: String?

    var body: some View {
        List {
            Section("账号") {
                LabeledContent("登录状态", value: viewModel.isLoggedIn ? viewModel.userDisplayName : "未登录")
                Button("网页登录") {
                    viewModel.startWebLogin()
                }
                Button(viewModel.isLoggedIn ? "重新登录" : "扫码登录") {
                    viewModel.showLogin = true
                }
                if viewModel.isLoggedIn {
                    Button("退出登录", role: .destructive) {
                        Task { await viewModel.logout() }
                    }
                }
            }

            Section("播放") {
                LabeledContent("当前状态", value: viewModel.playbackStateText)
                LabeledContent("播放模式", value: viewModel.playbackMode.title)
                LabeledContent("播放来源", value: "Bilibili")
            }

            Section("资料库") {
                LabeledContent("收藏", value: "\(viewModel.favorites.count) 首")
                LabeledContent("最近播放", value: "\(viewModel.recentlyPlayed.count) 首")
                LabeledContent("播放列表", value: "\(viewModel.playlists.count) 个")
                LabeledContent("收藏 UP 主", value: "\(viewModel.favoriteArtists.count) 个")
                if !viewModel.recentlyPlayed.isEmpty {
                    Button("清空最近播放", role: .destructive) {
                        viewModel.clearRecentlyPlayed()
                    }
                }
            }

            Section {
                LabeledContent("音频缓存", value: viewModel.audioCacheSizeText)

                Toggle("缓存最近播放 100 首", isOn: $viewModel.cachesRecentPlays)
                    .onChange(of: viewModel.cachesRecentPlays) { _, enabled in
                        viewModel.setCachesRecentPlays(enabled)
                    }

                Toggle("缓存我的收藏", isOn: $viewModel.cachesFavorites)
                    .onChange(of: viewModel.cachesFavorites) { _, enabled in
                        viewModel.setCachesFavorites(enabled)
                    }
                    .disabled(viewModel.favorites.isEmpty)

                if !viewModel.playlists.isEmpty {
                    ForEach(viewModel.playlists) { playlist in
                        Toggle("\(playlist.name)（\(playlist.items.count) 首）", isOn: Binding(
                            get: { viewModel.isPlaylistCached(playlist.id) },
                            set: { viewModel.setPlaylist(playlist.id, cached: $0) }
                        ))
                    }
                }

                if !viewModel.audioCacheStatusText.isEmpty {
                    Text(viewModel.audioCacheStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    viewModel.warmConfiguredAudioCache()
                } label: {
                    Label("立即缓存已选择列表", systemImage: "arrow.down.circle")
                }
                .disabled(!viewModel.hasConfiguredAudioCacheLists)

                Button("清理未保留缓存") {
                    viewModel.pruneAudioCache()
                }

                Button("清空音频缓存", role: .destructive) {
                    viewModel.clearAudioCache()
                }
            } header: {
                Text("缓存")
            } footer: {
                Text("默认保留最近播放的 100 首。勾选我的收藏或播放列表后，会后台缓存其中全部音乐；取消勾选后，歌曲仍可能因最近播放继续保留。")
            }

            Section("备份与恢复") {
                Button {
                    prepareListExport()
                } label: {
                    Label("导出列表备份", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.favorites.isEmpty && viewModel.playlists.isEmpty)

                Button {
                    showListImporter = true
                } label: {
                    Label("导入列表备份", systemImage: "square.and.arrow.down")
                }

                Text("每个列表会导出为一个独立 JSON 文件。导入时可以多选文件批量恢复。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("应用", value: "B-Music")
                Text("使用 iOS 原生界面承载 ENO-M 的搜索、登录与播放能力。")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showListExporter) {
            BMusicDocumentExporter(urls: listExportURLs) { result in
                showListExporter = false
                listExportURLs = []
                switch result {
                case .success(let count):
                    if count > 0 {
                        backupMessage = "已导出 \(count) 个列表备份文件。"
                    }
                case .failure(let error):
                    backupMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
        .fileImporter(
            isPresented: $showListImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true
        ) { result in
            handleListImport(result)
        }
        .alert("备份与恢复", isPresented: Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )) {
            Button("好") {
                backupMessage = nil
            }
        } message: {
            Text(backupMessage ?? "")
        }
    }

    private func prepareListExport() {
        do {
            listExportURLs = try viewModel.makeListBackupFiles()
            showListExporter = !listExportURLs.isEmpty
            if listExportURLs.isEmpty {
                backupMessage = "没有可以导出的列表。"
            }
        } catch {
            backupMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleListImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let summary = try viewModel.importListBackups(from: urls)
            var message = "已导入 \(summary.importedFiles) 个文件。我的收藏：\(summary.restoredFavorites ? "已恢复" : "未包含")；播放列表：更新 \(summary.updatedPlaylists) 个，新建 \(summary.createdPlaylists) 个。"
            if summary.failedFiles > 0 {
                message += "有 \(summary.failedFiles) 个文件未能识别。"
            }
            backupMessage = message
        } catch {
            backupMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}

private struct BMusicDocumentExporter: UIViewControllerRepresentable {
    let urls: [URL]
    let completion: (Result<Int, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<Int, Error>) -> Void

        init(completion: @escaping (Result<Int, Error>) -> Void) {
            self.completion = completion
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.success(0))
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(.success(urls.count))
        }
    }
}

private struct LoginScreen: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    if let image = viewModel.loginQRImage {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .accessibilityLabel("登录二维码")
                    } else if viewModel.isPreparingLogin {
                        ProgressView()
                            .frame(width: 220, height: 220)
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 88))
                            .foregroundStyle(.secondary)
                            .frame(width: 220, height: 220)
                    }

                    Text(viewModel.loginMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button(viewModel.loginQRImage == nil ? "生成二维码" : "刷新二维码") {
                        Task { await viewModel.startLogin() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isPreparingLogin)

                    Button("改用网页登录") {
                        viewModel.startWebLogin()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

            if viewModel.isLoggedIn {
                Section {
                    Label("已登录：\(viewModel.userDisplayName)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            if !viewModel.isLoggedIn && viewModel.loginQRImage == nil {
                await viewModel.startLogin()
            }
        }
    }
}

private struct WebLoginScreen: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        VStack(spacing: 0) {
            WebLoginView { cookie in
                viewModel.handleWebLoginCookie(cookie)
            }

            HStack(spacing: 10) {
                if viewModel.isCompletingWebLogin {
                    ProgressView()
                }

                Text(viewModel.webLoginMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()
            }
            .padding()
            .background(.bar)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            viewModel.webLoginMessage = "请在页面中完成 B 站登录，成功后会自动返回。"
        }
    }
}

private struct WebLoginView: UIViewRepresentable {
    let onCookiesChanged: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCookiesChanged: onCookiesChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)

        if let url = URL(string: "https://passport.bilibili.com/login") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.websiteDataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        private let onCookiesChanged: (String) -> Void

        init(onCookiesChanged: @escaping (String) -> Void) {
            self.onCookiesChanged = onCookiesChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            exportCookies(from: webView)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [onCookiesChanged] cookies in
                let cookie = Self.cookieString(from: cookies)
                guard !cookie.isEmpty else {
                    return
                }

                DispatchQueue.main.async {
                    onCookiesChanged(cookie)
                }
            }
        }

        private func exportCookies(from webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [onCookiesChanged] cookies in
                let cookie = Self.cookieString(from: cookies)
                guard !cookie.isEmpty else {
                    return
                }

                DispatchQueue.main.async {
                    onCookiesChanged(cookie)
                }
            }
        }

        private static func cookieString(from cookies: [HTTPCookie]) -> String {
            cookies
                .filter { cookie in
                    cookie.domain.contains("bilibili.com") || cookie.domain.contains("biliapi.net")
                }
                .sorted { lhs, rhs in
                    lhs.name < rhs.name
                }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
        }
    }
}

private struct MusicRow: View {
    @ObservedObject var viewModel: BMusicViewModel
    let item: BMusicVideo
    var queueContext: [BMusicVideo]? = nil

    var body: some View {
        VideoRow(
            item: item,
            isCurrent: viewModel.currentItem?.id == item.id,
            actionSystemImage: "plus",
            favoriteSystemImage: viewModel.isFavorite(item) ? "heart.fill" : "heart"
        ) {
            Task {
                if let queueContext {
                    await viewModel.play(item, in: queueContext)
                } else {
                    await viewModel.play(item)
                }
            }
        } favoriteAction: {
            viewModel.toggleFavorite(item)
        } addAction: {
            viewModel.showPlaylistPicker(for: item)
        }
    }
}

private struct VideoRow: View {
    let item: BMusicVideo
    let isCurrent: Bool
    var actionSystemImage = "plus"
    var showsPlayButton = false
    var showsActionButton = true
    var favoriteSystemImage: String? = nil
    let playAction: () -> Void
    var favoriteAction: (() -> Void)? = nil
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            AsyncImage(url: item.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                default:
                    ProgressView()
                }
            }
            .frame(width: 54, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if showsPlayButton {
                Button(action: playAction) {
                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "play.circle")
                        .font(.body)
                }
                .buttonStyle(.plain)
            }

            if let favoriteSystemImage, let favoriteAction {
                Button(action: favoriteAction) {
                    Image(systemName: favoriteSystemImage)
                        .font(.body)
                        .foregroundStyle(.pink)
                }
                .buttonStyle(.plain)
            }

            if showsActionButton {
                Button(action: addAction) {
                    Image(systemName: actionSystemImage)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: playAction)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}

private struct MiniPlayer: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        if viewModel.currentItem != nil || viewModel.isResolvingPlayback {
            HStack(spacing: 10) {
                MiniPlayerArtwork(item: viewModel.currentItem)

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.currentItem?.title ?? "准备播放")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(viewModel.currentItem?.author ?? viewModel.playbackDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 18) {
                    Button {
                        viewModel.togglePlayPause()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 20, height: 24)
                    }
                    .disabled(viewModel.currentItem == nil && !viewModel.isResolvingPlayback)

                    Button {
                        Task { await viewModel.playNext() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 22, height: 24)
                    }
                    .disabled(!viewModel.canPlayNext)
                }
                .foregroundStyle(.primary)
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .frame(height: 52)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.showPlayer = true
            }
        }
    }
}

private struct MiniPlayerArtwork: View {
    let item: BMusicVideo?

    var body: some View {
        AsyncImage(url: item?.coverURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            default:
                if item == nil {
                    placeholder
                } else {
                    ProgressView()
                }
            }
        }
        .frame(width: 40, height: 40)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PlayerScreen: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    PlayerDynamicBackground(item: viewModel.currentItem)

                    ScrollView {
                        VStack(spacing: 14) {
                            PlayerNowPlayingSection(
                                viewModel: viewModel,
                                artworkSize: min(proxy.size.width - 64, proxy.size.height * 0.35)
                            )

                            if viewModel.showQueueInPlayer {
                                PlayerQueueList(viewModel: viewModel)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.showPlayer = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                    }
                    .accessibilityLabel("收起播放器")
                }

                ToolbarItem(placement: .principal) {
                    Text("正在播放")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PlayerDynamicBackground: View {
    let item: BMusicVideo?
    @State private var palette = BMusicPlayerPalette.default

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.top, palette.middle, palette.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.glow)
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -130, y: -220)

            Circle()
                .fill(palette.accent)
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 150, y: 220)

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.54)
        }
        .ignoresSafeArea()
        .task(id: item?.id) {
            await updatePalette()
        }
    }

    private func updatePalette() async {
        guard let url = item?.coverURL else {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 1.25)) {
                    palette = .default
                }
            }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled, let image = UIImage(data: data) else {
                return
            }
            let nextPalette = await MainActor.run {
                BMusicPlayerPalette(averageColor: image.averageColor ?? .systemGray)
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 1.35)) {
                    palette = nextPalette
                }
            }
        } catch {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 1.25)) {
                    palette = .default
                }
            }
        }
    }
}

private struct BMusicPlayerPalette {
    var top: Color
    var middle: Color
    var bottom: Color
    var glow: Color
    var accent: Color

    static let `default` = BMusicPlayerPalette(
        top: Color(.systemBackground),
        middle: Color(.secondarySystemBackground),
        bottom: Color(.systemBackground),
        glow: Color(.systemPink).opacity(0.18),
        accent: Color(.systemTeal).opacity(0.12)
    )

    init(top: Color, middle: Color, bottom: Color, glow: Color, accent: Color) {
        self.top = top
        self.middle = middle
        self.bottom = bottom
        self.glow = glow
        self.accent = accent
    }

    init(averageColor: UIColor) {
        let base = averageColor.bMusicAdjusted(saturation: 1.25, brightness: 0.92)
        let soft = averageColor.bMusicAdjusted(saturation: 0.72, brightness: 1.18)
        let deep = averageColor.bMusicAdjusted(saturation: 1.15, brightness: 0.58)
        let bright = averageColor.bMusicAdjusted(saturation: 1.45, brightness: 1.22)

        top = Color(soft).opacity(0.48)
        middle = Color(base).opacity(0.34)
        bottom = Color(deep).opacity(0.42)
        glow = Color(bright).opacity(0.34)
        accent = Color(base).opacity(0.26)
    }
}

private struct PlayerNowPlayingSection: View {
    @ObservedObject var viewModel: BMusicViewModel
    let artworkSize: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            PlayerArtwork(item: viewModel.currentItem, size: artworkSize)
            PlayerTitleBlock(
                viewModel: viewModel,
                title: viewModel.currentItem?.title ?? "还没有播放"
            )
            PlayerFavoriteButton(viewModel: viewModel)
            PlayerProgressBlock(viewModel: viewModel, progress: viewModel.playbackProgress)
            PlayerControls(viewModel: viewModel)
            Text(viewModel.isResolvingPlayback ? viewModel.playbackDetail : viewModel.playbackProgress.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PlayerFavoriteButton: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        if let item = viewModel.currentItem {
            HStack(spacing: 10) {
                Button {
                    viewModel.toggleFavorite(item)
                } label: {
                    Label(viewModel.isFavorite(item) ? "已收藏" : "收藏", systemImage: viewModel.isFavorite(item) ? "heart.fill" : "heart")
                }
                .tint(.pink)

                Button {
                    viewModel.showPlaylistPicker(for: item)
                } label: {
                    Label("加入列表", systemImage: "text.badge.plus")
                }
                .tint(.indigo)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct PlayerTitleBlock: View {
    @ObservedObject var viewModel: BMusicViewModel
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if let artist = viewModel.currentItem?.artist {
                NavigationLink {
                    ArtistDetailScreen(viewModel: viewModel, artist: artist)
                } label: {
                    Text(artist.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(viewModel.playbackStateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PlayerProgressBlock: View {
    @ObservedObject var viewModel: BMusicViewModel
    @ObservedObject var progress: BMusicPlaybackProgress

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $progress.position, in: 0...max(progress.duration, 1)) { editing in
                if !editing {
                    viewModel.seek(to: progress.position)
                }
            }
            .disabled(progress.duration <= 0)

            HStack {
                Text(progress.position.durationText)
                Spacer()
                Text(progress.duration.durationText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct PlayerControls: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        HStack(spacing: 28) {
            Button {
                viewModel.cyclePlaybackMode()
            } label: {
                Image(systemName: viewModel.playbackMode.systemImage)
            }
            .accessibilityLabel(viewModel.playbackMode.title)

            Button {
                Task { await viewModel.playPrevious() }
            } label: {
                Image(systemName: "backward.fill")
            }
            .disabled(!viewModel.canPlayPrevious)

            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
            }
            .disabled(viewModel.currentItem == nil && !viewModel.isResolvingPlayback)

            Button {
                Task { await viewModel.playNext() }
            } label: {
                Image(systemName: "forward.fill")
            }
            .disabled(!viewModel.canPlayNext)

            Button {
                viewModel.showQueueInPlayer.toggle()
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("播放队列")
        }
        .font(.title2)
        .buttonStyle(.plain)
    }
}

private struct PlayerQueueSection: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        Section("播放队列") {
            if viewModel.queue.isEmpty {
                ContentUnavailableView("队列为空", systemImage: "music.note.list", description: Text("从搜索结果添加歌曲后，会出现在这里。"))
            } else {
                ForEach(viewModel.playbackQueueDisplayItems) { item in
                    MusicRow(viewModel: viewModel, item: item, queueContext: viewModel.queue)
                }
                .onDelete { offsets in
                    viewModel.removeFromDisplayedQueue(at: offsets)
                }
            }
        }
    }
}

private struct PlayerQueueList: View {
    @ObservedObject var viewModel: BMusicViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("播放队列")
                .font(.headline)

            if viewModel.queue.isEmpty {
                ContentUnavailableView("队列为空", systemImage: "music.note.list", description: Text("从搜索结果添加歌曲后，会出现在这里。"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.playbackQueueDisplayItems) { item in
                        PlayerQueueRow(
                            item: item,
                            isCurrent: viewModel.currentItem?.id == item.id,
                            isFavorite: viewModel.isFavorite(item)
                        ) {
                            Task { await viewModel.play(item, in: viewModel.queue) }
                        } favoriteAction: {
                            viewModel.toggleFavorite(item)
                        } addAction: {
                            viewModel.showPlaylistPicker(for: item)
                        }

                        if item.id != viewModel.playbackQueueDisplayItems.last?.id {
                            Divider()
                                .opacity(0.22)
                                .padding(.leading, 92)
                                .padding(.trailing, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct PlayerQueueRow: View {
    let item: BMusicVideo
    let isCurrent: Bool
    let isFavorite: Bool
    let playAction: () -> Void
    let favoriteAction: () -> Void
    let addAction: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            AsyncImage(url: item.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                default:
                    Rectangle()
                        .fill(.quaternary)
                }
            }
            .frame(width: 54, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Button(action: favoriteAction) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.body)
                    .foregroundStyle(.pink)
            }
            .buttonStyle(.plain)

            Button(action: addAction) {
                Image(systemName: "plus")
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: playAction)
        .background(Color.clear)
    }
}

private struct PlayerArtwork: View {
    let item: BMusicVideo?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: item?.coverURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            default:
                if item == nil {
                    placeholder
                } else {
                    ProgressView()
                }
            }
        }
        .frame(width: max(220, size), height: max(220, size))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "music.note")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class BMusicPlaybackProgress: ObservableObject {
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var detail = "未播放"

    func update(position: Double? = nil, duration: Double? = nil, isPlaying: Bool? = nil, detail: String? = nil) {
        if let position {
            self.position = position
        }
        if let duration {
            self.duration = duration
        }
        if let detail {
            self.detail = detail
        } else {
            self.detail = "\(self.position.durationText) / \(self.duration.durationText)"
        }
    }

    func reset(detail: String = "未播放") {
        position = 0
        duration = 0
        self.detail = detail
    }
}

@MainActor
final class BMusicViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var results: [BMusicVideo] = []
    @Published var queue: [BMusicVideo] = []
    @Published var favorites: [BMusicVideo] = []
    @Published var recentlyPlayed: [BMusicVideo] = []
    @Published var playlists: [BMusicPlaylist] = []
    @Published var favoriteArtists: [BMusicArtist] = []
    @Published var artistVideos: [Int: [BMusicVideo]] = [:]
    @Published var artistErrorMessages: [Int: String] = [:]
    @Published var loadingArtistID: Int?
    @Published var currentItem: BMusicVideo?
    @Published var isSearching = false
    @Published var isResolvingPlayback = false
    @Published var errorMessage = ""
    @Published var isPlaying = false
    @Published var playbackStateText = "空闲"
    @Published var playbackDetail = "未播放"
    @Published var showLogin = false
    @Published var showWebLogin = false
    @Published var isLoggedIn = false
    @Published var userDisplayName = "未登录"
    @Published var loginQRImage: UIImage?
    @Published var loginMessage = "使用哔哩哔哩客户端扫码登录。"
    @Published var webLoginMessage = "请在页面中完成 B 站登录，成功后会自动返回。"
    @Published var isPreparingLogin = false
    @Published var isCompletingWebLogin = false
    @Published var showPlayer = false
    @Published var showQueueInPlayer = true
    @Published var playbackMode: BMusicPlaybackMode = .listLoop
    @Published var showPlaylistPicker = false
    @Published var playlistPickerItem: BMusicVideo?
    @Published var cachesRecentPlays = true
    @Published var cachesFavorites = false
    @Published var cachedPlaylistIDs: Set<UUID> = []
    @Published var audioCacheSizeText = "计算中"
    @Published var audioCacheStatusText = ""
    @Published var recommendations = BMusicRecommendationStore.fallbackRecommendations
    @Published var recommendationShuffleSeed = 0
    @Published var isLoadingRecommendedKeywords = false
    let playbackProgress = BMusicPlaybackProgress()

    private let cookieStore = CookieStore()
    private lazy var apiClient = BiliApiClient(cookieStore: cookieStore)
    private lazy var loginClient = BiliLoginClient(cookieStore: cookieStore)
    private var audioPlayer: NativeAudioPlayer!
    private let libraryStore = BMusicLibraryStore()
    private let cachePreferencesStore = BMusicCachePreferencesStore()
    private let recommendationStore = BMusicRecommendationStore()
    private var page = 1
    private var hasMore = true
    private var loginTask: Task<Void, Never>?
    private var lastWebLoginCookie = ""
    private var playbackRequestID = UUID()
    private var currentQueueIndex: Int?
    private var audioCacheTask: Task<Void, Never>?

    var canPlayNext: Bool {
        guard !queue.isEmpty else { return false }
        if playbackMode == .shuffle || playbackMode == .listLoop {
            return queue.count > 1 || currentItem != nil
        }
        guard let currentItem,
              let index = queue.firstIndex(where: { $0.id == currentItem.id })
        else { return false }
        return queue.indices.contains(index + 1)
    }

    var canPlayPrevious: Bool {
        guard !queue.isEmpty else { return false }
        if playbackMode == .shuffle || playbackMode == .listLoop {
            return queue.count > 1 || currentItem != nil
        }
        guard let currentItem,
              let index = queue.firstIndex(where: { $0.id == currentItem.id })
        else { return false }
        return queue.indices.contains(index - 1)
    }

    var hasConfiguredAudioCacheLists: Bool {
        (cachesFavorites && !favorites.isEmpty)
            || playlists.contains { cachedPlaylistIDs.contains($0.id) && !$0.items.isEmpty }
    }

    var playbackQueueDisplayItems: [BMusicVideo] {
        guard !queue.isEmpty else {
            return []
        }

        guard playbackMode != .shuffle,
              let index = currentQueueDisplayIndex(),
              queue.indices.contains(index)
        else {
            return queue
        }

        return Array(queue[index...]) + Array(queue[..<index])
    }

    var displayRecommendations: [BMusicRecommendation] {
        BMusicRecommendationStore.displayRecommendations(from: recommendations, seed: recommendationShuffleSeed)
    }

    init() {
        audioPlayer = NativeAudioPlayer { [weak self] event, payload in
            Task { @MainActor in
                self?.handleAudioEvent(event, payload: payload)
            }
        }
        restoreLibrary()
        restoreCachePreferences()
        refreshAudioCacheSize()
    }

    func refreshUser() async {
        do {
            let response = try await loginClient.fetchUserInfo()
            let info = (response as? [String: Any])?["info"] as? [String: Any]
            isLoggedIn = info?["isLogin"] as? Bool ?? false
            userDisplayName = isLoggedIn ? (info?["uname"] as? String ?? "已登录") : "未登录"
        } catch {
            isLoggedIn = false
            userDisplayName = "未登录"
        }
    }

    func search(reset: Bool) async {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return
        }

        if reset {
            page = 1
            hasMore = true
            results = []
        }
        guard hasMore, !isSearching else {
            return
        }

        isSearching = true
        errorMessage = ""
        defer { isSearching = false }

        do {
            let response = try await apiClient.search(keyword: keyword, page: page, pageSize: 20)
            let items = BMusicVideo.videos(from: response)
            if reset {
                results = items
            } else {
                results.append(contentsOf: items.filter { newItem in
                    !results.contains(where: { $0.id == newItem.id })
                })
            }
            hasMore = !items.isEmpty
            page += 1
        } catch where error.isCancellation {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshRecommendedKeywords(force: Bool = false) async {
        if !force,
           let snapshot = recommendationStore.load(),
           Date().timeIntervalSince(snapshot.updatedAt) < 12 * 60 * 60 {
            recommendations = snapshot.recommendations
            return
        }

        isLoadingRecommendedKeywords = true
        defer { isLoadingRecommendedKeywords = false }

        do {
            let recommendations = try await fetchBilibiliRecommendations()
            if !recommendations.isEmpty {
                self.recommendations = recommendations
                recommendationStore.save(BMusicRecommendationSnapshot(updatedAt: Date(), recommendations: recommendations))
            }
        } catch {
            if let snapshot = recommendationStore.load(), !snapshot.recommendations.isEmpty {
                recommendations = snapshot.recommendations
            } else {
                recommendations = BMusicRecommendationStore.rotatedFallbackRecommendations()
            }
        }
    }

    func shuffleRecommendations() {
        recommendationShuffleSeed += 1
    }

    private func fetchBilibiliRecommendations() async throws -> [BMusicRecommendation] {
        let rankingRIDs = [3, 28, 30, 31]
        var weightedKeywords: [BMusicWeightedKeyword] = []

        for rid in rankingRIDs {
            let response = try await apiClient.musicRanking(rid: rid)
            weightedKeywords.append(contentsOf: BMusicRecommendationExtractor.keywords(fromRankingResponse: response))
        }

        let recommendations = BMusicRecommendationExtractor.recommendations(from: weightedKeywords)
        let fallback = BMusicRecommendationStore.rotatedFallbackRecommendations()
        return Array(Self.deduplicatedRecommendations(recommendations + fallback).prefix(40))
    }

    func loadMoreIfNeeded(current item: BMusicVideo) async {
        guard item.id == results.last?.id else {
            return
        }
        await search(reset: false)
    }

    func librarySearchResults(matching query: String) -> [BMusicVideo] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        var seen = Set<String>()
        let libraryItems = favorites + recentlyPlayed + playlists.flatMap(\.items)

        return libraryItems.filter { item in
            guard seen.insert(item.id).inserted else {
                return false
            }

            return item.title.lowercased().contains(normalizedQuery)
                || item.author.lowercased().contains(normalizedQuery)
                || item.duration.lowercased().contains(normalizedQuery)
        }
    }

    func libraryArtistSearchResults(matching query: String) -> [BMusicArtist] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        let libraryItems = favorites + recentlyPlayed + playlists.flatMap(\.items)
        let artists = favoriteArtists + libraryItems.compactMap(\.artist)
        var seen = Set<Int>()

        return artists.filter { artist in
            guard seen.insert(artist.id).inserted else {
                return false
            }

            return artist.name.lowercased().contains(normalizedQuery)
                || String(artist.id).contains(normalizedQuery)
        }
    }

    func addToQueue(_ item: BMusicVideo) {
        guard !queue.contains(where: { $0.id == item.id }) else {
            return
        }
        queue.append(item)
        saveLibrary()
    }

    func removeFromQueue(_ item: BMusicVideo) {
        queue.removeAll { $0.id == item.id }
        if currentItem?.id == item.id {
            cancelPendingPlayback()
            currentItem = nil
            currentQueueIndex = nil
            _ = audioPlayer.stop()
        } else {
            syncCurrentQueueIndex()
        }
        saveLibrary()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { queue.indices.contains($0) ? queue[$0].id : nil }
        queue.remove(atOffsets: offsets)
        if let currentItem, removedIDs.contains(currentItem.id) {
            cancelPendingPlayback()
            self.currentItem = nil
            currentQueueIndex = nil
            _ = audioPlayer.stop()
        } else {
            syncCurrentQueueIndex()
        }
        saveLibrary()
    }

    func removeFromDisplayedQueue(at offsets: IndexSet) {
        let displayItems = playbackQueueDisplayItems
        let removedIDs = offsets.compactMap { displayItems.indices.contains($0) ? displayItems[$0].id : nil }
        queue.removeAll { removedIDs.contains($0.id) }
        if let currentItem, removedIDs.contains(currentItem.id) {
            cancelPendingPlayback()
            self.currentItem = nil
            currentQueueIndex = nil
            _ = audioPlayer.stop()
        } else {
            syncCurrentQueueIndex()
        }
        saveLibrary()
    }

    func isFavorite(_ item: BMusicVideo) -> Bool {
        favorites.contains { $0.id == item.id }
    }

    func toggleFavorite(_ item: BMusicVideo) {
        if isFavorite(item) {
            removeFavorite(item)
        } else {
            addFavorite(item)
        }
    }

    func addFavorite(_ item: BMusicVideo) {
        guard !isFavorite(item) else {
            return
        }
        favorites.insert(item, at: 0)
        saveLibrary()
    }

    func removeFavorite(_ item: BMusicVideo) {
        favorites.removeAll { $0.id == item.id }
        saveLibrary()
        pruneAudioCache()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveLibrary()
        pruneAudioCache()
    }

    func replaceFavorites(with importedFavorites: [BMusicVideo]) {
        favorites = Self.deduplicatedVideos(importedFavorites)
        saveLibrary()
        if cachesFavorites {
            warmConfiguredAudioCache()
        }
    }

    func mergeFavorites(from importedFavorites: [BMusicVideo]) -> Int {
        let existingIDs = Set(favorites.map(\.id))
        let importedUniqueFavorites = Self.deduplicatedVideos(importedFavorites)
        let newFavorites = importedUniqueFavorites.filter { !existingIDs.contains($0.id) }
        favorites = newFavorites + favorites
        saveLibrary()
        if cachesFavorites {
            warmConfiguredAudioCache()
        }
        return newFavorites.count
    }

    func reorderFavorites(toMatch orderedItems: [BMusicVideo]) {
        let currentFavoritesByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        var reorderedFavorites = orderedItems.compactMap { currentFavoritesByID[$0.id] }
        let reorderedIDs = Set(reorderedFavorites.map(\.id))
        reorderedFavorites.append(contentsOf: favorites.filter { !reorderedIDs.contains($0.id) })
        favorites = reorderedFavorites
        saveLibrary()
        if cachesFavorites {
            warmConfiguredAudioCache()
        }
    }

    func makeListBackupFiles() throws -> [URL] {
        let backups = listBackups()
        guard !backups.isEmpty else {
            return []
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BMusicListBackups-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try backups.map { backup in
            let filename = "B-Music-\(backup.name.safeBackupFilename).json"
            let url = directory.appendingPathComponent(filename)
            try encoder.encode(backup).write(to: url, options: .atomic)
            return url
        }
    }

    func importListBackups(from urls: [URL]) throws -> BMusicListImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var summary = BMusicListImportSummary()

        for url in urls {
            let canAccess = url.startAccessingSecurityScopedResource()
            defer {
                if canAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url)
                let backup = try decoder.decode(BMusicListBackup.self, from: data)
                restoreListBackup(backup, summary: &summary)
                summary.importedFiles += 1
            } catch {
                summary.failedFiles += 1
            }
        }

        saveLibrary()
        if hasConfiguredAudioCacheLists {
            warmConfiguredAudioCache()
        } else {
            pruneAudioCache()
        }
        return summary
    }

    func removeRecentlyPlayed(at offsets: IndexSet) {
        recentlyPlayed.remove(atOffsets: offsets)
        saveLibrary()
        pruneAudioCache()
    }

    func clearRecentlyPlayed() {
        recentlyPlayed = []
        saveLibrary()
        pruneAudioCache()
    }

    func setCachesRecentPlays(_ enabled: Bool) {
        cachesRecentPlays = enabled
        saveCachePreferences()
        pruneAudioCache()
    }

    func setCachesFavorites(_ enabled: Bool) {
        cachesFavorites = enabled
        saveCachePreferences()
        if enabled {
            warmConfiguredAudioCache()
        } else {
            pruneAudioCache()
        }
    }

    func isPlaylistCached(_ playlistID: UUID) -> Bool {
        cachedPlaylistIDs.contains(playlistID)
    }

    func setPlaylist(_ playlistID: UUID, cached: Bool) {
        if cached {
            cachedPlaylistIDs.insert(playlistID)
        } else {
            cachedPlaylistIDs.remove(playlistID)
        }
        saveCachePreferences()
        if cached {
            warmConfiguredAudioCache()
        } else {
            pruneAudioCache()
        }
    }

    func warmConfiguredAudioCache() {
        let items = configuredAudioCacheItems()
        guard !items.isEmpty else {
            audioCacheStatusText = "还没有选择需要固定缓存的列表。"
            pruneAudioCache()
            return
        }

        audioCacheTask?.cancel()
        audioCacheTask = Task { [weak self, items] in
            guard let self else { return }
            var finished = 0
            var failed = 0

            for item in items {
                if Task.isCancelled {
                    return
                }

                self.audioCacheStatusText = "正在缓存 \(finished + 1)/\(items.count)：\(item.title)"
                do {
                    try await self.cacheAudio(item)
                    finished += 1
                } catch {
                    failed += 1
                }
            }

            if failed > 0 {
                self.audioCacheStatusText = "已缓存 \(finished) 首，\(failed) 首暂时失败。"
            } else {
                self.audioCacheStatusText = "已缓存 \(finished) 首。"
            }
            self.refreshAudioCacheSize()
            self.pruneAudioCache()
        }
    }

    func pruneAudioCache() {
        let keepIDs = audioCacheKeepIDs()
        Task { [weak self, keepIDs] in
            await BMusicAudioCache.shared.prune(keeping: keepIDs)
            let size = await BMusicAudioCache.shared.sizeInBytes()
            await MainActor.run {
                self?.audioCacheSizeText = size.bMusicByteSizeText
            }
        }
    }

    func clearAudioCache() {
        audioCacheTask?.cancel()
        let keepIDs = currentItem.map { Set([$0.id]) } ?? []
        Task { [weak self, keepIDs] in
            await BMusicAudioCache.shared.clear(keeping: keepIDs)
            let size = await BMusicAudioCache.shared.sizeInBytes()
            await MainActor.run {
                self?.audioCacheSizeText = size.bMusicByteSizeText
                self?.audioCacheStatusText = keepIDs.isEmpty ? "音频缓存已清空。" : "已清空缓存，当前播放中的歌曲暂时保留。"
            }
        }
    }

    func refreshAudioCacheSize() {
        Task { [weak self] in
            let size = await BMusicAudioCache.shared.sizeInBytes()
            await MainActor.run {
                self?.audioCacheSizeText = size.bMusicByteSizeText
            }
        }
    }

    func isFavoriteArtist(_ artist: BMusicArtist) -> Bool {
        favoriteArtists.contains { $0.id == artist.id }
    }

    func toggleFavoriteArtist(_ artist: BMusicArtist) {
        if isFavoriteArtist(artist) {
            removeFavoriteArtist(artist)
        } else {
            addFavoriteArtist(artist)
        }
    }

    func addFavoriteArtist(_ artist: BMusicArtist) {
        guard !isFavoriteArtist(artist) else {
            return
        }
        favoriteArtists.insert(artist, at: 0)
        saveLibrary()
    }

    func removeFavoriteArtist(_ artist: BMusicArtist) {
        favoriteArtists.removeAll { $0.id == artist.id }
        artistVideos[artist.id] = nil
        artistErrorMessages[artist.id] = nil
        saveLibrary()
    }

    func removeFavoriteArtists(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { favoriteArtists.indices.contains($0) ? favoriteArtists[$0].id : nil }
        favoriteArtists.remove(atOffsets: offsets)
        for id in removedIDs {
            artistVideos[id] = nil
            artistErrorMessages[id] = nil
        }
        saveLibrary()
    }

    func loadArtistVideos(_ artist: BMusicArtist, force: Bool = false) async {
        if !force, artistVideos[artist.id]?.isEmpty == false {
            return
        }
        loadingArtistID = artist.id
        artistErrorMessages[artist.id] = nil
        defer {
            if loadingArtistID == artist.id {
                loadingArtistID = nil
            }
        }

        do {
            let response = try await apiClient.spaceVideos(mid: artist.id, page: 1, pageSize: 50)
            artistVideos[artist.id] = BMusicVideo.spaceVideos(from: response, artist: artist)
        } catch where error.isCancellation {
            return
        } catch {
            artistErrorMessages[artist.id] = error.localizedDescription
        }
    }

    func showPlaylistPicker(for item: BMusicVideo) {
        playlistPickerItem = item
        showPlaylistPicker = true
    }

    func playlist(id: UUID) -> BMusicPlaylist? {
        playlists.first { $0.id == id }
    }

    func createPlaylist(named name: String, adding item: BMusicVideo? = nil) {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanedName.isEmpty ? "新播放列表" : cleanedName
        var playlist = BMusicPlaylist(name: finalName)
        if let item {
            playlist.items.append(item)
        }
        playlists.insert(playlist, at: 0)
        saveLibrary()
    }

    func deletePlaylists(at offsets: IndexSet) {
        let removedIDs = offsets.compactMap { playlists.indices.contains($0) ? playlists[$0].id : nil }
        playlists.remove(atOffsets: offsets)
        cachedPlaylistIDs.subtract(removedIDs)
        saveCachePreferences()
        saveLibrary()
        pruneAudioCache()
    }

    func renamePlaylist(_ playlistID: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else {
            return
        }
        playlists[index].name = cleanedName
        saveLibrary()
    }

    func clearPlaylist(_ playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        playlists[index].items = []
        saveLibrary()
        pruneAudioCache()
    }

    func add(_ item: BMusicVideo, toPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        playlists[index].items.removeAll { $0.id == item.id }
        playlists[index].items.insert(item, at: 0)
        saveLibrary()
        if cachedPlaylistIDs.contains(playlistID) {
            warmConfiguredAudioCache()
        }
    }

    func remove(_ item: BMusicVideo, fromPlaylist playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        playlists[index].items.removeAll { $0.id == item.id }
        saveLibrary()
        pruneAudioCache()
    }

    func removeItems(fromPlaylist playlistID: UUID, at offsets: IndexSet) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        playlists[index].items.remove(atOffsets: offsets)
        saveLibrary()
        pruneAudioCache()
    }

    func moveItems(inPlaylist playlistID: UUID, from source: IndexSet, to destination: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }
        playlists[index].items.move(fromOffsets: source, toOffset: destination)
        saveLibrary()
    }

    func play(_ item: BMusicVideo, in queueContext: [BMusicVideo]) async {
        let context = queueContext.contains(where: { $0.id == item.id }) ? queueContext : queueContext + [item]
        if !context.isEmpty {
            queue = context
            currentQueueIndex = context.firstIndex { $0.id == item.id }
            saveLibrary()
        }
        await play(item)
    }

    func play(_ item: BMusicVideo) async {
        let requestID = UUID()
        playbackRequestID = requestID

        if !queue.contains(where: { $0.id == item.id }) {
            queue.append(item)
        }
        currentQueueIndex = queue.firstIndex { $0.id == item.id }

        currentItem = item
        isResolvingPlayback = true
        playbackStateText = "加载中"
        playbackDetail = "正在获取音频地址..."
        playbackProgress.reset(detail: "正在获取音频地址...")
        errorMessage = ""
        defer {
            if isCurrentPlaybackRequest(requestID) {
                isResolvingPlayback = false
            }
        }

        do {
            if try await audioPlayer.playCached(
                cacheID: item.id,
                title: item.title,
                artist: item.author,
                artworkURL: item.coverURL?.absoluteString
            ) {
                guard isCurrentPlaybackRequest(requestID) else {
                    return
                }
                currentItem = item
                addRecentlyPlayed(item)
                playbackDetail = "使用本地缓存播放"
                playbackProgress.reset(detail: "使用本地缓存播放")
                return
            }

            let resolved = try await resolvePlayableVideo(item)
            guard isCurrentPlaybackRequest(requestID) else {
                return
            }

            currentItem = resolved.video
            replaceQueueItem(resolved.video)
            addRecentlyPlayed(resolved.video)
            _ = try await audioPlayer.play(
                url: resolved.audioURL,
                title: resolved.video.title,
                artist: resolved.video.author,
                artworkURL: resolved.video.coverURL?.absoluteString,
                cookie: cookieStore.read(),
                cacheID: resolved.video.id
            )
            guard isCurrentPlaybackRequest(requestID) else {
                return
            }
        } catch where error.isCancellation {
            if isCurrentPlaybackRequest(requestID) {
                playbackStateText = "空闲"
                playbackDetail = currentItem == nil ? "未播放" : playbackDetail
            }
        } catch {
            guard isCurrentPlaybackRequest(requestID) else {
                return
            }
            isPlaying = false
            playbackStateText = "播放失败"
            playbackDetail = error.localizedDescription
            playbackProgress.reset(detail: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func playNext() async {
        guard let next = nextQueueItem() else {
            return
        }
        await play(next)
    }

    func playPrevious() async {
        guard let previous = previousQueueItem() else {
            return
        }
        await play(previous)
    }

    func togglePlayPause() {
        if isPlaying {
            _ = audioPlayer.pause()
        } else {
            _ = audioPlayer.resume()
        }
    }

    func seek(to seconds: Double) {
        _ = audioPlayer.seek(seconds: seconds)
    }

    private func cancelPendingPlayback() {
        playbackRequestID = UUID()
        isResolvingPlayback = false
    }

    private func isCurrentPlaybackRequest(_ requestID: UUID) -> Bool {
        playbackRequestID == requestID
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
    }

    func startLogin() async {
        loginTask?.cancel()
        isPreparingLogin = true
        loginQRImage = nil
        loginMessage = "正在生成二维码..."
        defer { isPreparingLogin = false }

        do {
            let response = try await loginClient.generateQR()
            guard let dict = response as? [String: Any],
                  let oauthKey = dict["oauthKey"] as? String,
                  let qrImage = (dict["qrImage"] as? String)?.qrUIImage()
            else {
                throw BiliLoginError.invalidResponse
            }

            loginQRImage = qrImage
            loginMessage = "请使用哔哩哔哩客户端扫码确认。"
            pollLogin(oauthKey: oauthKey)
        } catch where error.isCancellation {
            loginMessage = "登录已取消。"
        } catch {
            loginMessage = error.localizedDescription
        }
    }

    func startWebLogin() {
        loginTask?.cancel()
        showLogin = false
        webLoginMessage = "请在页面中完成 B 站登录，成功后会自动返回。"
        guard !showWebLogin else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.showWebLogin = true
        }
    }

    func handleWebLoginCookie(_ cookie: String) {
        guard !isCompletingWebLogin,
              cookie != lastWebLoginCookie,
              cookie.contains("SESSDATA") || cookie.contains("DedeUserID")
        else {
            return
        }

        lastWebLoginCookie = cookie
        Task {
            await completeWebLogin(cookie)
        }
    }

    func completeWebLogin(_ cookie: String) async {
        isCompletingWebLogin = true
        webLoginMessage = "正在验证网页登录状态..."
        defer { isCompletingWebLogin = false }

        do {
            let response = try await loginClient.acceptWebLoginCookie(cookie)
            let info = (response as? [String: Any])?["info"] as? [String: Any]
            isLoggedIn = info?["isLogin"] as? Bool ?? true
            userDisplayName = info?["uname"] as? String ?? "已登录"
            loginMessage = "网页登录成功。"
            webLoginMessage = "已登录：\(userDisplayName)"
            showWebLogin = false
            showLogin = false
        } catch {
            webLoginMessage = "还没有拿到有效登录状态，请继续完成网页验证。"
        }
    }

    func logout() async {
        loginTask?.cancel()
        try? cookieStore.clear()
        clearWebLoginCookies()
        isLoggedIn = false
        userDisplayName = "未登录"
        loginQRImage = nil
        loginMessage = "已退出登录。"
        webLoginMessage = "已退出登录。"
        lastWebLoginCookie = ""
    }

    private func clearWebLoginCookies() {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.contains("bilibili.com") || cookie.domain.contains("biliapi.net") {
                cookieStore.delete(cookie)
            }
        }
    }

    private func pollLogin(oauthKey: String) {
        loginTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                do {
                    let response = try await self.loginClient.pollQR(oauthKey: oauthKey)
                    guard let dict = response as? [String: Any] else {
                        continue
                    }
                    self.loginMessage = dict["message"] as? String ?? self.loginMessage
                    if dict["status"] as? String == "confirmed" {
                        await self.refreshUser()
                        self.showLogin = false
                        self.loginTask?.cancel()
                        return
                    }
                    if dict["status"] as? String == "failed" {
                        self.loginTask?.cancel()
                        return
                    }
                } catch where error.isCancellation {
                    return
                } catch {
                    self.loginMessage = error.localizedDescription
                }
            }
        }
    }

    private func replaceQueueItem(_ item: BMusicVideo) {
        if let currentQueueIndex, queue.indices.contains(currentQueueIndex) {
            queue[currentQueueIndex] = item
        } else if let index = queue.firstIndex(where: { $0.id == item.id }) {
            queue[index] = item
            currentQueueIndex = index
        } else {
            return
        }

        if let favoriteIndex = favorites.firstIndex(where: { $0.id == item.id }) {
            favorites[favoriteIndex] = item
        }
        if let recentIndex = recentlyPlayed.firstIndex(where: { $0.id == item.id }) {
            recentlyPlayed[recentIndex] = item
        }
        for playlistIndex in playlists.indices {
            if let itemIndex = playlists[playlistIndex].items.firstIndex(where: { $0.id == item.id }) {
                playlists[playlistIndex].items[itemIndex] = item
            }
        }
        saveLibrary()
    }

    private func addRecentlyPlayed(_ item: BMusicVideo) {
        recentlyPlayed.removeAll { $0.id == item.id }
        recentlyPlayed.insert(item, at: 0)
        if recentlyPlayed.count > 100 {
            recentlyPlayed = Array(recentlyPlayed.prefix(100))
        }
        saveLibrary()
        pruneAudioCache()
    }

    private func cacheAudio(_ item: BMusicVideo) async throws {
        let resolved = try await resolvePlayableVideo(item)
        guard let audioURL = URL(string: resolved.audioURL) else {
            throw NativeAudioError.invalidURL
        }
        _ = try await BMusicAudioCache.shared.audioURL(
            for: resolved.video.id,
            sourceURL: audioURL,
            cookie: cookieStore.read()
        )
    }

    private func configuredAudioCacheItems() -> [BMusicVideo] {
        var items: [BMusicVideo] = []
        if cachesFavorites {
            items.append(contentsOf: favorites)
        }
        for playlist in playlists where cachedPlaylistIDs.contains(playlist.id) {
            items.append(contentsOf: playlist.items)
        }
        return Self.deduplicatedVideos(items)
    }

    private func audioCacheKeepIDs() -> Set<String> {
        var ids = Set<String>()
        if cachesRecentPlays {
            ids.formUnion(recentlyPlayed.prefix(100).map(\.id))
        }
        ids.formUnion(configuredAudioCacheItems().map(\.id))
        if let currentItem {
            ids.insert(currentItem.id)
        }
        return ids
    }

    private func restoreLibrary() {
        let snapshot = libraryStore.load()
        queue = snapshot.queue
        favorites = snapshot.favorites
        recentlyPlayed = snapshot.recentlyPlayed
        playlists = snapshot.playlists
        favoriteArtists = snapshot.favoriteArtists
    }

    private func restoreCachePreferences() {
        let preferences = cachePreferencesStore.load()
        cachesRecentPlays = preferences.cachesRecentPlays
        cachesFavorites = preferences.cachesFavorites
        cachedPlaylistIDs = Set(preferences.cachedPlaylistIDs)
    }

    private func saveLibrary() {
        libraryStore.save(BMusicLibrarySnapshot(
            queue: queue,
            favorites: favorites,
            recentlyPlayed: recentlyPlayed,
            playlists: playlists,
            favoriteArtists: favoriteArtists
        ))
    }

    private func saveCachePreferences() {
        cachePreferencesStore.save(BMusicCachePreferences(
            cachesRecentPlays: cachesRecentPlays,
            cachesFavorites: cachesFavorites,
            cachedPlaylistIDs: Array(cachedPlaylistIDs)
        ))
    }

    private func listBackups() -> [BMusicListBackup] {
        var backups: [BMusicListBackup] = []
        if !favorites.isEmpty {
            backups.append(BMusicListBackup(kind: .favorites, name: "我的收藏", items: favorites))
        }
        backups.append(contentsOf: playlists.map { playlist in
            BMusicListBackup(kind: .playlist, name: playlist.name, playlistID: playlist.id, items: playlist.items)
        })
        return backups
    }

    private func restoreListBackup(_ backup: BMusicListBackup, summary: inout BMusicListImportSummary) {
        let items = Self.deduplicatedVideos(backup.items)

        switch backup.kind {
        case .favorites:
            favorites = items
            summary.restoredFavorites = true
        case .playlist:
            if let playlistID = backup.playlistID,
               let index = playlists.firstIndex(where: { $0.id == playlistID }) {
                playlists[index].name = backup.name
                playlists[index].items = items
                summary.updatedPlaylists += 1
            } else if let index = playlists.firstIndex(where: { $0.name == backup.name }) {
                playlists[index].items = items
                summary.updatedPlaylists += 1
            } else {
                playlists.insert(BMusicPlaylist(id: backup.playlistID ?? UUID(), name: backup.name, items: items), at: 0)
                summary.createdPlaylists += 1
            }
        }
    }

    private static func deduplicatedVideos(_ videos: [BMusicVideo]) -> [BMusicVideo] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.id).inserted }
    }

    private static func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let normalized = value.lowercased()
            return seen.insert(normalized).inserted
        }
    }

    private static func deduplicatedRecommendations(_ values: [BMusicRecommendation]) -> [BMusicRecommendation] {
        var seen = Set<String>()
        return values.filter { value in
            seen.insert(value.keyword.lowercased()).inserted
        }
    }

    private func nextQueueItem() -> BMusicVideo? {
        guard !queue.isEmpty else {
            return nil
        }

        if playbackMode == .shuffle {
            guard queue.count > 1, let currentItem else {
                return queue.first
            }
            return queue.filter { $0.id != currentItem.id }.randomElement()
        }

        guard let index = resolvedCurrentQueueIndex() else {
            return queue.first
        }

        if queue.indices.contains(index + 1) {
            return queue[index + 1]
        }

        return playbackMode == .listLoop ? queue.first : nil
    }

    private func previousQueueItem() -> BMusicVideo? {
        guard !queue.isEmpty else {
            return nil
        }

        if playbackMode == .shuffle {
            guard queue.count > 1, let currentItem else {
                return queue.first
            }
            return queue.filter { $0.id != currentItem.id }.randomElement()
        }

        guard let index = resolvedCurrentQueueIndex() else {
            return queue.first
        }

        if queue.indices.contains(index - 1) {
            return queue[index - 1]
        }

        return playbackMode == .listLoop ? queue.last : nil
    }

    private func resolvedCurrentQueueIndex() -> Int? {
        if let currentQueueIndex, queue.indices.contains(currentQueueIndex) {
            return currentQueueIndex
        }

        guard let currentItem,
              let index = queue.firstIndex(where: { $0.id == currentItem.id })
        else {
            return nil
        }

        currentQueueIndex = index
        return index
    }

    private func currentQueueDisplayIndex() -> Int? {
        if let currentQueueIndex, queue.indices.contains(currentQueueIndex) {
            return currentQueueIndex
        }

        guard let currentItem else {
            return nil
        }

        return queue.firstIndex { $0.id == currentItem.id }
    }

    private func syncCurrentQueueIndex() {
        currentQueueIndex = currentItem.flatMap { current in
            queue.firstIndex { $0.id == current.id }
        }
    }

    private func handlePlaybackEnded() {
        switch playbackMode {
        case .repeatOne:
            _ = audioPlayer.seek(seconds: 0)
            _ = audioPlayer.resume()
        case .listLoop, .shuffle:
            Task { await playNext() }
        }
    }

    private func resolvePlayableVideo(_ item: BMusicVideo) async throws -> (video: BMusicVideo, audioURL: String) {
        var video = item
        var cid = item.cid

        if cid == nil {
            let response = try await apiClient.request(payload: [
                "contentScriptQuery": "getVideoInfo",
                "bvid": item.bvid
            ])
            if let detail = BMusicVideo.detail(from: response, fallback: item) {
                video = detail
                cid = detail.cid
            }
        }

        guard let cid else {
            throw BMusicError.missingCID
        }

        let playURL = try await apiClient.request(payload: [
            "contentScriptQuery": "getAudioOfVideo",
            "bvid": video.bvid,
            "cid": cid,
            "fnval": 16
        ])

        guard let audioURL = BMusicVideo.bestAudioURL(from: playURL) else {
            throw BMusicError.missingAudioURL
        }

        return (video, audioURL)
    }

    private func handleAudioEvent(_ event: String, payload: [String: Any]) {
        switch event {
        case "native-audio-state":
            let state = payload["state"] as? String ?? ""
            playbackStateText = BMusicPlaybackState.label(for: state)
            isPlaying = state == "playing"
            let message = payload["message"] as? String ?? ""
            playbackDetail = message.isEmpty ? playbackStateText : message
            playbackProgress.update(
                position: payload["position"] as? Double,
                duration: payload["duration"] as? Double,
                detail: message.isEmpty ? nil : message
            )
            if state == "ended" {
                handlePlaybackEnded()
            }
        case "native-audio-progress":
            let position = payload["position"] as? Double ?? 0
            let duration = payload["duration"] as? Double ?? 0
            if let nextIsPlaying = payload["isPlaying"] as? Bool, nextIsPlaying != isPlaying {
                isPlaying = nextIsPlaying
            }
            playbackProgress.update(position: position, duration: duration)
        case "native-audio-command":
            if payload["command"] as? String == "next" {
                Task { await playNext() }
            } else if payload["command"] as? String == "previous" {
                Task { await playPrevious() }
            }
        default:
            break
        }
    }
}

struct BMusicVideo: Codable, Identifiable, Hashable {
    let id: String
    let bvid: String
    var cid: Int?
    var title: String
    var author: String
    var authorID: Int?
    var cover: String
    var duration: String

    var coverURL: URL? {
        let normalized: String
        if cover.hasPrefix("//") {
            normalized = "https:\(cover)"
        } else if cover.hasPrefix("http://") {
            normalized = "https://\(cover.dropFirst("http://".count))"
        } else {
            normalized = cover
        }
        return URL(string: normalized)
    }

    var subtitle: String {
        [author, duration].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var artist: BMusicArtist? {
        guard let authorID, !author.isEmpty else {
            return nil
        }
        return BMusicArtist(id: authorID, name: author)
    }

    static func videos(from response: Any) -> [BMusicVideo] {
        let root = response as? [String: Any]
        let data = root?["data"] as? [String: Any]
        let result = data?["result"] as? [[String: Any]] ?? []
        return result.compactMap { BMusicVideo(searchResult: $0) }
    }

    static func detail(from response: Any, fallback: BMusicVideo) -> BMusicVideo? {
        guard let root = response as? [String: Any],
              let data = root["data"] as? [String: Any]
        else {
            return nil
        }

        var video = fallback
        video.cid = data.intValue(for: "cid")
        video.title = (data["title"] as? String)?.cleanedHTML() ?? fallback.title
        video.cover = data["pic"] as? String ?? fallback.cover
        if let owner = data["owner"] as? [String: Any],
           let name = owner["name"] as? String,
           !name.isEmpty {
            video.author = name
            video.authorID = owner.intValue(for: "mid") ?? fallback.authorID
        }
        if let duration = data.intValue(for: "duration") {
            video.duration = Double(duration).durationText
        }
        return video
    }

    static func bestAudioURL(from response: Any) -> String? {
        guard let root = response as? [String: Any],
              let data = root["data"] as? [String: Any]
        else {
            return nil
        }

        if let dash = data["dash"] as? [String: Any],
           let audio = dash["audio"] as? [[String: Any]] {
            let sorted = audio.sorted {
                ($0.intValue(for: "bandwidth") ?? 0) > ($1.intValue(for: "bandwidth") ?? 0)
            }
            for item in sorted {
                if let url = item["baseUrl"] as? String ?? item["base_url"] as? String {
                    return url
                }
                if let backup = item["backupUrl"] as? [String], let url = backup.first {
                    return url
                }
                if let backup = item["backup_url"] as? [String], let url = backup.first {
                    return url
                }
            }
        }

        if let durl = data["durl"] as? [[String: Any]] {
            return durl.compactMap { $0["url"] as? String }.first
        }

        return nil
    }

    static func spaceVideos(from response: Any, artist: BMusicArtist) -> [BMusicVideo] {
        guard let root = response as? [String: Any],
              let data = root["data"] as? [String: Any],
              let list = data["list"] as? [String: Any],
              let vlist = list["vlist"] as? [[String: Any]]
        else {
            return []
        }

        return vlist.compactMap { BMusicVideo(spaceVideo: $0, artist: artist) }
    }

    private init?(searchResult: [String: Any]) {
        guard let bvid = searchResult["bvid"] as? String, !bvid.isEmpty else {
            return nil
        }
        self.id = bvid
        self.bvid = bvid
        self.cid = searchResult.intValue(for: "cid")
        self.title = (searchResult["title"] as? String ?? "未命名视频").cleanedHTML()
        self.author = searchResult["author"] as? String ?? searchResult["typename"] as? String ?? ""
        self.authorID = searchResult.intValue(for: "mid") ?? searchResult.intValue(for: "upic_mid")
        self.cover = searchResult["pic"] as? String ?? ""

        if let duration = searchResult["duration"] as? String {
            self.duration = duration
        } else if let duration = searchResult.intValue(for: "duration") {
            self.duration = Double(duration).durationText
        } else {
            self.duration = ""
        }
    }

    private init?(spaceVideo: [String: Any], artist: BMusicArtist) {
        guard let bvid = spaceVideo["bvid"] as? String, !bvid.isEmpty else {
            return nil
        }
        self.id = bvid
        self.bvid = bvid
        self.cid = spaceVideo.intValue(for: "cid")
        self.title = (spaceVideo["title"] as? String ?? "未命名视频").cleanedHTML()
        self.author = artist.name
        self.authorID = artist.id
        self.cover = spaceVideo["pic"] as? String ?? ""

        if let duration = spaceVideo["length"] as? String {
            self.duration = duration
        } else if let duration = spaceVideo.intValue(for: "duration") {
            self.duration = Double(duration).durationText
        } else {
            self.duration = ""
        }
    }
}

struct BMusicArtist: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
}

struct BMusicPlaylist: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var items: [BMusicVideo]

    init(id: UUID = UUID(), name: String, items: [BMusicVideo] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

enum BMusicError: LocalizedError {
    case missingCID
    case missingAudioURL

    var errorDescription: String? {
        switch self {
        case .missingCID:
            return "没有拿到视频 CID，无法解析音频。"
        case .missingAudioURL:
            return "没有找到可播放的音频地址。"
        }
    }
}

enum BMusicPlaybackState {
    static func label(for state: String) -> String {
        switch state {
        case "loading":
            return "加载中"
        case "ready":
            return "准备就绪"
        case "playing":
            return "播放中"
        case "paused":
            return "已暂停"
        case "buffering":
            return "缓冲中"
        case "ended":
            return "已结束"
        case "failed":
            return "播放失败"
        case "stopped":
            return "已停止"
        default:
            return state.isEmpty ? "空闲" : state
        }
    }
}

enum BMusicPlaybackMode: String, CaseIterable {
    case listLoop
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .listLoop:
            return "列表循环"
        case .repeatOne:
            return "单曲循环"
        case .shuffle:
            return "随机播放"
        }
    }

    var systemImage: String {
        switch self {
        case .listLoop:
            return "repeat"
        case .repeatOne:
            return "repeat.1"
        case .shuffle:
            return "shuffle"
        }
    }

    var next: BMusicPlaybackMode {
        let modes = Self.allCases
        guard let index = modes.firstIndex(of: self) else {
            return .listLoop
        }
        return modes[modes.index(after: index) == modes.endIndex ? modes.startIndex : modes.index(after: index)]
    }
}

struct BMusicLibrarySnapshot: Codable {
    var queue: [BMusicVideo] = []
    var favorites: [BMusicVideo] = []
    var recentlyPlayed: [BMusicVideo] = []
    var playlists: [BMusicPlaylist] = []
    var favoriteArtists: [BMusicArtist] = []

    enum CodingKeys: String, CodingKey {
        case queue
        case favorites
        case recentlyPlayed
        case playlists
        case favoriteArtists
    }

    init(
        queue: [BMusicVideo] = [],
        favorites: [BMusicVideo] = [],
        recentlyPlayed: [BMusicVideo] = [],
        playlists: [BMusicPlaylist] = [],
        favoriteArtists: [BMusicArtist] = []
    ) {
        self.queue = queue
        self.favorites = favorites
        self.recentlyPlayed = recentlyPlayed
        self.playlists = playlists
        self.favoriteArtists = favoriteArtists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queue = try container.decodeIfPresent([BMusicVideo].self, forKey: .queue) ?? []
        favorites = try container.decodeIfPresent([BMusicVideo].self, forKey: .favorites) ?? []
        recentlyPlayed = try container.decodeIfPresent([BMusicVideo].self, forKey: .recentlyPlayed) ?? []
        playlists = try container.decodeIfPresent([BMusicPlaylist].self, forKey: .playlists) ?? []
        favoriteArtists = try container.decodeIfPresent([BMusicArtist].self, forKey: .favoriteArtists) ?? []
    }
}

struct BMusicListBackup: Codable {
    enum Kind: String, Codable {
        case favorites
        case playlist
    }

    var formatVersion = 1
    var appName = "B-Music"
    var exportedAt = Date()
    var kind: Kind
    var name: String
    var playlistID: UUID?
    var items: [BMusicVideo]
}

struct BMusicListImportSummary {
    var importedFiles = 0
    var failedFiles = 0
    var restoredFavorites = false
    var updatedPlaylists = 0
    var createdPlaylists = 0
}

struct BMusicRecommendation: Codable, Identifiable, Hashable {
    var keyword: String
    var score: Int

    var id: String {
        keyword
    }
}

struct BMusicWeightedKeyword {
    var keyword: String
    var score: Int
}

struct BMusicRecommendationSnapshot: Codable {
    var updatedAt: Date
    var recommendations: [BMusicRecommendation]

    enum CodingKeys: String, CodingKey {
        case updatedAt
        case recommendations
        case keywords
    }

    init(updatedAt: Date, recommendations: [BMusicRecommendation]) {
        self.updatedAt = updatedAt
        self.recommendations = recommendations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        if let recommendations = try container.decodeIfPresent([BMusicRecommendation].self, forKey: .recommendations) {
            self.recommendations = recommendations
        } else {
            let keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
            self.recommendations = keywords.enumerated().map { index, keyword in
                BMusicRecommendation(keyword: keyword, score: max(1, 10 - index))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(recommendations, forKey: .recommendations)
    }
}

final class BMusicRecommendationStore {
    static let displayLimit = 14
    static let fallbackKeywords = ["周杰伦", "邓紫棋", "林俊杰", "洛天依", "起风了", "晴天", "达拉崩吧", "光年之外"]
    static let fallbackRecommendations = fallbackKeywords.enumerated().map { index, keyword in
        BMusicRecommendation(keyword: keyword, score: max(1, 10 - index))
    }

    private let key = "b-music-recommendations-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BMusicRecommendationSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(BMusicRecommendationSnapshot.self, from: data)
    }

    func save(_ snapshot: BMusicRecommendationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    static func rotatedFallbackRecommendations() -> [BMusicRecommendation] {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let offset = day % fallbackRecommendations.count
        return Array(fallbackRecommendations[offset...]) + Array(fallbackRecommendations[..<offset])
    }

    static func displayRecommendations(from recommendations: [BMusicRecommendation], seed: Int) -> [BMusicRecommendation] {
        let source = recommendations.isEmpty ? fallbackRecommendations : recommendations
        return source
            .sorted { lhs, rhs in
                let lhsRank = lhs.score * 10 + stableJitter(lhs.keyword, seed: seed)
                let rhsRank = rhs.score * 10 + stableJitter(rhs.keyword, seed: seed)
                if lhsRank == rhsRank {
                    return lhs.keyword < rhs.keyword
                }
                return lhsRank > rhsRank
            }
            .prefix(displayLimit)
            .enumerated()
            .sorted { lhs, rhs in
                let left = stableJitter(lhs.element.keyword, seed: seed + lhs.offset + 11)
                let right = stableJitter(rhs.element.keyword, seed: seed + rhs.offset + 11)
                return left > right
            }
            .map(\.element)
    }

    private static func stableJitter(_ keyword: String, seed: Int) -> Int {
        abs((keyword + "\(seed)").stableHash % 100)
    }
}

enum BMusicRecommendationExtractor {
    static func keywords(fromRankingResponse response: Any) -> [BMusicWeightedKeyword] {
        guard let root = response as? [String: Any],
              let data = root["data"] as? [String: Any],
              let list = data["list"] as? [[String: Any]]
        else {
            return []
        }

        return list.enumerated().flatMap { index, item -> [BMusicWeightedKeyword] in
            let baseScore = max(1, 36 - index)
            var values: [BMusicWeightedKeyword] = []
            if let title = item["title"] as? String {
                values.append(contentsOf: weightedKeywords(fromTitle: title).map { keyword in
                    BMusicWeightedKeyword(keyword: keyword.keyword, score: baseScore + keyword.score)
                })
            }
            if let owner = item["owner"] as? [String: Any],
               let name = owner["name"] as? String {
                values.append(contentsOf: keywords(fromOwnerName: name).map { keyword in
                    BMusicWeightedKeyword(keyword: keyword, score: baseScore + 16)
                })
            }
            return values
        }
    }

    static func recommendations(from weightedKeywords: [BMusicWeightedKeyword]) -> [BMusicRecommendation] {
        var scores: [String: (keyword: String, score: Int)] = [:]
        for item in weightedKeywords {
            let normalized = item.keyword.lowercased()
            if let existing = scores[normalized] {
                scores[normalized] = (existing.keyword, existing.score + item.score)
            } else {
                scores[normalized] = (item.keyword, item.score)
            }
        }

        return scores.values
            .map { BMusicRecommendation(keyword: $0.keyword, score: $0.score) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.keyword < rhs.keyword
                }
                return lhs.score > rhs.score
            }
    }

    private static func weightedKeywords(fromTitle title: String) -> [(keyword: String, score: Int)] {
        let cleaned = title.cleanedHTML()
        let quoted = extractQuotedKeywords(from: cleaned)
        if !quoted.isEmpty {
            return quoted.map { ($0, 22) }
        }

        let separators = CharacterSet(charactersIn: "｜|/-_【】[]（）()《》「」『』“”\"：:，,。· ")
        return cleaned
            .components(separatedBy: separators)
            .map(cleanKeyword)
            .filter(isUsefulKeyword)
            .prefix(1)
            .map { ($0, 4) }
    }

    private static func keywords(fromOwnerName name: String) -> [String] {
        let cleaned = cleanKeyword(name)
        guard isUsefulKeyword(cleaned), cleaned.count <= 12 else {
            return []
        }
        return [cleaned]
    }

    private static func extractQuotedKeywords(from text: String) -> [String] {
        let patterns = [
            #"《([^》]{2,18})》"#,
            #"「([^」]{2,18})」"#,
            #"『([^』]{2,18})』"#,
            #""([^"]{2,18})""#
        ]

        return patterns.flatMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return [String]()
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard let valueRange = Range(match.range(at: 1), in: text) else {
                    return nil
                }
                let value = cleanKeyword(String(text[valueRange]))
                return isUsefulKeyword(value) ? value : nil
            }
        }
    }

    private static func cleanKeyword(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)\bcover\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bmv\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\blive\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bfull\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "翻唱", with: "")
            .replacingOccurrences(of: "完整版", with: "")
            .replacingOccurrences(of: "动态歌词", with: "")
            .replacingOccurrences(of: "现场", with: "")
            .replacingOccurrences(of: "原唱", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulKeyword(_ value: String) -> Bool {
        guard value.count >= 2, value.count <= 18 else {
            return false
        }
        let blocked = ["音乐", "歌曲", "合集", "高音质", "官方", "投稿", "视频", "字幕", "伴奏", "纯音乐"]
        return !blocked.contains(value)
    }
}

struct BMusicCachePreferences: Codable {
    var cachesRecentPlays = true
    var cachesFavorites = false
    var cachedPlaylistIDs: [UUID] = []
}

final class BMusicCachePreferencesStore {
    private let key = "b-music-cache-preferences-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BMusicCachePreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(BMusicCachePreferences.self, from: data)
        else {
            return BMusicCachePreferences()
        }
        return preferences
    }

    func save(_ preferences: BMusicCachePreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

final class BMusicLibraryStore {
    private let key = "b-music-library-v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BMusicLibrarySnapshot {
        guard let data = defaults.data(forKey: key) else {
            return BMusicLibrarySnapshot()
        }

        do {
            return try JSONDecoder().decode(BMusicLibrarySnapshot.self, from: data)
        } catch {
            return BMusicLibrarySnapshot()
        }
    }

    func save(_ snapshot: BMusicLibrarySnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: key)
        } catch {
            return
        }
    }
}

private extension [String: Any] {
    func intValue(for key: String) -> Int? {
        switch self[key] {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }
}

private extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }

        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private extension String {
    func cleanedHTML() -> String {
        let noTags = replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return noTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func qrUIImage() -> UIImage? {
        guard let comma = firstIndex(of: ",") else {
            return nil
        }
        let base64 = String(self[index(after: comma)...])
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        return UIImage(data: data)
    }

    var safeBackupFilename: String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名列表" : cleaned
    }

    var stableHash: Int {
        unicodeScalars.reduce(5381) { hash, scalar in
            ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
    }
}

private extension Int64 {
    var bMusicByteSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

private extension UIImage {
    var averageColor: UIColor? {
        guard let inputImage = CIImage(image: self) else {
            return nil
        }

        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )

        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: inputImage,
            kCIInputExtentKey: extentVector
        ]),
              let outputImage = filter.outputImage
        else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return UIColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: CGFloat(bitmap[3]) / 255
        )
    }
}

private extension UIColor {
    func bMusicAdjusted(saturation saturationMultiplier: CGFloat, brightness brightnessMultiplier: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        if getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            return UIColor(
                hue: hue,
                saturation: min(max(saturation * saturationMultiplier, 0), 1),
                brightness: min(max(brightness * brightnessMultiplier, 0), 1),
                alpha: alpha
            )
        }

        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            return UIColor(
                white: min(max(white * brightnessMultiplier, 0), 1),
                alpha: alpha
            )
        }

        return self
    }
}

private extension Double {
    var durationText: String {
        guard isFinite, self > 0 else {
            return "0:00"
        }
        let total = Int(self.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
