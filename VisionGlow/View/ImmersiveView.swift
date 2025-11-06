//
//  ImmersiveView.swift
//  VisionGlow
//
//  Created by DEV Studio on 2/5/25.
//

import SwiftUI
import ARKit
import RealityKit
import HomeKit
import RealityKitContent

struct ImmersiveView: View {
    @Environment(AppModel.self) var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        RealityView { content in
            content.add(model.setupContentEntity())
        }
        .installGestures()
        .task {
            print("Initializing immersive view")
            // Check whether the device supports world tracking.
            guard WorldTrackingProvider.isSupported else {
                print("WorldTrackingProvider is not supported on this device")
                return
            }
            print("Requesting world sensing authorization...")
            let authStatus = await model.session.requestAuthorization(for: [.worldSensing])
            
            guard authStatus[.worldSensing]! == .allowed else {
                print("World sensing authorization was not granted.")
                // You could show an error to the user here
                return
            }
            print("World sensing authorization granted.")
            model.debugSceneHierarchy()

            // Infinite loop to run the ARKit session and handle anchor updates.
            do {
                // Attempt to start an ARKit session with the world-tracking provider.
                try await model.session.run([model.worldTracking])
                print("--- ✅ ARKitSession RUNNING ---")
                for await update in model.worldTracking.anchorUpdates {
                    await model.handleAnchorUpdate(update)
                }
            } catch let error as ARKitSession.Error {
                // Handle any potential ARKit session errors.
                print("Encountered an error while running providers: \(error.localizedDescription)")
            } catch let error {
                // Handle any unexpected errors.
                print("Encountered an unexpected error: \(error.localizedDescription)")
            }
        }
        .gesture(LongPressGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                guard let accessoryComponent = value.entity.components[AccessoryComponent.self],
                      let accessory = model.homeStore.findAccessoriesById(accessoryId: accessoryComponent.accessoryId)
                      else { return }
                
                guard accessory.services.contains(where: { $0.serviceType == HMServiceTypeLightbulb }) else {
                    return
                }
                
                print("Long pressed on light: \(accessory.name), toggling power.")
                Task {
                    await model.toggleLight(accessoryId: accessory.uniqueIdentifier)
                }
            }
        )
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            guard let accessoryComponent = value.entity.components[AccessoryComponent.self],
                  let accessory = model.homeStore.findAccessoriesById(accessoryId: accessoryComponent.accessoryId)
                  else { return }
            
            let accessoryId = accessoryComponent.accessoryId
            print("Tapped on accessory with ID: \(accessoryId), name: \(accessory.name), type: \(accessory.category.categoryType)")
            
            guard !model.isPanelOpen(accessoryId) else {
                print("Control panel for accessory \(accessory.name) is already open.")
                return
            }
            
            model.markPanelOpened(accessoryId)
            print("Opening control panel for accessory: \(accessory.name)")
            openWindow(id: "controlPanel", value: accessoryId)
            print("Opened panels: \(model.openControlPanels)")
        })
    }
}
