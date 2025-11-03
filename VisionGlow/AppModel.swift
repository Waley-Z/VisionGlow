import SwiftUI
import ARKit
import Combine
import HomeKit
import RealityKit
import RealityKitContent

struct AccessoryComponent: RealityKit.Component {
    let accessoryId: UUID
}

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    var homeStore = HomeStore()
    
    let immersiveSpaceID = "ImmersiveSpace"

    let session = ARKitSession()
    let worldTracking = WorldTrackingProvider()
    var contentEntity = Entity()
    
    // Track both the sphere entity AND its anchor entity
    var orbEntities: [UUID: (sphere: Entity, anchor: AnchorEntity)] = [:]
    
    // Persistent mapping of (ARKit Anchor ID -> Accessory ID)
    private var anchorToAccessoryMap: [UUID: UUID] = [:]
    private let anchorMapKey = "VisionGlow.AnchorToAccessoryMap"
    
    var orbOpacity: Float = 0.0 {
        didSet {
            setOpacity(orbOpacity)
        }
    }
    
    init() {
        loadAnchorMap()
    }
    
    // MARK: - Persistence (UserDefaults)
    
    private func loadAnchorMap() {
        guard let data = UserDefaults.standard.data(forKey: anchorMapKey) else {
            print("No anchor map found in UserDefaults. Starting fresh.")
            return
        }
        
        do {
            let stringMap = try JSONDecoder().decode([String: String].self, from: data)
            self.anchorToAccessoryMap = [:]
            for (key, value) in stringMap {
                if let keyUUID = UUID(uuidString: key), let valueUUID = UUID(uuidString: value) {
                    self.anchorToAccessoryMap[keyUUID] = valueUUID
                }
            }
            print("Loaded anchor map with \(anchorToAccessoryMap.count) items.")
        } catch {
            print("Failed to decode anchor map: \(error). Resetting map.")
            self.anchorToAccessoryMap = [:]
        }
    }
    
    private func saveAnchorMapping(anchorID: UUID, accessoryID: UUID) {
        anchorToAccessoryMap[anchorID] = accessoryID
    }
    
    private func removeAnchorMapping(anchorID: UUID) {
        anchorToAccessoryMap.removeValue(forKey: anchorID)
        persistAnchorMap()
    }
    
    private func persistAnchorMap() {
        do {
            let stringMap = Dictionary(uniqueKeysWithValues:
                anchorToAccessoryMap.map { (key, value) in (key.uuidString, value.uuidString) }
            )
            let data = try JSONEncoder().encode(stringMap)
            UserDefaults.standard.set(data, forKey: anchorMapKey)
            print("Saved anchor map to UserDefaults.")
        } catch {
            print("Failed to encode and save anchor map: \(error)")
        }
    }
    
    // MARK: - RealityKit Content
    
    func setupContentEntity() -> Entity {
        return contentEntity
    }

    private func createOrbEntity(accessoryId: UUID) -> Entity {
        let entity = ModelEntity(
            mesh: .generateSphere(radius: 0.1),
            materials: [bubbleMaterial(opacity: orbOpacity)]
        )
        
        entity.name = "Orb_\(accessoryId)"
        entity.generateCollisionShapes(recursive: true)

        /// InputTargetComponent
        entity.components.set(InputTargetComponent())

        /// GestureComponent
        var gestureComponent = GestureComponent()
        gestureComponent.canDrag = true
        gestureComponent.canScale = true
        gestureComponent.canRotate = true
        gestureComponent.pivotOnDrag = true
        gestureComponent.preserveOrientationOnPivotDrag = true
        entity.components.set(gestureComponent)
        
        /// AccessoryComponent
        entity.components.set(AccessoryComponent(accessoryId: accessoryId))

        /// HoverEffectComponent
        entity.components.set(HoverEffectComponent(.spotlight(
            HoverEffectComponent.SpotlightHoverEffectStyle(
                color: .white, strength: 2.0
        ))))
        
        return entity
    }
    
    func handleAnchorUpdate(_ update: AnchorUpdate<WorldAnchor>) async {
        let arkitAnchor = update.anchor
        
        guard let accessoryId = anchorToAccessoryMap[arkitAnchor.id] else {
            print("Found unknown anchor \(arkitAnchor.id), removing.")
            try? await worldTracking.removeAnchor(forID: arkitAnchor.id)
            return
        }

        switch update.event {
        case .added:
            print("Anchor ADDED for accessory: \(accessoryId), tracked: \(arkitAnchor.isTracked)")
            
            // Don't add if we already have an entity for it
            guard orbEntities[accessoryId] == nil else {
                print("...but entity already exists. Ignoring.")
                return
            }
            
            let sphere = createOrbEntity(accessoryId: accessoryId)
            
            // Create an AnchorEntity at world origin first
            let anchorEntity = AnchorEntity()
            anchorEntity.name = "Anchor_\(accessoryId)"
            anchorEntity.transform = Transform(matrix: arkitAnchor.originFromAnchorTransform)

            anchorEntity.addChild(sphere)
            contentEntity.addChild(anchorEntity)
            
            // Store both the sphere and anchor
            orbEntities[accessoryId] = (sphere: sphere, anchor: anchorEntity)
            sphere.isEnabled = arkitAnchor.isTracked
            
            print("✅ Created orb at transform: \(arkitAnchor.originFromAnchorTransform)")
            print("   Anchor position should be: \(arkitAnchor.originFromAnchorTransform.translation())")
            
            // Debug scene hierarchy after a brief delay
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                await debugSceneHierarchy()
            }

        case .updated:
            if let (sphere, anchor) = orbEntities[accessoryId] {
                // Update the anchor's transform when ARKit refines the position
                anchor.transform = Transform(matrix: arkitAnchor.originFromAnchorTransform)
                sphere.isEnabled = arkitAnchor.isTracked
            }
            
        case .removed:
            print("Anchor REMOVED for accessory: \(accessoryId)")
            
            if let (_, anchorEntity) = orbEntities.removeValue(forKey: accessoryId) {
                anchorEntity.removeFromParent()
            }
            
            removeAnchorMapping(anchorID: arkitAnchor.id)
        }
    }
    
    // MARK: - Orb Management
    
    func addOrb(accessoryId: UUID) async {
        // 1. Find the OLD anchor (if it exists) *before* doing anything else.
        let oldAnchorID = anchorToAccessoryMap.first(where: { $0.value == accessoryId })?.key
        
        // 2. Create the NEW anchor.
        let distance: Float = 1.0
        guard let currentTransform = originFromDeviceTransform() else {
            print("❌ Could not get device transform")
            return
        }
        
        let targetLocation = currentTransform.translation() - distance * currentTransform.forward()
        let worldMatrix = float4x4(translation: targetLocation)
        let arkitAnchor = WorldAnchor(originFromAnchorTransform: worldMatrix)
        
        // 3. Try to add the NEW anchor to ARKit.
        do {
            try await worldTracking.addAnchor(arkitAnchor)
            print("✅ Added new WorldAnchor \(arkitAnchor.id) for accessory \(accessoryId)")

            // 4. (SUCCESS) The new anchor is saved. Now, save its mapping.
            // This will add the new anchor's mapping.
            saveAnchorMapping(anchorID: arkitAnchor.id, accessoryID: accessoryId)

            // 5. (SUCCESS) Now, it's safe to clean up the OLD anchor.
            if let oldAnchorID {
                print("Cleaning up old anchor \(oldAnchorID)")
                
                // Remove old visuals immediately.
                if let (_, anchorEntity) = orbEntities.removeValue(forKey: accessoryId) {
                    anchorEntity.removeFromParent()
                }
                
                // Remove old anchor from ARKit.
                try? await worldTracking.removeAnchor(forID: oldAnchorID)
                
                // Manually remove the old mapping from the dictionary.
                anchorToAccessoryMap.removeValue(forKey: oldAnchorID)
                
                // Persist the map again *after* the removal.
                persistAnchorMap()
            }
            
        } catch {
            // 6. (FAILURE) The new anchor failed to save.
            // Because we didn't delete the old anchor, it is still safe and sound.
            print("❌ Error adding new world anchor: \(error). The old anchor (if any) was preserved.")
        }
    }
    
    private func bubbleMaterial(opacity: Float) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white)
        material.blending = .transparent(
            opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: opacity)
        )
        material.metallic = .init(floatLiteral: 0.7)
        material.roughness = .init(floatLiteral: 0.1)
        material.clearcoat = .init(floatLiteral: 0.5)
        
        return material
    }

    @MainActor
    func handleOrbDragEnd(for entity: Entity) async {
        // Find the accessoryId for this orb
        guard let accessoryId = entity.components[AccessoryComponent.self]?.accessoryId else {
            print("Drag ended on an entity that is not an orb.")
            return
        }

        // Find the AnchorEntity (the orb's parent)
        guard let anchorEntity = entity.parent as? AnchorEntity else {
            print("Could not find anchor entity for orb.")
            return
        }

        // Find the old ARKit Anchor ID
        guard let oldAnchorID = anchorToAccessoryMap.first(where: { $0.value == accessoryId })?.key else {
            print("Could not find old anchor ID in map.")
            return
        }

        print("Orb for \(accessoryId) finished dragging. Re-anchoring...")

        // Get the orb's new world transform
        let newWorldTransform = entity.transformMatrix(relativeTo: nil)

        // Create the new ARKit anchor
        let newARKitAnchor = WorldAnchor(originFromAnchorTransform: newWorldTransform)

        do {
            // 1. Add the new anchor
            try await worldTracking.addAnchor(newARKitAnchor)

            // 2. Update the map to point to the new anchor
            saveAnchorMapping(anchorID: newARKitAnchor.id, accessoryID: accessoryId)

            // 3. Remove the old anchor's ID from the map
            anchorToAccessoryMap.removeValue(forKey: oldAnchorID)
            persistAnchorMap() // Save the removal

            // 4. Remove the old anchor from ARKit
            try? await worldTracking.removeAnchor(forID: oldAnchorID)

            // 5. Update the orb's parent AnchorEntity to the new transform
            anchorEntity.transform = Transform(matrix: newWorldTransform)

            // 6. Reset the orb's local position to (0,0,0)
            //    since it's now relative to the updated anchor
            entity.position = .zero

            print("✅ Re-anchored orb to new position.")

        } catch {
            print("❌ Failed to re-anchor orb: \(error).")
            // Note: You might want to add logic here to revert the orb's
            // position back to the anchor if saving fails.
        }
    }

    func originFromDeviceTransform() -> simd_float4x4? {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return nil
        }
        return deviceAnchor.originFromAnchorTransform
    }
    
    func setOpacity(_ opacity: Float) {
        for (_, (sphere, _)) in orbEntities {
            if let modelEntity = sphere as? ModelEntity {
                modelEntity.model?.materials = [bubbleMaterial(opacity: opacity)]
            }
        }
    }

    // MARK: - Accessory
    
    @MainActor
    func toggleLight(accessoryId: UUID) async {
        // 1. Find the accessory
        guard let accessory = homeStore.findAccessoriesById(accessoryId: accessoryId) else {
            print("Toggle Error: Accessory \(accessoryId) not found.")
            return
        }
        
        // 2. Find the power characteristic
        guard let lightService = accessory.services.first(where: { $0.serviceType == HMServiceTypeLightbulb }),
              let powerChar = lightService.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypePowerState })
        else {
            print("Toggle Error: Light service or power characteristic not found for \(accessory.name).")
            return
        }
        
        // 3. Read the current value
        // We use withCheckedContinuation to bridge the asynchronous completion handler
        let currentValue: Bool? = await withCheckedContinuation { continuation in
            powerChar.readValue { error in
                if let error = error {
                    print("Toggle Error: Failed to read power state: \(error.localizedDescription)")
                    continuation.resume(returning: nil) // Return nil on error
                } else if let value = powerChar.value as? Bool {
                    continuation.resume(returning: value) // Return current value
                } else {
                    print("Toggle Error: Could not read power state as Bool.")
                    continuation.resume(returning: nil) // Return nil if value is wrong type
                }
            }
        }
        
        // 4. If read was successful, write the new (opposite) value
        guard let currentBoolValue = currentValue else {
            print("Toggle Error: Could not determine current power state.")
            return
        }
        
        let newValue = !currentBoolValue
        
        powerChar.writeValue(newValue) { error in
            if let error = error {
                print("Toggle Error: Failed to set power state: \(error.localizedDescription)")
            } else {
                print("Toggle Success: Set \(accessory.name) power to \(newValue)")
            }
        }
    }
    
    // MARK: - Debug
    
    func debugSceneHierarchy() {
        print("\n========== SCENE HIERARCHY DEBUG ==========")
        print("contentEntity name: \(contentEntity.name)")
        print("contentEntity position: \(contentEntity.position)")
        print("contentEntity transform: \(contentEntity.transform)")
        print("contentEntity.parent: \(contentEntity.parent?.name ?? "nil")")
        print("contentEntity.scene: \(contentEntity.scene != nil ? "YES" : "NO")")
        print("contentEntity children count: \(contentEntity.children.count)")
        print("\norbEntities count: \(orbEntities.count)")
        
        for (index, child) in contentEntity.children.enumerated() {
            print("\n--- Child \(index): \(child.name) ---")
            print("  Type: \(type(of: child))")
            print("  Position: \(child.position)")
            print("  Position (world): \(child.position(relativeTo: nil))")
            print("  Transform: \(child.transform)")
            print("  isEnabled: \(child.isEnabled)")
            print("  isActive: \(child.isActive)")
            print("  Parent: \(child.parent?.name ?? "nil")")
            print("  Children count: \(child.children.count)")
            
            if let anchor = child as? AnchorEntity {
                print("  AnchorEntity anchoring: \(anchor.anchoring)")
            }
            
            for (subIndex, subChild) in child.children.enumerated() {
                print("    --- SubChild \(subIndex): \(subChild.name) ---")
                print("      Type: \(type(of: subChild))")
                print("      Position: \(subChild.position)")
                print("      Position (world): \(subChild.position(relativeTo: nil))")
                print("      isEnabled: \(subChild.isEnabled)")
                print("      isActive: \(subChild.isActive)")
                
                if let model = subChild as? ModelEntity {
                    print("      Has mesh: \(model.model?.mesh != nil)")
                    print("      Has materials: \(model.model?.materials.count ?? 0)")
                    if let material = model.model?.materials.first as? PhysicallyBasedMaterial {
                        print("      Material opacity: \(material.blending)")
                    }
                }
            }
        }
        
        print("\n===========================================\n")
    }
}
