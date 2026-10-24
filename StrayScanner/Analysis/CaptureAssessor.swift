// FaleAgro LiDAR — protótipo 1
// Lê o quadro do ARKit (cor, sceneDepth, confiança, pose) para a análise.
// A gravação bruta continua no DatasetEncoder.
// Baseado no Stray Scanner (MIT, Stray Robots).

import ARKit
import CoreVideo
import Foundation

final class CaptureAssessor {
    let modality: CaptureModality
    let escalaConfirmada: Bool
    private let lock = NSLock()
    private var recording = false
    private var recordingStarted: Date?
    private var samples: [FrameSample] = []
    private var warnings = WarningTotals()
    private var mesh: [UUID: [MeshPoint]] = [:]
    private var path: [SIMD3<Float>] = []
    private var lastTimestamp: Double?
    private var lastPosition: SIMD3<Float>?
    private var nextSampleTime: Double = 0
    private var sampleInterval: Double = 0.45
    private var nextPathTime: Double = 0

    init(modality: CaptureModality, escalaConfirmada: Bool) {
        self.modality = modality
        self.escalaConfirmada = escalaConfirmada
    }

    func setRecording(_ on: Bool) {
        lock.lock()
        recording = on
        if on {
            recordingStarted = Date()
            nextSampleTime = 0
            nextPathTime = 0
        }
        lock.unlock()
    }

    func update(frame: ARFrame) -> [AvisoTela] {
        let transform = frame.camera.transform
        let position = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let lookY = -transform.columns.2.y
        let tracking = qualidade(frame.camera.trackingState)
        let excesso = movimentoExcessivo(frame.camera.trackingState)
        let timestamp = frame.timestamp

        var speed: Float = 0
        if let lastTimestamp, let lastPosition {
            let dt = timestamp - lastTimestamp
            if dt > 0.001 && dt < 0.5 {
                let dx = position.x - lastPosition.x
                let dy = position.y - lastPosition.y
                let dz = position.z - lastPosition.z
                speed = Float(((dx * dx + dy * dy + dz * dz) / Float(dt * dt)).squareRoot())
            }
        }

        let sceneDepth = frame.sceneDepth
        var lowFraction: Float = 1
        var storedSample: FrameSample?
        if let sceneDepth {
            lowFraction = fractionLow(sceneDepth.confidenceMap) ?? 1
            if shouldSample(timestamp: timestamp) {
                storedSample = makeSample(
                    frame: frame,
                    depthMap: sceneDepth.depthMap,
                    confidenceMap: sceneDepth.confidenceMap,
                    position: position,
                    lookY: lookY,
                    tracking: tracking,
                    lowFraction: lowFraction,
                    speed: speed
                )
            }
        }

        lock.lock()
        lastTimestamp = timestamp
        lastPosition = position
        let gravando = recording
        let segundos: Float
        if gravando, let recordingStarted {
            segundos = Float(Date().timeIntervalSince(recordingStarted))
        } else {
            segundos = 0
        }
        if gravando {
            warnings.quadrosAvaliados += 1
            if tracking == .perdido { warnings.rastreamentoPerdido += 1 }
            if tracking == .limitado { warnings.rastreamentoLimitado += 1 }
            if excesso || speed > CaptureWarningLogic.velocidadeLimite(modality) {
                warnings.rapidoDemais += 1
            }
            if sceneDepth == nil || lowFraction > 0.45 {
                warnings.profundidadeBaixa += 1
            }
            if timestamp >= nextPathTime {
                path.append(position)
                if path.count > 4000 {
                    path = path.enumerated().compactMap { index, item in index % 2 == 0 ? item : nil }
                }
                nextPathTime = timestamp + 0.1
            }
            if let storedSample {
                samples.append(storedSample)
                if samples.count > 90 {
                    samples = samples.enumerated().compactMap { index, item in index % 2 == 0 ? item : nil }
                    sampleInterval *= 2
                }
                nextSampleTime = timestamp + sampleInterval
            }
        }
        let amostrasCima = samples.filter { $0.viewDirectionY > 0.55 }.count
        let amostrasBaixo = samples.filter { $0.viewDirectionY < -0.55 }.count
        let amostrasProfundidade = samples.filter { $0.lowConfidenceFraction < 0.55 }.count
        let stats = CanopyMath.pathStats(path)
        let vertices = mesh.values.reduce(0) { $0 + $1.count }
        lock.unlock()

        let contexto = ContextoAvisos(
            modality: modality,
            gravando: gravando,
            tracking: tracking,
            movimentoExcessivoDoARKit: excesso,
            velocidade: speed,
            fracaoProfundidadeBaixa: lowFraction,
            segundosGravando: segundos,
            amostrasParaCima: amostrasCima,
            amostrasParaBaixo: amostrasBaixo,
            comprimentoPercurso: stats.length,
            dispersaoLateral: stats.lateralSpread,
            verticesMalha: vertices,
            amostrasComProfundidade: amostrasProfundidade,
            escalaConfirmada: escalaConfirmada,
            semCenaProfundidade: sceneDepth == nil
        )
        return CaptureWarningLogic.mensagens(contexto)
    }

    func ingestMesh(_ anchors: [ARAnchor]) {
        var updates: [(UUID, [MeshPoint])] = []
        for anchor in anchors {
            guard let meshAnchor = anchor as? ARMeshAnchor else { continue }
            updates.append((meshAnchor.identifier, pontos(meshAnchor)))
        }
        guard !updates.isEmpty else { return }
        lock.lock()
        for update in updates {
            mesh[update.0] = update.1
        }
        lock.unlock()
    }

    func removeMesh(_ anchors: [ARAnchor]) {
        lock.lock()
        for anchor in anchors {
            mesh.removeValue(forKey: anchor.identifier)
        }
        lock.unlock()
    }

    func snapshot() -> (samples: [FrameSample], mesh: [MeshPoint], path: [SIMD3<Float>], warnings: WarningTotals, meshVertices: Int) {
        lock.lock()
        let copySamples = samples
        let copyPath = path
        let copyWarnings = warnings
        let copyMesh = mesh.values.flatMap { $0 }
        let vertices = copyMesh.count
        lock.unlock()
        return (copySamples, copyMesh, copyPath, copyWarnings, vertices)
    }

    private func shouldSample(timestamp: Double) -> Bool {
        lock.lock()
        let gravando = recording
        let due = timestamp >= nextSampleTime
        lock.unlock()
        return gravando && due
    }

    private func qualidade(_ state: ARCamera.TrackingState) -> TrackingQuality {
        switch state {
        case .normal:
            return .normal
        case .notAvailable:
            return .perdido
        case .limited:
            return .limitado
        }
    }

    private func movimentoExcessivo(_ state: ARCamera.TrackingState) -> Bool {
        if case .limited(let reason) = state, reason == .excessiveMotion {
            return true
        }
        return false
    }

    private func makeSample(
        frame: ARFrame,
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        position: SIMD3<Float>,
        lookY: Float,
        tracking: TrackingQuality,
        lowFraction: Float,
        speed: Float
    ) -> FrameSample? {
        guard let depth = copyDepth(depthMap) else { return nil }
        let confidence = copyConfidence(confidenceMap, width: depth.width, height: depth.height)
        let rgba = rgbaMatchingDepth(from: frame.capturedImage, depthWidth: depth.width, depthHeight: depth.height)
        let imageWidth = CVPixelBufferGetWidth(frame.capturedImage)
        let imageHeight = CVPixelBufferGetHeight(frame.capturedImage)
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let intrinsics = frame.camera.intrinsics
        let scaleX = Float(depth.width) / Float(imageWidth)
        let scaleY = Float(depth.height) / Float(imageHeight)
        return FrameSample(
            timestamp: frame.timestamp,
            rgba: rgba,
            width: depth.width,
            height: depth.height,
            depth: depth.values,
            confidence: confidence.values,
            fx: intrinsics.columns.0.x * scaleX,
            fy: intrinsics.columns.1.y * scaleY,
            cx: intrinsics.columns.2.x * scaleX,
            cy: intrinsics.columns.2.y * scaleY,
            transform: matrixArray(frame.camera.transform),
            viewDirectionY: lookY,
            tracking: tracking,
            lowConfidenceFraction: confidence.lowFraction,
            speedMetersPerSecond: speed
        )
    }

    private func copyDepth(_ buffer: CVPixelBuffer) -> (values: [Float], width: Int, height: Int)? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var values = [Float](repeating: .nan, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                let depth = row[x]
                if depth.isFinite && depth > 0.05 && depth < 8 {
                    values[y * width + x] = depth
                }
            }
        }
        return (values, width, height)
    }

    private func copyConfidence(_ buffer: CVPixelBuffer?, width: Int, height: Int) -> (values: [UInt8], lowFraction: Float) {
        var values = [UInt8](repeating: 0, count: width * height)
        guard let buffer, CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height else {
            return (values, 1)
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            return (values, 1)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return (values, 1) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var low = 0
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let value = row[x]
                values[y * width + x] = value
                if value == 0 { low += 1 }
            }
        }
        return (values, Float(low) / Float(width * height))
    }

    private func fractionLow(_ buffer: CVPixelBuffer?) -> Float? {
        guard let buffer else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        return copyConfidence(buffer, width: width, height: height).lowFraction
    }

    private func rgbaMatchingDepth(from image: CVPixelBuffer, depthWidth: Int, depthHeight: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: depthWidth * depthHeight * 4)
        guard CVPixelBufferGetPlaneCount(image) >= 2 else { return rgba }
        guard CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess else { return rgba }
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(image, 0),
              let uvPlane = CVPixelBufferGetBaseAddressOfPlane(image, 1) else { return rgba }
        let imageWidth = CVPixelBufferGetWidth(image)
        let imageHeight = CVPixelBufferGetHeight(image)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(image, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(image, 1)
        let fullRange = CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard imageWidth > 1, imageHeight > 1 else { return rgba }
        for y in 0..<depthHeight {
            let sourceY = min(imageHeight - 1, max(0, Int((Float(y) + 0.5) * Float(imageHeight) / Float(depthHeight))))
            let yRow = yPlane.advanced(by: sourceY * yStride).assumingMemoryBound(to: UInt8.self)
            let uvRow = uvPlane.advanced(by: (sourceY / 2) * uvStride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<depthWidth {
                let sourceX = min(imageWidth - 1, max(0, Int((Float(x) + 0.5) * Float(imageWidth) / Float(depthWidth))))
                let luma = Float(yRow[sourceX])
                let cb = Float(uvRow[(sourceX / 2) * 2])
                let cr = Float(uvRow[(sourceX / 2) * 2 + 1])
                let rgb = rgb(luma: luma, cb: cb, cr: cr, fullRange: fullRange)
                let index = (y * depthWidth + x) * 4
                rgba[index] = rgb.0
                rgba[index + 1] = rgb.1
                rgba[index + 2] = rgb.2
                rgba[index + 3] = 255
            }
        }
        return rgba
    }

    private func rgb(luma: Float, cb: Float, cr: Float, fullRange: Bool) -> (UInt8, UInt8, UInt8) {
        let yValue: Float
        if fullRange {
            yValue = luma
        } else {
            yValue = (luma - 16) * (255 / 219)
        }
        let cbCentered = cb - 128
        let crCentered = cr - 128
        let red = yValue + 1.402 * crCentered
        let green = yValue - 0.344136 * cbCentered - 0.714136 * crCentered
        let blue = yValue + 1.772 * cbCentered
        return (clampByte(red), clampByte(green), clampByte(blue))
    }

    private func clampByte(_ value: Float) -> UInt8 {
        if value <= 0 { return 0 }
        if value >= 255 { return 255 }
        return UInt8(value)
    }

    private func matrixArray(_ matrix: simd_float4x4) -> [Float] {
        var values = [Float](repeating: 0, count: 16)
        for column in 0..<4 {
            for row in 0..<4 {
                values[column * 4 + row] = matrix[column][row]
            }
        }
        return values
    }

    private func pontos(_ anchor: ARMeshAnchor) -> [MeshPoint] {
        let geometry = anchor.geometry
        let vertices = geometry.vertices
        guard vertices.count > 0 else { return [] }
        let contents = vertices.buffer.contents()
        let classification = geometry.classification
        var points: [MeshPoint] = []
        let step = 3
        points.reserveCapacity(vertices.count / step)
        var index = 0
        while index < vertices.count {
            let vertexPointer = contents.advanced(by: vertices.offset + vertices.stride * index).assumingMemoryBound(to: Float.self)
            let local = SIMD3<Float>(vertexPointer[0], vertexPointer[1], vertexPointer[2])
            let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
            var isFloor = false
            if let classification, index < classification.count {
                let classPointer = classification.buffer.contents().advanced(by: classification.offset + classification.stride * index)
                let raw = classPointer.assumingMemoryBound(to: UInt8.self).pointee
                isFloor = raw == UInt8(ARMeshClassification.floor.rawValue)
            }
            points.append(MeshPoint(position: SIMD3<Float>(world.x, world.y, world.z), isFloor: isFloor))
            index += step
        }
        return points
    }
}
