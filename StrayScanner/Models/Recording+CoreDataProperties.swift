//
//  Recording+CoreDataProperties.swift
//  StrayScanner
//
//  Created by Kenneth Blomqvist on 12/30/20.
//  Copyright © 2020 Stray Robots. All rights reserved.
//
//

import Foundation
import CoreData


extension Recording {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Recording> {
        return NSFetchRequest<Recording>(entityName: "Recording")
    }

    @NSManaged public var createdAt: Date?
    @NSManaged public var duration: Double
    @NSManaged public var name: String?
    @NSManaged public var id: UUID?
    @NSManaged public var rgbFilePath: String?
    @NSManaged public var depthFilePath: String?
    @NSManaged public var fazenda: String?
    @NSManaged public var talhao: String?
    @NSManaged public var variedade: String?
    @NSManaged public var dataPlantio: Date?
    @NSManaged public var tratamento: String?
    @NSManaged public var pontoAmostral: Int16
    @NSManaged public var modalidade: String?
    @NSManaged public var metricsSummary: String?
    @NSManaged public var metricsJSON: String?
    @NSManaged public var confidenceScore: Double
    @NSManaged public var escalaConfirmada: Bool

    func directoryPath() -> URL? {
        if let path = self.rgbFilePath {
            let rgb = URL(fileURLWithPath: path, relativeTo: pathsRelativeTo())
            return rgb.deletingLastPathComponent()
        }
        return Optional.none
    }
    
    func absoluteRgbPath() -> URL? {
        if let path = self.rgbFilePath {
            return URL(fileURLWithPath: path, relativeTo: pathsRelativeTo())
        }
        return Optional.none
    }

    func absoluteDepthPath() -> URL? {
        if let path = self.depthFilePath {
            return URL(fileURLWithPath: path, relativeTo: pathsRelativeTo())
        }
        return Optional.none
    }

    private func pathsRelativeTo() -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

extension Recording : Identifiable {

}
