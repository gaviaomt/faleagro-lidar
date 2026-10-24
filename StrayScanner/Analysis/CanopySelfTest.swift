// FaleAgro LiDAR — protótipo 1
// Checagens das contas, sem câmera. O app não chama isto sozinho.
// Baseado no Stray Scanner (MIT, Stray Robots).

import Foundation

enum CanopySelfTest {
    static func failures() -> [String] {
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        check(TextoBR.numero(1.5, casas: 1) == "1,5", "vírgula decimal")
        check(TextoBR.numero(10, casas: 0) == "10", "inteiro")
        check(TextoBR.rotuloConfianca(0.8) == "alta", "confiança alta")
        check(TextoBR.rotuloConfianca(0.5) == "média", "confiança média")
        check(TextoBR.rotuloConfianca(0.2) == "baixa", "confiança baixa")

        let separado = CanopyMath.otsuThreshold(histogram: histogramaBimodal())
        check(separado.index >= 15 && separado.index < 100, "otsu entre os modos: \(separado.index)")
        check(separado.eta > 0.5, "otsu eta \(separado.eta)")

        let verde = CanopyMath.excessGreen(r: 20, g: 140, b: 30)
        let marrom = CanopyMath.excessGreen(r: 140, g: 90, b: 40)
        let azul = CanopyMath.excessGreen(r: 100, g: 140, b: 220)
        check(verde > 0.4 && marrom < 0.15 && azul < 0.15, "excesso de verde verde=\(verde) marrom=\(marrom) azul=\(azul)")

        let tudoVerde = CanopyMath.analyzeFrame(frameSolido(r: 30, g: 140, b: 40, depth: 0.8, confidence: 2, lookY: -1), modality: .superior, cloudStride: 4)
        check(tudoVerde.fracaoVegetacao > 0.85, "lavoura toda verde ficou com cobertura \(tudoVerde.fracaoVegetacao)")

        let tudoMarrom = CanopyMath.analyzeFrame(frameSolido(r: 140, g: 90, b: 40, depth: 1.3, confidence: 2, lookY: -1), modality: .superior, cloudStride: 4)
        check(tudoMarrom.fracaoVegetacao < 0.1, "solo sem folha ficou com cobertura \(tudoMarrom.fracaoVegetacao)")
        check(tudoMarrom.fracaoSolo > 0.7, "solo sem folha ficou com solo \(tudoMarrom.fracaoSolo)")

        let metade = CanopyMath.analyzeFrame(frameMetade(), modality: .superior, cloudStride: 1)
        check(metade.fracaoVegetacao > 0.45 && metade.fracaoVegetacao < 0.55, "cobertura da metade \(metade.fracaoVegetacao)")
        check(metade.fracaoSolo > 0.40 && metade.fracaoSolo < 0.60, "solo da metade \(metade.fracaoSolo)")

        let ceu = CanopyMath.analyzeFrame(frameInferior(), modality: .inferior, cloudStride: 2)
        check(ceu.fracaoCeu > 0.40 && ceu.fracaoCeu < 0.60, "abertura \(ceu.fracaoCeu)")
        if let fechamento = ceu.fechamento {
            check(fechamento > 0.40 && fechamento < 0.60, "fechamento \(fechamento)")
        } else {
            check(false, "fechamento nil")
        }

        let identidade = matrizIdentidade()
        let centro = CanopyMath.unproject(u: 50, v: 50, depth: 2, fx: 100, fy: 100, cx: 50, cy: 50, transform: identidade)
        check(centro != nil && abs((centro?.x ?? 9)) < 0.001 && abs((centro?.y ?? 9)) < 0.001 && abs((centro?.z ?? 0) + 2) < 0.001, "desprojeção no centro \(String(describing: centro))")
        let abaixo = CanopyMath.unproject(u: 50, v: 60, depth: 2, fx: 100, fy: 100, cx: 50, cy: 50, transform: identidade)
        check((abaixo?.y ?? 0) < -0.15, "pixel abaixo do centro desce no mundo \(String(describing: abaixo))")

        var planoPontos: [SIMD3<Float>] = []
        for x in stride(from: Float(0), through: 1, by: 0.1) {
            for z in stride(from: Float(0), through: 1, by: 0.1) {
                planoPontos.append(SIMD3<Float>(x, 0, z))
            }
        }
        for _ in 0..<15 {
            planoPontos.append(SIMD3<Float>(0.2, 1.6, 0.2))
        }
        let plano = CanopyMath.ransacPlane(planoPontos)
        check(plano?.reliable == true, "plano com outlier reliable=\(String(describing: plano?.reliable)) rms=\(String(describing: plano?.rms))")
        check((plano?.rms ?? 1) < 0.02, "rms do plano \(String(describing: plano?.rms))")
        check((plano?.normalY ?? 0) > 0.95, "normal do plano \(String(describing: plano?.normalY))")

        let lateral = lateralSintetica()
        check(lateral.fit?.reliable == true, "lateral reliable \(String(describing: lateral.fit?.reliable)) pontos \(lateral.pontosCopa)")
        check((lateral.alturaMediaM ?? 0) > 0.40 && (lateral.alturaMediaM ?? 0) < 0.65, "altura média lateral \(String(describing: lateral.alturaMediaM))")
        check((lateral.alturaMaximaM ?? 9) < 0.70, "altura máxima não pode ser o pico de 5 m: \(String(describing: lateral.alturaMaximaM))")
        check((lateral.larguraM ?? 0) > 0.28 && (lateral.larguraM ?? 0) < 0.50, "largura \(String(describing: lateral.larguraM))")
        check((lateral.volumePorMetro ?? 0) > 0.10 && (lateral.volumePorMetro ?? 0) < 0.40, "volume aparente \(String(describing: lateral.volumePorMetro))")
        let faixaAlta = lateral.histograma.first { $0.deCm == 50 }
        check((faixaAlta?.fracao ?? 0) > 0.2, "histograma na faixa de 50 cm \(String(describing: faixaAlta?.fracao))")

        let superior = analiseSuperior()
        let cobertura = superior.relatorio.metricas.coberturaVegetacaoPct?.valor ?? -1
        let solo = superior.relatorio.metricas.soloExpostoPct?.valor ?? -1
        let altura = superior.relatorio.metricas.alturaMediaCm?.valor
        check(cobertura > 45 && cobertura < 55, "relatório cobertura \(cobertura)")
        check(solo > 40 && solo < 60, "relatório solo \(solo)")
        check(altura != nil && (altura ?? 0) > 40 && (altura ?? 0) < 85, "relatório altura \(String(describing: altura)) nota \(superior.relatorio.metricas.notaPlanoChao ?? "")")
        check(superior.relatorio.avisoGeral.contains("Não é biomassa"), "aviso de biomassa")
        check(superior.relatorio.metricas.volumeAparenteM3PorMetro == nil, "vista de cima não inventa volume")

        let lateralRelatorio = analiseLateral()
        let volume = lateralRelatorio.relatorio.metricas.volumeAparenteM3PorMetro
        check(volume?.nome == "Volume aparente", "nome do volume")
        check(volume?.unidade == "m³/m", "unidade do volume")
        check((volume?.valor ?? 0) > 0.10 && (volume?.valor ?? 0) < 0.40, "volume no relatório \(String(describing: volume?.valor))")
        check(volume?.significado.contains("Não é biomassa") == true, "volume avisa que não é biomassa")
        check(lateralRelatorio.relatorio.metricas.histogramaVertical?.isEmpty == false, "histograma no relatório")

        let rapido = CaptureWarningLogic.mensagens(contexto(modality: .lateral, velocidade: 0.9, gravando: true))
        check(rapido.contains { $0.texto.contains("rápido") }, "aviso de velocidade")
        let devagar = CaptureWarningLogic.mensagens(contexto(modality: .superior, velocidade: 0.4, gravando: true, amostrasBaixo: 10, segundos: 4))
        check(!devagar.contains { $0.texto.contains("rápido") }, "vista de cima a 0,4 m/s não é rápida")
        let incompleta = CaptureWarningLogic.areaIncompleta(
            modality: .lateral,
            amostrasParaCima: 0,
            amostrasParaBaixo: 0,
            comprimentoPercurso: 0.3,
            dispersaoLateral: 0.05,
            verticesMalha: 10,
            amostrasComProfundidade: 1,
            segundosGravando: 5
        )
        check(incompleta, "volta curta é área incompleta")
        let completa = CaptureWarningLogic.areaIncompleta(
            modality: .inferior,
            amostrasParaCima: 10,
            amostrasParaBaixo: 0,
            comprimentoPercurso: 0,
            dispersaoLateral: 0,
            verticesMalha: 0,
            amostrasComProfundidade: 10,
            segundosGravando: 5
        )
        check(!completa, "inferior com quadros para cima fica completo")

        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("faleagro-selftest-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try ReportFiles.writeRelatorio(superior.relatorio, to: directory)
            let json = try Data(contentsOf: directory.appendingPathComponent(CaptureFiles.metricas))
            let texto = String(data: json, encoding: .utf8) ?? ""
            check(texto.contains("biomassa"), "json menciona biomassa para negar o uso")
            check(texto.contains("\"estagio\" : 1") || texto.contains("\"estagio\": 1"), "json estagio 1: \(texto.prefix(180))")
            let decodificado = try ReportFiles.jsonDecoder().decode(RelatorioCaptura.self, from: json)
            check(decodificado.identificacao.fazenda == "São José", "fazenda sobrevive ao json")
            check(decodificado.identificacao.pontoAmostral == 3, "ponto amostral")

            let pontos = [
                WorldPoint(position: SIMD3<Float>(0, 0, 0), red: 10, green: 20, blue: 30, confidence: 2, klass: .solo, isFloor: true, height: 0),
                WorldPoint(position: SIMD3<Float>(0.1, 0.4, 0), red: 10, green: 80, blue: 20, confidence: 2, klass: .vegetacao, isFloor: false, height: 0.4)
            ]
            try ReportFiles.writePLY(pontos, to: directory)
            let ply = try Data(contentsOf: directory.appendingPathComponent(CaptureFiles.nuvem))
            if let range = ply.range(of: Data("end_header\n".utf8)) {
                let cabecalho = String(data: ply.prefix(upTo: range.upperBound), encoding: .utf8) ?? ""
                check(cabecalho.contains("element vertex 2"), "ply tem 2 vértices")
                check(cabecalho.contains("binary_little_endian"), "ply binário")
                check(cabecalho.contains("Nao e biomassa"), "ply avisa a limitação")
                let corpo = ply.suffix(from: range.upperBound)
                check(corpo.count == 30, "ply corpo \(corpo.count) bytes, esperado 30")
            } else {
                check(false, "ply sem end_header")
            }
        } catch {
            check(false, "arquivo de teste falhou: \(error)")
        }

        return failures
    }

    private static func histogramaBimodal() -> [Int] {
        var histogram = [Int](repeating: 0, count: 128)
        histogram[15] = 400
        histogram[100] = 400
        return histogram
    }

    private static func matrizIdentidade() -> [Float] {
        var matrix = [Float](repeating: 0, count: 16)
        matrix[0] = 1
        matrix[5] = 1
        matrix[10] = 1
        matrix[15] = 1
        return matrix
    }

    private static func matrizOlhandoParaBaixo() -> [Float] {
        [
            1, 0, 0, 0,
            0, 0, -1, 0,
            0, 1, 0, 0,
            0, 1.5, 0, 1
        ]
    }

    private static func frameSolido(r: UInt8, g: UInt8, b: UInt8, depth: Float, confidence: UInt8, lookY: Float) -> FrameSample {
        let width = 16
        let height = 12
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let depths = [Float](repeating: depth, count: width * height)
        let confidences = [UInt8](repeating: confidence, count: width * height)
        for index in 0..<(width * height) {
            rgba[index * 4] = r
            rgba[index * 4 + 1] = g
            rgba[index * 4 + 2] = b
            rgba[index * 4 + 3] = 255
        }
        return FrameSample(
            timestamp: 1,
            rgba: rgba,
            width: width,
            height: height,
            depth: depths,
            confidence: confidences,
            fx: 18,
            fy: 18,
            cx: 8,
            cy: 6,
            transform: matrizOlhandoParaBaixo(),
            viewDirectionY: lookY,
            tracking: .normal,
            lowConfidenceFraction: 0.05,
            speedMetersPerSecond: 0.05
        )
    }

    private static func frameMetade() -> FrameSample {
        let width = 48
        let height = 24
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var depths = [Float](repeating: 0, count: width * height)
        let confidences = [UInt8](repeating: 2, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x < width / 2 {
                    rgba[index * 4] = 0
                    rgba[index * 4 + 1] = 180
                    rgba[index * 4 + 2] = 0
                    depths[index] = 0.8
                } else {
                    rgba[index * 4] = 140
                    rgba[index * 4 + 1] = 90
                    rgba[index * 4 + 2] = 40
                    depths[index] = 1.4
                }
                rgba[index * 4 + 3] = 255
            }
        }
        return FrameSample(
            timestamp: 2,
            rgba: rgba,
            width: width,
            height: height,
            depth: depths,
            confidence: confidences,
            fx: 36,
            fy: 36,
            cx: Float(width) / 2,
            cy: Float(height) / 2,
            transform: matrizOlhandoParaBaixo(),
            viewDirectionY: -0.95,
            tracking: .normal,
            lowConfidenceFraction: 0.05,
            speedMetersPerSecond: 0.05
        )
    }

    private static func frameInferior() -> FrameSample {
        let width = 40
        let height = 20
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var depths = [Float](repeating: .nan, count: width * height)
        var confidences = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if x < width / 2 {
                    rgba[index * 4] = 100
                    rgba[index * 4 + 1] = 150
                    rgba[index * 4 + 2] = 230
                    depths[index] = .nan
                    confidences[index] = 0
                } else {
                    rgba[index * 4] = 20
                    rgba[index * 4 + 1] = 130
                    rgba[index * 4 + 2] = 30
                    depths[index] = 0.45
                    confidences[index] = 2
                }
                rgba[index * 4 + 3] = 255
            }
        }
        return FrameSample(
            timestamp: 3,
            rgba: rgba,
            width: width,
            height: height,
            depth: depths,
            confidence: confidences,
            fx: 30,
            fy: 30,
            cx: 20,
            cy: 10,
            transform: matrizIdentidade(),
            viewDirectionY: 0.9,
            tracking: .normal,
            lowConfidenceFraction: 0.4,
            speedMetersPerSecond: 0.02
        )
    }

    private static func lateralSintetica() -> LateralRaw {
        var points: [SIMD3<Float>] = []
        var floor: [SIMD3<Float>] = []
        for x in stride(from: Float(0), through: 1, by: 0.05) {
            for z in stride(from: Float(-0.25), through: 0.25, by: 0.05) {
                let ground = SIMD3<Float>(x, 0, z)
                floor.append(ground)
                points.append(ground)
            }
        }
        for x in stride(from: Float(0.05), through: 0.95, by: 0.05) {
            for z in stride(from: Float(-0.2), through: 0.2, by: 0.05) {
                points.append(SIMD3<Float>(x, 0.50, z))
                points.append(SIMD3<Float>(x, 0.25, z))
            }
        }
        points.append(SIMD3<Float>(0.5, 5, 0))
        return CanopyMath.measureLateral(points: points, floorHints: floor, cameraPath: caminhoLateral())
    }

    private static func caminhoLateral() -> [SIMD3<Float>] {
        var path: [SIMD3<Float>] = []
        var x = Float(-0.2)
        while x <= 1.2 {
            path.append(SIMD3<Float>(x, 1.0, -0.35))
            path.append(SIMD3<Float>(x, 1.0, 0.35))
            x += 0.1
        }
        var z = Float(-0.35)
        while z <= 0.35 {
            path.append(SIMD3<Float>(-0.2, 1.0, z))
            path.append(SIMD3<Float>(1.2, 1.0, z))
            z += 0.1
        }
        return path
    }

    private static func metadata(_ modality: CaptureModality) -> CaptureMetadata {
        CaptureMetadata(
            fazenda: "São José",
            talhao: "4",
            variedade: "BRS 284",
            dataPlantio: Date(timeIntervalSince1970: 1_700_000_000),
            tratamento: "testemunha",
            pontoAmostral: 3,
            modalidade: modality,
            escalaConfirmada: true
        )
    }

    private static func avisosBons() -> WarningTotals {
        var totals = WarningTotals()
        totals.quadrosAvaliados = 120
        return totals
    }

    private static func analiseSuperior() -> AnaliseCompleta {
        let frame = frameMetade()
        return CanopyAnalyzer.analisar(
            metadata: metadata(.superior),
            startedAt: Date(timeIntervalSince1970: 1_720_000_000),
            duration: 6,
            samples: Array(repeating: frame, count: 8),
            meshPoints: [],
            path: [SIMD3<Float>(0, 1.5, 0), SIMD3<Float>(0.1, 1.5, 0)],
            warnings: avisosBons(),
            meshVertexCount: 0
        )
    }

    private static func analiseLateral() -> AnaliseCompleta {
        var points: [SIMD3<Float>] = []
        var floor: [SIMD3<Float>] = []
        for x in stride(from: Float(0), through: 1, by: 0.05) {
            for z in stride(from: Float(-0.25), through: 0.25, by: 0.05) {
                floor.append(SIMD3<Float>(x, 0, z))
            }
        }
        for x in stride(from: Float(0.05), through: 0.95, by: 0.05) {
            for z in stride(from: Float(-0.2), through: 0.2, by: 0.05) {
                points.append(SIMD3<Float>(x, 0.50, z))
                points.append(SIMD3<Float>(x, 0.25, z))
            }
        }
        var mesh: [MeshPoint] = floor.map { MeshPoint(position: $0, isFloor: true) }
        mesh.append(contentsOf: points.map { MeshPoint(position: $0, isFloor: false) })
        return CanopyAnalyzer.analisar(
            metadata: metadata(.lateral),
            startedAt: Date(timeIntervalSince1970: 1_720_000_000),
            duration: 12,
            samples: [],
            meshPoints: mesh,
            path: caminhoLateral(),
            warnings: avisosBons(),
            meshVertexCount: mesh.count
        )
    }

    private static func contexto(
        modality: CaptureModality,
        velocidade: Float,
        gravando: Bool,
        amostrasBaixo: Int = 0,
        segundos: Float = 3
    ) -> ContextoAvisos {
        ContextoAvisos(
            modality: modality,
            gravando: gravando,
            tracking: .normal,
            movimentoExcessivoDoARKit: false,
            velocidade: velocidade,
            fracaoProfundidadeBaixa: 0.1,
            segundosGravando: segundos,
            amostrasParaCima: 0,
            amostrasParaBaixo: amostrasBaixo,
            comprimentoPercurso: 3,
            dispersaoLateral: 0.4,
            verticesMalha: 200,
            amostrasComProfundidade: 8,
            escalaConfirmada: false,
            semCenaProfundidade: false
        )
    }
}
