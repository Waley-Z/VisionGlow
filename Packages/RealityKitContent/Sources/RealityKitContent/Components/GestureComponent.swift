/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A component that handles gesture logic for an entity, allowing simultaneous drag, rotate, and scale gestures.
*/

import Combine
import RealityKit
import SwiftUI

// MARK: - EntityGestureState

@MainActor
public class EntityGestureState {
    
    /// The entity currently being manipulated.
    var targetedEntity: Entity?
    
    // MARK: - Drag
    
    /// The starting position for dragging.
    var dragStartPosition: SIMD3<Float> = .zero
    
    /// Indicates if a drag gesture is in progress.
    var isDragging = false
    
    /// The pivot entity for pivot-based dragging.
    var pivotEntity: Entity?
    
    /// The initial orientation of the entity.
    var initialOrientation: simd_quatf?
    
    // MARK: - Scale

    /// The starting scale value for scaling.
    var startScale: SIMD3<Float> = .one
    
    /// Indicates if a scale gesture is in progress.
    var isScaling = false
    
    // MARK: - Rotation

    /// The starting rotation value for rotating.
    var startOrientation: Rotation3D?
    
    /// Indicates if a rotation gesture is in progress.
    var isRotating = false

    // MARK: - Singleton Accessor

    /// Retrieves the shared instance.
    public static let shared = EntityGestureState()
    
    // MARK: - Publisher
        
    /// Publishes the entity that just finished being dragged.
    public let dragEndedPublisher = PassthroughSubject<Entity, Never>()

    /// Publishes the entity and its final scale when scaling ends
    public let scaleEndedPublisher = PassthroughSubject<Entity, Never>()
}

// MARK: - GestureComponent

/// A component that handles gesture logic for an entity, allowing simultaneous gestures.
public struct GestureComponent: Component, Codable {
    
    /// A Boolean value that indicates whether a gesture can drag the entity.
    public var canDrag: Bool = true
    
    /// A Boolean value that indicates whether dragging can move the object in an arc.
    public var pivotOnDrag: Bool = true
    
    /// A Boolean value that indicates whether a pivot drag keeps the orientation toward the viewer throughout the drag gesture.
    ///
    /// The property only applies when `pivotOnDrag` is `true`.
    public var preserveOrientationOnPivotDrag: Bool = true
    
    /// A Boolean value that indicates whether a gesture can scale the entity.
    public var canScale: Bool = true
    
    /// A Boolean value that indicates whether a gesture can rotate the entity.
    public var canRotate: Bool = true
    
    public init() {}
    
    // MARK: - Gesture Logic
    
    /// Handle `.onChanged` actions for gestures.
    @MainActor
    mutating func onChanged<T>(value: EntityTargetValue<T>) {
        if value.gestureValue is DragGesture.Value {
            handleDragChanged(value: value as! EntityTargetValue<DragGesture.Value>)
        } else if value.gestureValue is MagnifyGesture.Value {
            handleScaleChanged(value: value as! EntityTargetValue<MagnifyGesture.Value>)
        } else if value.gestureValue is RotateGesture3D.Value {
            handleRotateChanged(value: value as! EntityTargetValue<RotateGesture3D.Value>)
        }
    }
    
    /// Handle `.onEnded` actions for gestures.
    @MainActor
    mutating func onEnded<T>(value: EntityTargetValue<T>) {
        if value.gestureValue is DragGesture.Value {
            handleDragEnded(value: value as! EntityTargetValue<DragGesture.Value>)
        } else if value.gestureValue is MagnifyGesture.Value {
            handleScaleEnded(value: value as! EntityTargetValue<MagnifyGesture.Value>)
        } else if value.gestureValue is RotateGesture3D.Value {
            handleRotateEnded(value: value as! EntityTargetValue<RotateGesture3D.Value>)
        }
    }
    
    // MARK: - Drag Logic
    
    @MainActor
    private func handleDragChanged(value: EntityTargetValue<DragGesture.Value>) {
        guard canDrag else { return }
        let state = EntityGestureState.shared
        let entity = value.entity
        
        if !state.isDragging {
            state.isDragging = true
            state.dragStartPosition = entity.position(relativeTo: nil)
            if state.targetedEntity == nil {
                state.targetedEntity = entity
                state.initialOrientation = entity.orientation(relativeTo: nil)
            }
        }
        
        let translation3D = value.convert(value.gestureValue.translation3D, from: .local, to: .scene)
        
        let offset = SIMD3<Float>(Float(translation3D.x),
                                  Float(translation3D.y),
                                  Float(translation3D.z))
        
        entity.setPosition(state.dragStartPosition + offset, relativeTo: nil)
    }
    
    @MainActor
    private func handleDragEnded(value: EntityTargetValue<DragGesture.Value>) {
        let state = EntityGestureState.shared
        state.isDragging = false
        state.targetedEntity = nil
        state.dragEndedPublisher.send(value.entity)
    }
    
    // MARK: - Scale Logic
    
    @MainActor
    private func handleScaleChanged(value: EntityTargetValue<MagnifyGesture.Value>) {
        guard canScale else { return }
        let state = EntityGestureState.shared
        let entity = value.entity
        
        if !state.isScaling {
            state.isScaling = true
            state.startScale = entity.scale(relativeTo: nil)
            if state.targetedEntity == nil {
                state.targetedEntity = entity
            }
        }
        
        let magnification = Float(value.magnification)
        entity.setScale(state.startScale * magnification, relativeTo: nil)
    }
    
    @MainActor
    private func handleScaleEnded(value: EntityTargetValue<MagnifyGesture.Value>) {
        let state = EntityGestureState.shared
        state.isScaling = false
        state.scaleEndedPublisher.send(value.entity)
    }
    
    // MARK: - Rotate Logic
    
    @MainActor
    private func handleRotateChanged(value: EntityTargetValue<RotateGesture3D.Value>) {
        guard canRotate else { return }
        let state = EntityGestureState.shared
        let entity = value.entity
        
        if !state.isRotating {
            state.isRotating = true
            state.startOrientation = Rotation3D(entity.orientation(relativeTo: nil))
            if state.targetedEntity == nil {
                state.targetedEntity = entity
            }
        }
        
        let rotation = value.rotation
        let flippedRotation = Rotation3D(angle: rotation.angle,
                                         axis: RotationAxis3D(x: -rotation.axis.x,
                                                              y: rotation.axis.y,
                                                              z: -rotation.axis.z))
        if let startOrientation = state.startOrientation {
            let newOrientation = startOrientation.rotated(by: flippedRotation)
            entity.setOrientation(simd_quatf(newOrientation), relativeTo: nil)
        }
    }
    
    @MainActor
    private func handleRotateEnded(value: EntityTargetValue<RotateGesture3D.Value>) {
        let state = EntityGestureState.shared
        state.isRotating = false
    }
}

func CalculateDaysBetweenDyas(_ date1: Date, _ date2: Date) -> Int {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.day], from: date1, to: date2)
    return components.day!
}
