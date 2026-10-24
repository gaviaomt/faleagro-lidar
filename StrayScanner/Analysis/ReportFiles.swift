// FaleAgro LiDAR — protótipo 1
// Grava metricas.json e a nuvem PLY ao lado da captura bruta.
// Baseado no Stray Scanner (MIT, Stray Robots).

import Foundation

enum ReportFiles {
    static func writeIdentificacao(_ metadata: CaptureMetadata, to directory: URL) throws {
        let encoder = jsonEncoder()
        let data = try encoder.encode(metadata)
        try data.write(to: directory.appendingPathComponent(CaptureFiles.identificacao), options: .atomic)
    }

    static func writeRelatorio(_ relatorio: RelatorioCaptura, to directory: URL) throws {
        let encoder = jsonEncoder()
        let data = try encoder.encode(relatorio)
        try data.write(to: directory.appendingPathComponent(CaptureFiles.metricas), options: .atomic)
    }

    static func writePLY(_ points: [WorldPoint], to directory: URL) throws {
        let limited = points.count > 80000 ? Array(points.prefix(80000)) : points
        var header = "ply\n"
        header += "format binary_little_endian 1.0\n"
        header += "comment FaleAgro LiDAR estagio 1\n"
        header += "comment Coordenadas em metros. Eixo Y para cima. Origem no inicio da sessao ARKit, nao e GPS.\n"
        header += "comment Nao e biomassa. O LiDAR nao separa folhas individuais nem hastes finas.\n"
        header += "comment O volume aparente esta em metricas.json, nao neste arquivo.\n"
        header += "element vertex \(limited.count)\n"
        header += "property float x\n"
        header += "property float y\n"
        header += "property float z\n"
        header += "property uchar red\n"
        header += "property uchar green\n"
        header += "property uchar blue\n"
        header += "end_header\n"
        var data = Data(header.utf8)
        data.reserveCapacity(data.count + limited.count * 15)
        for point in limited {
            let color = cor(point)
            appendFloat(point.position.x, to: &data)
            appendFloat(point.position.y, to: &data)
            appendFloat(point.position.z, to: &data)
            data.append(color.0)
            data.append(color.1)
            data.append(color.2)
        }
        try data.write(to: directory.appendingPathComponent(CaptureFiles.nuvem), options: .atomic)
    }

    static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func appendFloat(_ value: Float, to data: inout Data) {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { raw in
            data.append(contentsOf: raw)
        }
    }

    private static func cor(_ point: WorldPoint) -> (UInt8, UInt8, UInt8) {
        guard let height = point.height, height.isFinite else {
            switch point.klass {
            case .vegetacao: return (point.red, point.green, point.blue)
            case .solo: return (140, 96, 48)
            case .ceu: return (150, 180, 220)
            case .indefinido: return (point.red, point.green, point.blue)
            }
        }
        let t = min(1, max(0, height / 1.2))
        let red = UInt8(140 * (1 - t) + 36 * t)
        let green = UInt8(90 * (1 - t) + 150 * t)
        let blue = UInt8(40 * (1 - t) + 48 * t)
        return (red, green, blue)
    }
}
