//
//  LEConstants.swift
//  CobbleLEKit
//
//  Created by crc32 on 09/10/2021.
//

import Foundation
import CoreBluetooth
public struct LEConstants {
    public static let pairServiceUUID = CBUUID(string: "0000fed9-0000-1000-8000-00805f9b34fb")
    public static let connectivityUUID = CBUUID(string: "00000001-328E-0FBB-C642-1AA6699BDADA")
    public static let pairTriggerUUID = CBUUID(string: "00000002-328E-0FBB-C642-1AA6699BDADA")
    public static let connParamsUUID = CBUUID(string: "00000005-328E-0FBB-C642-1AA6699BDADA")
    
    public static let appLaunchServiceUUID = CBUUID(string: "20000000-328E-0FBB-C642-1AA6699BDADA")
    public static let appLaunchCharUUID = CBUUID(string: "20000001-328E-0FBB-C642-1AA6699BDADA")
}
