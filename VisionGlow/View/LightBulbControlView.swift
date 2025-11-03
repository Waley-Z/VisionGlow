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
    
    private var accessory: HMAccessory {
        appModel.homeStore.findAccessoriesById(accessoryId: accessoryId)!
    }
    
    private var lightService: HMService? {
        accessory.services.first { $0.serviceType == HMServiceTypeLightbulb }
    }
    
    private var powerStateCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypePowerState }
    }
    
    private var brightnessCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypeBrightness }
    }
    
    private var hueCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypeHue }
    }
    
    private var saturationCharacteristic: HMCharacteristic? {
        lightService?.characteristics.first { $0.characteristicType == HMCharacteristicTypeSaturation }
    }
    
    @State private var isOn: Bool = false
    @State private var brightness: Double = 50
    @State private var hue: Double = 0
    @State private var saturation: Double = 50
    
    @State private var brightnessWriteCancellable: AnyCancellable?
    @State private var hueWriteCancellable: AnyCancellable?
    @State private var satWriteCancellable: AnyCancellable?
    private let brightnessSubject = PassthroughSubject<Double, Never>()
    private let hueSubject = PassthroughSubject<Double, Never>()
    private let saturationSubject = PassthroughSubject<Double, Never>()
    
    var body: some View {
        VStack(spacing: 20) {
            Text(accessory.name)
                .font(.title)
            
            Toggle("Power", isOn: $isOn)
                .toggleStyle(.switch)
                .onChange(of: isOn) { _, newValue in
                    setPowerState(newValue)
                }
            
            if brightnessCharacteristic != nil {
                VStack {
                    Text("Brightness: \(Int(brightness))")
                    Slider(value: $brightness, in: 0...100, step: 1)
                        .onChange(of: brightness) { _, newValue in
                            brightnessSubject.send(newValue)
                        }
                }
            }
            
            if hueCharacteristic != nil {
                VStack {
                    Text("Hue: \(Int(hue))")
                    Slider(value: $hue, in: 0...360, step: 1)
                        .onChange(of: hue) { _, newValue in
                            hueSubject.send(newValue)
                        }
                }
            }
            
            if saturationCharacteristic != nil {
                VStack {
                    Text("Saturation: \(Int(saturation))")
                    Slider(value: $saturation, in: 0...100, step: 1)
                        .onChange(of: saturation) { _, newValue in
                            saturationSubject.send(newValue)
                        }
                }
            }
        }
        .padding()
        .onAppear {
            if let characteristic = powerStateCharacteristic {
                characteristic.readValue { error in
                    if let error = error {
                        print("Error reading power state: \(error.localizedDescription)")
                    } else if let value = characteristic.value as? Bool {
                        DispatchQueue.main.async {
                            self.isOn = value
                        }
                    }
                }
            } else {
                print("Power characteristic not found.")
            }
            
            if let characteristic = brightnessCharacteristic {
                characteristic.readValue { error in
                    if let error = error {
                        print("Error reading brightness: \(error.localizedDescription)")
                    } else if let value = characteristic.value as? NSNumber {
                        DispatchQueue.main.async {
                            self.brightness = value.doubleValue
                        }
                    }
                }
            }
            
            if brightnessWriteCancellable == nil {
                brightnessWriteCancellable = brightnessSubject
                    .removeDuplicates(by: { abs($0 - $1) < 1 }) // ignore +/-1 changes
                    .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
                    .sink { value in setBrightness(value) }
            }
            
            if let characteristic = hueCharacteristic {
                characteristic.readValue { error in
                    if let error = error {
                        print("Error reading hue: \(error.localizedDescription)")
                    } else if let value = characteristic.value as? NSNumber {
                        DispatchQueue.main.async {
                            self.hue = value.doubleValue
                        }
                    }
                }
            }
            
            if hueWriteCancellable == nil {
                hueWriteCancellable = hueSubject
                    .removeDuplicates(by: { abs($0 - $1) < 2 })           // ignore +/-2°
                    .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
                    .sink { value in setHue(value) }
            }
            
            if let characteristic = saturationCharacteristic {
                characteristic.readValue { error in
                    if let error = error {
                        print("Error reading saturation: \(error.localizedDescription)")
                    } else if let value = characteristic.value as? NSNumber {
                        DispatchQueue.main.async {
                            self.saturation = value.doubleValue
                        }
                    }
                }
            }
            
            if satWriteCancellable == nil {
                satWriteCancellable = saturationSubject
                    .removeDuplicates(by: { abs($0 - $1) < 1 })           // ignore +/-1
                    .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
                    .sink { value in setSaturation(value) }
            }
        }
        .onDisappear {
            brightnessWriteCancellable?.cancel(); brightnessWriteCancellable = nil
            hueWriteCancellable?.cancel();        hueWriteCancellable = nil
            satWriteCancellable?.cancel();        satWriteCancellable = nil
        }
    }
    
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
    
    private func setSaturation(_ newValue: Double) {
        guard let characteristic = saturationCharacteristic else {
            print("Saturation characteristic not found.")
            return
        }
        
        characteristic.writeValue(NSNumber(value: newValue)) { error in
            if let error = error {
                print("Error setting saturation: \(error.localizedDescription)")
            } else {
                print("Saturation successfully set to \(newValue)")
            }
        }
    }
}
