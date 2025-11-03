//
//  ContentView.swift
//  VisionGlow
//
//  Created by DEV Studio on 2/5/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
import HomeKit

struct ContentView: View {
    @Environment(AppModel.self) var appModel
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: HomeStore

    @State private var selectedRoomID: UUID?
    @State private var showOpacitySlider = false

    var body: some View {
        NavigationSplitView {
            // LEFT SIDEBAR
            NavigationStack {
                if model.rooms.isEmpty {
                    Text("No rooms found")
                } else {
                    List(model.rooms, id: \.uniqueIdentifier, selection: $selectedRoomID) { room in
                        Text(room.name)
                            .tag(room.uniqueIdentifier as UUID?)
                    }
                }
            }
            .navigationTitle(model.homes.first?.name ?? "My Home")
        } detail: {
            // RIGHT DETAIL
            if let selectedRoomID = selectedRoomID,
               let room = model.rooms.first(where: { $0.uniqueIdentifier == selectedRoomID }) {
                AccessoriesInRoomView(room: room)
            } else {
                Text("Select a room")
                    .foregroundStyle(.secondary)
            }
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            Button(action: {
                showOpacitySlider.toggle()
            }) {
                Label("Orb Opacity", systemImage: "slider.horizontal.3")
            }
            // Attach the popover to the button
            .popover(isPresented: $showOpacitySlider) {
                Slider(value: Binding(get: { appModel.orbOpacity }, set: { appModel.orbOpacity = $0 }), in: 0...1)
                    .frame(minWidth: 250)
                    .padding(.horizontal, 20)
            }
        }
        .onAppear {
            Task {
                await openImmersiveSpace(id: appModel.immersiveSpaceID)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Re-enter immersive space after returning from Home
                Task { await openImmersiveSpace(id: appModel.immersiveSpaceID) }
            }
        }
    }
}

/// Shows the accessories belonging to one room.
struct AccessoriesInRoomView: View {
    @Environment(AppModel.self) var appModel

    let room: HMRoom
    private let sphereName = "Glow Orb"

    var body: some View {
        let accessories = room.accessories
            .filter { $0.category.categoryType != HMAccessoryCategoryTypeBridge }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }  // ← sort A→Z

        List(accessories, id: \.uniqueIdentifier) { accessory in
            HStack {
                Text(accessory.name)
                Spacer()
                Button("Place \(sphereName)") {
                    placeGlowOrb(for: accessory)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(room.name)
    }

    private func placeGlowOrb(for accessory: HMAccessory) {
        print("Placing a \(sphereName) for accessory: \(accessory.name)")
        Task {
            await appModel.addOrb(accessoryId: accessory.uniqueIdentifier)
        }
    }
}
