import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    var onBackToProjects: () -> Void
    @State private var excludedNames = ""
    @State private var selectedPhoto: String?
    @State private var isEditingAlbums = false
    @State private var showNewAlbumPrompt = false
    @State private var newAlbumName = ""
    @State private var pendingAlbumDropPaths: [String] = []
    @State private var showDeleteBinConfirm = false
    @State private var isEditingSources = false
    @State private var browseYearsExpanded = false
    @State private var browsePlacesExpanded = false
    @State private var browseCamerasExpanded = false
    @State private var filterSourcesExpanded = false
    @AppStorage(AppPreferences.showPeopleBarKey) private var showPeopleBar = true
    @AppStorage(AppPreferences.photoSortKey) private var storedPhotoSort = LibraryPhotoSort.dateNewest.rawValue
    @State private var gridCellFrames: [String: CGRect] = [:]
    @State private var dragStrokeTouched: Set<String> = []
    @State private var lastDragPoint: CGPoint?
    @State private var isDragSelecting = false

    private let gridSpacing: CGFloat = 6
    private let gridMinimumCell: CGFloat = 96

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 232)
            } detail: {
                libraryMainColumn
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationSplitViewStyle(.balanced)

            if selectedPhoto != nil {
                PhotoDetailView(
                    path: Binding(
                        get: { selectedPhoto ?? "" },
                        set: { selectedPhoto = $0 }
                    ),
                    paths: model.visiblePaths,
                    model: model
                ) {
                    selectedPhoto = nil
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPhoto != nil)
        .onAppear {
            if let sort = LibraryPhotoSort(rawValue: storedPhotoSort) {
                model.photoSort = sort
            }
            model.onAppear()
            syncFiltersFromProject()
        }
        .onChange(of: model.photoSort) { _, newValue in
            storedPhotoSort = newValue.rawValue
        }
        .onDisappear { model.close() }
        .frame(minWidth: 720, minHeight: 480)
        .alert("New album", isPresented: $showNewAlbumPrompt) {
            TextField("Name", text: $newAlbumName)
            Button("Cancel", role: .cancel) {
                newAlbumName = ""
                pendingAlbumDropPaths = []
            }
            Button("Create") {
                let trimmed = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let albumId = model.createManualAlbum(name: trimmed), !pendingAlbumDropPaths.isEmpty {
                    model.addPathsToAlbum(albumId: albumId, paths: pendingAlbumDropPaths)
                }
                newAlbumName = ""
                pendingAlbumDropPaths = []
            }
        } message: {
            if pendingAlbumDropPaths.isEmpty {
                Text("Add a manual album to this project.")
            } else {
                let count = pendingAlbumDropPaths.count
                let noun = count == 1 ? "photo" : "photos"
                Text("Create an album and add \(count) \(noun).")
            }
        }
        .alert("Delete from source?", isPresented: $showDeleteBinConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await model.deleteBinFromSource() }
            }
        } message: {
            Text(deleteBinConfirmMessage)
        }
    }

    private var deleteBinConfirmMessage: String {
        let count = model.deleteBinCount
        let plural = count == 1 ? "photo" : "photos"
        return """
        This will move \(count) \(plural) to the Trash on your Mac, removing them from their original source folders. Photo Viewer cannot undo this; restore files from the Trash in Finder if needed.

        Continue only if you are sure.
        """
    }

    private var libraryMainColumn: some View {
        VStack(spacing: 0) {
            LibraryHeaderBar(
                model: model,
                excludedNames: $excludedNames,
                onExport: model.exportSelectedAlbum
            )
            LibraryAnalysisSection(
                model: model,
                showPeopleBar: showPeopleBar,
                onShowPeople: { showPeopleBar = true },
                onHidePeople: hidePeopleBar
            )
            LibraryFilterPanel(model: model)
            photoGrid
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedSidebarKey) {
            Section {
                Button(action: onBackToProjects) {
                    Label("Projects", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .sidebarListRowInsets()
            }

            Section("Filter") {
                filterSidebarRow("All Photos", systemImage: "photo.on.rectangle", key: nil)
                if model.sidebarScreenshotCount > 0 {
                    filterSidebarRow(
                        "Screenshots (\(model.sidebarScreenshotCount))",
                        systemImage: "rectangle.dashed",
                        key: "browse:screenshots"
                    )
                }
                if !model.sidebarYears.isEmpty {
                    DisclosureGroup(isExpanded: $browseYearsExpanded) {
                        ForEach(model.sidebarYears, id: \.year) { row in
                            filterSidebarRow(
                                "\(row.year) (\(row.count))",
                                systemImage: "calendar",
                                key: "date:\(row.year)"
                            )
                        }
                    } label: {
                        sidebarFilterGroupLabel("Years", systemImage: "calendar", count: model.sidebarYears.count)
                    }
                }
                if !model.sidebarPlaces.isEmpty {
                    DisclosureGroup(isExpanded: $browsePlacesExpanded) {
                        ForEach(model.sidebarPlaces.prefix(30), id: \.name) { row in
                            filterSidebarRow(
                                sidebarBucketLabel(row.name, count: row.count),
                                systemImage: "mappin.and.ellipse",
                                key: "place:\(row.name)"
                            )
                        }
                    } label: {
                        sidebarFilterGroupLabel("Places", systemImage: "mappin.and.ellipse", count: model.sidebarPlaces.count)
                    }
                }
                if !model.sidebarCameras.isEmpty {
                    DisclosureGroup(isExpanded: $browseCamerasExpanded) {
                        ForEach(model.sidebarCameras.prefix(30), id: \.name) { row in
                            filterSidebarRow(
                                sidebarBucketLabel(row.name, count: row.count),
                                systemImage: "camera",
                                key: "camera:\(row.name)"
                            )
                        }
                    } label: {
                        sidebarFilterGroupLabel("Cameras", systemImage: "camera", count: model.sidebarCameras.count)
                    }
                }
                if !filterSourcePaths.isEmpty {
                    DisclosureGroup(isExpanded: $filterSourcesExpanded) {
                        ForEach(model.project.sourceBookmarks) { source in
                            filterSidebarRow(
                                filterSourceTitle(source.displayPath),
                                systemImage: "externaldrive",
                                key: "source:\(source.displayPath)"
                            )
                        }
                        ForEach(legacySources, id: \.self) { path in
                            filterSidebarRow(
                                filterSourceTitle(path),
                                systemImage: "folder",
                                key: "source:\(path)"
                            )
                        }
                    } label: {
                        sidebarFilterGroupLabel(
                            "Sources",
                            systemImage: "folder",
                            count: filterSourcePaths.count
                        )
                    }
                }
            }
            Section {
                favoritesSidebarRow
                newAlbumDropRow
                ForEach(model.userCreatedAlbums) { album in
                    albumRow(album)
                        .tag("album:\(album.id)")
                }
            } header: {
                albumsSectionHeader
            }
            Section("Delete bin") {
                deleteBinSidebarRow
            }
            Section {
                ForEach(model.project.sourceBookmarks) { source in
                    sourceRow(
                        title: source.displayPath,
                        systemImage: "externaldrive",
                        showsDelete: isEditingSources
                    ) {
                        model.removeSource(id: source.id)
                    }
                    .selectionDisabled(true)
                }
                ForEach(legacySources, id: \.self) { path in
                    sourceRow(
                        title: path,
                        systemImage: "folder",
                        showsDelete: isEditingSources
                    ) {
                        model.removeLegacySource(path: path)
                    }
                    .selectionDisabled(true)
                }
            } header: {
                sourcesSectionHeader
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            AppInfoSidebarHeader()
        }
        .onChange(of: model.selectedSidebarKey) { _, newValue in
            model.applySidebarKey(newValue)
            revealFilterSidebarSelection(newValue)
        }
    }

    /// Expand the relevant Filter subgroup when a nested filter is active.
    private func revealFilterSidebarSelection(_ key: String?) {
        guard let key else { return }
        if key.hasPrefix("date:") { browseYearsExpanded = true }
        if key.hasPrefix("place:") { browsePlacesExpanded = true }
        if key.hasPrefix("camera:") { browseCamerasExpanded = true }
        if key.hasPrefix("source:") { filterSourcesExpanded = true }
    }

    private var showsDeleteBinChrome: Bool {
        model.isViewingDeleteBin
    }

    private var showsActiveFilterBanner: Bool {
        model.isViewFiltered && !model.isViewingDeleteBin
    }

    private var gridBottomChromeInset: CGFloat {
        var inset: CGFloat = 0
        if showsActiveFilterBanner { inset += 58 }
        if !model.selectedPaths.isEmpty { inset += 52 }
        if showsDeleteBinChrome { inset += 58 }
        return inset
    }

    private var gridBottomChrome: some View {
        VStack(spacing: 0) {
            if showsActiveFilterBanner {
                LibraryActiveFilterBar(model: model, onReset: resetViewFilters)
            }
            if !model.selectedPaths.isEmpty {
                LibrarySelectionActionBar(model: model) {
                    pendingAlbumDropPaths = Array(model.selectedPaths)
                    showNewAlbumPrompt = true
                }
            }
            if showsDeleteBinChrome {
                LibraryDeleteBinBar(
                    model: model,
                    showDeleteConfirm: $showDeleteBinConfirm,
                    embeddedInBottomChrome: true
                )
            }
        }
    }

    private var photoGrid: some View {
        ZStack(alignment: .bottom) {
            Group {
                if model.visiblePaths.isEmpty && model.activity.isCataloging {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading your library…")
                            .foregroundStyle(.secondary)
                    }
                } else if model.visiblePaths.isEmpty {
                    ContentUnavailableView(
                        model.hasNarrowedGrid ? "No matching photos" : "No photos",
                        systemImage: "photo",
                        description: Text(
                            model.hasNarrowedGrid
                                ? "Nothing in the library matches the current filters."
                                : "Add a source folder to begin."
                        )
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: gridMinimumCell), spacing: gridSpacing)],
                            alignment: .leading,
                            spacing: gridSpacing
                        ) {
                            ForEach(model.visiblePaths, id: \.self) { path in
                                let inBin = model.project.deleteBinPaths.contains(path)
                                let payload = PhotoAlbumDragDrop.payload(for: path, model: model)
                                PhotoGridCellContainer(
                                    path: path,
                                    isGridSelected: model.selectedPaths.contains(path),
                                    isInDeleteBin: inBin,
                                    reportsDragFrames: isDragSelecting || !model.selectedPaths.isEmpty,
                                    thumbnailLoader: model.thumbnail(for:),
                                    dragPayload: payload,
                                    onSingleTap: { model.toggleGridSelection(path: path) },
                                    onDoubleTap: { selectedPhoto = path }
                                )
                                .equatable()
                                .contextMenu {
                                    Button(model.selectedPaths.contains(path) ? "Deselect" : "Select") {
                                        model.toggleGridSelection(path: path)
                                    }
                                    Button(inBin ? "Remove from delete bin" : "Add to delete bin") {
                                        if inBin {
                                            model.removeFromDeleteBin(paths: [path])
                                        } else {
                                            model.addToDeleteBin(paths: [path])
                                        }
                                    }
                                    Divider()
                                    ForEach(model.project.albums.filter { $0.kind == .manual }) { album in
                                        Button("Add to \(album.name)") {
                                            model.addToAlbum(albumId: album.id, path: path)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coordinateSpace(name: "photoGrid")
                        .onPhotoGridCellFramesChange { frames in
                            if isDragSelecting {
                                gridCellFrames = frames
                            }
                        }
                        .photoGridDragSelect(
                            model: model,
                            cellFrames: gridCellFrames,
                            strokeTouched: $dragStrokeTouched,
                            lastDragPoint: $lastDragPoint,
                            isDragSelecting: $isDragSelecting
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, gridBottomChromeInset)

            gridBottomChrome
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var albumsSectionHeader: some View {
        HStack(spacing: 4) {
            Text("Albums")
            Spacer(minLength: 4)
            if model.selectedAlbumId != nil {
                Button("All") {
                    model.clearAlbumFilter()
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
            SidebarSectionIconButton(
                systemImage: isEditingAlbums ? "checkmark.circle" : "pencil",
                isEmphasized: isEditingAlbums,
                help: isEditingAlbums ? "Done editing albums" : "Edit albums"
            ) {
                isEditingAlbums.toggle()
            }
            SidebarSectionIconButton(systemImage: "plus", help: "New album") {
                showNewAlbumPrompt = true
            }
        }
        .sidebarSectionHeaderActionsLayout()
        .textCase(nil)
    }

    private var favoritesSidebarRow: some View {
        let key = "album:\(AlbumConstants.favoritesAlbumId)"
        let isSelected = model.selectedSidebarKey == key
        let count = model.favoritesAlbum?.memberPaths.count ?? 0
        return Button {
            model.selectFavoritesAlbum()
        } label: {
            SidebarStandardLabel(
                title: "Favorites (\(count))",
                systemImage: "star.fill",
                iconForeground: .yellow,
                titleForeground: isSelected ? .accentColor : .primary
            )
        }
        .buttonStyle(SidebarListRowButtonStyle(isSelected: isSelected, density: .compact))
        .albumPhotoDropDestination(acceptsDrop: true) { paths in
            model.addPathsToAlbum(albumId: AlbumConstants.favoritesAlbumId, paths: paths)
            return true
        }
        .help("Starred photos — drag here to favorite")
        .tag(key)
        .sidebarListRowInsets(compact: true)
    }

    private var newAlbumDropRow: some View {
        SidebarStandardLabel(
            title: "New album…",
            systemImage: "plus.rectangle.on.folder",
            iconForeground: .secondary,
            titleForeground: .secondary
        )
        .font(.callout)
        .sidebarPlaceholderRowStyle()
        .albumPhotoDropDestination(acceptsDrop: true) { paths in
            pendingAlbumDropPaths = paths
            showNewAlbumPrompt = true
            return true
        }
        .help("Drag photos here to create a new album")
        .selectionDisabled(true)
    }

    @ViewBuilder
    private func albumRow(_ album: Album) -> some View {
        let albumKey = "album:\(album.id)"
        let isSelected = model.selectedSidebarKey == albumKey
        let acceptsPhotoDrop = album.kind == .manual
        Button {
            if model.groupBy == .albums, model.selectedAlbumId == album.id {
                model.clearAlbumFilter()
            } else {
                model.selectAlbum(id: album.id)
            }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                SidebarStandardLabel(
                    title: album.name,
                    systemImage: albumIcon(album),
                    iconForeground: isSelected ? .accentColor : .secondary,
                    titleForeground: isSelected ? .accentColor : .primary
                )
                if isEditingAlbums, !album.isFavorites {
                    SidebarSectionIconButton(
                        systemImage: "trash",
                        role: .destructive,
                        help: "Delete album"
                    ) {
                        model.deleteAlbum(id: album.id)
                    }
                }
            }
        }
        .buttonStyle(SidebarListRowButtonStyle(isSelected: isSelected))
        .sidebarListRowInsets()
        .albumPhotoDropDestination(acceptsDrop: acceptsPhotoDrop) { paths in
            guard acceptsPhotoDrop else { return false }
            model.addPathsToAlbum(albumId: album.id, paths: paths)
            return true
        }
        .help(acceptsPhotoDrop ? "Drag photos here to add to this album" : "Smart albums are rule-based and can’t accept dropped photos")
    }

    private func albumIcon(_ album: Album) -> String {
        switch album.kind {
        case .smart: return "sparkles"
        case .favorites: return "star.fill"
        case .manual: return "folder"
        }
    }

    private var sourcesSectionHeader: some View {
        HStack(spacing: 4) {
            Text("Sources")
            Spacer(minLength: 4)
            SidebarSectionIconButton(
                systemImage: isEditingSources ? "checkmark.circle" : "pencil",
                isEmphasized: isEditingSources,
                help: isEditingSources ? "Done editing sources" : "Edit sources"
            ) {
                isEditingSources.toggle()
            }
            SidebarSectionIconButton(systemImage: "plus", help: "Add source folder…") {
                model.addSourceFolder()
            }
        }
        .sidebarSectionHeaderActionsLayout()
        .textCase(nil)
        .help("Add, remove, or edit indexed folders. Use Filter → Sources to narrow the grid.")
    }

    private func sourceRow(
        title: String,
        systemImage: String,
        showsDelete: Bool,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            SidebarStandardLabel(
                title: title,
                systemImage: systemImage,
                iconForeground: .secondary,
                titleForeground: .secondary
            )
            if showsDelete {
                SidebarSectionIconButton(
                    systemImage: "trash",
                    role: .destructive,
                    help: "Remove source",
                    action: onDelete
                )
            }
        }
        .sidebarPlaceholderRowStyle()
    }

    private var legacySources: [String] {
        model.project.sources.filter { path in
            !model.project.sourceBookmarks.contains { $0.displayPath == path }
        }
    }

    private var filterSourcePaths: [String] {
        model.project.sourceBookmarks.map(\.displayPath) + legacySources
    }

    private func filterSourceTitle(_ path: String) -> String {
        let short = (path as NSString).lastPathComponent
        return short.isEmpty ? path : short
    }

    private func syncFiltersFromProject() {
        excludedNames = model.project.filter.excludedNameFragments.joined(separator: ", ")
    }

    private func resetViewFilters() {
        model.resetAllViewFilters()
    }

    private func hidePeopleBar() {
        model.cancelCombiningPeople()
        showPeopleBar = false
    }

    private var deleteBinSidebarRow: some View {
        let key = "bin"
        let isSelected = model.selectedSidebarKey == key
        return Button {
            model.showDeleteBinInSidebar()
        } label: {
            SidebarStandardLabel(
                title: "Delete bin (\(model.deleteBinCount))",
                systemImage: "trash",
                iconForeground: isSelected ? .orange : .secondary
            )
        }
        .buttonStyle(SidebarListRowButtonStyle(isSelected: isSelected, emphasis: .warning))
        .listRowBackground(Color.clear)
        .photoPathsDropDestination(
            acceptsDrop: true,
            highlight: Color.orange.opacity(0.35)
        ) { paths in
            model.addToDeleteBin(paths: paths)
            return true
        }
        .help("Drag photos here to add to the delete bin")
        .tag(key)
        .sidebarListRowInsets()
    }

    @ViewBuilder
    private func filterSidebarRow(_ title: String, systemImage: String, key: String?) -> some View {
        let isSelected = model.selectedSidebarKey == key
        Button {
            model.selectSidebarFilter(key)
        } label: {
            SidebarStandardLabel(
                title: title,
                systemImage: systemImage,
                iconForeground: isSelected ? .accentColor : .secondary,
                titleForeground: isSelected ? .accentColor : .primary
            )
        }
        .buttonStyle(SidebarListRowButtonStyle(isSelected: isSelected))
        .tag(key)
        .sidebarListRowInsets()
    }

    private func sidebarFilterGroupLabel(_ title: String, systemImage: String, count: Int) -> some View {
        SidebarStandardLabel(title: title, systemImage: systemImage)
            .badge(count)
    }

    private func sidebarBucketLabel(_ name: String, count: Int) -> String {
        let short = (name as NSString).lastPathComponent
        let title = short.count < name.count ? short : name
        if title.count > 28 {
            return "\(String(title.prefix(26)))… (\(count))"
        }
        return "\(title) (\(count))"
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}