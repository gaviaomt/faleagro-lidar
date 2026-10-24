//
//  SessionDetail.swift
//  FaleAgro LiDAR
//

import AVKit
import CoreData
import SwiftUI

class SessionDetailViewModel: ObservableObject {
    private var dataContext: NSManagedObjectContext?

    init() {
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        dataContext = appDelegate?.persistentContainer.viewContext
    }

    func delete(recording: Recording) {
        recording.deleteFiles()
        dataContext?.delete(recording)
        do {
            try dataContext?.save()
        } catch {
            print("Could not delete recording. \(error)")
        }
    }
}

struct SessionDetailView: View {
    @ObservedObject var viewModel = SessionDetailViewModel()
    var recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var tempPackageURL: URL?
    @State private var isCreatingPackage = false
    @State private var player: AVPlayer?
    @State private var shareError: String?
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cabecalho
                if let relatorio {
                    confiancaBloco(relatorio)
                    metricasBloco(relatorio)
                    if let faixas = relatorio.metricas.histogramaVertical, !faixas.isEmpty {
                        histogramaBloco(faixas)
                    }
                    if !relatorio.motivos.isEmpty {
                        bloco(titulo: "Por que a confiança é essa", linhas: relatorio.motivos)
                    }
                    bloco(titulo: "Limitações", linhas: relatorio.limitacoes)
                } else {
                    Text(recording.metricsSummary ?? "Esta medição não tem números calculados.")
                        .foregroundColor(Color("TextColor"))
                }
                video
                botoes
            }
            .padding(16)
        }
        .background(Color("BackgroundColor").ignoresSafeArea())
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingShareSheet) {
            if let packageURL = tempPackageURL {
                ShareSheet(activityItems: [packageURL]) { _, _, _, _ in
                    DispatchQueue.main.async {
                        try? FileManager.default.removeItem(at: packageURL)
                        tempPackageURL = nil
                        showingShareSheet = false
                    }
                }
            }
        }
        .alert("Não deu para exportar", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
        .alert("Apagar esta medição?", isPresented: $confirmDelete) {
            Button("Apagar", role: .destructive) {
                viewModel.delete(recording: recording)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("A pasta da captura sai deste iPhone.")
        }
    }

    private var titulo: String {
        if let fazenda = recording.fazenda, !fazenda.isEmpty {
            return fazenda
        }
        return "Medição"
    }

    private var relatorio: RelatorioCaptura? {
        guard let json = recording.metricsJSON, let data = json.data(using: .utf8) else { return nil }
        return try? ReportFiles.jsonDecoder().decode(RelatorioCaptura.self, from: data)
    }

    private var cabecalho: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(linhaIdentificacao)
                .font(.title3.weight(.semibold))
                .foregroundColor(Color("TextColor"))
            if let variedade = recording.variedade, !variedade.isEmpty {
                Text("Variedade \(variedade)")
            }
            if let tratamento = recording.tratamento, !tratamento.isEmpty {
                Text("Tratamento \(tratamento)")
            }
            if let plantio = recording.dataPlantio {
                Text("Plantio \(dataCurta(plantio))")
            }
            Text(dataLonga)
            Text(recording.escalaConfirmada ? "Referência de escala marcada manualmente." : "Referência de escala não confirmada.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .foregroundColor(Color("TextColor"))
    }

    private var linhaIdentificacao: String {
        let modo = recording.modalidade.flatMap { CaptureModality(rawValue: $0)?.nome } ?? "Medição"
        let ponto = recording.pontoAmostral > 0 ? "ponto \(recording.pontoAmostral)" : ""
        let talhao = recording.talhao.map { "talhão \($0)" } ?? ""
        return [modo, talhao, ponto].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func confiancaBloco(_ relatorio: RelatorioCaptura) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Confiança \(relatorio.rotuloConfiancaGeral)")
                .font(.headline)
            Text(relatorio.avisoGeral)
                .font(.subheadline)
        }
        .foregroundColor(Color("TextColor"))
    }

    private func metricasBloco(_ relatorio: RelatorioCaptura) -> some View {
        let itens = [
            relatorio.metricas.coberturaVegetacaoPct,
            relatorio.metricas.soloExpostoPct,
            relatorio.metricas.aberturaDosselPct,
            relatorio.metricas.indiceFechamento,
            relatorio.metricas.alturaMediaCm,
            relatorio.metricas.alturaMaximaCm,
            relatorio.metricas.larguraAparenteCm,
            relatorio.metricas.volumeAparenteM3PorMetro
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Medidas")
                .font(.headline)
                .foregroundColor(Color("TextColor"))
            if let nota = relatorio.metricas.notaPlanoChao {
                Text(nota)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(Array(itens.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.nome)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(valor(item))
                            .font(.body.weight(.semibold))
                    }
                    Text("Confiança \(item.rotuloConfianca)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.significado)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(Color("TextColor"))
            }
        }
    }

    private func histogramaBloco(_ faixas: [FaixaHistograma]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Distribuição vertical")
                .font(.headline)
            Text("Cada barra é a fração dos pontos da copa naquela faixa de altura. Não são folhas contadas.")
                .font(.footnote)
                .foregroundColor(.secondary)
            ForEach(faixas.filter { $0.fracao > 0.005 }, id: \.deCm) { faixa in
                HStack {
                    Text("\(faixa.deCm)–\(faixa.ateCm) cm")
                        .font(.caption)
                        .frame(width: 78, alignment: .leading)
                    Text(String(repeating: "█", count: max(1, Int((faixa.fracao * 16).rounded()))))
                        .font(.caption)
                        .foregroundColor(Color(red: 0.12, green: 0.38, blue: 0.18))
                    Text(TextoBR.numero(faixa.fracao * 100, casas: 0) + "%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .foregroundColor(Color("TextColor"))
    }

    private func bloco(titulo: String, linhas: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .font(.headline)
            ForEach(Array(linhas.enumerated()), id: \.offset) { _, linha in
                Text("• \(linha)")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(Color("TextColor"))
    }

    private var video: some View {
        VideoPlayer(player: player)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                if player == nil, let url = recording.absoluteRgbPath() {
                    player = AVPlayer(url: url)
                }
            }
    }

    private var botoes: some View {
        VStack(spacing: 12) {
            Button(action: shareItem) {
                HStack {
                    if isCreatingPackage {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isCreatingPackage ? "Preparando arquivo…" : "Exportar JSON e PLY")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.12, green: 0.38, blue: 0.18))
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(isCreatingPackage)
            Text("O arquivo leva metricas.json, nuvem.ply e a captura bruta (vídeo, profundidade, pose). Dá para mandar por AirDrop ou salvar nos Arquivos, sem internet se o destino for o próprio iPhone.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Button(action: { confirmDelete = true }) {
                Text("Apagar medição")
                    .foregroundColor(Color("DangerColor"))
            }
        }
    }

    private func valor(_ item: MetricaValor) -> String {
        guard let numero = item.valor else { return "não calculada" }
        let casas = item.unidade == "0 a 1" || item.unidade == "m³/m" ? 2 : 0
        return TextoBR.numero(numero, casas: casas) + " " + item.unidade
    }

    private func dataCurta(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var dataLonga: String {
        guard let created = recording.createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        let duracao = Int(recording.duration.rounded())
        return "\(formatter.string(from: created)) · \(duracao) s"
    }

    private func shareItem() {
        isCreatingPackage = true
        Task {
            do {
                let packageURL = try await ShareUtility.createShareableArchive(for: recording)
                await MainActor.run {
                    tempPackageURL = packageURL
                    isCreatingPackage = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isCreatingPackage = false
                    shareError = "Não consegui montar o arquivo para compartilhar. \(error.localizedDescription)"
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    let completionWithItemsHandler: UIActivityViewController.CompletionWithItemsHandler?

    init(activityItems: [Any], completionHandler: UIActivityViewController.CompletionWithItemsHandler? = nil) {
        self.activityItems = activityItems
        self.completionWithItemsHandler = completionHandler
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.completionWithItemsHandler = completionWithItemsHandler
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
