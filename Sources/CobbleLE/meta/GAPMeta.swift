//
//  GAPMeta.swift
//  CobbleLEKit
//
//  Created by crc32 on 18/10/2021.
//

import Foundation
public struct GAPMeta {
    public let vendor: Int16
    public let payloadType: UInt8
    public let serialNumber: String
    
    public let hardwarePlatform: UInt8?
    public let color: UInt8?
    public let major: UInt8?
    public let minor: UInt8?
    public let patch: UInt8?
    
    private let flags: UInt8?
    public var runningPRF: Bool? {
        if flags != nil {
            return flags! & 0x01 > 0
        }else {
            return nil
        }
    }
    public var firstUse: Bool? {
        if flags != nil {
            return flags! & 0x02 > 0
        }else {
            return nil
        }
    }
    
    private let mandatoryDataSize = (UInt16.bitWidth/8)+(UInt8.bitWidth/8)+((UInt8.bitWidth/8)*12)
    
    public init (data: [UInt8]) {
        var seek = 0
        if data.count - seek >= mandatoryDataSize {
            vendor = Int16(UInt16(littleEndian: data.withUnsafeBufferPointer {
                (($0.baseAddress!+seek).withMemoryRebound(to: UInt16.self, capacity: 1) {$0})
            }.pointee))
            seek += UInt16.bitWidth/8
            
            payloadType = data[seek]
            seek += UInt8.bitWidth/8
            serialNumber = String(bytes: data[seek...seek+12], encoding: .utf8) ?? "??"
            seek += serialNumber.count
        }else {
            print("GAPMeta: Mandatory manufacturer specific data malformed")
            vendor = -1
            payloadType = 0
            serialNumber = "??"
        }
        
        if data.count - seek >= 6 {
            hardwarePlatform = data[seek]
            seek += UInt8.bitWidth/8
            
            color = data[seek]
            seek += UInt8.bitWidth/8
            
            major = data[seek]
            seek += UInt8.bitWidth/8
            
            minor = data[seek]
            seek += UInt8.bitWidth/8
            
            patch = data[seek]
            seek += UInt8.bitWidth/8
            
            flags = data[seek]
            seek += UInt8.bitWidth/8
        }else {
            hardwarePlatform = nil
            color = nil
            major = nil
            minor = nil
            patch = nil
            flags = nil
        }
    }
}
