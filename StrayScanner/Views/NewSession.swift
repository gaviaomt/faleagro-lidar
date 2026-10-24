//
//  NewSession.swift
//  FaleAgro LiDAR
//

import SwiftUI

private enum FormMemory {
    private static let key = "FaleAgroUltimaFicha"

    static func load() -> (fazenda: String, talhao: String, variedade: String, tratamento: String, ponto: Int, modalidade: CaptureModality, data: Date) {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else {
            return ("", "", "", "", 1, .superior, Date())
        }
        return (saved.fazenda, saved.talhao, saved.variedade, saved.tratamento, saved.ponto, saved.modalidade, saved.dataPlantio)
    }

    static func save(fazenda: String, talhao: String, variedade: String, tratamento: String, ponto: Int, modalidade: CaptureModality, data: Date) {
        let saved = Saved(fazenda: fazenda, talhao: talhao, variedade: variedade, tratamento: tratamento, ponto: ponto, modalidade: modalidade, dataPlantio: data)
        if let encoded = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    private struct Saved: Codable {
        var fazenda: String
        var talhao: String
        var variedade: String
        var tratamento: String
        var ponto: Int
        var modalidade: CaptureModality
        var dataPlantio: Date
    }
}

struct RecordSessionManager: UIViewControllerRepresentable {
    var metadata: CaptureMetadata
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> RecordSessionViewController {
        let viewController = RecordSessionViewController(nibName: "RecordSessionView", bundle: nil)
        viewController.metadata = metadata
        viewController.setDismissFunction {
            dismiss()
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: RecordSessionViewController, context: Context) {}
}

struct NewSessionView: View {
    @State private var fazenda: String
    @State private var talhao: String
    @State private var variedade: String
    @State private var tratamento: String
    @State private var dataPlantio: Date
    @State private var ponto: Int
    @State private var modalidade: CaptureModality
    @State private var escalaConfirmada = false
    @State private var irParaCaptura = false

    init() {
        let saved = FormMemory.load()
        _fazenda = State(initialValue: saved.fazenda)
        _talhao = State(initialValue: saved.talhao)
        _variedade = State(initialValue: saved.variedade)
        _tratamento = State(initialValue: saved.tratamento)
        _dataPlantio = State(initialValue: min(saved.data, Date()))
        _ponto = State(initialValue: (1...5).contains(saved.ponto) ? saved.ponto : 1)
        _modalidade = State(initialValue: saved.modalidade)
    }

    private var fichaPronta: Bool {
        !fazenda.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !talhao.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !variedade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !tratamento.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (1...5).contains(ponto)
    }

    var body: some View {
        Form {
            Section(header: Text("Onde é a medição")) {
                TextField("Fazenda", text: $fazenda)
                TextField("Talhão", text: $talhao)
                TextField("Variedade", text: $variedade)
                DatePicker("Data de plantio", selection: $dataPlantio, in: ...Date(), displayedComponents: .date)
                TextField("Tratamento", text: $tratamento)
            }
            Section(header: Text("Ponto amostral"), footer: Text("Use o mesmo ponto quando repetir a medição nesse lugar.")) {
                Picker("Ponto amostral", selection: $ponto) {
                    ForEach(1...5, id: \.self) { numero in
                        Text("\(numero)").tag(numero)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(header: Text("Como vai medir")) {
                ForEach(CaptureModality.allCases, id: \.self) { item in
                    Button(action: { modalidade = item }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: modalidade == item ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(Color(red: 0.12, green: 0.38, blue: 0.18))
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.nome)
                                    .font(.headline)
                                    .foregroundColor(Color("TextColor"))
                                Text(item.instrucaoLonga)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section(footer: Text("Por enquanto esta marcação é manual. O app não procura a referência sozinho e não calibra biomassa.")) {
                Toggle("Vi uma referência de escala na cena", isOn: $escalaConfirmada)
            }
            Section {
                Text("As medidas são de estrutura do dossel. O app não calcula biomassa e não estima peso.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .environment(\.locale, Locale(identifier: "pt_BR"))
        .navigationTitle("Nova medição")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: comecar) {
                Text("Começar captura")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(fichaPronta ? Color(red: 0.12, green: 0.38, blue: 0.18) : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .disabled(!fichaPronta)
        }
        .navigationDestination(isPresented: $irParaCaptura) {
            RecordSessionManager(metadata: rascunho())
                .ignoresSafeArea()
                .navigationTitle(modalidade.nome)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func rascunho() -> CaptureMetadata {
        CaptureMetadata(
            fazenda: fazenda.trimmingCharacters(in: .whitespacesAndNewlines),
            talhao: talhao.trimmingCharacters(in: .whitespacesAndNewlines),
            variedade: variedade.trimmingCharacters(in: .whitespacesAndNewlines),
            dataPlantio: dataPlantio,
            tratamento: tratamento.trimmingCharacters(in: .whitespacesAndNewlines),
            pontoAmostral: ponto,
            modalidade: modalidade,
            escalaConfirmada: escalaConfirmada
        )
    }

    private func comecar() {
        guard fichaPronta else { return }
        FormMemory.save(
            fazenda: fazenda.trimmingCharacters(in: .whitespacesAndNewlines),
            talhao: talhao.trimmingCharacters(in: .whitespacesAndNewlines),
            variedade: variedade.trimmingCharacters(in: .whitespacesAndNewlines),
            tratamento: tratamento.trimmingCharacters(in: .whitespacesAndNewlines),
            ponto: ponto,
            modalidade: modalidade,
            data: dataPlantio
        )
        irParaCaptura = true
    }
}
