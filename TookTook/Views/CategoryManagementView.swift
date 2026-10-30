import SwiftData
import SwiftUI

/// 거래가 카테고리를 참조하므로 삭제 대신 보관한다.
struct CategoryManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExpenseCategory.displayOrder) private var categories: [ExpenseCategory]

    @State private var editing: ExpenseCategory?
    @State private var showAdd = false
    @State private var errorMessage: String?

    private var active: [ExpenseCategory] { categories.filter { !$0.isArchived } }
    private var archived: [ExpenseCategory] { categories.filter(\.isArchived) }

    var body: some View {
        List {
            Section {
                ForEach(active) { category in
                    Button {
                        editing = category
                    } label: {
                        Label(category.name, systemImage: category.symbol)
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("보관") { setArchived(category, true) }
                            .tint(.orange)
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("보관한 카테고리는 새 지출에 보이지 않지만 기존 기록은 그대로 유지돼요.")
            }

            if !archived.isEmpty {
                Section("보관됨") {
                    ForEach(archived) { category in
                        HStack {
                            Label(category.name, systemImage: category.symbol)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("복원") { setArchived(category, false) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("카테고리")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label("카테고리 추가", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showAdd) {
            CategoryEditor(title: "새 카테고리", name: "", symbol: ExpenseCategory.symbolChoices[0]) { name, symbol in
                try StackStore(context: context).addCategory(name: name, symbol: symbol)
            }
        }
        .sheet(item: $editing) { category in
            CategoryEditor(title: "카테고리 수정", name: category.name, symbol: category.symbol) { name, symbol in
                guard let trimmed = name.nilIfBlank else { return }
                category.name = trimmed
                category.symbol = symbol
                try StackStore(context: context).saveChanges()
            }
        }
        .errorAlert($errorMessage)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = active
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.displayOrder = index
        }
        persist()
    }

    private func setArchived(_ category: ExpenseCategory, _ value: Bool) {
        category.isArchived = value
        persist()
    }

    private func persist() {
        do {
            try StackStore(context: context).saveChanges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CategoryEditor: View {
    let title: String
    let onSave: (String, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var errorMessage: String?

    init(title: String, name: String, symbol: String, onSave: @escaping (String, String) throws -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: name)
        _symbol = State(initialValue: symbol)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("예: 술자리", text: $name)
                }
                Section("아이콘") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(ExpenseCategory.symbolChoices, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle().fill(symbol == item ? Color.accentColor.opacity(0.25) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                            .accessibilityAddTraits(symbol == item ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        do {
                            try onSave(name, symbol)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(name.nilIfBlank == nil)
                }
            }
            .errorAlert($errorMessage)
        }
    }
}
