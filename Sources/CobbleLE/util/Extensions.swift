//
//  File.swift
//  
//
//  Created by crc32 on 11/10/2021.
//

import Foundation

extension Array where Element == Bool {
    func toBytes() -> [UInt8] {
        var bArr = [UInt8](repeating: 0, count: (self.count + 7) / 8)
        for i in self.indices {
            let i2 = i / 8
            let i3 = i % 8
            if self[i] {
                bArr[i2] = (1 << i3 | bArr[i2])
            }
        }
        return bArr
    }
}
