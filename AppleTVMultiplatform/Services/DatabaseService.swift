
import Foundation
import SwiftData
import FactoryKit
import SwiftUI
import CoreData

protocol DatabaseServiceInterface: AnyObject, Sendable {
    
    var mainContext: ModelContext { get }
}

/// Use Database service as class with @MainActor because
/// CoreData/SwiftData better works in one-threaded manner.
/// Other services should be `actor`s.
final class DatabaseService: DatabaseServiceInterface {

    private static let cloudKitContainerIdentifier = "iCloud.com.ohmyapps.hiplayer"

    private let sharedModelContainer: ModelContainer
    
    /// For tests use `isStoredInMemoryOnly = true`.
    /// 
    init(isStoredInMemoryOnly: Bool) {
        let logger = Container.shared.logger()
        let schema = Schema([PlaylistItem.self, PlaylistSettingsItem.self, AppSettings.self])
        let localDatabase = ModelConfiguration.CloudKitDatabase.none
        let cloudKitDatabase = ModelConfiguration.CloudKitDatabase.private(Self.cloudKitContainerIdentifier)
        if isStoredInMemoryOnly {
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: localDatabase
            )
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                logger.info("Database model container", private: modelConfiguration.url.path)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        } else {
            var modelConfiguration: ModelConfiguration?
            var usesCloudKit = false
            #if DEBUG
            if let path = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("DATABASE_PATH=")
            }).flatMap({
                $0.components(separatedBy: "DATABASE_PATH=").last
            }).flatMap({
                $0.isEmpty ? nil : $0
            }) {
                let url = URL(fileURLWithPath: path, isDirectory: false)
                modelConfiguration = ModelConfiguration(
                    schema: schema, url: url, allowsSave: false, cloudKitDatabase: localDatabase)
            } else if ProcessInfo.processInfo.arguments.contains("--in-memory-database-only") {
                modelConfiguration = ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: localDatabase)
            }
            #endif
            if modelConfiguration == nil {
                modelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: isStoredInMemoryOnly,
                    cloudKitDatabase: cloudKitDatabase
                )
                usesCloudKit = true
            }
            guard let modelConfiguration else {
                fatalError("Could not create ModelContainer.")
            }
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
                logger.info("Database model container", private: modelConfiguration.url.path)
            } catch {
                guard usesCloudKit else {
                    fatalError("Could not create ModelContainer: \(error)")
                }

                logger.error(error)
                logger.info("CloudKit model container unavailable. Falling back to local SwiftData store.")
                let localModelConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: isStoredInMemoryOnly,
                    cloudKitDatabase: localDatabase
                )
                do {
                    sharedModelContainer = try ModelContainer(for: schema, configurations: [localModelConfiguration])
                    logger.info("Database model container", private: localModelConfiguration.url.path)
                } catch {
                    fatalError("Could not create ModelContainer: \(error)")
                }
            }
        }
    }
    
    var mainContext: ModelContext { sharedModelContainer.mainContext }
}

extension FactoryKit.Container {

    @MainActor
    var databaseService: Factory<DatabaseServiceInterface> {
        if ProcessInfo.processInfo.isPreview || ProcessInfo.processInfo.isRunningUnitTests {
            return self { DatabaseService(isStoredInMemoryOnly: true) }.singleton
        } else {
            return self { DatabaseService(isStoredInMemoryOnly: false) }.singleton
        }
    }
}
