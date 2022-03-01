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
    
    private let queue = DispatchQueue(label: "LEPeripheralControllerUtil", qos: .utility)
    private let ioReadQueue = DispatchQueue(label: "LEPeripheralControllerIORead", qos: .userInitiated)
    private let ioWriteQueue = DispatchQueue(label: "LEPeripheralControllerIOWrite", qos: .userInitiated)
    
    private var pendingServices = Dictionary<CBUUID, (Error?)->()>()
    private let pendingServicesSemaphore = DispatchSemaphore(value: 1)
    
    private var characteristicReadCallbacks = Dictionary<CBUUID, (CBATTRequest)->()>()
    private let characteristicReadCBSemaphore = DispatchSemaphore(value: 1)
    
    private var characteristicWriteCallbacks = Dictionary<CBUUID, ([CBATTRequest])->()>()
    private let characteristicWriteCBSemaphore = DispatchSemaphore(value: 1)
    
    private var characteristicSubscribeCallbacks = Dictionary<CBUUID, (CBCentral)->()>()
    private let characteristicSubscribeCBSemaphore = DispatchSemaphore(value: 1)
    
    private let characteristicUpdateSemaphore = DispatchSemaphore(value: 1)
    
    public var ready: Bool { return peripheralManager.state == .poweredOn }
    private let readyGroup = DispatchGroup()
    private var waitingForReady = false
    
    private var pendingUpdates: [PendingUpdate]
    
    private class PendingUpdate {
        let value: Data
        let characteristic: CBMutableCharacteristic
        let callback: (()->())
        
        init(value: Data, characteristic: CBMutableCharacteristic, callback: @escaping ()->()) {
            self.value = value
            self.characteristic = characteristic
            self.callback = callback
        }
    }
    
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
    public func setCharacteristicCallback(uuid: CBUUID, onSubscribe: @escaping (CBCentral)->()) {
        queue.async {
            self.characteristicSubscribeCBSemaphore.wait()
            self.characteristicSubscribeCallbacks[uuid] = onSubscribe
            self.characteristicSubscribeCBSemaphore.signal()
        }
    }
    
    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        ioWriteQueue.async {
            while !self.pendingUpdates.isEmpty {
                let pendingUpdate = self.pendingUpdates.remove(at: 0)
                guard self.peripheralManager.updateValue(pendingUpdate.value, for: pendingUpdate.characteristic, onSubscribedCentrals: nil) else {
                    self.pendingUpdates.insert(pendingUpdate, at: 0)
                    break
                }
                self.queue.async {
                    pendingUpdate.callback()
                }
            }
        }
    }
    
    public func updateValue(value: Data, forChar: CBMutableCharacteristic, onUpdate: @escaping ()->()) {
        ioWriteQueue.async {
            self.characteristicUpdateSemaphore.wait()
            defer {
                self.characteristicUpdateSemaphore.signal()
            }
            if !self.peripheralManager.updateValue(value, for: forChar, onSubscribedCentrals: nil) {
                self.pendingUpdates.append(PendingUpdate(value: value, characteristic: forChar, callback: onUpdate))
            }else {
                self.queue.async {
                    onUpdate()
                }
            }
        }
    }
    
    public func removeAllServices() {
        peripheralManager.removeAllServices()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        queue.async {
            self.characteristicSubscribeCBSemaphore.wait()
            let cb = self.characteristicSubscribeCallbacks[characteristic.uuid]
            self.characteristicSubscribeCBSemaphore.signal()
            cb?(central)
        }
    }
    
    public func respond(to: CBATTRequest, withResult: CBATTError.Code, data: Data? = nil) {
        if data != nil {
            to.value = data
        }
        peripheralManager.respond(to: to, withResult: withResult)
    }
}
