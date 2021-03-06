//
//  LEClientController.swift
//  CobbleLEKit
//
//  Created by crc32 on 08/10/2021.
//

import Foundation
import CoreBluetooth

public class LEClientController: NSObject, CBPeripheralDelegate {
    private var running = false
    private let peripheral: CBPeripheral
    private let centralManager: CBCentralManager
    private let stateCallback: (ConnectivityStatus) -> ()
    
    public init(peripheral: CBPeripheral, centralManager: CBCentralManager, stateCallback: @escaping (ConnectivityStatus) -> ()) {
        self.peripheral = peripheral
        self.centralManager = centralManager
        self.stateCallback = stateCallback
        super.init()
        peripheral.delegate = self
    }
    
    public func connect(requireANCS: Bool = false) {
        if #available(iOS 13.0, *), requireANCS {
            centralManager.connect(peripheral, options: [
                CBConnectPeripheralOptionRequiresANCS: true
            ])
        } else {
            centralManager.connect(peripheral)
        }
    }
    
    public func disconnect() {
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            print("Failed to discover services: " + error!.localizedDescription)
            return
        }
        
        print("Discovered services.")
        let pairService = peripheral.services?.first(where: { $0.uuid == LEConstants.pairServiceUUID })
        peripheral.discoverCharacteristics(nil, for: pairService!)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if (error != nil) {
            print("Error discovering characteristics: " + error!.localizedDescription)
            return
        }
        
        print("Discovered characteristics.")
        switch service.uuid {
        case LEConstants.pairServiceUUID:
            let connParamChar = service.characteristics?.first(where: { $0.uuid == LEConstants.connParamsUUID })
            if (connParamChar == nil) {
                print("Starting connectivity w/o connparams")
                deviceConnectivity()
            }else {
                peripheral.discoverDescriptors(for: connParamChar!)
            }
            break
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) {
            print("Error discovering descriptors for char " + characteristic.uuid.uuidString + ": " + error!.localizedDescription)
            return
        }
        
        switch characteristic.uuid {
        case LEConstants.connParamsUUID:
            peripheral.setNotifyValue(true, for: characteristic)
            break
        case LEConstants.connectivityUUID:
            peripheral.setNotifyValue(true, for: characteristic)
            if #available(iOS 14.0, *), ProcessInfo.processInfo.isiOSAppOnMac { // Workaround for iOS BT stack on Mac
                peripheral.setNotifyValue(true, for: characteristic)
            }
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        if (error != nil) {
            print("Error writing desc value for char " + descriptor.characteristic!.uuid.uuidString + ": " + error!.localizedDescription)
            return
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) {
            print("Error updating notif state for char " + characteristic.uuid.uuidString + ": " + error!.localizedDescription)
            return
        }
        
        switch characteristic.uuid {
        case LEConstants.connParamsUUID:
            let disableParamManagementVal: [UInt8] = [0x00, 0x01]
            peripheral.writeValue(Data(disableParamManagementVal), for: characteristic, type: .withResponse)
            break
        case LEConstants.connectivityUUID:
            print("Subscribed successfully to connectivity")
            break
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) {
            print("Error writing to char " + characteristic.uuid.uuidString + ": " + error!.localizedDescription)
            return
        }
        
        switch characteristic.uuid {
        case LEConstants.connParamsUUID:
            print("Starting connectivity after connparams")
            deviceConnectivity()
            break
        default:
            break
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if (error != nil) {
            print("Error while listening to char " + characteristic.uuid.uuidString + ": " + error!.localizedDescription)
            return
        }
        
        switch characteristic.uuid {
        case LEConstants.connectivityUUID:
            let status = ConnectivityStatus(characteristicValue: characteristic.value!)
            print("Connectivity status update: " + status.description)
            stateCallback(status)
            if !running {
                running = true
                if status.connected && status.paired {
                    print("Paired.")
                }else {
                    print("Not yet paired, pairing...")
                    let pairTrigger = characteristic.service?.characteristics?.first(where: { $0.uuid == LEConstants.pairTriggerUUID })
                    /*if pairTrigger!.properties.contains(.write) {
                        print("Writing pairing trigger")
                        peripheral.writeValue(Data([true, status.supportsPinningWithoutSlaveSecurity, false, false, false, false].toBytes()), for: pairTrigger!, type: .withResponse)
                    }else {
                        print("Reading pairing trigger")
                        let _ = peripheral.readValue(for: pairTrigger!)
                    }*/
                    // The above is the right way, but the pebble apparently doesn't want that and neither does the iOS app apparently
                    print("Reading pairing trigger")
                    peripheral.readValue(for: pairTrigger!)
                }
            }
            break
        default:
            break
        }
    }
    
    private func deviceConnectivity() {
        let pairService = peripheral.services?.first(where: { $0.uuid == LEConstants.pairServiceUUID })
        let connCharacteristic = pairService!.characteristics!.first(where: { $0.uuid == LEConstants.connectivityUUID })
        peripheral.discoverDescriptors(for: connCharacteristic!)
    }
}
