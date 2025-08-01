//
//  MQTTManager.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 7/31/23.
//

import Foundation
import CocoaMQTT
import OSLog
import Security

protocol MqttClientProxyManagerDelegate: AnyObject {
	func onMqttConnected()
	func onMqttDisconnected()
	func onMqttMessageReceived(message: CocoaMQTTMessage)
	func onMqttError(message: String)
}

class MqttClientProxyManager {
	// Singleton Instance
	static let shared = MqttClientProxyManager()
	private static let defaultKeepAliveInterval: Int32 = 60
	weak var delegate: MqttClientProxyManagerDelegate?
	var mqttClientProxy: CocoaMQTT?
	var topic = "msh"
	var debugLog = false
	func connectFromConfigSettings(node: NodeInfoEntity) {
		let originalAddress = node.mqttConfig?.address ?? "mqtt.meshtastic.org"
		let defaultServerAddress = "mqtt.meshtastic.org"
		var useSsl = node.mqttConfig?.tlsEnabled == true
		var defaultServerPort = useSsl ? 8883 : 1883
		var host = originalAddress
		if originalAddress.contains(":") {
			host = host.components(separatedBy: ":")[0]
			defaultServerPort = Int(originalAddress.components(separatedBy: ":")[1]) ?? (useSsl ? 8883 : 1883)
		}
		// Require TLS for the public Server
		if host.lowercased() == defaultServerAddress {
			useSsl = true
			defaultServerPort = 8883
		}
		let port = defaultServerPort
		let root = node.mqttConfig?.root?.count ?? 0 > 0 ? node.mqttConfig?.root : "msh"
		let prefix = root!
		topic = prefix + "/2/e" + "/#"
		// Require opt in to map report terms to connect
		if node.mqttConfig?.mapReportingEnabled ?? false && UserDefaults.mapReportingOptIn || !(node.mqttConfig?.mapReportingEnabled ?? false) {
			connect(host: host, port: port, useSsl: useSsl, topic: topic, node: node)
		} else {
			delegate?.onMqttError(message: "MQTT Map Reporting Terms need to be accepted.")
		}
	}
	func connect(host: String, port: Int, useSsl: Bool, topic: String?, node: NodeInfoEntity) {
		guard !host.isEmpty else {
			delegate?.onMqttDisconnected()
			return
		}
		let clientId = "MeshtasticAppleMqttProxy-" + (node.user?.userId ?? String(ProcessInfo().processIdentifier))
		mqttClientProxy = CocoaMQTT(clientID: clientId, host: host, port: UInt16(port))
		if let mqttClient = mqttClientProxy {
			mqttClient.enableSSL = useSsl
			mqttClient.allowUntrustCACertificate = true
			mqttClient.username =  node.mqttConfig?.username
			mqttClient.password = node.mqttConfig?.password
			mqttClient.keepAlive = 60
			mqttClient.cleanSession = true
			if debugLog {
				mqttClient.logLevel = .debug
			}
			mqttClient.willMessage = CocoaMQTTMessage(topic: "/will", string: "dieout")
			mqttClient.autoReconnect = true
			mqttClient.delegate = self
			let success = mqttClient.connect()
			if !success {
				delegate?.onMqttError(message: "Mqtt connect error")
			}
		} else {
			delegate?.onMqttError(message: "Mqtt initialization error")
		}
	}
	func subscribe(topic: String, qos: CocoaMQTTQoS) {
		Logger.mqtt.info("📲 [MQTT Client Proxy] subscribed to: \(topic, privacy: .public)")
		mqttClientProxy?.subscribe(topic, qos: qos)
	}
	func unsubscribe(topic: String) {
		mqttClientProxy?.unsubscribe(topic)
		Logger.mqtt.info("📲 [MQTT Client Proxy] unsubscribe to topic: \(topic, privacy: .public)")
	}
	func publish(message: String, topic: String, qos: CocoaMQTTQoS) {
		mqttClientProxy?.publish(topic, withString: message, qos: qos)
		Logger.mqtt.debug("📲 [MQTT Client Proxy] publish for: \(topic, privacy: .public)")
	}
	func disconnect() {
		if let client = mqttClientProxy {
			client.disconnect()
			Logger.mqtt.info("📲 [MQTT Client Proxy] disconnected")
		}
	}
}

extension MqttClientProxyManager: CocoaMQTTDelegate {
	func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
		Logger.mqtt.info("📲 [MQTT Client Proxy] didConnectAck: \(ack, privacy: .public)")
		if ack == .accept {
			delegate?.onMqttConnected()
		} else {
			// Connection error
			var errorDescription = "Unknown Error"
			switch ack {
			case .accept:
				errorDescription = "No Error"
			case .unacceptableProtocolVersion:
				errorDescription = "Unacceptable Protocol version"
			case .identifierRejected:
				errorDescription = "Invalid Id"
			case .serverUnavailable:
				errorDescription = "Invalid Server"
			case .badUsernameOrPassword:
				errorDescription = "Invalid Credentials"
			case .notAuthorized:
				errorDescription = "Authorization Error"
			default:
				errorDescription = "Unknown Error"
			}
			Logger.services.error("📲 [MQTT Client Proxy] \(errorDescription, privacy: .public)")
			delegate?.onMqttError(message: errorDescription)
			self.disconnect()
		}
	}
	func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
		let isValid = SecTrustEvaluateWithError(trust, nil)
		if isValid {
			Logger.mqtt.info("📲 [MQTT Client Proxy] TLS validation succeeded.")
			completionHandler(true)
		} else {
			Logger.mqtt.warning("📲 [MQTT Client Proxy] TLS validation failed.")
			completionHandler(true)
		}
	}
	func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
		Logger.mqtt.debug("📲 [MQTT Client Proxy] disconnected: \(err?.localizedDescription ?? "", privacy: .public)")
		if let error = err {
			delegate?.onMqttError(message: error.localizedDescription)
		}
		delegate?.onMqttDisconnected()
	}
	func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
		Logger.mqtt.info("📲 [MQTT Client Proxy] published messsage from MqttClientProxyManager: \(message, privacy: .public)")
	}
	func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
		Logger.mqtt.info("📲 [MQTT Client Proxy] published Ack from MqttClientProxyManager: \(id, privacy: .public)")
	}

	public func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
		delegate?.onMqttMessageReceived(message: message)
		Logger.mqtt.info("📲 [MQTT Client Proxy] message received on topic: \(message.topic, privacy: .public)")
	}
	func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
		Logger.mqtt.debug("📲 [MQTT Client Proxy] subscribed to topics: \(success.allKeys.count, privacy: .public) topics. failed: \(failed.count, privacy: .public) topics")
	}
	func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
		Logger.mqtt.debug("📲 [MQTT Client Proxy] unsubscribed from topics: \(topics.joined(separator: "- "), privacy: .public)")
	}
	func mqttDidPing(_ mqtt: CocoaMQTT) {
		Logger.mqtt.debug("📲 [MQTT Client Proxy] ping")
	}
	func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
		Logger.mqtt.debug("📲 [MQTT Client Proxy] pong")
	}
}
