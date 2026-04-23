//
//  ZoneKitCameraController.swift
//  ZoneKit
//
//  Created by Dustin Nielson on 2/27/26.
//


#if os(iOS)

import Foundation
import AVFoundation
import CoreMedia
import OSLog
import LoggingKit


// MARK: - CameraControllerDelegate

@available(iOS 17.0, *)
protocol ZoneKitCameraControllerDelegate: AnyObject {
    func cameraController(_ controller: ZoneKitCameraController, didDiscoverCamera source: ZoneKitSource)
    func cameraController(_ controller: ZoneKitCameraController, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, from source: ZoneKitSource)
}

// MARK: - CameraController

@available(iOS 17.0, *)
class ZoneKitCameraController: NSObject {

    private weak var delegate: ZoneKitCameraControllerDelegate?

    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.capturekit.cameraController.sessionQueue", qos: .userInteractive)

    private var frontCamera: AVCaptureDevice?
    private var backCamera: AVCaptureDevice?

    private var currentInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var currentSource: ZoneKitSource?

    private let captureQueue = DispatchQueue(
        label: "com.capturekit.cameraController.capture",
        qos: .userInteractive
    )

    init(delegate: ZoneKitCameraControllerDelegate) {
        self.delegate = delegate
        super.init()

        setupCaptureSession()
    }

    // MARK: - Setup

    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        sessionQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            session.sessionPreset = .high
            session.startRunning()
            mlog.debug("Capture session started")
        }
    }

    // MARK: - Discovery

    func discoverCameras() {
        mlog.debug("Discovering cameras")

        // Discover front camera
        if let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            frontCamera = frontDevice
            let source = createZoneKitSource(position: .front)
            delegate?.cameraController(self, didDiscoverCamera: source)
            mlog.debug("Found front camera")
        }

        // Discover back camera
        if let backDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            backCamera = backDevice
            let source = createZoneKitSource(position: .back)
            delegate?.cameraController(self, didDiscoverCamera: source)
            mlog.debug("Found back camera")
        }
    }

    func availableSources() -> [ZoneKitSource] {
        var sources: [ZoneKitSource] = []

        if frontCamera != nil {
            sources.append(createZoneKitSource(position: .front))
        }

        if backCamera != nil {
            sources.append(createZoneKitSource(position: .back))
        }

        return sources
    }

    private func createZoneKitSource(position: AVCaptureDevice.Position) -> ZoneKitSource {
        let sourceType: ZoneKitSourceType = position == .front ? .cameraFront : .cameraBack
        let displayName = position == .front ? "Front Camera" : "Back Camera"
        let id = position == .front ? "camera-front" : "camera-back"

        return ZoneKitSource(
            id: id,
            type: sourceType,
            displayName: displayName,
            manufacturer: "Apple Inc.",
            modelID: displayName,
            uniqueID: id
        )
    }

    // MARK: - Capture Control

    func startCapture(position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let session = self.captureSession else { return }

            // Stop current capture if any
            if self.currentInput != nil {
                self.stopCapture()
            }

            let device = position == .front ? self.frontCamera : self.backCamera
            guard let captureDevice = device else {
                mlog.error("Camera not available: \(position == .front ? "front" : "back")")
                return
            }

            mlog.info("Starting capture from \(position == .front ? "front" : "back") camera")

            do {
                session.beginConfiguration()
                defer { session.commitConfiguration() }

                // Create input
                let input = try AVCaptureDeviceInput(device: captureDevice)

                if session.canAddInput(input) {
                    session.addInput(input)
                    self.currentInput = input
                    mlog.debug("Added camera input")
                }

                // Create video output if needed
                if self.videoOutput == nil {
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                        kCVPixelBufferMetalCompatibilityKey as String: true  // Ensure Metal compatibility
                    ]
                    output.setSampleBufferDelegate(self, queue: self.captureQueue)

                    if session.canAddOutput(output) {
                        session.addOutput(output)
                        self.videoOutput = output
                        mlog.debug("Added video output")
                    }
                }

                self.currentSource = self.createZoneKitSource(position: position)

            } catch {
                mlog.error("Failed to start camera capture: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        captureSession?.stopRunning()
    }

    func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard let session = self.captureSession else { return }

            session.beginConfiguration()
            defer { session.commitConfiguration() }

            if let input = self.currentInput {
                session.removeInput(input)
                self.currentInput = nil
            }

            if let output = self.videoOutput {
                session.removeOutput(output)
                self.videoOutput = nil
            }

            self.currentSource = nil

            mlog.debug("Camera capture stopped")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

@available(iOS 17.0, *)
extension ZoneKitCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let source = currentSource else { return }

        // Forward to delegate - already on capture queue
        delegate?.cameraController(self, didOutputSampleBuffer: sampleBuffer, from: source)
    }
}

#endif
