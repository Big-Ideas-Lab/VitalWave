//
//  V0Status.swift
//  wearable-ios
//
//  Created by Jade Chng on 10/6/26.
//

import Foundation

/// A status reply from VitalWave v0 protocol version 3.
struct V0Status {
    enum RecordingState: UInt8 {
        case idle = 0
        case recording = 1
        case fault = 2
    }

    let state: RecordingState
    let reason: UInt8
    let sensorMask: UInt8
    let sessionID: UInt32
    let lastRequestID: UInt16
    let chargerState: UInt16
    let framesGenerated: UInt32
    let framesDropped: UInt32

    init(data: Data) throws {
        let bytes = Array(data)

        guard bytes.count == 20 else {
            throw DecodeError.wrongLength
        }

        guard bytes[0] == 3 else {
            throw DecodeError.unsupportedVersion
        }

        guard let state = RecordingState(rawValue: bytes[1]) else {
            throw DecodeError.invalidState
        }

        self.state = state
        reason = bytes[2]
        sensorMask = bytes[3]
        sessionID = Self.uint32(bytes, at: 4)
        lastRequestID = Self.uint16(bytes, at: 8)
        chargerState = Self.uint16(bytes, at: 10)
        framesGenerated = Self.uint32(bytes, at: 12)
        framesDropped = Self.uint32(bytes, at: 16)
    }

    private static func uint16(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt16 {
        UInt16(bytes[offset])
            | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    enum DecodeError: Error {
        case wrongLength
        case unsupportedVersion
        case invalidState
    }
}
