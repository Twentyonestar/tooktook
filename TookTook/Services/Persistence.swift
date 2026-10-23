import Foundation
import Observation
import SwiftData

/// 저장소 파일 위치와 여는 방법. 열기에 실패해도 새 저장소를 만들거나 파일을 지우지 않는다.
enum Persistence {
    /// SwiftData 기본 위치와 같다 (Library/Application Support/default.store). 기존 설치본의 파일을 그대로 연다.
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// 열기 전 사본과 열기 실패 사본을 두는 곳. 앱이 자동으로 지우지 않는다(최근 것만 남기는 정리는 사본끼리만).
    static var defaultBackupsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "StoreBackups", directoryHint: .isDirectory)
    }

    static let currentSchemaVersion = SchemaV2.versionIdentifier.description
    static let schemaVersionKey = "storeSchemaVersion"
    static let keptBackups = 3

    /// 저장소를 연다.
    /// - 스키마 버전 표식이 다르면(버전 관리 이전 설치본 포함) 열기 전에 파일 사본을 남긴다.
    /// - CloudKit 동기화는 명시적으로 끈다. 기본값(.automatic)은 iCloud 권한이 생기는 순간 검증 안 된 모델로 동기화를 시작한다.
    static func openContainer(
        at storeURL: URL = defaultStoreURL,
        backupsDirectory: URL = defaultBackupsDirectory,
        defaults: UserDefaults = .standard
    ) throws -> ModelContainer {
        if defaults.string(forKey: schemaVersionKey) != currentSchemaVersion {
            _ = try? copyStoreFiles(at: storeURL, into: backupsDirectory, label: "before-\(currentSchemaVersion)")
        }

        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TookTookMigrationPlan.self,
            configurations: configuration
        )
        defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
        return container
    }

    /// 저장소 파일(본체, -wal, -shm)을 날짜가 붙은 폴더에 **복사**한다. 원본은 건드리지 않는다.
    /// 저장소가 아직 없으면(첫 실행) 아무것도 하지 않는다.
    @discardableResult
    static func copyStoreFiles(at storeURL: URL, into backupsDirectory: URL, label: String, now: Date = .now) throws -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return nil }

        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.standard))
            .replacingOccurrences(of: ":", with: "")
        let folder = backupsDirectory.appending(path: "\(label)-\(stamp)-\(UUID().uuidString.prefix(4))", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(at: source, to: folder.appending(path: source.lastPathComponent))
        }
        pruneBackups(in: backupsDirectory, keeping: keptBackups, label: label)
        return folder
    }

    /// 같은 종류의 사본이 너무 쌓이지 않게 오래된 **사본**만 정리한다. 원본 저장소는 대상이 아니다.
    private static func pruneBackups(in directory: URL, keeping count: Int, label: String) {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ) else { return }
        let matching = folders
            .filter { $0.lastPathComponent.hasPrefix(label + "-") }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a > b
            }
        for old in matching.dropFirst(count) {
            try? fileManager.removeItem(at: old)
        }
    }
}

enum StoreUnavailableError: LocalizedError {
    case notOpened

    var errorDescription: String? {
        "기록 저장소를 열 수 없어 스택을 남기지 못했어요. 툭툭가계부를 열어 확인해 주세요."
    }
}

/// 앱과 App Intent가 함께 쓰는 저장소 상태. 실패 상태에서는 컨테이너를 내주지 않는다.
@MainActor
@Observable
final class StoreController {
    enum State {
        case ready(ModelContainer)
        case failed(String)
    }

    static let shared = StoreController()

    private(set) var state: State
    /// 열기에 실패했을 때 원본을 복사해 둔 위치
    private(set) var preservedCopy: URL?

    private let opener: () throws -> ModelContainer
    private let storeURL: URL
    private let backupsDirectory: URL

    init(
        storeURL: URL = Persistence.defaultStoreURL,
        backupsDirectory: URL = Persistence.defaultBackupsDirectory,
        opener: (() throws -> ModelContainer)? = nil
    ) {
        self.storeURL = storeURL
        self.backupsDirectory = backupsDirectory
        self.opener = opener ?? { try Persistence.openContainer(at: storeURL, backupsDirectory: backupsDirectory) }
        state = .failed("")
        load()
    }

    var container: ModelContainer? {
        if case .ready(let container) = state { return container }
        return nil
    }

    func requireContainer() throws -> ModelContainer {
        guard let container else { throw StoreUnavailableError.notOpened }
        return container
    }

    /// 다시 시도. 원본 파일은 지우거나 교체하지 않고 같은 파일을 다시 연다.
    func retry() {
        load()
    }

    private func load() {
        do {
            state = .ready(try opener())
        } catch {
            // 다시 시도하다 파일이 바뀌어도 처음 실패한 상태를 되살릴 수 있게 사본을 남긴다.
            if preservedCopy == nil {
                preservedCopy = try? Persistence.copyStoreFiles(at: storeURL, into: backupsDirectory, label: "failed-open")
            }
            state = .failed(String(describing: error))
        }
    }
}
