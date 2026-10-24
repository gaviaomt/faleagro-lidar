//
//  ShareUtility.swift
//  StrayScanner
//
//  Created by Claude on 6/24/25.
//

import Foundation

/// Utility class for creating shareable archives from recording datasets
class ShareUtility {
    
    /// Creates a shareable ZIP archive from a recording's dataset
    /// - Parameter recording: The recording to create a ZIP archive for
    /// - Returns: URL of the created ZIP file
    static func createShareableArchive(for recording: Recording) async throws -> URL {
        guard let sourceDirectory = recording.directoryPath() else {
            throw NSError(domain: "ShareError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Não achei a pasta desta medição."])
        }
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let archiveURL = tempDirectory.appendingPathComponent("FaleAgro_\(suggestedName(for: recording)).zip")
        
        // Remove existing archive if it exists
        try? FileManager.default.removeItem(at: archiveURL)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try createZipArchive(sourceDirectory: sourceDirectory, destinationURL: archiveURL)
                    continuation.resume(returning: archiveURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private static func createZipArchive(sourceDirectory: URL, destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: sourceDirectory, options: [.forUploading], error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let error = coordinatorError ?? copyError {
            throw error
        }
    }

    private static func suggestedName(for recording: Recording) -> String {
        let raw = recording.name ?? "medicao"
        let folded = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
        var output = ""
        var lastUnderscore = false
        for scalar in folded.unicodeScalars {
            let value = scalar.value
            let isLetterOrDigit = (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
            if isLetterOrDigit {
                output.unicodeScalars.append(scalar)
                lastUnderscore = false
            } else if !lastUnderscore && !output.isEmpty {
                output.append("_")
                lastUnderscore = true
            }
        }
        while output.last == "_" { output.removeLast() }
        let clipped = String(output.prefix(40))
        return clipped.isEmpty ? "medicao" : clipped
    }
}
