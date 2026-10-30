import SwiftUI

/// 외부 링크. 게시 전에는 nil로 두고, 임의 주소를 넣지 않는다.
enum AppLinks {
    /// 개인정보 처리방침을 웹에 게시한 뒤 주소를 넣는다. nil이면 앱 안의 사본만 보여준다.
    static let privacyPolicyURL: URL? = nil
}

/// 앱에 함께 들어가는 PrivacyPolicy.md를 보여준다. 웹 게시본과 같은 파일이다.
struct PrivacyPolicyView: View {
    private let lines = PrivacyPolicyDocument.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    switch line {
                    case .title(let text):
                        Text(PrivacyPolicyDocument.inline(text)).font(.title.bold())
                    case .heading(let text):
                        Text(PrivacyPolicyDocument.inline(text)).font(.headline).padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").accessibilityHidden(true)
                            Text(PrivacyPolicyDocument.inline(text))
                        }
                    case .paragraph(let text):
                        Text(PrivacyPolicyDocument.inline(text))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("개인정보 처리방침")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = AppLinks.privacyPolicyURL {
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: url) {
                        Label("웹에서 보기", systemImage: "safari")
                    }
                }
            }
        }
    }
}

/// 처리방침 Markdown에서 쓰는 형식만 읽는다: `# 제목`, `## 소제목`, `- 목록`, 일반 문단.
enum PrivacyPolicyDocument {
    enum Line: Equatable {
        case title(String)
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    static func load(bundle: Bundle = .main) -> [Line] {
        guard let url = bundle.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [.paragraph("개인정보 처리방침을 불러오지 못했어요.")] }
        return parse(text)
    }

    /// 문장 안의 **굵게**, [링크](주소) 같은 인라인 표기를 적용한다. 해석에 실패하면 원문을 그대로 쓴다.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    static func parse(_ text: String) -> [Line] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            if line.hasPrefix("## ") { return .heading(String(line.dropFirst(3))) }
            if line.hasPrefix("# ") { return .title(String(line.dropFirst(2))) }
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return .paragraph(line)
        }
    }
}
