//
//  CameraControlView.swift
//  VisionGlow
//
//  Created by DEV Studio on 10/14/25.
//

import SwiftUI
import HomeKit

struct CameraControlView: View {
    let accessory: HMAccessory

    // Find the first camera profile on the accessory (if present)
    private var cameraProfile: HMCameraProfile? {
        accessory.profiles.compactMap { $0 as? HMCameraProfile }.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraStreamView(profile: cameraProfile)
                .aspectRatio(16.0/9.0, contentMode: .fit)  // keep the video in 16:9
                .frame(minWidth: 160, idealWidth: 640, maxWidth: .infinity,
                       minHeight: 90, idealHeight: 360, maxHeight: .infinity)
        }
    }
}

// UIKit wrapper for HMCameraView
private struct CameraStreamView: UIViewRepresentable {
    let profile: HMCameraProfile?

    final class Coordinator: NSObject, HMCameraStreamControlDelegate {
        weak var cameraView: HMCameraView?
        var streamControl: HMCameraStreamControl?

        // MARK: - HMCameraStreamControlDelegate
        func cameraStreamControlDidStartStream(_ control: HMCameraStreamControl) {
            // Wire the live stream to the view when it’s ready
            cameraView?.cameraSource = control.cameraStream
        }

        func cameraStreamControl(_ control: HMCameraStreamControl, didStopWithError error: Error?) {
            // Clear the view’s source so the next open starts cleanly
            cameraView?.cameraSource = nil
        }

        // Convenience
        func start() {
            guard let control = streamControl else { return }
            control.delegate = self
            // In case a previous session was lingering, stop first.
            control.stopStream()
            control.startStream()
        }

        func stop() {
            streamControl?.stopStream()
            cameraView?.cameraSource = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HMCameraView {
        let view = HMCameraView(frame: .zero)
        context.coordinator.cameraView = view

        // Hold a strong reference to the streamControl for lifecycle management
        context.coordinator.streamControl = profile?.streamControl

        // Start the stream now; delegate will assign cameraSource.
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: HMCameraView, context: Context) {
        // No-op
    }

    static func dismantleUIView(_ uiView: HMCameraView, coordinator: Coordinator) {
        // IMPORTANT: stop the stream when the window closes
        coordinator.stop()
        coordinator.streamControl = nil
    }
}
