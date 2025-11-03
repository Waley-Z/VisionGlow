//
//  HomeStore.swift
//  VisionGlow
//
//  Created by DEV Studio on 2/5/25.
//

import Foundation
import HomeKit
import Combine

class HomeStore: NSObject, ObservableObject, HMHomeManagerDelegate {
    @Published var homes: [HMHome] = []
    @Published var rooms: [HMRoom] = []
    @Published var accessories: [HMAccessory] = []
    private var manager: HMHomeManager!

    override init(){
        super.init()
        load()
    }
    
    func load() {
        if manager == nil {
            manager = .init()
            manager.delegate = self
        }
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        print("DEBUG: Updated Homes!")
        self.homes = self.manager.homes
        findRooms(homeId: self.homes.first?.uniqueIdentifier ?? UUID())
        for home in homes {
            findAccessories(homeId: home.uniqueIdentifier)
        }
    }
    
    func findRooms(homeId: UUID) {
        guard let home = homes.first(where: {$0.uniqueIdentifier == homeId}) else {
            print("ERROR: No Home found!")
            return
        }

        let allRooms = [home.roomForEntireHome()] + home.rooms
        let nonEmptyRooms = allRooms
            .filter { !$0.accessories.isEmpty }
            .sorted { $0.name < $1.name }

        self.rooms = nonEmptyRooms
    }

    func findAccessories(homeId: UUID) {
        guard let devices = homes.first(where: {$0.uniqueIdentifier == homeId})?.accessories else {
            print("ERROR: No Accessory not found!")
            return
        }
        accessories += devices
    }
    
    func findAccessoriesById(accessoryId: UUID) -> HMAccessory? {
        return accessories.first(where: {$0.uniqueIdentifier == accessoryId})
    }
}
