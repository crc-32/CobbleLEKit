//
//  ConnectivityStatus.swift
//  CobbleLEKit
//
//  Created by crc32 on 07/10/2021.
//

import Foundation

public enum PairingErrorCode: UInt8 {
    case noError = 0
    case passkeyEntryFailed = 1
    case oobNotAvailable = 2
    case authenticationRequirements = 3
    case confirmValueFailed = 4
    case pairingNotSupported = 5
    case encryptionKeySize = 6
    case commandNotSupported = 7
    case unspecifiedReason = 8
    case repeatedAttempts = 9
    case invalidParameters = 10
    case dhkeyCheckFailed = 11
    case numericComparisonFailed = 12
    case brEdrPairingInProgress = 13
    case crossTransportKeyDerivNotAllowed = 14
    case unknown = 255
}

public class ConnectivityStatus: CustomStringConvertible {
    public let connected: Bool
    public let paired: Bool
    public let encrypted: Bool
    public let hasBondedGateway: Bool
    public let supportsPinningWithoutSlaveSecurity: Bool
    public let hasRemoteAttemptedToUseStalePairing: Bool
    public let pairingErrorCode: PairingErrorCode
    
    public init(characteristicValue: Data) {
        let flags = characteristicValue[0]
        connected = flags & 0b1 > 0
        paired = flags & 0b10 > 0
        encrypted = flags & 0b100 > 0
        hasBondedGateway = flags & 0b1000 > 0
        supportsPinningWithoutSlaveSecurity = flags & 0b10000 > 0
        hasRemoteAttemptedToUseStalePairing = flags & 0b100000 > 0
        
        let errCode = PairingErrorCode(rawValue: characteristicValue[3])
        pairingErrorCode = errCode != nil ? errCode! : PairingErrorCode.unknown
    }
    
    public var description: String { return "ConnectivityStatus: connected: \(connected), paired: \(paired), encrypted: \(encrypted), hasBondedGateway: \(hasBondedGateway), supportsPinningWithoutSlaveSecurity: \(supportsPinningWithoutSlaveSecurity), hasRemoteAttemptedToUseStalePairing: \(hasRemoteAttemptedToUseStalePairing), pairingErrorCode: \(pairingErrorCode)" }
}
