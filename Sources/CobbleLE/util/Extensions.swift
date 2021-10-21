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

public extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension ContiguousBytes {
    func object<T>() -> T { withUnsafeBytes { $0.load(as: T.self) } }
}

extension Data {
    func subdata<R: RangeExpression>(in range: R) -> Self where R.Bound == Index {
        subdata(in: range.relative(to: self) )
    }
    func object<T>(at offset: Int) -> T { subdata(in: offset...).object() }
}

extension Numeric {
    var data: Data {
        var source = self
        return Data(bytes: &source, count: MemoryLayout<Self>.size)
    }
}
