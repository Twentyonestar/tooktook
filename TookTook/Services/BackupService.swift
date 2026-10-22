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

@MainActor
enum BackupService {
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

    /// 현재 데이터를 모두 지우고 백업 내용으로 바꾼다.
    static func restore(_ payload: BackupPayload, into context: ModelContext) throws {
        try context.delete(model: LedgerTransaction.self)
        try context.delete(model: Stack.self)
        try context.delete(model: ExpenseCategory.self)

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
