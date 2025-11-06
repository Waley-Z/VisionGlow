//
//  VisionGlowApp.swift
//  VisionGlow
//
//  Created by DEV Studio on 2/5/25.
//

import SwiftUI
import HomeKit
import RealityKitContent

@main
struct VisionGlowApp: App {

    @State private var appModel = AppModel()

    init() {
        RealityKitContent.GestureComponent.registerComponent()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: appModel.homeStore)
                .environment(appModel)
        }
        .defaultSize(CGSize(width: 950, height: 650))

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        ControlPanelWindow()
            .environment(appModel)
     }
}

struct ControlPanelWindow: Scene {
    @Environment(AppModel.self) var appModel

    var body: some Scene {
        WindowGroup("Control Panel", id: "controlPanel", for: UUID.self) { $id in
            Group {
                if let id,
                   let accessory = appModel.homeStore.findAccessoriesById(accessoryId: id) {
                    if accessory.services.contains(where: { $0.serviceType == HMServiceTypeLightbulb }) {
                        LightBulbControlView(accessoryId: accessory.uniqueIdentifier)
                            .environment(appModel)
                    } else if accessory.services.contains(where: { $0.serviceType == HMServiceTypeTemperatureSensor }) {
                        TemperatureSensorControlView(accessoryId: accessory.uniqueIdentifier)
                            .environment(appModel)
                    } else if accessory.profiles.contains(where: { $0 is HMCameraProfile }) {
                        CameraControlView(accessory: accessory)
                            .aspectRatio(16.0/9.0, contentMode: .fit)
                            .frame(width: 640, height: 360)
                            .background(Color.black)
                    } else {
                        Text("Unsupported accessory type")
                    }
                } else {
                    Text("Accessory not found")
                }
            }
            .padding(24)
            .onDisappear() {
                print("Control Panel window for accessory \(String(describing: id)) closed.")
                if let id { appModel.markPanelClosed(id) }
            }
        }
        .defaultSize(CGSize(width: 400, height: 400))
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.utilityPanel) }
    }
}
