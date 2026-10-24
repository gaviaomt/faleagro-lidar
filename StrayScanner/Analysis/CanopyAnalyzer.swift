// FaleAgro LiDAR — protótipo 1
// Junta os quadros da captura nas medidas mostradas ao agricultor.
// Baseado no Stray Scanner (MIT, Stray Robots).

import Foundation

enum CanopyAnalyzer {
    static func analisar(
        metadata: CaptureMetadata,
        startedAt: Date,
        duration: TimeInterval,
        samples: [FrameSample],
        meshPoints: [MeshPoint],
        path: [SIMD3<Float>],
        warnings: WarningTotals,
        meshVertexCount: Int
    ) -> AnaliseCompleta {
        let oriented = samples.filter { orientacaoCorreta($0, modality: metadata.modalidade) }
        let usados = oriented.count >= 3 ? oriented : samples
        let orientacaoFraca = oriented.count < 3 && !samples.isEmpty

        var contagens: [ContagemImagem] = []
        var pontosProfundidade: [WorldPoint] = []
        var limiarFixo = 0
        for sample in usados {
            let contagem = CanopyMath.analyzeFrame(sample, modality: metadata.modalidade, cloudStride: 3)
            contagens.append(contagem)
            pontosProfundidade.append(contentsOf: contagem.pontos)
            if contagem.usouLimiarFixo { limiarFixo += 1 }
        }

        var nuvem = pontosProfundidade
        let usouMalha = meshVertexCount >= 80 && metadata.modalidade == .lateral
        if metadata.modalidade == .lateral {
            for meshPoint in meshPoints {
                nuvem.append(WorldPoint(
                    position: meshPoint.position,
                    red: 170,
                    green: 170,
                    blue: 160,
                    confidence: 2,
                    klass: .indefinido,
                    isFloor: meshPoint.isFloor,
                    height: nil
                ))
            }
        }
        nuvem = CanopyMath.voxelDownsample(nuvem, voxel: 0.02)
        if nuvem.count > 80000 {
            nuvem = CanopyMath.voxelDownsample(nuvem, voxel: 0.035)
        }

        let stats = CanopyMath.pathStats(path)
        let amostrasCima = samples.filter { $0.viewDirectionY > 0.55 }.count
        let amostrasBaixo = samples.filter { $0.viewDirectionY < -0.55 }.count
        let amostrasProfundidade = samples.filter { $0.lowConfidenceFraction < 0.55 && $0.depth.contains(where: { $0.isFinite }) }.count
        let incompleta = CaptureWarningLogic.areaIncompleta(
            modality: metadata.modalidade,
            amostrasParaCima: amostrasCima,
            amostrasParaBaixo: amostrasBaixo,
            comprimentoPercurso: stats.length,
            dispersaoLateral: stats.lateralSpread,
            verticesMalha: meshVertexCount,
            amostrasComProfundidade: amostrasProfundidade,
            segundosGravando: Float(duration)
        )

        var motivos: [String] = []
        if samples.count < 5 {
            motivos.append("Poucos quadros úteis. Grave por mais tempo, devagar.")
        }
        if orientacaoFraca {
            motivos.append("O celular não ficou na orientação pedida na maior parte da captura.")
        }
        if incompleta {
            motivos.append("A área ficou incompleta para esta modalidade.")
        }
        if warnings.quadrosAvaliados > 0 {
            let pressa = Double(warnings.rapidoDemais) / Double(warnings.quadrosAvaliados)
            let rastreioRuim = Double(warnings.rastreamentoPerdido + warnings.rastreamentoLimitado) / Double(warnings.quadrosAvaliados)
            let profundidadeRuim = Double(warnings.profundidadeBaixa) / Double(warnings.quadrosAvaliados)
            if pressa > 0.2 {
                motivos.append("Houve movimento rápido demais em parte da captura.")
            }
            if rastreioRuim > 0.3 {
                motivos.append("O rastreamento ficou limitado ou perdido em parte do tempo.")
            }
            if profundidadeRuim > 0.3 {
                motivos.append("Muitos quadros com profundidade de confiança baixa.")
            }
        }
        if !metadata.escalaConfirmada {
            motivos.append(FaleAgroTextos.notaEscalaNao)
        }
        if limiarFixo > contagens.count / 2 && !contagens.isEmpty {
            motivos.append("A cena estava uniforme e o corte de verde usou um limiar fixo, não só o automático.")
        }
        if metadata.modalidade == .lateral && meshVertexCount < 80 {
            motivos.append("A malha 3D do ARKit ficou pequena. A nuvem usa principalmente a profundidade acumulada.")
        }

        let penalidade = penalidadeGlobal(samples: samples, warnings: warnings, incompleta: incompleta, escala: metadata.escalaConfirmada)
        let qualidadeBase = qualidade(
            samples: usados,
            warnings: warnings,
            orientacaoFraca: orientacaoFraca
        )

        var metricas = MetricasRelatorio()
        switch metadata.modalidade {
        case .superior:
            preencherSuperior(&metricas, contagens: contagens, pontos: pontosProfundidade, qualidade: qualidadeBase, penalidade: penalidade, motivos: &motivos)
        case .inferior:
            preencherInferior(&metricas, contagens: contagens, qualidade: qualidadeBase, penalidade: penalidade, motivos: &motivos)
        case .lateral:
            preencherLateral(&metricas, nuvem: nuvem, meshPoints: meshPoints, path: path, qualidade: qualidadeBase, penalidade: penalidade, motivos: &motivos)
        }

        let produzidas = confiancasProduzidas(metricas)
        var geral = produzidas.min() ?? 0.2
        if produzidas.isEmpty { geral = min(geral, 0.25) }
        if metricasFaltando(metadata.modalidade, metricas) {
            geral = min(geral, 0.35)
            motivos.append("Uma medida pedida não pôde ser calculada. O número ausente não foi inventado.")
        }
        geral = min(1, max(0, geral))

        let fonte: String
        if usouMalha && !pontosProfundidade.isEmpty {
            fonte = "Malha do ARKit mais profundidade acumulada do LiDAR."
        } else if usouMalha {
            fonte = "Malha do ARKit."
        } else {
            fonte = "Profundidade acumulada do LiDAR."
        }

        let relatorio = RelatorioCaptura(
            aplicativo: "FaleAgro LiDAR",
            estagio: 1,
            versaoFormato: 1,
            avisoGeral: FaleAgroTextos.avisoGeral,
            limitacoes: FaleAgroTextos.limitacoes,
            identificacao: IdentificacaoRelatorio(
                fazenda: metadata.fazenda,
                talhao: metadata.talhao,
                variedade: metadata.variedade,
                dataPlantio: metadata.dataPlantio,
                tratamento: metadata.tratamento,
                pontoAmostral: metadata.pontoAmostral,
                modalidade: metadata.modalidade.rawValue,
                modalidadeNome: metadata.modalidade.nome,
                escalaConfirmadaManualmente: metadata.escalaConfirmada,
                notaEscala: metadata.escalaConfirmada ? FaleAgroTextos.notaEscalaSim : FaleAgroTextos.notaEscalaNao
            ),
            captura: CapturaRelatorio(
                inicio: startedAt,
                duracaoSegundos: duration,
                quadrosAmostrados: samples.count,
                pontosNuvem: nuvem.count,
                usouMalhaARKit: usouMalha,
                verticesMalha: meshVertexCount,
                fonteNuvem: fonte,
                avisos: AvisosRelatorio(
                    quadrosAvaliados: warnings.quadrosAvaliados,
                    rapidoDemais: warnings.rapidoDemais,
                    rastreamentoPerdido: warnings.rastreamentoPerdido,
                    rastreamentoLimitado: warnings.rastreamentoLimitado,
                    profundidadeBaixa: warnings.profundidadeBaixa,
                    areaIncompletaNoFim: incompleta
                ),
                comprimentoPercursoMetros: Double(stats.length),
                dispersaoLateralMetros: Double(stats.lateralSpread)
            ),
            metricas: metricas,
            confiancaGeral: geral,
            rotuloConfiancaGeral: TextoBR.rotuloConfianca(geral),
            motivos: motivos,
            resumoLista: resumo(metadata.modalidade, metricas)
        )
        return AnaliseCompleta(relatorio: relatorio, nuvem: nuvem)
    }

    private static func orientacaoCorreta(_ sample: FrameSample, modality: CaptureModality) -> Bool {
        switch modality {
        case .inferior: return sample.viewDirectionY > 0.55
        case .superior: return sample.viewDirectionY < -0.55
        case .lateral: return true
        }
    }

    private static func preencherSuperior(
        _ metricas: inout MetricasRelatorio,
        contagens: [ContagemImagem],
        pontos: [WorldPoint],
        qualidade: Double,
        penalidade: Double,
        motivos: inout [String]
    ) {
        guard !contagens.isEmpty else { return }
        let total = contagens.reduce(0) { $0 + $1.total }
        let veg = contagens.reduce(0) { $0 + $1.vegetacao }
        let solo = contagens.reduce(0) { $0 + $1.solo }
        let indefinido = contagens.reduce(0) { $0 + $1.indefinido }
        let eta = contagens.reduce(Float(0)) { $0 + $1.eta } / Float(contagens.count)
        let cobertura = total > 0 ? Double(veg) / Double(total) * 100 : 0
        let soloPct = total > 0 ? Double(solo) / Double(total) * 100 : 0
        let fracaoIndefinida = total > 0 ? Double(indefinido) / Double(total) : 1
        let separacao = min(1, Double(eta) / 0.35)
        let confiancaCor = combinar([
            (separacao, 0.35),
            (1 - fracaoIndefinida, 0.25),
            (qualidade, 0.40)
        ]) * penalidade

        metricas.coberturaVegetacaoPct = metrica(
            nome: "Cobertura de vegetação",
            valor: cobertura,
            unidade: "%",
            confianca: confiancaCor,
            significado: "Parte da imagem, vista de cima, classificada como vegetação pelo verde em excesso, com ajuda da profundidade."
        )
        metricas.soloExpostoPct = metrica(
            nome: "Solo exposto",
            valor: soloPct,
            unidade: "%",
            confianca: confiancaCor * (fracaoIndefinida > 0.45 ? 0.75 : 1),
            significado: "Parte da imagem que parece chão à mostra, não folha. Sombra escura fica de fora e entra como indefinido."
        )

        let soloPontos = pontos.filter { $0.klass == .solo }.map { $0.position }
        let copaPontos = pontos.filter { $0.klass == .vegetacao }.map { $0.position }
        let altura = CanopyMath.measureHeights(canopy: copaPontos, floorPoints: soloPontos, fallbackPoints: pontos.map { $0.position })
        metricas.planoChaoConfiavel = altura.fit?.reliable ?? false
        if let fit = altura.fit, fit.reliable, let media = altura.mediaM, let maxima = altura.maximaM {
            let confiancaAltura = combinar([
                (Double(planoScore(fit)), 0.55),
                (qualidade, 0.30),
                (min(1, Double(altura.pontosCopa) / 80), 0.15)
            ]) * penalidade
            metricas.alturaMediaCm = metrica(
                nome: "Altura média do dossel",
                valor: Double(media * 100),
                unidade: "cm",
                confianca: confiancaAltura,
                significado: "Altura aparente da superfície da copa acima do plano do chão. Não é trena em cada planta."
            )
            metricas.alturaMaximaCm = metrica(
                nome: "Altura máxima do dossel",
                valor: Double(maxima * 100),
                unidade: "cm",
                confianca: confiancaAltura,
                significado: "Maior altura aparente da copa no que foi visto de cima, depois de ignorar picos isolados do sensor."
            )
            metricas.notaPlanoChao = "Plano do chão usado. Normal para cima \(TextoBR.numero(Double(fit.normalY), casas: 2)), resíduo \(TextoBR.numero(Double(fit.rms * 100), casas: 1)) cm."
        } else {
            metricas.alturaMediaCm = metrica(
                nome: "Altura média do dossel",
                valor: nil,
                unidade: "cm",
                confianca: 0.2 * penalidade,
                significado: "Não calculada: o plano do chão não ficou confiável ou havia pouca copa com profundidade."
            )
            metricas.alturaMaximaCm = metrica(
                nome: "Altura máxima do dossel",
                valor: nil,
                unidade: "cm",
                confianca: 0.2 * penalidade,
                significado: "Não calculada junto com a altura média."
            )
            metricas.notaPlanoChao = "Altura omitida de propósito. O chão não ficou confiável o bastante para virar um número."
            motivos.append("Altura do dossel omitida: o plano do chão não ficou confiável.")
        }
    }

    private static func preencherInferior(
        _ metricas: inout MetricasRelatorio,
        contagens: [ContagemImagem],
        qualidade: Double,
        penalidade: Double,
        motivos: inout [String]
    ) {
        guard !contagens.isEmpty else { return }
        let total = contagens.reduce(0) { $0 + $1.total }
        let veg = contagens.reduce(0) { $0 + $1.vegetacao }
        let ceu = contagens.reduce(0) { $0 + $1.ceu }
        let indefinido = contagens.reduce(0) { $0 + $1.indefinido }
        let eta = contagens.reduce(Float(0)) { $0 + $1.eta } / Float(contagens.count)
        let abertura = total > 0 ? Double(ceu) / Double(total) * 100 : 0
        let base = veg + ceu
        let fechamento = base > 0 ? Double(veg) / Double(base) : nil
        let fracaoIndefinida = total > 0 ? Double(indefinido) / Double(total) : 1
        var confianca = combinar([
            (min(1, Double(eta) / 0.25 + 0.35), 0.30),
            (1 - fracaoIndefinida, 0.30),
            (qualidade, 0.40)
        ]) * penalidade
        if base < total / 5 {
            confianca *= 0.6
            motivos.append("Poucos pixels claros de céu ou de folha. A abertura pode estar instável.")
        }
        metricas.aberturaDosselPct = metrica(
            nome: "Abertura do dossel",
            valor: abertura,
            unidade: "%",
            confianca: confianca,
            significado: "Fração da imagem, olhando de baixo, que parece céu. É a fração de céu visível, não um mapa de cada folha."
        )
        metricas.indiceFechamento = metrica(
            nome: "Índice de fechamento",
            valor: fechamento,
            unidade: "0 a 1",
            confianca: fechamento == nil ? 0.2 * penalidade : confianca,
            significado: "Folhas divididas por folhas mais céu. Perto de 1 a copa está fechada. Ignora pixels indefinidos, e a confiança cai se eles forem muitos."
        )
    }

    private static func preencherLateral(
        _ metricas: inout MetricasRelatorio,
        nuvem: [WorldPoint],
        meshPoints: [MeshPoint],
        path: [SIMD3<Float>],
        qualidade: Double,
        penalidade: Double,
        motivos: inout [String]
    ) {
        let positions = nuvem.map { $0.position }
        let floor = meshPoints.filter { $0.isFloor }.map { $0.position }
        let bruto = CanopyMath.measureLateral(points: positions, floorHints: floor, cameraPath: path)
        metricas.planoChaoConfiavel = bruto.fit?.reliable ?? false
        metricas.comprimentoTrechoMetros = bruto.comprimentoM.map { Double($0) }
        if let faixas = Optional(bruto.histograma), !faixas.isEmpty, bruto.fit?.reliable == true {
            metricas.histogramaVertical = faixas.map {
                FaixaHistograma(deCm: $0.deCm, ateCm: $0.ateCm, fracao: Double($0.fracao))
            }
        }
        guard let fit = bruto.fit, fit.reliable,
              let media = bruto.alturaMediaM,
              let maxima = bruto.alturaMaximaM,
              let largura = bruto.larguraM,
              let volume = bruto.volumePorMetro else {
            let vazia = "Não calculada: o plano do chão ou o trecho de 1 m não ficou confiável."
            metricas.alturaMediaCm = metrica(nome: "Altura média do dossel", valor: nil, unidade: "cm", confianca: 0.2, significado: vazia)
            metricas.alturaMaximaCm = metrica(nome: "Altura máxima do dossel", valor: nil, unidade: "cm", confianca: 0.2, significado: vazia)
            metricas.larguraAparenteCm = metrica(nome: "Largura aparente", valor: nil, unidade: "cm", confianca: 0.2, significado: vazia)
            metricas.volumeAparenteM3PorMetro = metrica(nome: "Volume aparente", valor: nil, unidade: "m³/m", confianca: 0.2, significado: "Volume aparente não calculado. Não é biomassa.")
            metricas.notaPlanoChao = "Medidas 3D omitidas de propósito. Repita andando mais devagar, com o chão visível, ao redor de 1 m da linha."
            motivos.append("Medidas laterais omitidas: chão ou cobertura do trecho insuficientes.")
            return
        }
        let confianca = combinar([
            (Double(planoScore(fit)), 0.45),
            (qualidade, 0.25),
            (min(1, Double(bruto.pontosCopa) / 200), 0.15),
            (min(1, Double(bruto.celulas) / 20), 0.15)
        ]) * penalidade
        metricas.alturaMediaCm = metrica(
            nome: "Altura média do dossel",
            valor: Double(media * 100),
            unidade: "cm",
            confianca: confianca,
            significado: "Média da superfície aparente da copa no trecho de cerca de 1 m, acima do plano do chão."
        )
        metricas.alturaMaximaCm = metrica(
            nome: "Altura máxima do dossel",
            valor: Double(maxima * 100),
            unidade: "cm",
            confianca: confianca,
            significado: "Maior altura aparente da copa no trecho, por células de 5 cm, sem um ponto isolado mandar no número."
        )
        metricas.larguraAparenteCm = metrica(
            nome: "Largura aparente",
            valor: Double(largura * 100),
            unidade: "cm",
            confianca: confianca,
            significado: "Largura aparente da copa no trecho, de lado. Não separa a linha vizinha se a caminhada não cercou só uma linha."
        )
        metricas.volumeAparenteM3PorMetro = metrica(
            nome: "Volume aparente",
            valor: Double(volume),
            unidade: "m³/m",
            confianca: confianca,
            significado: "Volume aparente da copa por metro de linha, incluindo o ar entre as folhas. Não é biomassa."
        )
        let comprimento = bruto.comprimentoM ?? 0
        metricas.notaPlanoChao = "Plano do chão usado no trecho de \(TextoBR.numero(Double(comprimento), casas: 2)) m. Normal para cima \(TextoBR.numero(Double(fit.normalY), casas: 2))."
        if nuvem.count < 200 {
            motivos.append("A nuvem do trecho tem poucos pontos. Os centímetros podem oscilar.")
        }
    }

    private static func metrica(nome: String, valor: Double?, unidade: String, confianca: Double, significado: String) -> MetricaValor {
        let limitada = min(1, max(0, confianca))
        let valorFinito: Double?
        if let valor, valor.isFinite {
            valorFinito = valor
        } else {
            valorFinito = nil
        }
        return MetricaValor(
            nome: nome,
            valor: valorFinito,
            unidade: unidade,
            confianca: limitada,
            rotuloConfianca: TextoBR.rotuloConfianca(limitada),
            significado: significado
        )
    }

    private static func planoScore(_ fit: PlaneFit) -> Float {
        guard fit.reliable else { return 0 }
        let rms = min(1, max(0, 1 - fit.rms / 0.05))
        let fraction = min(1, max(0, fit.inlierFraction / 0.7))
        let normal = min(1, max(0, (fit.normalY - 0.85) / 0.15))
        return 0.4 * rms + 0.35 * fraction + 0.25 * normal
    }

    private static func qualidade(samples: [FrameSample], warnings: WarningTotals, orientacaoFraca: Bool) -> Double {
        let amostras = min(1, Double(samples.count) / 8)
        let profundidadeAmostras: Double
        if samples.isEmpty {
            profundidadeAmostras = 0
        } else {
            let media = samples.reduce(Float(0)) { $0 + $1.lowConfidenceFraction } / Float(samples.count)
            profundidadeAmostras = Double(max(0, 1 - media))
        }
        let quadros = max(1, warnings.quadrosAvaliados)
        let rastreio = 1 - Double(warnings.rastreamentoPerdido + warnings.rastreamentoLimitado) / Double(quadros)
        let pressa = 1 - Double(warnings.rapidoDemais) / Double(quadros)
        var valor = combinar([
            (amostras, 0.25),
            (profundidadeAmostras, 0.25),
            (max(0, rastreio), 0.30),
            (max(0, pressa), 0.20)
        ])
        if orientacaoFraca { valor *= 0.55 }
        if warnings.quadrosAvaliados == 0 { valor *= 0.7 }
        return min(1, max(0, valor))
    }

    private static func penalidadeGlobal(samples: [FrameSample], warnings: WarningTotals, incompleta: Bool, escala: Bool) -> Double {
        var fator = 1.0
        if samples.count < 5 { fator *= 0.45 }
        else if samples.count < 8 { fator *= 0.75 }
        if !escala { fator *= 0.9 }
        if incompleta { fator *= 0.7 }
        if warnings.quadrosAvaliados > 0 {
            let pressa = Double(warnings.rapidoDemais) / Double(warnings.quadrosAvaliados)
            let rastreio = Double(warnings.rastreamentoPerdido + warnings.rastreamentoLimitado) / Double(warnings.quadrosAvaliados)
            let profundidade = Double(warnings.profundidadeBaixa) / Double(warnings.quadrosAvaliados)
            if pressa > 0.25 { fator *= 0.75 }
            if rastreio > 0.3 { fator *= 0.7 }
            if profundidade > 0.35 { fator *= 0.75 }
        }
        return fator
    }

    private static func combinar(_ partes: [(Double, Double)]) -> Double {
        let peso = partes.reduce(0) { $0 + $1.1 }
        if peso <= 0 { return 0 }
        let soma = partes.reduce(0) { $0 + max(0, min(1, $1.0)) * $1.1 }
        return min(1, max(0, soma / peso))
    }

    private static func confiancasProduzidas(_ metricas: MetricasRelatorio) -> [Double] {
        var valores: [Double] = []
        for metrica in [metricas.coberturaVegetacaoPct, metricas.soloExpostoPct, metricas.aberturaDosselPct, metricas.indiceFechamento, metricas.alturaMediaCm, metricas.alturaMaximaCm, metricas.larguraAparenteCm, metricas.volumeAparenteM3PorMetro] {
            if let metrica, metrica.valor != nil {
                valores.append(metrica.confianca)
            }
        }
        return valores
    }

    private static func metricasFaltando(_ modality: CaptureModality, _ metricas: MetricasRelatorio) -> Bool {
        switch modality {
        case .inferior:
            return metricas.aberturaDosselPct?.valor == nil || metricas.indiceFechamento?.valor == nil
        case .superior:
            return metricas.coberturaVegetacaoPct?.valor == nil || metricas.soloExpostoPct?.valor == nil || metricas.alturaMediaCm?.valor == nil
        case .lateral:
            return metricas.alturaMediaCm?.valor == nil || metricas.larguraAparenteCm?.valor == nil || metricas.volumeAparenteM3PorMetro?.valor == nil
        }
    }

    private static func resumo(_ modality: CaptureModality, _ metricas: MetricasRelatorio) -> String {
        switch modality {
        case .superior:
            let cobertura = textoPercentual(metricas.coberturaVegetacaoPct)
            let solo = textoPercentual(metricas.soloExpostoPct)
            let altura = textoCentimetros(metricas.alturaMediaCm)
            return "Cobertura \(cobertura) · solo \(solo) · altura \(altura)"
        case .inferior:
            let abertura = textoPercentual(metricas.aberturaDosselPct)
            let fechamento: String
            if let valor = metricas.indiceFechamento?.valor {
                fechamento = TextoBR.numero(valor, casas: 2)
            } else {
                fechamento = "indisponível"
            }
            return "Abertura \(abertura) · fechamento \(fechamento)"
        case .lateral:
            guard metricas.alturaMediaCm?.valor != nil else { return "Medidas 3D indisponíveis" }
            let media = textoCentimetros(metricas.alturaMediaCm)
            let maxima = textoCentimetros(metricas.alturaMaximaCm)
            let largura = textoCentimetros(metricas.larguraAparenteCm)
            return "Altura méd. \(media) · máx. \(maxima) · largura \(largura)"
        }
    }

    private static func textoPercentual(_ metrica: MetricaValor?) -> String {
        guard let valor = metrica?.valor else { return "indisponível" }
        return TextoBR.numero(valor, casas: 0) + "%"
    }

    private static func textoCentimetros(_ metrica: MetricaValor?) -> String {
        guard let valor = metrica?.valor else { return "indisponível" }
        return TextoBR.numero(valor, casas: 0) + " cm"
    }
}
