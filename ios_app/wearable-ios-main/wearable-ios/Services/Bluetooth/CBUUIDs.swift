//
//  CBUUIDs.swift
//  wearable-ios
//
//  Created by Luke Redmore on 10/10/23.
//  Updated by Jade 10/06/26
//

@preconcurrency import CoreBluetooth

struct CBUUIDs {
    static let kBLEService_UUID =
        "7bfa0001-6e4d-4b9d-923b-5d234081a100"

    // Commands: write with response
    static let kBLE_Characteristic_uuid_Tx =
        "7bfa0002-6e4d-4b9d-923b-5d234081a100"

    // Raw sensor samples: notifications
    static let kBLE_Characteristic_uuid_Rx =
        "7bfa0004-6e4d-4b9d-923b-5d234081a100"

    static let BLEService_UUID =
        CBUUID(string: kBLEService_UUID)

    static let BLE_Characteristic_uuid_Tx =
        CBUUID(string: kBLE_Characteristic_uuid_Tx)

    static let BLE_Characteristic_uuid_Rx =
        CBUUID(string: kBLE_Characteristic_uuid_Rx)

    // Recording state and command acknowledgements
    static let statusUUID =
        CBUUID(string: "7bfa0003-6e4d-4b9d-923b-5d234081a100")

    // Charger and button information
    static let telemetryUUID =
        CBUUID(string: "7bfa0005-6e4d-4b9d-923b-5d234081a100")

    // One sample frame is 20 bytes.
    // A notification can contain multiple frames.
    static let MaxCharacters = 20
}
