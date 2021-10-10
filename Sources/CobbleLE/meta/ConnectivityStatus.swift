//
//  ConnectivityStatus.swift
//  CobbleLEKit
//
//  Created by crc32 on 07/10/2021.
//

import Foundation
public class ConnectivityStatus: CustomStringConvertible {
    let connected: Bool
    let paired: Bool
    let encrypted: Bool
    let hasBondedGateway: Bool
    let supportsPinningWithoutSlaveSecurity: Bool
    let hasRemoteAttemptedToUseStalePairing: Bool
    let pairingErrorCode: UInt8
    
    init(characteristicValue: Data) {
        let flags = characteristicValue[0]
        connected = flags & 0b1 > 0
        paired = flags & 0b10 > 0
        encrypted = flags & 0b100 > 0
        hasBondedGateway = flags & 0b1000 > 0
        supportsPinningWithoutSlaveSecurity = flags & 0b10000 > 0
        hasRemoteAttemptedToUseStalePairing = flags & 0b100000 > 0
        pairingErrorCode = characteristicValue[3]
    }
    
    public var description: String { return "ConnectivityStatus: connected: \(connected), paired: \(paired), encrypted: \(encrypted), hasBondedGateway: \(hasBondedGateway), supportsPinningWithoutSlaveSecurity: \(supportsPinningWithoutSlaveSecurity), hasRemoteAttemptedToUseStalePairing: \(hasRemoteAttemptedToUseStalePairing), pairingErrorCode: \(pairingErrorCode)" }
}
