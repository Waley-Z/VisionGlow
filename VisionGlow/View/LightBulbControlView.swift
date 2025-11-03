//
//  LightBulbControlView.swift
//  VisionGlow
//
//  Created by DEV Studio on 2/19/25.
//


import SwiftUI
import HomeKit
import Combine


struct LightBulbControlView: View {
    let accessoryId: UUID
    @Environment(AppModel.self) var appModel
    
    // MARK: - Accessory & Service Properties
    
    private var accessory: HMAccessory {
        appModel.homeStore.findAccessoriesById(accessoryId: accessoryId)!
    }
    
    private var lightService: HMService? {
        accessory.services.first { $0.serviceType == HMServiceTypeLightbulb }
    }
    
    // MARK: - Characteristic Properties
    
    private var powerStateCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypePowerState }
    }
    
    private var brightnessCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypeBrightness }
    }
    
    private var hueCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypeHue }
    }
    
    private var colorTemperatureCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypeColorTemperature }
    }
    
    // MARK: - State Variables
    
    @State private var isOn: Bool = false
    @State private var brightness: Double = 50
    @State private var hue: Double = 0
    
    // --- Temperature State ---
    @State private var miredValue: Double = 300
    @State private var miredMin: Double = 153
    @State private var miredMax: Double = 500

    @State private var kelvinValue: Double = 3300
    
    @State private var isInitializing: Bool = true

    // MARK: - Combine Publishers & Cancellables
    
    @State private var brightnessWriteCancellable: AnyCancellable?
    @State private var hueWriteCancellable: AnyCancellable?
    @State private var tempWriteCancellable: AnyCancellable?
    
    private let brightnessSubject = PassthroughSubject<Double, Never>()
    private let hueSubject = PassthroughSubject<Double, Never>()
    private let miredSubject = PassthroughSubject<Double, Never>()
    
    // MARK: - Body View
    
    var body: some View {
        VStack(spacing: 24) {
            Text(accessory.name)
                .font(.title)
            
            Toggle("Power", isOn: $isOn)
                .toggleStyle(.switch)
                .onChange(of: isOn) { _, newValue in
                    guard !isInitializing else { return }
                    setPowerState(newValue)
                }
            
            // --- Brightness ---
            if brightnessCharacteristic != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Brightness: \(Int(brightness))%")
                    Slider(value: $brightness, in: 0...100, step: 1)
                        .onChange(of: brightness) { _, newValue in
                            guard !isInitializing else { return }
                            brightnessSubject.send(newValue)
                        }
                }
            }
            
            // --- Hue (Color) ---
            if hueCharacteristic != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                    HueGradientSlider(hue: $hue)
                        .frame(height: 28)
                        .onChange(of: hue) { _, newValue in
                            guard !isInitializing else { return }
                            hueSubject.send(newValue)
                        }
                }
            }
            
            // --- Color Temperature (in Kelvin) ---
            if colorTemperatureCharacteristic != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temperature: \(Int(kelvinValue)) K")
                    
                    TemperatureGradientSlider(
                        kelvin: $kelvinValue,
                        kelvinMin: (1_000_000 / miredMax),
                        kelvinMax: (1_000_000 / miredMin)
                    )
                    .frame(height: 28)
                    .onChange(of: kelvinValue) { _, newKelvin in
                        guard !isInitializing else { return }
                        let newMired = 1_000_000 / newKelvin
                        self.miredValue = newMired
                        miredSubject.send(newMired)
                    }
                }
            }
        }
        .padding()
        .task {
            // Setup cancellables before any state changes
            setupCancellables()
            // Load initial state
            await loadAccessoryState()
            // Only now allow onChange to trigger writes
            // Use a small delay to ensure all pending onChange calls have been processed
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            isInitializing = false
        }
        .onDisappear {
            brightnessWriteCancellable?.cancel(); brightnessWriteCancellable = nil
            hueWriteCancellable?.cancel();        hueWriteCancellable = nil
            tempWriteCancellable?.cancel();       tempWriteCancellable = nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadAccessoryState() async {
        print("--- Reading initial accessory states... ---")
        
        await withTaskGroup(of: Void.self) { group in
            if let char = powerStateCharacteristic {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        char.readValue { error in
                            if let error = error {
                                print("Error reading power: \(error.localizedDescription)")
                            } else if let value = char.value as? Bool {
                                Task { @MainActor in
                                    self.isOn = value
                                    print("Read Power: \(value)")
                                }
                            }
                            continuation.resume()
                        }
                    }
                }
            }
            
            if let char = brightnessCharacteristic {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        char.readValue { error in
                            if let error = error {
                                print("Error reading brightness: \(error.localizedDescription)")
                            } else if let value = char.value as? NSNumber {
                                Task { @MainActor in
                                    self.brightness = value.doubleValue
                                    print("Read Brightness: \(self.brightness)")
                                }
                            }
                            continuation.resume()
                        }
                    }
                }
            }
            
            if let char = hueCharacteristic {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        char.readValue { error in
                            if let error = error {
                                print("Error reading hue: \(error.localizedDescription)")
                            } else if let value = char.value as? NSNumber {
                                Task { @MainActor in
                                    self.hue = value.doubleValue
                                    print("Read Hue: \(self.hue)")
                                }
                            }
                            continuation.resume()
                        }
                    }
                }
            }
            
            if let char = colorTemperatureCharacteristic {
                // Metadata is sync, read it on main actor
                await MainActor.run {
                    if let min = char.metadata?.minimumValue as? Double,
                       let max = char.metadata?.maximumValue as? Double {
                        self.miredMin = min
                        self.miredMax = max
                    }
                }
                
                group.addTask {
                    await withCheckedContinuation { continuation in
                        char.readValue { error in
                            if let error = error {
                                print("Error reading temp: \(error.localizedDescription)")
                            } else if let value = char.value as? NSNumber {
                                Task { @MainActor in
                                    self.miredValue = value.doubleValue
                                    self.kelvinValue = 1_000_000 / self.miredValue
                                    print("Read Mired: \(self.miredValue) (Calculated Kelvin: \(self.kelvinValue))")
                                }
                            }
                            continuation.resume()
                        }
                    }
                }
            }
        }
        
        print("--- Finished reading states. ---")
    }

    private func setupCancellables() {
        if brightnessWriteCancellable == nil {
            brightnessWriteCancellable = brightnessSubject
                .removeDuplicates(by: { abs($0 - $1) < 5 })
                .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
                .sink { value in setBrightness(value) }
        }
        
        if hueWriteCancellable == nil {
            hueWriteCancellable = hueSubject
                .removeDuplicates(by: { abs($0 - $1) < 20 })
                .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
                .sink { value in setHue(value) }
        }
        
        if tempWriteCancellable == nil {
            tempWriteCancellable = miredSubject
                .removeDuplicates(by: { abs($0 - $1) < 50 })
                .throttle(for: .milliseconds(200), scheduler: RunLoop.main, latest: true)
                .sink { miredValue in
                    setColorTemperature(miredValue)
                }
        }
    }
    
    // MARK: - HomeKit Write Functions
    
    private func setPowerState(_ on: Bool) {
        guard let characteristic = powerStateCharacteristic else {
            print("Power characteristic not found.")
            return
        }
        
        characteristic.writeValue(on) { error in
            if let error = error {
                print("Error setting power state: \(error.localizedDescription)")
            } else {
                print("Power state successfully set to \(on)")
            }
        }
    }
    
    private func setBrightness(_ newValue: Double) {
        guard let characteristic = brightnessCharacteristic else {
            print("Brightness characteristic not found.")
            return
        }
        
        characteristic.writeValue(NSNumber(value: newValue)) { error in
            if let error = error {
                print("Error setting brightness: \(error.localizedDescription)")
            } else {
                print("Brightness successfully set to \(newValue)")
            }
        }
    }

    private func setHue(_ newValue: Double) {
        guard let characteristic = hueCharacteristic else {
            print("Hue characteristic not found.")
            return
        }
        
        characteristic.writeValue(NSNumber(value: newValue)) { error in
            if let error = error {
                print("Error setting hue: \(error.localizedDescription)")
            } else {
                print("Hue successfully set to \(newValue)")
            }
        }
    }
    
    private func setColorTemperature(_ newMiredValue: Double) {
        guard let characteristic = colorTemperatureCharacteristic else {
            print("Color Temperature characteristic not found.")
            return
        }
        
        characteristic.writeValue(NSNumber(value: newMiredValue)) { error in
            if let error = error {
                print("Error setting color temperature: \(error.localizedDescription)")
            } else {
                print("Color Temperature successfully set to \(newMiredValue) Mireds")
            }
        }
    }
}

// MARK: - HueGradientSlider

private struct HueGradientSlider: View {
    @Binding var hue: Double
    
    private let hueGradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(hue: 0.0, saturation: 1, brightness: 1),
            Color(hue: 1/6, saturation: 1, brightness: 1),
            Color(hue: 2/6, saturation: 1, brightness: 1),
            Color(hue: 3/6, saturation: 1, brightness: 1),
            Color(hue: 4/6, saturation: 1, brightness: 1),
            Color(hue: 5/6, saturation: 1, brightness: 1),
            Color(hue: 1.0, saturation: 1, brightness: 1)
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        Slider(value: $hue, in: 0...360, step: 1)
            .background(
                hueGradient
                    .clipShape(Capsule())
            )
    }
}

// MARK: - TemperatureGradientSlider

private struct TemperatureGradientSlider: View {
    @Binding var kelvin: Double
    let kelvinMin: Double
    let kelvinMax: Double
    
    private var tempGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 1.0, green: 0.9, blue: 0.6),  // Warm
                Color(red: 1.0, green: 1.0, blue: 1.0), // Neutral
                Color(red: 0.8, green: 0.9, blue: 1.0)  // Cool
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var body: some View {
        Slider(value: $kelvin, in: kelvinMin...kelvinMax, step: 1)
            .background(
                tempGradient
                    .clipShape(Capsule())
            )
    }
}
