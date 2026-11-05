import SwiftData
import SwiftUI
import ObjectKeyCore

/// 태그 고르기. 기본 태그와 쓰고 있는 태그를 칩으로 보여 주고, 새 태그를 더할 수 있다.
struct TagPicker: View {
    @Binding var tags: [String]
    @Query private var keys: [KeyObject]
    @State private var adding = false
    @State private var newTag = ""

    var body: some View {
        let options = TagRules.all(used: keys.map(\.tags) + [tags])
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { tag in
                    let on = tags.contains(tag)
                    Button {
                        if on { tags.removeAll { $0 == tag } } else { tags.append(tag) }
                    } label: {
                        Text("#\(tag)").font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(Capsule().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Button { newTag = ""; adding = true } label: {
                    Label("새 태그", systemImage: "plus").font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.4)))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
        .alert("새 태그", isPresented: $adding) {
            TextField("예: 회사", text: $newTag)
            Button("추가") {
                if let tag = TagRules.normalize(newTag), !tags.contains(tag) { tags.append(tag) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("\(TagRules.maxLength)자까지 쓸 수 있어요.")
        }
    }
}

/// 홈 위쪽 태그 필터. 고른 태그는 기억한다.
struct TagFilterBar: View {
    let tags: [String]
    @Binding var selection: String
    let onEdit: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("전체", selected: selection.isEmpty) { selection = "" }
                ForEach(tags, id: \.self) { tag in
                    chip("#\(tag)", selected: selection == tag) { selection = tag }
                }
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3").font(.subheadline)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("태그 관리")
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(Capsule().fill(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 태그 이름 바꾸기·지우기. 지워도 물건과 기록은 그대로다.
struct TagManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var keys: [KeyObject]
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        let tags = TagRules.all(used: keys.map(\.tags), includeDefaults: false)
        NavigationStack {
            List {
                Section {
                if tags.isEmpty {
                    Text("아직 쓰고 있는 태그가 없어요. 물건 등록이나 습관 설정에서 붙일 수 있어요.").foregroundStyle(.secondary)
                }
                ForEach(tags, id: \.self) { tag in
                    Button {
                        newName = tag
                        renaming = tag
                    } label: {
                        LabeledContent("#\(tag)", value: "물건 \(keys.filter { $0.tags.contains(tag) }.count)개")
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    for i in offsets { remove(tags[i]) }
                }
                } footer: {
                    if !tags.isEmpty { Text("누르면 이름을 바꾸고, 왼쪽으로 밀면 지워요. 태그를 지워도 물건과 기록은 그대로예요.") }
                }
            }
            .navigationTitle("태그 관리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .alert("태그 이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
                   presenting: renaming) { old in
                TextField("새 이름", text: $newName)
                Button("바꾸기") { rename(old, to: newName) }
                Button("취소", role: .cancel) {}
            }
        }
    }

    private func rename(_ old: String, to new: String) {
        for key in keys where key.tags.contains(old) { key.tags = TagRules.rename(key.tags, from: old, to: new) }
        context.saveOrReport()
    }

    private func remove(_ tag: String) {
        for key in keys where key.tags.contains(tag) { key.tags.removeAll { $0 == tag } }
        context.saveOrReport()
    }
}
