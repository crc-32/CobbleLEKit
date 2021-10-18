//
//  PPoGATTService.swift
//  
//
//  Created by crc32 on 15/10/2021.
//

import Foundation
import CoreBluetooth

class PPoGATTService: NSObject, StreamDelegate {
    static let maxMTU = 185
    
    let serverController: LEPeripheralController
    
    let deviceServerUUID = CBUUID(string: "10000000-328E-0FBB-C642-1AA6699BDADA")
    let deviceCharacteristicUUID = CBUUID(string: "10000001-328E-0FBB-C642-1AA6699BDADA")
    let metaCharacteristicUUID = CBUUID(string: "10000002-328E-0FBB-C642-1AA6699BDADA")
    
    var deviceCharacteristic: CBMutableCharacteristic!
    
    let metaResponse: [UInt8] = [0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    let readBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: maxMTU - 4)
    
    private var seq = 0
    private var remoteSeq = 0
    private var currentRXPend = 0
    private var lastAck: GATTPacket?
    private var delayedAckJob: DispatchWorkItem?
    
    private var initialReset = false
    private var coalescedAcking = false
    private var windowNegotiation = false
    private var connectionVersion: UInt8 = 0
    private var maxRXWindow: UInt8 = LEConstants.maxRXWindow
    private var maxTXWindow: UInt8 = LEConstants.maxTXWindow
    private var packetsInFlight = 0
    private var pendingPackets = [GATTPacket]()
    private var ackPending = Dictionary<UInt8, DispatchSemaphore>()
    
    private let queue = DispatchQueue.global(qos: .utility)
    private let highPrioQueue = DispatchQueue.global(qos: .userInteractive)
    private let packetWriteSemaphore = DispatchSemaphore(value: 1)
    private let packetReadSemaphore = DispatchSemaphore(value: 1)
    private let dataUpdateSemaphore = DispatchSemaphore(value: 1)
    
    init(serverController: LEPeripheralController) {
        self.serverController = serverController
        super.init()
        let service = CBMutableService(type: deviceServerUUID, primary: true)
        let metaCharacteristic = CBMutableCharacteristic(type: metaCharacteristicUUID, properties: .read, value: Data(metaResponse), permissions: .readEncryptionRequired)
        deviceCharacteristic = CBMutableCharacteristic(type: deviceCharacteristicUUID, properties: [.writeWithoutResponse, .notifyEncryptionRequired], value: nil, permissions: .writeEncryptionRequired)
        deviceCharacteristic.descriptors = [CBMutableDescriptor(type: CBUUID(string: CBUUIDClientCharacteristicConfigurationString), value: nil)]
        
        service.characteristics = [metaCharacteristic, deviceCharacteristic]
        serverController.addService(service: service) { error in
            if error != nil {
                print("GATTService: Error adding service: \(error!.localizedDescription)")
            }
        }
        serverController.setCharacteristicCallback(uuid: metaCharacteristicUUID, onRead: self.onMetaRead)
        serverController.setCharacteristicCallback(uuid: deviceCharacteristicUUID, onWrite: self.onWrite)
    }
    
    private func getNextSeq(current: Int) -> Int {
        return (current + 1) % 32
    }
    
    private func onWrite(requests: [CBATTRequest]) {
        queue.async { [self] in
            packetReadSemaphore.wait()
            for request in requests {
                if request.value != nil {
                    let packet = GATTPacket(rawData: request.value!)
                    if packet.type != nil {
                        switch packet.type! {
                        case .data:
                            if packet.sequence == remoteSeq {
                                sendAck(sequence: packet.sequence)
                            }
                        case .ack:
                            for i in 0...packet.sequence {
                                let ind = ackPending.index(forKey: i)
                                if ind != nil {
                                    ackPending.remove(at: ind!).value.signal()
                                }
                                packetsInFlight = max(0, packetsInFlight-1)
                            }
                            print("GATTService: Got ACK for \(packet.sequence)")
                            
                        case .reset:
                            assert(seq == 0, "GATTService: Got reset on non zero sequence")
                            if packet.connectionVersion > 0 {
                                coalescedAcking = true
                                windowNegotiation = true
                            }
                            connectionVersion = packet.connectionVersion
                            requestReset()
                            sendResetAck(sequence: packet.sequence)
                        case .resetAck:
                            print("GATTService: Got reset ACK")
                            if windowNegotiation, !packet.hasWindowSizes {
                                print("GATTService: FW does not support window sizes in reset complete, reverting to connectionVersion 0")
                                connectionVersion = 0
                                coalescedAcking = false
                                windowNegotiation = false
                            }
                            
                            if windowNegotiation {
                                maxRXWindow = min(packet.maxRXWindow, LEConstants.maxRXWindow)
                                maxTXWindow = min(packet.maxTXWindow, LEConstants.maxTXWindow)
                                print("GATTService: Windows negotiated: rx = \(maxRXWindow), tx = \(maxTXWindow)")
                            }
                            sendResetAck(sequence: packet.sequence)
                        }
                    }
                }
            }
            packetReadSemaphore.signal()
        }
    }
    
    func requestReset() {
        writePacket(type: .reset, data: [connectionVersion], sequence: 0)
    }
    private func sendAck(sequence: UInt8) {
        if !coalescedAcking {
            currentRXPend = 0
            writePacket(type: .ack, data: nil, sequence: sequence)
        }else {
            currentRXPend += 1
            delayedAckJob?.cancel()
            if currentRXPend >= maxRXWindow / 2 {
                currentRXPend = 0
                writePacket(type: .ack, data: nil, sequence: sequence)
            }else {
                delayedAckJob = DispatchWorkItem { [self] in
                    currentRXPend = 0
                    writePacket(type: .ack, data: nil, sequence: sequence)
                }
                highPrioQueue.asyncAfter(deadline: .now() + 0.2, execute: delayedAckJob!)
            }
        }
    }
    private func sendResetAck(sequence: UInt8) {
        writePacket(type: .resetAck, data: windowNegotiation ? [maxRXWindow, maxTXWindow] : nil, sequence: sequence) { [self] in
            reset()
        }
    }
    
    private func updateData() {
        highPrioQueue.async { [self] in
            dataUpdateSemaphore.wait()
            if !pendingPackets.isEmpty {
                if packetsInFlight >= maxTXWindow {
                    packetsInFlight += 1
                    let packet = pendingPackets.removeFirst()
                    serverController.updateValue(value: packet.rawData, forChar: deviceCharacteristic) {
                        dataUpdateSemaphore.signal()
                    }
                }else {
                    dataUpdateSemaphore.signal()
                }
            }else {
                dataUpdateSemaphore.signal()
            }
        }
    }
    
    private func onMetaRead(request: CBATTRequest) {
        print("GATTService: Meta read")
    }
    
    private func writePacket(type: GATTPacketType, data: [UInt8]?, sequence: UInt8? = nil, done: (() -> ())? = nil) {
        queue.async { [self] in
            packetWriteSemaphore.wait()
            let nextSeq = self.getNextSeq(current: self.seq)
            let packet = GATTPacket(type: type, sequence: sequence ?? UInt8(nextSeq), data: data ?? [])
            if type == .ack {
                lastAck = packet
            }
            if type == .data {
                highPrioQueue.async {
                    dataUpdateSemaphore.wait()
                    let sem = DispatchSemaphore(value: 0)
                    ackPending[packet.sequence] = sem
                    pendingPackets.append(packet)
                    if sequence == nil {
                        self.seq = nextSeq
                    }
                    dataUpdateSemaphore.signal()
                    sem.wait()
                    done?()
                }
            }else {
                packetsInFlight += 1
                serverController.updateValue(value: packet.rawData, forChar: deviceCharacteristic) {
                    done?()
                    packetWriteSemaphore.signal()
                }
            }
        }
    }
    
    public func write(rawProtocolPacket: [UInt8]) {
        let maxPacketSize = PPoGATTService.maxMTU - 4
        let chunkCount = Int(ceil(Double(rawProtocolPacket.count) / Double(maxPacketSize)))
        var chunked = rawProtocolPacket.chunked(into: chunkCount)
        while !chunked.isEmpty {
            writePacket(type: .data, data: chunked.removeFirst()) { [self] in
                updateData()
            }
        }
    }
    
    private func reset() {
        print("GATTService: Resetting LE")
        remoteSeq = 0
        seq = 0
        lastAck = nil
        packetsInFlight = 0
        if !initialReset {
            print("Initial reset, everything is connected now")
        }
        initialReset = true
    }
}
