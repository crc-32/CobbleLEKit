//
//  LEPeripheralController.swift
//  CobbleLEKit
//
//  Created by crc32 on 09/10/2021.
//

import Foundation
import CoreBluetooth

public class LEPeripheralController: NSObject, CBPeripheralManagerDelegate {
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
    
    private let characteristicUpdateSemaphore = DispatchSemaphore(value: 1)
    
    public var ready: Bool { return peripheralManager.state == .poweredOn }
    private let readyGroup = DispatchGroup()
    private var waitingForReady = false
    
    public override init() {
        waitingForReady = true
        readyGroup.enter()
        peripheralManager = CBPeripheralManager();
        super.init()
        peripheralManager.delegate = self
    }
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("Peripheral: Powered on")
            if waitingForReady {
                readyGroup.leave()
                waitingForReady = false
            }
        default:
            if !waitingForReady {
                waitingForReady = true
                readyGroup.enter()
            }
        }
    }
    
    public func waitForReady(onReady: @escaping () -> ()) {
        if ready {
            onReady()
        } else {
            readyGroup.notify(queue: queue) {
                onReady()
            }
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        ioReadQueue.async {
            self.characteristicReadCBSemaphore.wait()
            let cb = self.characteristicReadCallbacks[request.characteristic.uuid]
            self.characteristicReadCBSemaphore.signal()
            cb?(request)
        }
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        ioWriteQueue.async {
            self.characteristicWriteCBSemaphore.wait()
            let cb = self.characteristicWriteCallbacks[requests[0].characteristic.uuid]
            self.characteristicWriteCBSemaphore.signal()
            cb?(requests)
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        queue.async {
            self.pendingServicesSemaphore.wait()
            let cb = self.pendingServices[service.uuid]
            self.pendingServices.removeValue(forKey: service.uuid)
            self.pendingServicesSemaphore.signal()
            cb?(error)
        }
    }
    
    public func addService(service: CBMutableService, didAdd: @escaping (Error?)->()) {
        queue.async {
            self.pendingServicesSemaphore.wait()
            self.pendingServices[service.uuid] = didAdd
            self.pendingServicesSemaphore.signal()
        }
        peripheralManager.add(service)
    }
    
    public func setCharacteristicCallback(uuid: CBUUID, onWrite: @escaping ([CBATTRequest])->()) {
        queue.async {
            self.characteristicWriteCBSemaphore.wait()
            self.characteristicWriteCallbacks[uuid] = onWrite
            self.characteristicWriteCBSemaphore.signal()
        }
    }
    public func setCharacteristicCallback(uuid: CBUUID, onRead: @escaping (CBATTRequest)->()) {
        queue.async {
            self.characteristicReadCBSemaphore.wait()
            self.characteristicReadCallbacks[uuid] = onRead
            self.characteristicReadCBSemaphore.signal()
        }
    }
    
    public func updateValue(value: Data, forChar: CBMutableCharacteristic, onUpdate: @escaping ()->()) {
        ioWriteQueue.async {
            self.characteristicUpdateSemaphore.wait()
            self.peripheralManager.updateValue(value, for: forChar, onSubscribedCentrals: nil)
            self.characteristicUpdateSemaphore.signal()
            onUpdate()
        }
    }
}
