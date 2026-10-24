// FaleAgro LiDAR — protótipo 1
// Avisos de captura. Não bloqueiam a gravação.
// Baseado no Stray Scanner (MIT, Stray Robots).

import Foundation

enum CaptureWarningLogic {
    static func velocidadeLimite(_ modality: CaptureModality) -> Float {
        modality == .lateral ? 0.40 : 0.70
    }

    static func areaIncompleta(
        modality: CaptureModality,
        amostrasParaCima: Int,
        amostrasParaBaixo: Int,
        comprimentoPercurso: Float,
        dispersaoLateral: Float,
        verticesMalha: Int,
        amostrasComProfundidade: Int,
        segundosGravando: Float
    ) -> Bool {
        if segundosGravando < 2 { return true }
        switch modality {
        case .inferior:
            return amostrasParaCima < 8
        case .superior:
            return amostrasParaBaixo < 8
        case .lateral:
            let caminhouEmVolta = comprimentoPercurso >= 2.0 && dispersaoLateral >= 0.25
            let temGeometria = verticesMalha >= 80 || amostrasComProfundidade >= 6
            return !caminhouEmVolta || !temGeometria
        }
    }

    static func mensagens(_ contexto: ContextoAvisos) -> [AvisoTela] {
        var avisos: [AvisoTela] = []
        if contexto.semCenaProfundidade {
            avisos.append(AvisoTela(texto: "Sem profundidade LiDAR neste quadro.", nivel: .grave))
        }
        switch contexto.tracking {
        case .perdido:
            avisos.append(AvisoTela(texto: "Rastreamento perdido. Aponte para a lavoura e mova devagar.", nivel: .grave))
        case .limitado:
            avisos.append(AvisoTela(texto: "Rastreamento limitado. Vá mais devagar e mostre o chão e as plantas.", nivel: .atencao))
        case .normal:
            break
        }
        let limite = velocidadeLimite(contexto.modality)
        if contexto.movimentoExcessivoDoARKit || contexto.velocidade > limite {
            avisos.append(AvisoTela(texto: "Muito rápido. Mova o celular mais devagar.", nivel: .grave))
        }
        if contexto.fracaoProfundidadeBaixa > 0.45 {
            avisos.append(AvisoTela(texto: "Confiança da profundidade baixa. Chegue um pouco mais perto e evite reflexo forte no sensor.", nivel: .atencao))
        }
        if contexto.gravando {
            let incompleta = areaIncompleta(
                modality: contexto.modality,
                amostrasParaCima: contexto.amostrasParaCima,
                amostrasParaBaixo: contexto.amostrasParaBaixo,
                comprimentoPercurso: contexto.comprimentoPercurso,
                dispersaoLateral: contexto.dispersaoLateral,
                verticesMalha: contexto.verticesMalha,
                amostrasComProfundidade: contexto.amostrasComProfundidade,
                segundosGravando: contexto.segundosGravando
            )
            if incompleta {
                let detalhe: String
                switch contexto.modality {
                case .inferior:
                    detalhe = "Área incompleta. Segure parado, com a câmera para cima, por mais alguns segundos."
                case .superior:
                    detalhe = "Área incompleta. Segure parado, com a câmera para baixo, vendo copa e um pouco de chão."
                case .lateral:
                    detalhe = "Área incompleta. Ande devagar ao redor de 1 m da linha, dos dois lados."
                }
                avisos.append(AvisoTela(texto: detalhe, nivel: .atencao))
            }
        } else {
            switch contexto.modality {
            case .inferior where contexto.tracking == .normal:
                if contexto.amostrasParaCima == 0 {
                    avisos.append(AvisoTela(texto: "Antes de gravar: câmera para cima, perto do chão.", nivel: .info))
                }
            case .superior where contexto.tracking == .normal:
                avisos.append(AvisoTela(texto: "Antes de gravar: câmera para baixo, acima da copa.", nivel: .info))
            case .lateral:
                avisos.append(AvisoTela(texto: "Antes de gravar: prepare 1 m de linha para caminhar ao redor.", nivel: .info))
            default:
                break
            }
        }
        if !contexto.escalaConfirmada {
            avisos.append(AvisoTela(texto: "Referência de escala não confirmada. A marcação é manual.", nivel: .info))
        }
        return avisos
    }
}
