//
//  FactoryResetNodeIntent.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/25/24.
//

import Foundation
import AppIntents

struct FactoryResetNodeIntent: AppIntent {
	static var title: LocalizedStringResource = "Factory Reset"
	static var description: IntentDescription = "Perform a factory reset on the node you are connected to"
	@Parameter(title: "Hard Reset", description: "In addition to Config, Keys and BLE bonds will be wiped", default: false)
	var hardReset: Bool
	@Parameter(title: "Provide Confirmation", description: "Show a confirmation dialog before performing the factory reset", default: true)
	var provideConfirmation: Bool

	func perform() async throws -> some IntentResult {
		// Request user confirmation before performing the factory reset
		if provideConfirmation {
			try await requestConfirmation(result: .result(dialog: "Are you sure you want to factory reset the node?"), confirmationActionName: ConfirmationActionName
				.custom(acceptLabel: "Factory Reset", acceptAlternatives: [], denyLabel: "Cancel", denyAlternatives: [], destructive: true))
		}

		// Ensure the node is connected
		if !BLEManager.shared.isConnected {
			throw AppIntentErrors.AppIntentError.notConnected
		}

		// Safely unwrap the connected node information
		if let connectedPeripheralNum = BLEManager.shared.connectedPeripheral?.num,
		   let connectedNode = getNodeInfo(id: connectedPeripheralNum, context: PersistenceController.shared.container.viewContext),
		   let fromUser = connectedNode.user,
		   let toUser = connectedNode.user {

			// Attempt to send a factory reset command, throw an error if it fails
			if !BLEManager.shared.sendFactoryReset(fromUser: fromUser, toUser: toUser, resetDevice: hardReset) {
				throw AppIntentErrors.AppIntentError.message("Failed to perform factory reset")
			}
		} else {
			throw AppIntentErrors.AppIntentError.message("Failed to retrieve connected node or required data")
		}
//		
		return .result()
	}
}
