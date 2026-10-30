import Foundation
import SwiftUI
import Testing
@testable import TookTook

/// 출시 전 점검 항목 중 코드로 확인할 수 있는 것: 처리방침 번들 포함·해석, 차트 색상 구분.
struct ReleaseContentTests {
    @Test func 처리방침_형식을_줄_단위로_읽는다() {
        let lines = PrivacyPolicyDocument.parse("""
        # 제목

        본문 문장
        ## 1. 소제목
        - 항목 하나
          - 들여쓴 항목
        """)
        #expect(lines == [
            .title("제목"),
            .paragraph("본문 문장"),
            .heading("1. 소제목"),
            .bullet("항목 하나"),
            .bullet("들여쓴 항목"),
        ])
    }

    @Test func 처리방침_굵게_표기는_기호_없이_보인다() {
        let text = PrivacyPolicyDocument.inline("정보는 **iPhone 안에만** 저장됩니다.")
        #expect(String(text.characters) == "정보는 iPhone 안에만 저장됩니다.")
    }

    @Test func 처리방침_파일이_앱에_포함되어_있다() {
        let lines = PrivacyPolicyDocument.load()
        #expect(lines.first == .title("툭툭가계부 개인정보 처리방침"))
        #expect(lines.contains { if case .heading = $0 { true } else { false } })
        // Apple 지도 서비스로 좌표가 전달된다는 사실을 처리방침이 밝히고 있어야 한다.
        #expect(lines.contains { line in
            if case .bullet(let text) = line { text.contains("Apple") && text.contains("역지오코딩") } else { false }
        })
    }

    /// 게시 후 HTTPS 접속을 확인한 주소만 쓴다(2026-10-31 확인). 주소를 바꾸면 다시 확인하고 이 테스트를 고친다.
    @Test func 웹_주소는_게시해_확인한_HTTPS_주소다() {
        #expect(AppLinks.privacyPolicyURL?.absoluteString == "https://twentyonestar.github.io/tooktook/privacy/")
        #expect(AppLinks.supportURL?.absoluteString == "https://twentyonestar.github.io/tooktook/support/")
    }

    @Test func 기본_카테고리_색상은_모두_다르다() {
        let colors = DefaultCategory.all.map { CategoryPalette.color(forDefaultKey: $0.key) }
        #expect(colors.allSatisfy { $0 != nil })
        #expect(Set(colors.compactMap { $0?.description }).count == DefaultCategory.all.count)
    }
}
