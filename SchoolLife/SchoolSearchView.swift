import SwiftUI

struct SchoolSearchView: View {
    @ObservedObject var neisManager: NeisManager
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack {
                TextField("학교명을 입력하세요 (예: 강남고)", text: $searchText)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding()
                    .onSubmit { neisManager.searchSchool(query: searchText) }

                List(neisManager.schools) { school in
                    Button(action: {
                        neisManager.saveSchool(school: school)
                        DispatchQueue.main.async {
                            dismiss()
                        }
                    }) {
                        VStack(alignment: .leading) {
                            Text(school.SCHUL_NM).font(.headline).foregroundColor(.primary)
                            Text(school.ORG_RDNMA ?? "").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("학교 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
