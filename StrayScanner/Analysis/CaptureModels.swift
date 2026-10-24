// FaleAgro LiDAR — protótipo 1
// Medidas de estrutura do dossel. Sem biomassa e sem calibração.
// Baseado no Stray Scanner (MIT, Stray Robots).

import Foundation

enum CaptureModality: String, Codable, CaseIterable {
    case inferior = "A"
    case lateral = "B"
    case superior = "C"

    var nome: String {
        switch self {
        case .inferior: return "A · Inferior"
        case .lateral: return "B · Lateral 3D"
        case .superior: return "C · Superior"
        }
    }

    var instrucaoCurta: String {
        switch self {
        case .inferior:
            return "Perto do chão, câmera apontando para cima."
        case .lateral:
            return "Ande devagar ao redor de 1 m da linha."
        case .superior:
            return "Acima da copa, câmera apontando para baixo."
        }
    }

    var instrucaoLonga: String {
        switch self {
        case .inferior:
            return "Encoste o celular perto do chão, no meio da linha, com a câmera de trás olhando para o céu através da copa. Fique parado por alguns segundos."
        case .lateral:
            return "Escolha cerca de 1 m de linha. Ande bem devagar ao redor desse trecho, dos dois lados, sem sacudir o celular. O app monta a forma 3D desse pedaço."
        case .superior:
            return "Segure o celular acima da copa, com a câmera olhando para baixo. Tente ver folhas e um pouco de chão entre as plantas. Fique o mais parado que der."
        }
    }
}

struct CaptureMetadata: Codable, Equatable {
    var fazenda: String
    var talhao: String
    var variedade: String
    var dataPlantio: Date
    var tratamento: String
    var pontoAmostral: Int
    var modalidade: CaptureModality
    var escalaConfirmada: Bool

    var tituloCurto: String {
        "\(fazenda) · \(talhao) · P\(pontoAmostral)"
    }
}

enum TrackingQuality: String, Codable {
    case normal
    case limitado
    case perdido
}

enum PointClass: String, Codable {
    case vegetacao
    case solo
    case ceu
    case indefinido
}

struct FrameSample {
    var timestamp: Double
    var rgba: [UInt8]
    var width: Int
    var height: Int
    var depth: [Float]
    var confidence: [UInt8]
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    var transform: [Float]
    var viewDirectionY: Float
    var tracking: TrackingQuality
    var lowConfidenceFraction: Float
    var speedMetersPerSecond: Float
}

struct WorldPoint {
    var position: SIMD3<Float>
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var confidence: UInt8
    var klass: PointClass
    var isFloor: Bool
    var height: Float?
}

struct MeshPoint {
    var position: SIMD3<Float>
    var isFloor: Bool
}

struct WarningTotals {
    var quadrosAvaliados: Int = 0
    var rapidoDemais: Int = 0
    var rastreamentoPerdido: Int = 0
    var rastreamentoLimitado: Int = 0
    var profundidadeBaixa: Int = 0
}

enum AvisoNivel {
    case info
    case atencao
    case grave
}

struct AvisoTela {
    var texto: String
    var nivel: AvisoNivel
}

struct ContextoAvisos {
    var modality: CaptureModality
    var gravando: Bool
    var tracking: TrackingQuality
    var movimentoExcessivoDoARKit: Bool
    var velocidade: Float
    var fracaoProfundidadeBaixa: Float
    var segundosGravando: Float
    var amostrasParaCima: Int
    var amostrasParaBaixo: Int
    var comprimentoPercurso: Float
    var dispersaoLateral: Float
    var verticesMalha: Int
    var amostrasComProfundidade: Int
    var escalaConfirmada: Bool
    var semCenaProfundidade: Bool
}

struct MetricaValor: Codable {
    var nome: String
    var valor: Double?
    var unidade: String
    var confianca: Double
    var rotuloConfianca: String
    var significado: String
}

struct FaixaHistograma: Codable {
    var deCm: Int
    var ateCm: Int
    var fracao: Double
}

struct IdentificacaoRelatorio: Codable {
    var fazenda: String
    var talhao: String
    var variedade: String
    var dataPlantio: Date
    var tratamento: String
    var pontoAmostral: Int
    var modalidade: String
    var modalidadeNome: String
    var escalaConfirmadaManualmente: Bool
    var notaEscala: String
}

struct AvisosRelatorio: Codable {
    var quadrosAvaliados: Int
    var rapidoDemais: Int
    var rastreamentoPerdido: Int
    var rastreamentoLimitado: Int
    var profundidadeBaixa: Int
    var areaIncompletaNoFim: Bool
}

struct CapturaRelatorio: Codable {
    var inicio: Date
    var duracaoSegundos: Double
    var quadrosAmostrados: Int
    var pontosNuvem: Int
    var usouMalhaARKit: Bool
    var verticesMalha: Int
    var fonteNuvem: String
    var avisos: AvisosRelatorio
    var comprimentoPercursoMetros: Double
    var dispersaoLateralMetros: Double
}

struct MetricasRelatorio: Codable {
    var coberturaVegetacaoPct: MetricaValor?
    var soloExpostoPct: MetricaValor?
    var aberturaDosselPct: MetricaValor?
    var indiceFechamento: MetricaValor?
    var alturaMediaCm: MetricaValor?
    var alturaMaximaCm: MetricaValor?
    var larguraAparenteCm: MetricaValor?
    var volumeAparenteM3PorMetro: MetricaValor?
    var planoChaoConfiavel: Bool?
    var comprimentoTrechoMetros: Double?
    var histogramaVertical: [FaixaHistograma]?
    var notaPlanoChao: String?
}

struct RelatorioCaptura: Codable {
    var aplicativo: String
    var estagio: Int
    var versaoFormato: Int
    var avisoGeral: String
    var limitacoes: [String]
    var identificacao: IdentificacaoRelatorio
    var captura: CapturaRelatorio
    var metricas: MetricasRelatorio
    var confiancaGeral: Double
    var rotuloConfiancaGeral: String
    var motivos: [String]
    var resumoLista: String
}

struct AnaliseCompleta {
    var relatorio: RelatorioCaptura
    var nuvem: [WorldPoint]
}

enum FaleAgroTextos {
    static let avisoGeral = "Medidas de estrutura do dossel da soja. Não é biomassa, não é peso e não há calibração agronômica."

    static let notaEscalaSim = "Você marcou que havia uma referência de escala visível. O app não reconhece essa referência sozinho. As distâncias usam a escala métrica do LiDAR e do ARKit."

    static let notaEscalaNao = "Referência de escala não confirmada. As distâncias usam a escala métrica do LiDAR e do ARKit, sem checagem visual."

    static let limitacoes: [String] = [
        "O LiDAR do iPhone não separa folha por folha nem haste fina. Pontos somem ou atravessam folhas estreitas.",
        "A altura é a superfície aparente da copa em relação ao chão, quando o plano do chão fica confiável. Não é a altura de cada planta medida com trena.",
        "O volume aparente é o volume sob essa superfície, em metros cúbicos por metro de linha. Inclui o ar entre as folhas. Não é biomassa e não foi calibrado.",
        "Cobertura, solo exposto, abertura e fechamento vêm da cor (verde em excesso) com ajuda da profundidade. Sombra forte, sol estourado ou céu encoberto mudam os números.",
        "A marcação de referência de escala é manual. O app não detecta a referência sozinho.",
        "Nada neste protótipo estima produtividade, massa seca ou adubo."
    ]
}

enum TextoBR {
    static func numero(_ valor: Double, casas: Int) -> String {
        let negativo = valor < 0
        var magnitude = abs(valor)
        var fator = 1.0
        for _ in 0..<casas { fator *= 10 }
        magnitude = (magnitude * fator).rounded() / fator
        let inteiro = Int(magnitude)
        let sinal = negativo ? "-" : ""
        if casas <= 0 {
            return sinal + String(inteiro)
        }
        var fracao = Int(((magnitude - Double(inteiro)) * fator).rounded())
        var inteiroAjustado = inteiro
        let limite = Int(fator)
        if fracao >= limite {
            fracao = 0
            inteiroAjustado += 1
        }
        var textoFracao = String(fracao)
        while textoFracao.count < casas {
            textoFracao = "0" + textoFracao
        }
        return "\(sinal)\(inteiroAjustado),\(textoFracao)"
    }

    static func rotuloConfianca(_ valor: Double) -> String {
        if valor >= 0.75 { return "alta" }
        if valor >= 0.45 { return "média" }
        return "baixa"
    }
}

enum CaptureFiles {
    static let identificacao = "identificacao.json"
    static let metricas = "metricas.json"
    static let nuvem = "nuvem.ply"
}
