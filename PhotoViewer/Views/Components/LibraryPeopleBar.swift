import SwiftUI

struct LibraryPeopleBar: View {
    @Bindable var model: LibraryViewModel
    var onHide: () -> Void
    var embedded: Bool = false
    @State private var renamingPersonId: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private let chipAvatarSize: CGFloat = 40
    /// Room for avatar, name, and the hover remove control that sits above the circle.
    private let peopleStripHeight: CGFloat = 68

    private var sortedPeople: [PersonGroup] {
        model.project.personGroups.sorted { lhs, rhs in
            let leftName = (lhs.displayName ?? "").lowercased()
            let rightName = (rhs.displayName ?? "").lowercased()
            if leftName != rightName { return leftName < rightName }
            if lhs.memberPhotoPaths.count != rhs.memberPhotoPaths.count {
                return lhs.memberPhotoPaths.count > rhs.memberPhotoPaths.count
            }
            return lhs.id < rhs.id
        }
    }

    private var selectedPersonId: String? {
        guard let key = model.selectedSidebarKey, key.hasPrefix("person:") else { return nil }
        return String(key.dropFirst("person:".count))
    }

    var body: some View {
        if sortedPeople.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("People")
                        .font(.caption.weight(.semibold))
                    Text("· \(sortedPeople.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if model.isCombiningPeople {
                        Text("\(model.peopleMergeSelection.count) selected")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Cancel") { model.cancelCombiningPeople() }
                            .controlSize(.mini)
                        Button("Merge") { model.mergeSelectedPeople() }
                            .controlSize(.mini)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.peopleMergeSelection.count < 2)
                    } else {
                        Button("Combine") { model.toggleCombiningPeople() }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                            .disabled(sortedPeople.count < 2)
                        if selectedPersonId != nil {
                            Button("All") { model.clearPersonFilter() }
                                .controlSize(.mini)
                                .buttonStyle(.bordered)
                        }
                        Button(action: onHide) {
                            Image(systemName: "eye.slash")
                        }
                        .controlSize(.mini)
                        .buttonStyle(.borderless)
                        .help("Hide People section")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(sortedPeople) { person in
                            PersonFaceChip(
                                avatarSize: chipAvatarSize,
                                person: person,
                                isFilterSelected: !model.isCombiningPeople && selectedPersonId == person.id,
                                isMergeSelected: model.peopleMergeSelection.contains(person.id),
                                allowsEditActions: !model.isCombiningPeople,
                                isRenaming: renamingPersonId == person.id,
                                renameText: $renameText,
                                renameFocused: $renameFocused,
                                loader: model.faceChipImage(for:),
                                onSelect: {
                                    if model.isCombiningPeople {
                                        model.togglePersonForMerge(id: person.id)
                                    } else {
                                        model.selectPerson(id: person.id)
                                    }
                                },
                                onBeginRename: { beginRename(person) },
                                onCommitRename: { commitRename(for: person.id) },
                                onRemove: { model.removePersonGroup(id: person.id) }
                            )
                            .contextMenu {
                                if !model.isCombiningPeople {
                                    Button("Rename…") { beginRename(person) }
                                    if sortedPeople.count > 1 {
                                        Menu("Combine with…") {
                                            ForEach(sortedPeople.filter { $0.id != person.id }.prefix(40)) { other in
                                                Button(otherLabel(other)) {
                                                    Task {
                                                        await model.mergePersonGroups(
                                                            primaryId: person.id,
                                                            secondaryId: other.id
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Divider()
                                    Button("Remove face detection", role: .destructive) {
                                        model.removePersonGroup(id: person.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                }
                .scrollClipDisabled()
                .frame(height: renamingPersonId == nil ? peopleStripHeight : peopleStripHeight + 28)
            }
            .padding(.horizontal, embedded ? 0 : 12)
            .padding(.vertical, embedded ? 0 : 4)
            .background {
                if !embedded {
                    Color(nsColor: .underPageBackgroundColor).opacity(0.4)
                }
            }
            .overlay(alignment: .bottom) {
                if !embedded { Divider() }
            }
        }
    }

    private func beginRename(_ person: PersonGroup) {
        renamingPersonId = person.id
        renameText = person.displayName ?? ""
        renameFocused = true
    }

    private func commitRename(for personId: String) {
        guard renamingPersonId == personId else { return }
        model.renamePerson(id: personId, name: renameText)
        renamingPersonId = nil
        renameText = ""
    }

    private func otherLabel(_ person: PersonGroup) -> String {
        let name = person.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (name?.isEmpty == false) ? name! : "Person"
        return "\(title) (\(person.memberPhotoPaths.count))"
    }
}

private struct PersonFaceChip: View {
    let avatarSize: CGFloat
    let person: PersonGroup
    let isFilterSelected: Bool
    let isMergeSelected: Bool
    let allowsEditActions: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    var renameFocused: FocusState<Bool>.Binding
    let loader: (PersonGroup) async -> NSImage?
    let onSelect: () -> Void
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onRemove: () -> Void

    @State private var image: NSImage?
    @State private var isAvatarHovered = false
    @State private var isNameHovered = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Button(action: onSelect) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let image {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            }
                        }
                        .frame(width: avatarSize, height: avatarSize)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(strokeColor, lineWidth: strokeWidth)
                        }

                        Text("\(person.memberPhotoPaths.count)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.thinMaterial, in: Capsule())
                            .offset(x: 4, y: 4)
                    }
                }
                .buttonStyle(.plain)
                .onHover { isAvatarHovered = $0 }

                if allowsEditActions && isAvatarHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .zIndex(1)
                    .help("Remove this face detection result")
                    .transition(.opacity)
                }
            }
            .frame(width: avatarSize + 6, height: avatarSize + 6, alignment: .center)

            if isRenaming {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .frame(width: avatarSize + 12)
                    .focused(renameFocused)
                    .onSubmit(onCommitRename)
                    .onAppear { renameFocused.wrappedValue = true }
            } else {
                HStack(spacing: 3) {
                    Text(subtitleLabel)
                        .font(.caption2)
                        .lineLimit(1)
                    if allowsEditActions && isNameHovered {
                        Button(action: onBeginRename) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Rename")
                    }
                }
                .frame(width: avatarSize + 12)
                .contentShape(Rectangle())
                .onHover { isNameHovered = $0 }
                .onTapGesture(count: 2, perform: onBeginRename)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isAvatarHovered)
        .animation(.easeOut(duration: 0.15), value: isNameHovered)
        .help(helpText)
        .task(id: person.id) {
            image = await loader(person)
        }
    }

    private var subtitleLabel: String {
        let name: String
        if let display = person.displayName, !display.isEmpty {
            name = display
        } else {
            name = "Person"
        }
        return name
    }

    private var helpText: String {
        let base = person.displayName ?? "Unnamed person"
        return "\(base) · \(person.memberPhotoPaths.count) photos. Hover the name to rename or the face to remove."
    }

    private var strokeColor: Color {
        if isMergeSelected { return .orange }
        if isFilterSelected { return Color.accentColor }
        return Color.primary.opacity(0.12)
    }

    private var strokeWidth: CGFloat {
        (isMergeSelected || isFilterSelected) ? 2.5 : 1
    }
}