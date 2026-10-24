//
//  SessionRow.swift
//  FaleAgro LiDAR
//

import SwiftUI

struct SessionRow: View {
    var session: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo)
                .font(.headline)
                .foregroundColor(Color("TextColor"))
            Text(subtitulo)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if let resumo = session.metricsSummary, !resumo.isEmpty {
                Text(resumo)
                    .font(.subheadline)
                    .foregroundColor(Color("TextColor"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(confianca)
                .font(.caption.weight(.semibold))
                .foregroundColor(corConfianca)
        }
        .padding(.vertical, 6)
    }

    private var titulo: String {
        if let fazenda = session.fazenda, let talhao = session.talhao, !fazenda.isEmpty {
            return "\(fazenda) · \(talhao)"
        }
        return session.name ?? "Medição"
    }

    private var subtitulo: String {
        let data = dataTexto
        let modo = nomeModalidade
        let ponto = session.pontoAmostral > 0 ? "ponto \(session.pontoAmostral)" : nil
        return [modo, ponto, data].compactMap { $0 }.joined(separator: " · ")
    }

    private var nomeModalidade: String? {
        guard let raw = session.modalidade, let modality = CaptureModality(rawValue: raw) else { return nil }
        return modality.nome
    }

    private var dataTexto: String {
        guard let created = session.createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: created)
    }

    private var confianca: String {
        let rotulo = TextoBR.rotuloConfianca(session.confidenceScore)
        return "Confiança \(rotulo) (\(TextoBR.numero(session.confidenceScore * 100, casas: 0))%)"
    }

    private var corConfianca: Color {
        if session.confidenceScore >= 0.75 { return Color(red: 0.1, green: 0.4, blue: 0.16) }
        if session.confidenceScore >= 0.45 { return Color(red: 0.55, green: 0.32, blue: 0.05) }
        return Color(red: 0.6, green: 0.15, blue: 0.1)
    }
}
