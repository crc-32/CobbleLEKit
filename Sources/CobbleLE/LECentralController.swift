//
//  LECentralController.swift
//  CobbleLEKit
//
//  Created by crc32 on 06/08/2021.
//

import Foundation
import CoreBluetooth

public class LECentralController: NSObject, CBCentralManagerDelegate {
    public var centralManager: CBCentralManager
    private let queue = DispatchQueue.global(qos: .utility)
    
    private var discoveryCallback: ((CBPeripheral, Int) -> ())?
    public var ancsUpdateCallback: ((CBPeripheral) -> ())?
    
    private var canScan = false;
    
    public override init() {
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        centralManager.delegate = self
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("unknown")
        case .resetting:
            print("resetting")
        case .unsupported:
            print("unsupported")
        case .unauthorized:
            print("unauthorized")
        case .poweredOff:
            print("poweredOff")
            canScan = false
            stopScan()
        case .poweredOn:
            print("poweredOn")
            canScan = true
        default:
            print("unknown")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print(peripheral.name! + " connected.")
        peripheral.discoverServices(nil)
        
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if error != nil {
            print("Failed to connect: " + error!.localizedDescription)
        }
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print(peripheral.name! + " disconnected.")
    }
    
    public func startScan(discoveredDevice: @escaping (CBPeripheral, Int) -> ()) {
        if canScan {
            discoveryCallback = discoveredDevice
            centralManager.scanForPeripherals(withServices: [LEConstants.pairServiceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)
            ])
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        ancsUpdateCallback?(peripheral)
    }
    
    public func stopScan() {
        discoveryCallback = nil
        if centralManager.isScanning {
            centralManager.stopScan()
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveryCallback?(peripheral, Int(truncating: RSSI))
    }
}
