import Foundation
import AVFoundation
import UIKit
import Combine

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didCaptureFrame image: UIImage)
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

protocol CameraFrameDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutputContinuousFrame image: UIImage)
}

final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()
    
    @Published var isAuthorized = false
    @Published var isSessionRunning = false
    @Published var capturedFrames: [UIImage] = []
    @Published var currentFrame: UIImage?
    @Published var isContinuousCaptureEnabled = false
    @Published var permissionError: String?
    
    weak var delegate: CameraManagerDelegate?
    weak var frameDelegate: CameraFrameDelegate?
    
    let session: AVCaptureSession
    let previewLayer: AVCaptureVideoPreviewLayer
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.memorycam.camera.session")
    private let processingQueue = DispatchQueue(label: "com.memorycam.camera.processing", qos: .userInteractive)
    
    private var isCapturingFrames = false
    private var frameCaptureCount = 0
    private var targetFrameCount = 10
    
    private var lastFrameTime: Date = Date()
    private var frameInterval: TimeInterval = 0.3
    private var continuousFrameCallback: ((UIImage) -> Void)?
    
    private override init() {
        session = AVCaptureSession()
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }
    
    func checkAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            await MainActor.run {
                self.isAuthorized = true
                self.permissionError = nil
            }
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                self.isAuthorized = granted
                if !granted {
                    self.permissionError = "Camera access denied. Please enable in Settings."
                }
            }
        case .denied, .restricted:
            await MainActor.run {
                self.isAuthorized = false
                self.permissionError = "Camera access denied. Please enable in Settings."
            }
        @unknown default:
            await MainActor.run {
                self.isAuthorized = false
                self.permissionError = "Unknown camera permission status."
            }
        }
    }
    
    func configure() {
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }
    
    private func setupSession() {
        guard !Thread.isMainThread else {
            sessionQueue.async { [weak self] in
                self?.setupSession()
            }
            return
        }
        
        session.beginConfiguration()
        session.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            print("[CameraManager] Failed to get video device")
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                print("[CameraManager] Cannot add video input")
            }
            
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            
            session.commitConfiguration()
            print("[CameraManager] Session configured successfully")
            
        } catch {
            print("[CameraManager] Failed to setup session: \(error)")
            session.commitConfiguration()
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
                return
            }
            
            self.session.startRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
            
            print("[CameraManager] Session started: \(self.session.isRunning)")
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if !self.session.isRunning {
                return
            }
            
            self.session.stopRunning()
            
            DispatchQueue.main.async {
                self.isSessionRunning = false
            }
            
            print("[CameraManager] Session stopped")
        }
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func startFrameCapture(count: Int = 10, callback: @escaping (UIImage) -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.capturedFrames.removeAll()
            self?.frameCaptureCount = 0
            self?.targetFrameCount = count
            self?.isCapturingFrames = true
            self?.continuousFrameCallback = callback
        }
    }
    
    func stopFrameCapture() {
        DispatchQueue.main.async { [weak self] in
            self?.isCapturingFrames = false
            self?.continuousFrameCallback = nil
        }
    }
    
    func stopContinuousFrameCapture() {
        DispatchQueue.main.async { [weak self] in
            self?.isContinuousCaptureEnabled = false
        }
    }
    
    func getLastFrame() -> UIImage? {
        return capturedFrames.last
    }
    
    func getCurrentFrame() -> UIImage? {
        return currentFrame
    }
    
    func setFrameCallback(_ callback: @escaping (UIImage) -> Void) {
        continuousFrameCallback = callback
        isContinuousCaptureEnabled = true
    }
    
    private func shouldProcessFrame() -> Bool {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFrameTime)
        return elapsed >= frameInterval
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraManager(self, didOutput: sampleBuffer)
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let image = UIImage(cgImage: cgImage)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrame = image
        }
        
        if isContinuousCaptureEnabled && shouldProcessFrame() {
            lastFrameTime = Date()
            
            if let callback = continuousFrameCallback {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let frame = self.currentFrame else { return }
                    callback(frame)
                }
            }
            
            frameDelegate?.cameraManager(self, didOutputContinuousFrame: image)
        }
        
        guard isCapturingFrames, frameCaptureCount < targetFrameCount else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.capturedFrames.append(image)
            self.frameCaptureCount += 1
            self.delegate?.cameraManager(self, didCaptureFrame: image)
            
            if self.frameCaptureCount >= self.targetFrameCount {
                self.isCapturingFrames = false
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            delegate?.cameraManager(self, didFailWithError: error)
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.capturedFrames.append(image)
        }
    }
}
