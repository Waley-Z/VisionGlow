//
//  TemperatureSensorControlView.swift
//  VisionGlow
//
//  Created by DEV Studio on 2/20/25.
//


import SwiftUI
import HomeKit

struct TemperatureSensorControlView: View {
    let accessoryId: UUID
    @Environment(AppModel.self) var appModel
    
    private var accessory: HMAccessory {
        appModel.homeStore.findAccessoriesById(accessoryId: accessoryId)!
    }

    // Assuming the temperature sensor service can be identified:
    private var temperatureCharacteristic: HMCharacteristic? {
        accessory.services.first { $0.serviceType == HMServiceTypeTemperatureSensor }?
            .characteristics.first { $0.characteristicType == HMCharacteristicTypeCurrentTemperature }
    }
    
    @State private var currentTemperatureC: Double = 0.0
    
    private var currentTemperatureF: Double {
        currentTemperatureC * 9.0/5.0 + 32.0
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(accessory.name)
                .font(.title)
            
            if let _ = temperatureCharacteristic {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(currentTemperatureF, specifier: "%.0f")")
                        .font(.system(size: 64, weight: .bold))
                    Text("°F")
                        .font(.system(size: 24, weight: .regular))
                }
            } else {
                Text("Temperature sensor not available")
            }
        }
        .padding()
        .onAppear {
            if let characteristic = temperatureCharacteristic {
                characteristic.readValue { error in
                    if let error = error {
                        print("Error reading temperature: \(error.localizedDescription)")
                    } else if let value = characteristic.value as? NSNumber {
                        DispatchQueue.main.async {
                            self.currentTemperatureC = value.doubleValue
                        }
                    }
                }
            }
        }
    }
}
