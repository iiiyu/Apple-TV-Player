
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
        let cloudSchema = Schema([PlaylistItem.self])
        let localSchema = Schema([PlaylistSettingsItem.self, AppSettings.self])
        let schema = Schema([PlaylistItem.self, PlaylistSettingsItem.self, AppSettings.self])
        let localDatabase = ModelConfiguration.CloudKitDatabase.none
        let cloudKitDatabase = ModelConfiguration.CloudKitDatabase.private(Self.cloudKitContainerIdentifier)
        if isStoredInMemoryOnly {
            let cloudModelConfiguration = ModelConfiguration(
                "CloudPlaylists",
                schema: cloudSchema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: localDatabase
            )
            let localModelConfiguration = ModelConfiguration(
                "LocalPlaybackState",
                schema: localSchema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitDatabase: localDatabase
            )
            do {
                sharedModelContainer = try ModelContainer(
                    for: schema,
                    configurations: [cloudModelConfiguration, localModelConfiguration]
                )
                logger.info("Database model container", private: localModelConfiguration.url.path)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        } else {
            var modelConfigurations: [ModelConfiguration]?
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
                modelConfigurations = [
                    ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: localDatabase)
                ]
            } else if ProcessInfo.processInfo.arguments.contains("--in-memory-database-only") {
                modelConfigurations = [
                    ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: localDatabase)
                ]
            }
            #endif
            if modelConfigurations == nil {
                modelConfigurations = [
                    ModelConfiguration(
                        "CloudPlaylists",
                        schema: cloudSchema,
                        isStoredInMemoryOnly: isStoredInMemoryOnly,
                        cloudKitDatabase: cloudKitDatabase
                    ),
                    ModelConfiguration(
                        "LocalPlaybackState",
                        schema: localSchema,
                        isStoredInMemoryOnly: isStoredInMemoryOnly,
                        cloudKitDatabase: localDatabase
                    )
                ]
                usesCloudKit = true
            }
            guard let modelConfigurations else {
                fatalError("Could not create ModelContainer.")
            }
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: modelConfigurations)
                if usesCloudKit {
                    logger.info(
                        "CloudKit playlist model container",
                        private: Self.cloudKitContainerIdentifier
                    )
                } else {
                    logger.info("Database model container")
                }
            } catch {
                guard usesCloudKit else {
                    fatalError("Could not create ModelContainer: \(error)")
                }

                logger.error(error)
                logger.info("CloudKit playlist container unavailable. Falling back to local SwiftData stores.")
                let localModelConfigurations = [
                    ModelConfiguration(
                        "CloudPlaylists",
                        schema: cloudSchema,
                        isStoredInMemoryOnly: isStoredInMemoryOnly,
                        cloudKitDatabase: localDatabase
                    ),
                    ModelConfiguration(
                        "LocalPlaybackState",
                        schema: localSchema,
                        isStoredInMemoryOnly: isStoredInMemoryOnly,
                        cloudKitDatabase: localDatabase
                    )
                ]
                do {
                    sharedModelContainer = try ModelContainer(for: schema, configurations: localModelConfigurations)
                    logger.info("Database model container")
                } catch {
                    logger.error(error)
                    logger.info("Local SwiftData store unavailable. Falling back to an in-memory store.")
                    let inMemoryModelConfiguration = ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: localDatabase
                    )
                    do {
                        sharedModelContainer = try ModelContainer(for: schema, configurations: [inMemoryModelConfiguration])
                        logger.info("Database model container", private: inMemoryModelConfiguration.url.path)
                    } catch {
                        fatalError("Could not create ModelContainer: \(error)")
                    }
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
