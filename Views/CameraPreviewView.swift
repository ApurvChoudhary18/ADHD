import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.cameraManager = cameraManager
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.updatePreviewFrame()
    }
    
    static func dismantleUIView(_ uiView: CameraPreviewUIView, coordinator: ()) {
        uiView.cleanup()
    }
}

class CameraPreviewUIView: UIView {
    var cameraManager: CameraManager? {
        didSet {
            if let manager = cameraManager {
                setupPreviewLayer(with: manager)
            }
        }
    }
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .black
        clipsToBounds = true
    }
    
    private func setupPreviewLayer(with manager: CameraManager) {
        previewLayer?.removeFromSuperlayer()
        
        let layer = AVCaptureVideoPreviewLayer(session: manager.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        previewLayer = layer
        
        manager.startSession()
    }
    
    func updatePreviewFrame() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let layer = self.previewLayer else { return }
            layer.frame = self.bounds
        }
    }
    
    func cleanup() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

#Preview {
    CameraPreviewView(cameraManager: CameraManager.shared)
}
