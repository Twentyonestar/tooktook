import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupPayload: Codable {
    struct CategoryRecord: Codable {
        var id: UUID
        var name: String
        var symbol: String
        var displayOrder: Int
        var isArchived: Bool
    }

    struct StackRecord: Codable {
        var id: UUID
        var createdAt: Date
        var captureSource: String
        var status: String
        var latitude: Double?
        var longitude: Double?
        var horizontalAccuracy: Double?
        var locationStatus: String
        var placeLabel: String?
        var completedAt: Date?
        var transactionId: UUID?
        var discardedAt: Date?
        var isPossibleDuplicate: Bool
    }

    struct TransactionRecord: Codable {
        var id: UUID
        var sourceStackId: UUID?
        var amountKRW: Int64
        var categoryId: UUID
        var occurredAt: Date
        var memo: String?
        var createdAt: Date
        var updatedAt: Date
    }

    var version = 1
    var exportedAt: Date
    var categories: [CategoryRecord]
    var stacks: [StackRecord]
    var transactions: [TransactionRecord]
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateIdentifier
    case brokenReference(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "지원하지 않는 백업 형식이에요 (버전 \(version)). 앱을 업데이트한 뒤 다시 시도해 주세요."
        case .duplicateIdentifier: "백업 파일 안에 같은 항목이 두 번 들어 있어요."
        case .brokenReference(let detail): "백업 파일의 기록 연결이 맞지 않아요. \(detail)"
        }
    }
}

/// 가져오기 정책: 병합하지 않고 기기 데이터를 백업 내용으로 **전체 교체**한다.
/// 같은 파일을 여러 번 가져와도 결과가 같고, 중복 기록이 생기지 않는다.
/// 파일을 먼저 검증하고, 삭제와 삽입을 한 번의 저장으로 처리해 실패하면 기존 데이터가 그대로 남는다.
@MainActor
enum BackupService {
    static let currentVersion = 1

    static func makePayload(from context: ModelContext) throws -> BackupPayload {
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let stacks = try context.fetch(FetchDescriptor<Stack>())
        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        return BackupPayload(
            exportedAt: .now,
            categories: categories.map {
                .init(id: $0.id, name: $0.name, symbol: $0.symbol, displayOrder: $0.displayOrder, isArchived: $0.isArchived)
            },
            stacks: stacks.map {
                .init(
                    id: $0.id, createdAt: $0.createdAt, captureSource: $0.captureSourceRaw, status: $0.statusRaw,
                    latitude: $0.latitude, longitude: $0.longitude, horizontalAccuracy: $0.horizontalAccuracy,
                    locationStatus: $0.locationStatusRaw, placeLabel: $0.placeLabel, completedAt: $0.completedAt,
                    transactionId: $0.transactionId, discardedAt: $0.discardedAt, isPossibleDuplicate: $0.isPossibleDuplicate
                )
            },
            transactions: transactions.map {
                .init(
                    id: $0.id, sourceStackId: $0.sourceStackId, amountKRW: $0.amountKRW, categoryId: $0.categoryId,
                    occurredAt: $0.occurredAt, memo: $0.memo, createdAt: $0.createdAt, updatedAt: $0.updatedAt
                )
            }
        )
    }

    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupPayload.self, from: data)
    }

    /// 기존 데이터를 지우기 전에 호출해 파일 자체의 무결성을 확인한다.
    static func validate(_ payload: BackupPayload) throws {
        guard payload.version <= currentVersion else { throw BackupError.unsupportedVersion(payload.version) }

        let categoryIds = Set(payload.categories.map(\.id))
        let stackIds = Set(payload.stacks.map(\.id))
        let transactionIds = Set(payload.transactions.map(\.id))
        guard categoryIds.count == payload.categories.count,
              stackIds.count == payload.stacks.count,
              transactionIds.count == payload.transactions.count
        else { throw BackupError.duplicateIdentifier }

        for transaction in payload.transactions {
            guard categoryIds.contains(transaction.categoryId) else {
                throw BackupError.brokenReference("지출이 없는 카테고리를 가리켜요.")
            }
            if let stackId = transaction.sourceStackId, !stackIds.contains(stackId) {
                throw BackupError.brokenReference("지출이 없는 스택을 가리켜요.")
            }
        }
        for stack in payload.stacks {
            if let transactionId = stack.transactionId, !transactionIds.contains(transactionId) {
                throw BackupError.brokenReference("정리된 스택의 지출 기록이 없어요.")
            }
        }
    }

    /// 현재 데이터를 모두 지우고 백업 내용으로 바꾼다.
    static func restore(_ payload: BackupPayload, into context: ModelContext) throws {
        try validate(payload)

        // 일괄 삭제(delete(model:))는 저장 전에 스토어에 반영될 수 있어 rollback으로 되돌릴 수 없다.
        // 개별 삭제로 한 번의 save 안에 묶는다.
        for transaction in try context.fetch(FetchDescriptor<LedgerTransaction>()) { context.delete(transaction) }
        for stack in try context.fetch(FetchDescriptor<Stack>()) { context.delete(stack) }
        for category in try context.fetch(FetchDescriptor<ExpenseCategory>()) { context.delete(category) }

        for record in payload.categories {
            context.insert(ExpenseCategory(
                id: record.id, name: record.name, symbol: record.symbol,
                displayOrder: record.displayOrder, isArchived: record.isArchived
            ))
        }
        for record in payload.stacks {
            let stack = Stack(
                id: record.id,
                createdAt: record.createdAt,
                captureSource: CaptureSource(rawValue: record.captureSource) ?? .imported,
                status: StackStatus(rawValue: record.status) ?? .pending,
                locationStatus: LocationStatus(rawValue: record.locationStatus) ?? .notRequested,
                isPossibleDuplicate: record.isPossibleDuplicate
            )
            stack.latitude = record.latitude
            stack.longitude = record.longitude
            stack.horizontalAccuracy = record.horizontalAccuracy
            stack.placeLabel = record.placeLabel
            stack.completedAt = record.completedAt
            stack.transactionId = record.transactionId
            stack.discardedAt = record.discardedAt
            context.insert(stack)
        }
        for record in payload.transactions {
            context.insert(LedgerTransaction(
                id: record.id, sourceStackId: record.sourceStackId, amountKRW: record.amountKRW,
                categoryId: record.categoryId, occurredAt: record.occurredAt, memo: record.memo,
                createdAt: record.createdAt, updatedAt: record.updatedAt
            ))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
