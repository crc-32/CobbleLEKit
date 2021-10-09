//
//  LEPeripheralController.swift
//  CobbleLEKit
//
//  Created by crc32 on 09/10/2021.
//

import Foundation
import CoreBluetooth

class LEPeripheralController: NSObject, CBPeripheralManagerDelegate {
    private var peripheralManager: CBPeripheralManager
    
    private let queue = DispatchQueue.global(qos: .utility)
    private let ioReadQueue = DispatchQueue.global(qos: .userInitiated)
    private let ioWriteQueue = DispatchQueue.global(qos: .userInitiated)
    
    private var pendingServices = Dictionary<CBUUID, (Error?)->()>()
    private let pendingServicesSemaphore = DispatchSemaphore(value: 1)
    
    private var characteristicReadCallbacks = Dictionary<CBUUID, (CBATTRequest)->()>()
    private let characteristicReadCBSemaphore = DispatchSemaphore(value: 1)
    
    private var characteristicWriteCallbacks = Dictionary<CBUUID, ([CBATTRequest])->()>()
    private let characteristicWriteCBSemaphore = DispatchSemaphore(value: 1)
    
    override init() {
        peripheralManager = CBPeripheralManager();
        super.init()
        peripheralManager.delegate = self
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            let appLaunchService = CBMutableService(type: LEConstants.appLaunchServiceUUID, primary: true)
            let appLaunchCharacteristic = CBMutableCharacteristic(type: LEConstants.appLaunchCharUUID, properties: CBCharacteristicProperties.read, value: nil, permissions: [.readable, .readEncryptionRequired])
            appLaunchService.characteristics = [appLaunchCharacteristic]
            
            addService(service: appLaunchService) {error in
                if error != nil {
                    print("Error adding applaunch service: " + error!.localizedDescription)
                }else {
                    print("Added applaunch")
                }
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        ioReadQueue.async {
            self.characteristicReadCBSemaphore.wait()
            let cb = self.characteristicReadCallbacks[request.characteristic.uuid]
            self.characteristicReadCBSemaphore.signal()
            cb?(request)
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        ioWriteQueue.async {
            self.characteristicWriteCBSemaphore.wait()
            let cb = self.characteristicWriteCallbacks[requests[0].characteristic.uuid]
            self.characteristicWriteCBSemaphore.signal()
            cb?(requests)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        queue.async {
            self.pendingServicesSemaphore.wait()
            let cb = self.pendingServices[service.uuid]
            self.pendingServices.removeValue(forKey: service.uuid)
            self.pendingServicesSemaphore.signal()
            cb?(error)
        }
    }
    
    func addService(service: CBMutableService, didAdd: @escaping (Error?)->()) {
        queue.async {
            self.pendingServicesSemaphore.wait()
            self.pendingServices[service.uuid] = didAdd
            self.pendingServicesSemaphore.signal()
        }
        peripheralManager.add(service)
    }
    
    func setCharacteristicCallback(uuid: CBUUID, onWrite: @escaping ([CBATTRequest])->()) {
        queue.async {
            self.characteristicWriteCBSemaphore.wait()
            self.characteristicWriteCallbacks[uuid] = onWrite
            self.characteristicWriteCBSemaphore.signal()
        }
    }
    func setCharacteristicCallback(uuid: CBUUID, onRead: @escaping (CBATTRequest)->()) {
        queue.async {
            self.characteristicReadCBSemaphore.wait()
            self.characteristicReadCallbacks[uuid] = onRead
            self.characteristicReadCBSemaphore.signal()
        }
    }
}
