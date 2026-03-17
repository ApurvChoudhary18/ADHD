import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.layer.addSublayer(cameraManager.previewLayer)
        cameraManager.previewLayer.frame = view.bounds
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            cameraManager.previewLayer.frame = uiView.bounds
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        CameraManager.shared.stopSession()
    }
}

#Preview {
    CameraPreviewView(cameraManager: CameraManager.shared)
}
