//
//  RecordSessionViewController.swift
//  Stray Scanner / FaleAgro LiDAR
//
//  Captura RGB-D do Stray Scanner, com avisos e medidas de dossel.
//

import ARKit
import CoreData
import CoreMotion
import Foundation
import Metal
import UIKit

let FpsDividers: [Int] = [1, 2, 4, 12, 60]
let AvailableFpsSettings: [Int] = FpsDividers.map { Int(60 / $0) }
let FpsUserDefaultsKey: String = "FaleAgroFPSIndex"

class MetalView: UIView {
    override class var layerClass: AnyClass {
        get { CAMetalLayer.self }
    }
    override var layer: CAMetalLayer {
        super.layer as! CAMetalLayer
    }
}

private final class BannerLabel: UILabel {
    var insets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

class RecordSessionViewController: UIViewController, ARSessionDelegate {
    private var unsupported = false
    private var arConfiguration: ARWorldTrackingConfiguration?
    private let session = ARSession()
    private let motionManager = CMMotionManager()
    private var renderer: CameraRenderer?
    private var updateLabelTimer: Timer?
    private var startedRecording: Date?
    private var dataContext: NSManagedObjectContext!
    private var datasetEncoder: DatasetEncoder?
    private let imuOperationQueue = OperationQueue()
    private var chosenFpsSetting = 3
    private let recordingLock = NSLock()
    private var recordingActive = false
    private var didFinalize = false
    private var assessor: CaptureAssessor?
    private var lastWarningSignature = ""
    private var lastWarningUITime: TimeInterval = 0
    private let warningStack = UIStackView()
    private let instructionLabel = BannerLabel()
    private var warningLabels: [BannerLabel] = []
    private let processingCover = UIView()
    private let processingLabel = UILabel()

    @IBOutlet private var rgbView: MetalView!
    @IBOutlet private var depthView: MetalView!
    @IBOutlet private var recordButton: RecordButton!
    @IBOutlet private var timeLabel: UILabel!
    @IBOutlet weak var fpsButton: UIButton!
    var dismissFunction: Optional<() -> Void> = Optional.none
    var metadata: CaptureMetadata?

    func setDismissFunction(_ fn: Optional<() -> Void>) {
        dismissFunction = fn
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if UserDefaults.standard.object(forKey: FpsUserDefaultsKey) == nil {
            chosenFpsSetting = 3
        } else {
            chosenFpsSetting = UserDefaults.standard.integer(forKey: FpsUserDefaultsKey)
        }
        if chosenFpsSetting < 0 || chosenFpsSetting >= AvailableFpsSettings.count {
            chosenFpsSetting = 3
        }
        updateFpsSetting()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        dataContext = appDelegate.persistentContainer.newBackgroundContext()
        renderer = CameraRenderer(rgbLayer: rgbView.layer, depthLayer: depthView.layer)
        if let metadata {
            assessor = CaptureAssessor(modality: metadata.modalidade, escalaConfirmada: metadata.escalaConfirmada)
        }

        depthView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewTapped)))
        rgbView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewTapped)))

        setViewProperties()
        session.delegate = self
        recordButton.setCallback { recording in
            self.toggleRecording(recording)
        }
        fpsButton.layer.masksToBounds = true
        fpsButton.layer.cornerRadius = 12.0
        imuOperationQueue.qualityOfService = .userInitiated
        installOverlays()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.pause()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        recordingLock.lock()
        let active = recordingActive
        recordingLock.unlock()
        if active {
            stopRecording(dismissAfter: false)
        } else {
            updateLabelTimer?.invalidate()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = max(20, warningStack.bounds.width - 24)
        instructionLabel.preferredMaxLayoutWidth = width
        for label in warningLabels {
            label.preferredMaxLayoutWidth = width
        }
    }

    private func startSession() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal]
        arConfiguration = config
        guard ARWorldTrackingConfiguration.isSupported, ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            unsupported = true
            showUnsupportedAlert()
            return
        }
        config.frameSemantics.insert(.sceneDepth)
        if metadata?.modalidade == .lateral {
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
                config.sceneReconstruction = .meshWithClassification
            } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }
        }
        session.run(config)
    }

    private func startRawIMU() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 1200.0
            motionManager.startAccelerometerUpdates(to: imuOperationQueue) { data, error in
                guard let data else {
                    if let error { print("Error retrieving accelerometer data: \(error.localizedDescription)") }
                    return
                }
                self.datasetEncoder?.addRawAccelerometer(data: data)
            }
        }
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 1200.0
            motionManager.startGyroUpdates(to: imuOperationQueue) { data, error in
                guard let data else {
                    if let error { print("Error retrieving gyroscope data: \(error.localizedDescription)") }
                    return
                }
                self.datasetEncoder?.addRawGyroscope(data: data)
            }
        }
    }

    private func stopRawIMU() {
        if motionManager.isAccelerometerActive { motionManager.stopAccelerometerUpdates() }
        if motionManager.isGyroActive { motionManager.stopGyroUpdates() }
    }

    private func toggleRecording(_ recording: Bool) {
        if unsupported {
            showUnsupportedAlert()
            return
        }
        if metadata == nil {
            showMessage(title: "Falta a ficha", message: "Volte e preencha a fazenda, o talhão e a modalidade antes de gravar.")
            return
        }
        recordingLock.lock()
        let active = recordingActive
        recordingLock.unlock()
        if recording && !active {
            startRecording()
        } else if active && !recording {
            stopRecording(dismissAfter: true)
        }
    }

    private func startRecording() {
        guard let configuration = arConfiguration else { return }
        recordingLock.lock()
        recordingActive = true
        didFinalize = false
        recordingLock.unlock()
        startedRecording = Date()
        updateTime()
        updateLabelTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            self.updateTime()
        }
        let encoder = DatasetEncoder(arConfiguration: configuration, fpsDivider: FpsDividers[chosenFpsSetting])
        datasetEncoder = encoder
        if let metadata {
            try? ReportFiles.writeIdentificacao(metadata, to: encoder.datasetDirectory)
        }
        assessor?.setRecording(true)
        startRawIMU()
    }

    private func stopRecording(dismissAfter: Bool) {
        recordingLock.lock()
        if didFinalize || !recordingActive {
            recordingLock.unlock()
            return
        }
        didFinalize = true
        recordingActive = false
        let encoder = datasetEncoder
        recordingLock.unlock()

        let started = startedRecording ?? Date()
        let duration = Date().timeIntervalSince(started)
        startedRecording = nil
        updateLabelTimer?.invalidate()
        updateLabelTimer = nil
        stopRawIMU()
        assessor?.setRecording(false)
        showProcessing(true)

        let metadata = self.metadata
        let assessor = self.assessor
        DispatchQueue.global(qos: .userInitiated).async {
            encoder?.wrapUp()
            let snap = assessor?.snapshot()
            var report: RelatorioCaptura?
            var cloud: [WorldPoint] = []
            if let metadata, let snap {
                let analysis = CanopyAnalyzer.analisar(
                    metadata: metadata,
                    startedAt: started,
                    duration: duration,
                    samples: snap.samples,
                    meshPoints: snap.mesh,
                    path: snap.path,
                    warnings: snap.warnings,
                    meshVertexCount: snap.meshVertices
                )
                var ajustado = analysis.relatorio
                cloud = analysis.nuvem
                if let encoder, encoder.status != .allGood {
                    ajustado.motivos.append("A gravação bruta do vídeo ou da profundidade teve um erro. As medidas usaram os quadros já lidos na memória.")
                    ajustado.confiancaGeral = min(ajustado.confiancaGeral, 0.4)
                    ajustado.rotuloConfiancaGeral = TextoBR.rotuloConfianca(ajustado.confiancaGeral)
                }
                report = ajustado
            }
            if let encoder, let report {
                try? ReportFiles.writeRelatorio(report, to: encoder.datasetDirectory)
                if !cloud.isEmpty {
                    try? ReportFiles.writePLY(cloud, to: encoder.datasetDirectory)
                }
            }
            DispatchQueue.main.async {
                if let encoder {
                    self.saveRecording(started: started, duration: duration, encoder: encoder, report: report)
                }
                self.showProcessing(false)
                NotificationCenter.default.post(name: NSNotification.Name("sessionsChanged"), object: nil)
                if dismissAfter {
                    self.dismissFunction?()
                }
            }
        }
    }

    private func saveRecording(started: Date, duration: TimeInterval, encoder: DatasetEncoder, report: RelatorioCaptura?) {
        guard let metadata else { return }
        let json = report.flatMap { try? String(data: ReportFiles.jsonEncoder().encode($0), encoding: .utf8) }
        dataContext.performAndWait {
            guard let entity = NSEntityDescription.entity(forEntityName: "Recording", in: self.dataContext) else { return }
            let recording = Recording(entity: entity, insertInto: self.dataContext)
            recording.id = encoder.id
            recording.duration = duration
            recording.createdAt = started
            recording.name = metadata.tituloCurto
            recording.rgbFilePath = encoder.rgbFilePath.relativeString
            recording.depthFilePath = encoder.depthFilePath.relativeString
            recording.fazenda = metadata.fazenda
            recording.talhao = metadata.talhao
            recording.variedade = metadata.variedade
            recording.dataPlantio = metadata.dataPlantio
            recording.tratamento = metadata.tratamento
            recording.pontoAmostral = Int16(metadata.pontoAmostral)
            recording.modalidade = metadata.modalidade.rawValue
            recording.escalaConfirmada = metadata.escalaConfirmada
            recording.metricsSummary = report?.resumoLista
            recording.metricsJSON = json
            recording.confidenceScore = report?.confiancaGeral ?? 0
            do {
                try self.dataContext.save()
            } catch {
                print("Could not save recording. \(error)")
            }
        }
    }

    private func showMessage(title: String, message: String) {
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.addAction(UIAlertAction(title: "OK", style: .default))
        present(controller, animated: true)
    }

    private func updateTime() {
        guard let started = startedRecording else { return }
        let seconds = Date().timeIntervalSince(started)
        let minutes = Int(floor(seconds / 60).truncatingRemainder(dividingBy: 60))
        let hours = Int(floor(seconds / 3600))
        let roundSeconds = Int(floor(seconds.truncatingRemainder(dividingBy: 60)))
        timeLabel.text = String(format: "%02d:%02d:%02d", hours, minutes, roundSeconds)
    }

    @objc func viewTapped() {
        guard let renderer else { return }
        switch renderer.renderMode {
        case .depth:
            renderer.renderMode = .rgb
            rgbView.isHidden = false
            depthView.isHidden = true
        case .rgb:
            renderer.renderMode = .depth
            depthView.isHidden = false
            rgbView.isHidden = true
        }
    }

    @IBAction func fpsButtonTapped() {
        chosenFpsSetting = (chosenFpsSetting + 1) % AvailableFpsSettings.count
        updateFpsSetting()
        UserDefaults.standard.set(chosenFpsSetting, forKey: FpsUserDefaultsKey)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        renderer?.render(frame: frame)
        let avisos = assessor?.update(frame: frame) ?? []
        let now = Date().timeIntervalSinceReferenceDate
        if now - lastWarningUITime > 0.25 {
            lastWarningUITime = now
            let signature = avisos.map(\.texto).joined(separator: "|")
            if signature != lastWarningSignature {
                lastWarningSignature = signature
                DispatchQueue.main.async {
                    self.showWarnings(avisos)
                }
            }
        }
        recordingLock.lock()
        let active = recordingActive
        if active {
            datasetEncoder?.add(frame: frame)
        }
        recordingLock.unlock()
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        assessor?.ingestMesh(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        assessor?.ingestMesh(anchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        assessor?.removeMesh(anchors)
    }

    private func setViewProperties() {
        view.backgroundColor = UIColor(named: "BackgroundColor")
    }

    private func updateFpsSetting() {
        let fps = AvailableFpsSettings[chosenFpsSetting]
        fpsButton.setTitle("\(fps)/s", for: .normal)
    }

    private func showUnsupportedAlert() {
        let alert = UIAlertController(
            title: "Este iPhone não serve",
            message: "O FaleAgro LiDAR precisa do sensor LiDAR e do ARKit. Use um iPhone 16 Pro Max (ou outro iPhone Pro com LiDAR).",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.dismissFunction?()
        }))
        present(alert, animated: true)
    }

    private func installOverlays() {
        instructionLabel.numberOfLines = 0
        instructionLabel.textAlignment = .center
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        instructionLabel.backgroundColor = UIColor(red: 0.05, green: 0.28, blue: 0.12, alpha: 0.88)
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.clipsToBounds = true
        let instrucao = metadata?.modalidade.instrucaoCurta ?? "Aponte a câmera para a lavoura."
        instructionLabel.text = instrucao + " Toque na imagem para alternar cor e profundidade."

        warningStack.axis = .vertical
        warningStack.spacing = 6
        warningStack.translatesAutoresizingMaskIntoConstraints = false
        warningStack.addArrangedSubview(instructionLabel)
        view.addSubview(warningStack)

        processingCover.translatesAutoresizingMaskIntoConstraints = false
        processingCover.backgroundColor = UIColor(white: 0, alpha: 0.55)
        processingCover.isHidden = true
        processingLabel.translatesAutoresizingMaskIntoConstraints = false
        processingLabel.textColor = .white
        processingLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        processingLabel.numberOfLines = 0
        processingLabel.textAlignment = .center
        processingLabel.text = "Calculando as medidas neste iPhone.\nPode levar alguns segundos."
        processingCover.addSubview(processingLabel)
        view.addSubview(processingCover)

        NSLayoutConstraint.activate([
            warningStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            warningStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            warningStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            processingCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            processingCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            processingCover.topAnchor.constraint(equalTo: view.topAnchor),
            processingCover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            processingLabel.centerXAnchor.constraint(equalTo: processingCover.centerXAnchor),
            processingLabel.centerYAnchor.constraint(equalTo: processingCover.centerYAnchor),
            processingLabel.leadingAnchor.constraint(equalTo: processingCover.leadingAnchor, constant: 24),
            processingLabel.trailingAnchor.constraint(equalTo: processingCover.trailingAnchor, constant: -24)
        ])
    }

    private func showWarnings(_ avisos: [AvisoTela]) {
        for label in warningLabels {
            warningStack.removeArrangedSubview(label)
            label.removeFromSuperview()
        }
        warningLabels.removeAll()
        for aviso in avisos.prefix(4) {
            let label = BannerLabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.textColor = .white
            label.font = .systemFont(ofSize: 14, weight: .bold)
            label.text = aviso.texto
            label.layer.cornerRadius = 10
            label.clipsToBounds = true
            switch aviso.nivel {
            case .grave:
                label.backgroundColor = UIColor(red: 0.62, green: 0.12, blue: 0.08, alpha: 0.92)
            case .atencao:
                label.backgroundColor = UIColor(red: 0.55, green: 0.32, blue: 0.05, alpha: 0.92)
            case .info:
                label.backgroundColor = UIColor(white: 0.1, alpha: 0.72)
            }
            warningStack.addArrangedSubview(label)
            warningLabels.append(label)
        }
    }

    private func showProcessing(_ on: Bool) {
        processingCover.isHidden = !on
        recordButton.isUserInteractionEnabled = !on
        if on { view.bringSubviewToFront(processingCover) }
    }
}
