//
//  CameraPreviewView.swift
//  Squirrel2
//
//  Live camera preview using AVFoundation for inline camera experience
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    @Binding var capturedImage: UIImage?
    @Binding var isCapturing: Bool
    let onError: (String) -> Void
    
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        let parent: CameraPreviewView
        var captureSession: AVCaptureSession?
        var photoOutput: AVCapturePhotoOutput?
        var isProcessingPhoto = false
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
            super.init()
        }
        
        func setupCamera(in view: UIView) {
            captureSession = AVCaptureSession()
            guard let captureSession = captureSession else { return }
            
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .photo
            
            // Setup video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
                parent.onError("Camera not available")
                return
            }
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            // Setup photo output
            photoOutput = AVCapturePhotoOutput()
            if let photoOutput = photoOutput, captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
            }
            
            captureSession.commitConfiguration()
            
            // Setup preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
            
            // Start session on background queue
            DispatchQueue.global(qos: .userInitiated).async {
                captureSession.startRunning()
            }
        }
        
        func capturePhoto() {
            guard let photoOutput = photoOutput else {
                parent.onError("Camera not ready")
                return
            }
            
            // Prevent multiple captures
            guard !isProcessingPhoto else {
                print("Already processing a photo, skipping capture")
                return
            }
            
            isProcessingPhoto = true
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
        
        // AVCapturePhotoCaptureDelegate
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            defer {
                isProcessingPhoto = false
            }
            
            if let error = error {
                parent.onError("Failed to capture photo: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.parent.isCapturing = false
                }
                return
            }
            
            guard let imageData = photo.fileDataRepresentation(),
                  let image = UIImage(data: imageData) else {
                parent.onError("Failed to process photo")
                DispatchQueue.main.async {
                    self.parent.isCapturing = false
                }
                return
            }
            
            // Fix orientation if needed
            let fixedImage = image.fixedOrientation()
            
            DispatchQueue.main.async {
                self.parent.capturedImage = fixedImage
                self.parent.isCapturing = false
            }
        }
        
        func stopSession() {
            captureSession?.stopRunning()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        // Request camera permission first
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted {
                DispatchQueue.main.async {
                    context.coordinator.setupCamera(in: view)
                }
            } else {
                onError("Camera access denied. Please enable in Settings.")
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Handle capture trigger - only capture if isCapturing is true and we're not already processing
        if isCapturing && !context.coordinator.isProcessingPhoto {
            context.coordinator.capturePhoto()
        }
        
        // Update preview layer frame on size changes
        if let previewLayer = uiView.layer.sublayers?.first(where: { $0 is AVCaptureVideoPreviewLayer }) as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSession()
    }
}

// Helper extension to fix image orientation
extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}