// FaleAgro LiDAR — protótipo 1
// Contas de estrutura do dossel. Não estimam biomassa.
// Baseado no Stray Scanner (MIT, Stray Robots).

import Foundation

struct PlaneModel {
    var normal: SIMD3<Float>
    var d: Float

    func height(_ point: SIMD3<Float>) -> Float {
        CanopyMath.dot(normal, point) + d
    }
}

struct PlaneFit {
    var plane: PlaneModel
    var inlierFraction: Float
    var rms: Float
    var inliers: Int
    var normalY: Float
    var span: Float
    var reliable: Bool
}

struct FaixaAltura {
    var deCm: Int
    var ateCm: Int
    var fracao: Float
}

struct LateralRaw {
    var fit: PlaneFit?
    var alturaMediaM: Float?
    var alturaMaximaM: Float?
    var larguraM: Float?
    var volumeM3: Float?
    var volumePorMetro: Float?
    var comprimentoM: Float?
    var histograma: [FaixaAltura]
    var pontosNoTrecho: Int
    var pontosCopa: Int
    var celulas: Int
}

struct AlturaCopa {
    var mediaM: Float?
    var maximaM: Float?
    var fit: PlaneFit?
    var pontosCopa: Int
}

struct ContagemImagem {
    var vegetacao: Int = 0
    var solo: Int = 0
    var ceu: Int = 0
    var indefinido: Int = 0
    var total: Int = 0
    var eta: Float = 0
    var usouLimiarFixo: Bool = false
    var profundidadeChao: Float?
    var pontos: [WorldPoint] = []

    var fracaoVegetacao: Float {
        guard total > 0 else { return 0 }
        return Float(vegetacao) / Float(total)
    }

    var fracaoSolo: Float {
        guard total > 0 else { return 0 }
        return Float(solo) / Float(total)
    }

    var fracaoCeu: Float {
        guard total > 0 else { return 0 }
        return Float(ceu) / Float(total)
    }

    var fechamento: Float? {
        let base = vegetacao + ceu
        guard base > 0 else { return nil }
        return Float(vegetacao) / Float(base)
    }
}

enum CanopyMath {
    static let limiarVerdeFixo: Float = 0.20
    static let alturaMaximaAceita: Float = 2.5
    static let cellSize: Float = 0.05

    static func dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    static func length(_ a: SIMD3<Float>) -> Float {
        dot(a, a).squareRoot()
    }

    static func normalize(_ a: SIMD3<Float>) -> SIMD3<Float> {
        let magnitude = length(a)
        if magnitude < 1e-6 { return SIMD3<Float>(0, 0, 0) }
        return a / magnitude
    }

    static func percentile(_ values: [Float], _ fraction: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let clamped = min(1, max(0, fraction))
        let index = Int((Float(sorted.count - 1) * clamped).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 { return sorted[count / 2] }
        return 0.5 * (sorted[count / 2 - 1] + sorted[count / 2])
    }

    /// Excesso de verde normalizado: (2G − R − B) / (R + G + B).
    /// Folha fica alto. Solo e céu ficam perto de zero ou negativos.
    static func excessGreen(r: Int, g: Int, b: Int) -> Float {
        let sum = r + g + b
        if sum <= 0 { return 0 }
        return Float(2 * g - r - b) / Float(sum)
    }

    static func otsuThreshold(histogram: [Int]) -> (index: Int, eta: Float) {
        let bins = histogram.count
        guard bins > 1 else { return (0, 0) }
        var total = 0
        var sumAll = 0.0
        for index in 0..<bins {
            total += histogram[index]
            sumAll += Double(index) * Double(histogram[index])
        }
        if total == 0 { return (0, 0) }

        var sumBackground = 0.0
        var weightBackground = 0
        var best = -1.0
        var bestIndex = 0
        var totalVariance = 0.0
        let mean = sumAll / Double(total)
        for index in 0..<bins {
            let delta = Double(index) - mean
            totalVariance += Double(histogram[index]) * delta * delta
        }

        for index in 0..<bins {
            weightBackground += histogram[index]
            if weightBackground == 0 { continue }
            let weightForeground = total - weightBackground
            if weightForeground == 0 { break }
            sumBackground += Double(index) * Double(histogram[index])
            let meanBackground = sumBackground / Double(weightBackground)
            let meanForeground = (sumAll - sumBackground) / Double(weightForeground)
            let between = Double(weightBackground) * Double(weightForeground) * (meanBackground - meanForeground) * (meanBackground - meanForeground)
            if between > best {
                best = between
                bestIndex = index
            }
        }
        let eta: Float
        if totalVariance <= 1e-9 || best < 0 {
            eta = 0
        } else {
            eta = Float(min(1, best / totalVariance))
        }
        return (bestIndex, eta)
    }

    static func greenBin(_ excess: Float) -> Int {
        let clamped = min(1.5, max(-0.5, excess))
        let unit = (clamped + 0.5) / 2.0
        return min(127, max(0, Int(unit * 127)))
    }

    static func greenBinCenter(_ index: Int) -> Float {
        let unit = (Float(index) + 0.5) / 128.0
        return unit * 2.0 - 0.5
    }

    static func solve3(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var m = matrix
        var y = rhs
        for column in 0..<3 {
            var pivot = column
            var best = abs(m[column][column])
            if column < 2 {
                for row in (column + 1)..<3 {
                    let value = abs(m[row][column])
                    if value > best {
                        best = value
                        pivot = row
                    }
                }
            }
            if best < 1e-10 { return nil }
            if pivot != column {
                m.swapAt(pivot, column)
                y.swapAt(pivot, column)
            }
            let divisor = m[column][column]
            for item in column..<3 {
                m[column][item] /= divisor
            }
            y[column] /= divisor
            for row in 0..<3 where row != column {
                let factor = m[row][column]
                if factor == 0 { continue }
                for item in column..<3 {
                    m[row][item] -= factor * m[column][item]
                }
                y[row] -= factor * y[column]
            }
        }
        return y
    }

    /// Plano quase horizontal: y em função de x e z. A normal aponta para cima.
    static func fitPlane(_ points: [SIMD3<Float>]) -> PlaneModel? {
        guard points.count >= 3 else { return nil }
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var atb = [Double](repeating: 0, count: 3)
        var centroid = SIMD3<Float>(0, 0, 0)
        for point in points {
            let row = [Double(point.x), Double(point.z), 1.0]
            let height = Double(point.y)
            centroid += point
            for i in 0..<3 {
                atb[i] += row[i] * height
                for j in 0..<3 {
                    ata[i][j] += row[i] * row[j]
                }
            }
        }
        guard solve3(ata, atb) != nil else { return nil }
        centroid /= Float(points.count)
        guard let solution = solve3(ata, atb) else { return nil }
        let slopeX = Float(solution[0])
        let slopeZ = Float(solution[1])
        var normal = SIMD3<Float>(slopeX, -1, slopeZ)
        normal = normalize(normal)
        if length(normal) < 0.5 { return nil }
        if normal.y < 0 { normal = -normal }
        let d = -dot(normal, centroid)
        return PlaneModel(normal: normal, d: d)
    }

    static func ransacPlane(_ candidates: [SIMD3<Float>], iterations: Int = 60, threshold: Float = 0.03, seed: UInt64 = 42) -> PlaneFit? {
        guard candidates.count >= 3 else { return nil }
        var rng = SplitMix64(state: seed == 0 ? 1 : seed)
        var bestInliers: [SIMD3<Float>] = []
        let sampleCap = min(candidates.count, 2500)
        let pool = candidates.count > sampleCap ? Array(candidates.prefix(sampleCap)) : candidates

        if pool.count >= 3 {
            for _ in 0..<iterations {
                let i0 = rng.int(pool.count)
                var i1 = rng.int(pool.count)
                var i2 = rng.int(pool.count)
                if i1 == i0 { i1 = (i1 + 1) % pool.count }
                if i2 == i0 || i2 == i1 { i2 = (i2 + 2) % pool.count }
                guard let trial = fitPlane([pool[i0], pool[i1], pool[i2]]) else { continue }
                if trial.normal.y < 0.75 { continue }
                var inliers: [SIMD3<Float>] = []
                inliers.reserveCapacity(pool.count / 2)
                for point in pool where abs(trial.height(point)) <= threshold {
                    inliers.append(point)
                }
                if inliers.count > bestInliers.count {
                    bestInliers = inliers
                }
            }
        }

        let refitSource = bestInliers.count >= 3 ? bestInliers : pool
        guard let plane = fitPlane(refitSource) else { return nil }
        var inliers: [SIMD3<Float>] = []
        var residual = 0.0
        for point in pool {
            let distance = abs(plane.height(point))
            if distance <= threshold {
                inliers.append(point)
                residual += Double(distance * distance)
            }
        }
        guard let refined = fitPlane(inliers.count >= 3 ? inliers : refitSource) else { return nil }
        inliers.removeAll(keepingCapacity: true)
        residual = 0
        for point in pool {
            let distance = abs(refined.height(point))
            if distance <= threshold {
                inliers.append(point)
                residual += Double(distance * distance)
            }
        }
        let used = inliers.isEmpty ? refitSource : inliers
        let rms = used.isEmpty ? 999 : Float((residual / Double(max(1, used.count))).squareRoot())
        let fraction = Float(used.count) / Float(pool.count)
        let span = horizontalSpan(used)
        let minInliers = min(40, max(8, pool.count / 5))
        let reliable = used.count >= minInliers
            && fraction >= 0.45
            && rms <= 0.035
            && refined.normal.y >= 0.85
            && span >= 0.30
        return PlaneFit(
            plane: refined,
            inlierFraction: fraction,
            rms: rms,
            inliers: used.count,
            normalY: refined.normal.y,
            span: span,
            reliable: reliable
        )
    }

    static func horizontalSpan(_ points: [SIMD3<Float>]) -> Float {
        guard points.count >= 2 else { return 0 }
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }
        let dx = maxX - minX
        let dz = maxZ - minZ
        return (dx * dx + dz * dz).squareRoot()
    }

    static func pathStats(_ positions: [SIMD3<Float>]) -> (length: Float, lateralSpread: Float) {
        guard positions.count >= 2 else { return (0, 0) }
        var length: Float = 0
        for index in 1..<positions.count {
            let dx = positions[index].x - positions[index - 1].x
            let dz = positions[index].z - positions[index - 1].z
            length += (dx * dx + dz * dz).squareRoot()
        }
        var meanX: Float = 0
        var meanZ: Float = 0
        for position in positions {
            meanX += position.x
            meanZ += position.z
        }
        meanX /= Float(positions.count)
        meanZ /= Float(positions.count)
        var cxx: Float = 0
        var czz: Float = 0
        var cxz: Float = 0
        for position in positions {
            let dx = position.x - meanX
            let dz = position.z - meanZ
            cxx += dx * dx
            czz += dz * dz
            cxz += dx * dz
        }
        let angle = 0.5 * atan2(2 * cxz, cxx - czz)
        let lateralX = -sin(angle)
        let lateralZ = cos(angle)
        var minL = Float.greatestFiniteMagnitude
        var maxL = -Float.greatestFiniteMagnitude
        for position in positions {
            let lateral = (position.x - meanX) * lateralX + (position.z - meanZ) * lateralZ
            minL = min(minL, lateral)
            maxL = max(maxL, lateral)
        }
        return (length, maxL - minL)
    }

    /// Desprojeta um pixel do mapa de profundidade para o mundo.
    /// A profundidade do ARKit é positiva. A câmera olha para −Z.
    static func unproject(u: Float, v: Float, depth: Float, fx: Float, fy: Float, cx: Float, cy: Float, transform: [Float]) -> SIMD3<Float>? {
        guard transform.count == 16, fx > 1, fy > 1, depth.isFinite, depth > 0.05, depth < 8 else { return nil }
        let cameraX = (u - cx) * depth / fx
        let cameraY = -((v - cy) * depth / fy)
        let cameraZ = -depth
        let x = transform[0] * cameraX + transform[4] * cameraY + transform[8] * cameraZ + transform[12]
        let y = transform[1] * cameraX + transform[5] * cameraY + transform[9] * cameraZ + transform[13]
        let z = transform[2] * cameraX + transform[6] * cameraY + transform[10] * cameraZ + transform[14]
        let point = SIMD3<Float>(x, y, z)
        if !point.x.isFinite || !point.y.isFinite || !point.z.isFinite { return nil }
        return point
    }

    static func analyzeFrame(_ sample: FrameSample, modality: CaptureModality, cloudStride: Int) -> ContagemImagem {
        var result = ContagemImagem()
        let pixelCount = sample.width * sample.height
        guard pixelCount > 0, sample.rgba.count >= pixelCount * 4 else { return result }
        let hasDepth = sample.depth.count == pixelCount
        let hasConfidence = sample.confidence.count == pixelCount
        result.total = pixelCount

        var excess = [Float](repeating: 0, count: pixelCount)
        var histogram = [Int](repeating: 0, count: 128)
        for index in 0..<pixelCount {
            let base = index * 4
            let value = excessGreen(r: Int(sample.rgba[base]), g: Int(sample.rgba[base + 1]), b: Int(sample.rgba[base + 2]))
            excess[index] = value
            histogram[greenBin(value)] += 1
        }
        let otsu = otsuThreshold(histogram: histogram)
        let otsuValue = greenBinCenter(otsu.index)
        let useFixed = otsu.eta < 0.30 || otsuValue > 0.45 || otsuValue < 0.08
        let threshold = useFixed ? limiarVerdeFixo : otsuValue
        result.eta = otsu.eta
        result.usouLimiarFixo = useFixed

        var groundDepths: [Float] = []
        if modality == .superior && hasDepth && hasConfidence {
            for index in 0..<pixelCount where excess[index] <= threshold {
                let depth = sample.depth[index]
                if sample.confidence[index] >= 1 && depth.isFinite && depth > 0.15 && depth < 6 {
                    groundDepths.append(depth)
                }
            }
            if groundDepths.count >= 30 {
                result.profundidadeChao = percentile(groundDepths, 0.75)
            }
        }

        let stride = max(1, cloudStride)
        for y in 0..<sample.height {
            for x in 0..<sample.width {
                let index = y * sample.width + x
                let base = index * 4
                let r = Int(sample.rgba[base])
                let g = Int(sample.rgba[base + 1])
                let b = Int(sample.rgba[base + 2])
                let luma = (r + g + b) / 3
                let depth = hasDepth ? sample.depth[index] : Float.nan
                let confidence: UInt8 = hasConfidence ? sample.confidence[index] : 0
                let klass = classifyPixel(
                    r: r, g: g, b: b,
                    luma: luma,
                    excess: excess[index],
                    threshold: threshold,
                    depth: depth,
                    confidence: confidence,
                    groundDepth: result.profundidadeChao,
                    modality: modality
                )
                switch klass {
                case .vegetacao: result.vegetacao += 1
                case .solo: result.solo += 1
                case .ceu: result.ceu += 1
                case .indefinido: result.indefinido += 1
                }
                if x % stride == 0 && y % stride == 0 && hasDepth && confidence >= 1 {
                    if let position = unproject(
                        u: Float(x),
                        v: Float(y),
                        depth: depth,
                        fx: sample.fx,
                        fy: sample.fy,
                        cx: sample.cx,
                        cy: sample.cy,
                        transform: sample.transform
                    ) {
                        result.pontos.append(WorldPoint(
                            position: position,
                            red: UInt8(r),
                            green: UInt8(g),
                            blue: UInt8(b),
                            confidence: confidence,
                            klass: klass,
                            isFloor: false,
                            height: nil
                        ))
                    }
                }
            }
        }
        return result
    }

    static func classifyPixel(
        r: Int, g: Int, b: Int,
        luma: Int,
        excess: Float,
        threshold: Float,
        depth: Float,
        confidence: UInt8,
        groundDepth: Float?,
        modality: CaptureModality
    ) -> PointClass {
        if excess > threshold && luma >= 15 {
            return .vegetacao
        }
        if modality == .superior, let groundDepth, confidence >= 1, depth.isFinite, luma >= 15 {
            if depth < groundDepth - 0.12 {
                return .vegetacao
            }
        }
        if isSky(r: r, g: g, b: b, luma: luma, excess: excess, threshold: threshold, depth: depth, confidence: confidence) {
            return .ceu
        }
        if isSoil(r: r, g: g, b: b, luma: luma, excess: excess, threshold: threshold, depth: depth, confidence: confidence, groundDepth: groundDepth) {
            return .solo
        }
        return .indefinido
    }

    static func isSky(r: Int, g: Int, b: Int, luma: Int, excess: Float, threshold: Float, depth: Float, confidence: UInt8) -> Bool {
        if excess > threshold && luma >= 15 { return false }
        let maxChannel = max(r, max(g, b))
        let minChannel = min(r, min(g, b))
        let saturation = maxChannel - minChannel
        let bright = luma >= 185 && saturation <= 40
        let blue = b > r + 12 && b > g + 6 && luma >= 100 && excess < 0.15
        let hole = confidence == 0 && luma >= 150 && excess < threshold
        if confidence >= 1 && depth.isFinite && depth > 0.05 && depth < 4 && !bright && !blue {
            return false
        }
        return bright || blue || hole
    }

    static func isSoil(r: Int, g: Int, b: Int, luma: Int, excess: Float, threshold: Float, depth: Float, confidence: UInt8, groundDepth: Float?) -> Bool {
        if luma < 25 || luma > 220 { return false }
        if confidence < 1 { return false }
        if let groundDepth, depth.isFinite {
            let tolerance = max(0.08, groundDepth * 0.12)
            if depth < groundDepth - 0.10 { return false }
            return abs(depth - groundDepth) <= tolerance || depth > groundDepth
        }
        return r + 15 > b && g + 10 > b && excess < threshold
    }

    static func measureHeights(canopy: [SIMD3<Float>], floorPoints: [SIMD3<Float>], fallbackPoints: [SIMD3<Float>]) -> AlturaCopa {
        let candidates: [SIMD3<Float>]
        if floorPoints.count >= 12 {
            candidates = floorPoints
        } else if fallbackPoints.count >= 12 {
            let sorted = fallbackPoints.sorted { $0.y < $1.y }
            let count = max(12, sorted.count / 5)
            candidates = Array(sorted.prefix(count))
        } else {
            return AlturaCopa(mediaM: nil, maximaM: nil, fit: nil, pontosCopa: canopy.count)
        }
        guard let fit = ransacPlane(candidates) else {
            return AlturaCopa(mediaM: nil, maximaM: nil, fit: nil, pontosCopa: canopy.count)
        }
        guard fit.reliable else {
            return AlturaCopa(mediaM: nil, maximaM: nil, fit: fit, pontosCopa: canopy.count)
        }
        let heights = canopy.map { fit.plane.height($0) }.filter { $0 > 0.03 && $0 < alturaMaximaAceita }
        guard heights.count >= 20 else {
            return AlturaCopa(mediaM: nil, maximaM: nil, fit: fit, pontosCopa: heights.count)
        }
        let cells = cellHeights(points: canopy, plane: fit.plane, along: SIMD3<Float>(1, 0, 0), lateral: SIMD3<Float>(0, 0, 1), restrictToWindow: false, windowCenter: 0, windowHalf: 0)
        if cells.heights.isEmpty {
            return AlturaCopa(mediaM: percentile(heights, 0.90), maximaM: percentile(heights, 0.99), fit: fit, pontosCopa: heights.count)
        }
        let mean = cells.heights.reduce(0, +) / Float(cells.heights.count)
        let maxHeight = cells.heights.max() ?? mean
        return AlturaCopa(mediaM: mean, maximaM: maxHeight, fit: fit, pontosCopa: heights.count)
    }

    static func measureLateral(points: [SIMD3<Float>], floorHints: [SIMD3<Float>], cameraPath: [SIMD3<Float>]) -> LateralRaw {
        var raw = LateralRaw(
            fit: nil,
            alturaMediaM: nil,
            alturaMaximaM: nil,
            larguraM: nil,
            volumeM3: nil,
            volumePorMetro: nil,
            comprimentoM: nil,
            histograma: [],
            pontosNoTrecho: 0,
            pontosCopa: 0,
            celulas: 0
        )
        let candidates: [SIMD3<Float>]
        if floorHints.count >= 12 {
            candidates = floorHints
        } else if points.count >= 12 {
            let sorted = points.sorted { $0.y < $1.y }
            candidates = Array(sorted.prefix(max(12, sorted.count / 5)))
        } else {
            return raw
        }
        guard let fit = ransacPlane(candidates) else { return raw }
        raw.fit = fit
        guard fit.reliable else { return raw }

        let hint = rowDirection(path: cameraPath, points: points, plane: fit.plane)
        let along = horizontalAxis(hint, planeNormal: fit.plane.normal)
        let lateral = normalize(cross(fit.plane.normal, along))
        guard length(along) > 0.5, length(lateral) > 0.5 else { return raw }

        let pathAlong = cameraPath.map { dot(along, $0) }
        let center = pathAlong.isEmpty ? median(points.map { dot(along, $0) }) : median(pathAlong)
        let pathLateral = cameraPath.map { dot(lateral, $0) }
        let lateralMin: Float
        let lateralMax: Float
        if pathLateral.count >= 2 {
            let spread = (pathLateral.max() ?? 0) - (pathLateral.min() ?? 0)
            if spread >= 0.25 {
                lateralMin = pathLateral.min() ?? -0.35
                lateralMax = pathLateral.max() ?? 0.35
            } else {
                let mid = median(pathLateral)
                lateralMin = mid - 0.35
                lateralMax = mid + 0.35
            }
        } else {
            lateralMin = -0.45
            lateralMax = 0.45
        }

        var cropped: [SIMD3<Float>] = []
        cropped.reserveCapacity(points.count)
        for point in points {
            let alongValue = dot(along, point)
            let lateralValue = dot(lateral, point)
            let height = fit.plane.height(point)
            if alongValue < center - 0.5 || alongValue > center + 0.5 { continue }
            if lateralValue < lateralMin || lateralValue > lateralMax { continue }
            if height < -0.15 || height > alturaMaximaAceita { continue }
            cropped.append(point)
        }
        raw.pontosNoTrecho = cropped.count
        let canopy = cropped.filter { fit.plane.height($0) > 0.05 }
        raw.pontosCopa = canopy.count
        guard canopy.count >= 30 else { return raw }

        let cells = cellHeights(points: cropped, plane: fit.plane, along: along, lateral: lateral, restrictToWindow: true, windowCenter: center, windowHalf: 0.5)
        raw.celulas = cells.heights.count
        guard !cells.heights.isEmpty else { return raw }
        raw.alturaMediaM = cells.heights.reduce(0, +) / Float(cells.heights.count)
        raw.alturaMaximaM = cells.heights.max()
        let lateralValues = canopy.map { dot(lateral, $0) }
        if lateralValues.count >= 10 {
            raw.larguraM = max(0, percentile(lateralValues, 0.95) - percentile(lateralValues, 0.05))
        }
        raw.volumeM3 = cells.volume
        raw.comprimentoM = cells.length
        if let length = cells.length, length > 0.05 {
            raw.volumePorMetro = cells.volume / length
        }
        raw.histograma = histogram(of: canopy.map { fit.plane.height($0) })
        return raw
    }

    static func histogram(of heights: [Float]) -> [FaixaAltura] {
        let binCount = 20
        var counts = [Int](repeating: 0, count: binCount)
        var used = 0
        for height in heights where height > 0.02 && height < alturaMaximaAceita {
            let cm = min(199, max(0, Int(height * 100)))
            let bin = min(binCount - 1, cm / 10)
            counts[bin] += 1
            used += 1
        }
        var bands: [FaixaAltura] = []
        for index in 0..<binCount {
            let fraction = used > 0 ? Float(counts[index]) / Float(used) : 0
            bands.append(FaixaAltura(deCm: index * 10, ateCm: (index + 1) * 10, fracao: fraction))
        }
        return bands
    }

    static func voxelDownsample(_ points: [WorldPoint], voxel: Float) -> [WorldPoint] {
        guard voxel > 0 else { return points }
        var chosen: [SIMD3<Int>: WorldPoint] = [:]
        chosen.reserveCapacity(points.count)
        for point in points {
            let key = SIMD3<Int>(
                Int(floor(point.position.x / voxel)),
                Int(floor(point.position.y / voxel)),
                Int(floor(point.position.z / voxel))
            )
            if let existing = chosen[key] {
                if point.isFloor && !existing.isFloor {
                    chosen[key] = point
                }
            } else {
                chosen[key] = point
            }
        }
        return Array(chosen.values)
    }

    private struct CellSummary {
        var heights: [Float]
        var volume: Float
        var length: Float?
    }

    private static func cellHeights(
        points: [SIMD3<Float>],
        plane: PlaneModel,
        along: SIMD3<Float>,
        lateral: SIMD3<Float>,
        restrictToWindow: Bool,
        windowCenter: Float,
        windowHalf: Float
    ) -> CellSummary {
        struct Key: Hashable {
            var a: Int
            var b: Int
        }
        var buckets: [Key: [Float]] = [:]
        for point in points {
            let height = plane.height(point)
            if height < 0.03 || height > alturaMaximaAceita { continue }
            let alongValue = dot(along, point)
            let lateralValue = dot(lateral, point)
            if restrictToWindow && (alongValue < windowCenter - windowHalf || alongValue > windowCenter + windowHalf) {
                continue
            }
            let key = Key(
                a: Int(floor(alongValue / cellSize)),
                b: Int(floor(lateralValue / cellSize))
            )
            buckets[key, default: []].append(height)
        }
        var heights: [Float] = []
        var minA = Int.max
        var maxA = Int.min
        for (key, values) in buckets where values.count >= 2 {
            heights.append(percentile(values, 0.90))
            minA = min(minA, key.a)
            maxA = max(maxA, key.a)
        }
        let volume = heights.reduce(Float(0)) { $0 + $1 * cellSize * cellSize }
        let length: Float?
        if heights.isEmpty || minA > maxA {
            length = nil
        } else {
            let span = Float(maxA - minA + 1) * cellSize
            length = min(1, max(span, cellSize))
        }
        return CellSummary(heights: heights, volume: volume, length: length)
    }

    private static func rowDirection(path: [SIMD3<Float>], points: [SIMD3<Float>], plane: PlaneModel) -> SIMD3<Float> {
        let source = path.count >= 2 ? path : points
        guard source.count >= 2 else { return SIMD3<Float>(1, 0, 0) }
        var mean = SIMD3<Float>(0, 0, 0)
        for point in source { mean += point }
        mean /= Float(source.count)
        var cxx: Float = 0
        var czz: Float = 0
        var cxz: Float = 0
        for point in source {
            let dx = point.x - mean.x
            let dz = point.z - mean.z
            cxx += dx * dx
            czz += dz * dz
            cxz += dx * dz
        }
        let angle = 0.5 * atan2(2 * cxz, cxx - czz)
        let direction = SIMD3<Float>(cos(angle), 0, sin(angle))
        let projected = direction - plane.normal * dot(plane.normal, direction)
        if length(projected) < 0.05 { return SIMD3<Float>(1, 0, 0) }
        return normalize(projected)
    }

    private static func horizontalAxis(_ direction: SIMD3<Float>, planeNormal: SIMD3<Float>) -> SIMD3<Float> {
        var axis = direction - planeNormal * dot(planeNormal, direction)
        if length(axis) < 0.05 {
            axis = SIMD3<Float>(1, 0, 0) - planeNormal * planeNormal.x
        }
        if length(axis) < 0.05 {
            axis = SIMD3<Float>(0, 0, 1) - planeNormal * planeNormal.z
        }
        return normalize(axis)
    }
}

struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(_ upper: Int) -> Int {
        if upper <= 1 { return 0 }
        return Int(next() % UInt64(upper))
    }
}
