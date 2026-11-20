import MapKit
import SwiftUI

struct PhotoDetailView: View {
    @Binding var path: String
    let paths: [String]
    var model: LibraryViewModel
    var onClose: () -> Void

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var metadataExpanded = false
    @State private var annotation: PhotoAnnotation
    @State private var isFavorite = false
    @State private var lastScrollStep = Date.distantPast
    @State private var chromeVisible = true
    @State private var chromeIdleGeneration = 0
    @FocusState private var keysFocused: Bool
    @State private var showLocationMap = false
    @State private var photoCategories: [String] = []

    private let room = Color(red: 0.11, green: 0.14, blue: 0.19)
    private let chromeIdleDelay: Duration = .milliseconds(750)

    init(path: Binding<String>, paths: [String], model: LibraryViewModel, onClose: @escaping () -> Void) {
        _path = path
        self.paths = paths
        self.model = model
        self.onClose = onClose
        _annotation = State(initialValue: model.annotation(for: path.wrappedValue))
        _isFavorite = State(initialValue: model.isFavorite(path: path.wrappedValue))
    }

    var body: some View {
        ZStack {
            room.ignoresSafeArea()

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(metadataExpanded ? 12 : 8)
                    .contentShape(Rectangle())
                    .background {
                        ScrollWheelHandler { delta in
                            scrollNavigate(delta: delta)
                        }
                    }
                    .onTapGesture {
                        if metadataExpanded {
                            return
                        }
                        if chromeVisible {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                metadataExpanded = true
                            }
                        } else {
                            revealChromeBriefly()
                        }
                    }
            } else if isLoading {
                ProgressView("Loading photo…")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.85))
            }

            VStack(spacing: 0) {
                topChrome
                    .offset(y: topChromeOffset)
                    .opacity(topChromeOpacity)
                    .allowsHitTesting(chromeVisible || metadataExpanded)
                Spacer(minLength: 0)
                bottomChrome
                    .offset(y: bottomChromeOffset)
                    .opacity(bottomChromeOpacity)
                    .allowsHitTesting(chromeVisible || metadataExpanded)
            }
            .animation(.easeInOut(duration: 0.22), value: chromeVisible)
            .animation(.easeInOut(duration: 0.28), value: metadataExpanded)

            PointerActivityTracker(onActivity: notePointerActivity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .onAppear { scheduleChromeAutoHide() }
        .focusable()
        .focused($keysFocused)
        .focusEffectDisabled()
        .onAppear { keysFocused = true }
        .onKeyPress(.leftArrow) {
            guard !metadataExpanded else { return .ignored }
            step(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !metadataExpanded else { return .ignored }
            step(by: 1)
            return .handled
        }
        .onKeyPress(.space) {
            guard !metadataExpanded else { return .ignored }
            toggleFavorite()
            return .handled
        }
        .onChange(of: metadataExpanded) { _, expanded in
            if expanded {
                chromeVisible = true
            } else {
                scheduleChromeAutoHide()
            }
        }
        .task(id: path) {
            await loadForCurrentPath()
        }
        .sheet(isPresented: $showLocationMap) {
            if let coordinate = photoCoordinate {
                PhotoLocationMapSheet(
                    coordinate: coordinate,
                    photoTitle: (path as NSString).lastPathComponent
                )
            }
        }
    }

    private var photoCategoryChips: some View {
        HStack(spacing: 6) {
            ForEach(photoCategories, id: \.self) { category in
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(category)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.18)))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
        }
    }

    private var topChromeOffset: CGFloat {
        chromeVisible || metadataExpanded ? 0 : -72
    }

    private var topChromeOpacity: Double {
        chromeVisible || metadataExpanded ? 1 : 0
    }

    private var bottomChromeOffset: CGFloat {
        guard !metadataExpanded else { return 0 }
        return chromeVisible ? 0 : 88
    }

    private var bottomChromeOpacity: Double {
        metadataExpanded ? 1 : (chromeVisible ? 1 : 0)
    }

    private func notePointerActivity() {
        revealChromeBriefly()
    }

    private func revealChromeBriefly() {
        chromeVisible = true
        scheduleChromeAutoHide()
    }

    private func scheduleChromeAutoHide() {
        chromeIdleGeneration += 1
        let generation = chromeIdleGeneration
        Task {
            try? await Task.sleep(for: chromeIdleDelay)
            await MainActor.run {
                guard generation == chromeIdleGeneration, !metadataExpanded else { return }
                chromeVisible = false
            }
        }
    }

    private var topChrome: some View {
        HStack(spacing: 12) {
            Button {
                saveAndDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 4) {
                Text((path as NSString).lastPathComponent)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let position = positionLabel {
                        Text(position)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    if !photoCategories.isEmpty {
                        photoCategoryChips
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                model.addToDeleteBin(paths: [path])
            } label: {
                Image(systemName: model.project.deleteBinPaths.contains(path) ? "trash.fill" : "trash")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.project.deleteBinPaths.contains(path) ? Color.orange : .white.opacity(0.85))
            .help("Add to delete bin")

            Button {
                toggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFavorite ? Color.yellow : .white.opacity(0.85))
            .help("Favorite (Space)")

            if photoCoordinate != nil {
                Button {
                    showLocationMap = true
                } label: {
                    Label("Location", systemImage: "map")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .help("Show where this photo was taken")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.35))
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if metadataExpanded {
            metadataPanel
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    metadataExpanded = true
                }
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Details & metadata")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("← → browse · Space favorite · Scroll next/prev")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
    }

    private var metadataPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Details")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        metadataExpanded = false
                    }
                    keysFocused = true
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    factsGrid
                    annotationSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxHeight: min(420, 520))
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var factsGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(MetadataReader.facts(url: URL(fileURLWithPath: path)), id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)
                    Text(row.1)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
            if !annotation.place.isEmpty {
                GridRow {
                    Text("Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .trailing)
                    Text(annotation.place)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var annotationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Annotation")
                .font(.subheadline.weight(.semibold))
            TextField("Place", text: $annotation.place)
                .textFieldStyle(.roundedBorder)
            TextField("Items (comma-separated)", text: Binding(
                get: { annotation.items.joined(separator: ", ") },
                set: { annotation.items = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
            ))
            .textFieldStyle(.roundedBorder)
            Button("Save annotation") {
                model.updateAnnotation(annotation)
            }
            .controlSize(.small)
        }
    }

    private var photoCoordinate: CLLocationCoordinate2D? {
        let meta = MetadataReader.read(url: URL(fileURLWithPath: path))
        guard let lat = meta.latitude, let lon = meta.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var positionLabel: String? {
        ViewerNavigation.positionLabel(path: path, paths: paths)
    }

    private func step(by delta: Int) {
        guard let next = ViewerNavigation.steppedPath(from: path, in: paths, by: delta) else { return }
        persistAnnotation()
        path = next
    }

    private func scrollNavigate(delta: CGFloat) {
        let now = Date()
        guard now.timeIntervalSince(lastScrollStep) > 0.15 else { return }
        lastScrollStep = now
        if delta < 0 {
            step(by: 1)
        } else if delta > 0 {
            step(by: -1)
        }
    }

    private func toggleFavorite() {
        isFavorite = model.toggleFavorite(path: path)
    }

    private func persistAnnotation() {
        model.updateAnnotation(annotation)
    }

    private func loadForCurrentPath() async {
        isLoading = true
        image = nil
        photoCategories = []
        annotation = model.annotation(for: path)
        isFavorite = model.isFavorite(path: path)
        async let categories = model.analysisCategories(for: path)
        async let loadedImage = model.fullImage(for: path)
        photoCategories = await categories
        image = await loadedImage
        isLoading = false
        keysFocused = true
    }

    private func saveAndDismiss() {
        persistAnnotation()
        onClose()
    }
}