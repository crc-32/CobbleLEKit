//
//  GATTPacket.swift
//  
//
//  Created by crc32 on 15/10/2021.
//

import Foundation



public enum GATTPacketType: UInt8 {
    case data = 0
    case ack = 1
    case reset = 2
    case resetAck = 3
}

public struct GATTPacket {
    public let header: UInt8
    public let data: [UInt8]
    
    public var type: GATTPacketType? { GATTPacketType(rawValue: header & 0b111) }
    public var sequence: UInt8 { (header & 0b11111000) >> 3 }
    
    public var connectionVersion: UInt8 {
        assert(type == .reset, "connectionVersion is only available on reset packet (type was \(String(describing: type)))")
        return data[1]
    }
    public var hasWindowSizes: Bool {
        assert(type == .resetAck, "hasWindowSizes is only available on reset ack packet (type was \(String(describing: type)))")
        return data.count >= 3
    }
    public var maxTXWindow: UInt8 {
        assert(type == .resetAck, "maxTXWindow is only available on reset ack packet (type was \(String(describing: type)))")
        return data[2]
    }
    public var maxRXWindow: UInt8 {
        assert(type == .resetAck, "maxRXWindow is only available on reset ack packet (type was \(String(describing: type)))")
        return data[1]
    }
    
    public init(rawData: Data) {
        header = rawData.object()
        data = [UInt8](rawData.subdata(in: 1...))
    }
    public var rawData: Data { header.data + Data(data) }
    
    public init(type: GATTPacketType, sequence: UInt8, data: [UInt8]) {
        var headerVal: UInt8 = 0
        headerVal |= type.rawValue
        headerVal |= (sequence << 3)
        
        self.header = headerVal
        self.data = data
    }
}
