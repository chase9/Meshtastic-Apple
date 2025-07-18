//
//  UserList.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/29/23.
//

import SwiftUI
import CoreData
import OSLog
import TipKit

struct UserList: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@State private var searchText = ""
	@State private var viaLora = true
	@State private var viaMqtt = true
	@State private var isOnline = false
	@State private var isPkiEncrypted = false
	@State private var isFavorite = false
	@State private var isIgnored = false
	@State private var isEnvironment = false
	@State private var distanceFilter = false
	@State private var maxDistance: Double = 800000
	@State private var hopsAway: Double = -1.0
	@State private var roleFilter = false
	@State private var deviceRoles: Set<Int> = []
	@State private var editingFilters = false
	@State private var showingHelp = false
	@State private var showingTrustConfirm: Bool = false

	var boolFilters: [Bool] {[
		isFavorite,
		isOnline,
		isEnvironment,
		distanceFilter,
		roleFilter
	]}

	@Binding var node: NodeInfoEntity?
	@Binding var userSelection: UserEntity?

	@State private var isPresentingDeleteUserMessagesConfirm: Bool = false

	var body: some View {
		let localeDateFormat = DateFormatter.dateFormat(fromTemplate: "yyMMdd", options: 0, locale: Locale.current)
		let dateFormatString = (localeDateFormat ?? "MM/dd/YY")
		VStack {
			FilteredUserList(
				searchText: searchText,
				viaLora: viaLora,
				viaMqtt: viaMqtt,
				isOnline: isOnline,
				isPkiEncrypted: isPkiEncrypted,
				isFavorite: isFavorite,
				isIgnored: isIgnored,
				isEnvironment: isEnvironment,
				distanceFilter: distanceFilter,
				maxDistance: maxDistance,
				hopsAway: hopsAway,
				roleFilter: roleFilter,
				deviceRoles: deviceRoles,
				userSelection: $userSelection
			) { users in
				List(users, selection: $userSelection) { (user: UserEntity) in
					let mostRecent = user.messageList.last
					let lastMessageTime = Date(timeIntervalSince1970: TimeInterval(Int64((mostRecent?.messageTimestamp ?? 0 ))))
					let lastMessageDay = Calendar.current.dateComponents([.day], from: lastMessageTime).day ?? 0
					let currentDay = Calendar.current.dateComponents([.day], from: Date()).day ?? 0
					if user.num != bleManager.connectedPeripheral?.num ?? 0 {
						NavigationLink(value: user) {
							ZStack {
								Image(systemName: "circle.fill")
									.opacity(user.unreadMessages > 0 ? 1 : 0)
									.font(.system(size: 10))
									.foregroundColor(.accentColor)
									.brightness(0.2)
							}

							CircleText(text: user.shortName ?? "?", color: Color(UIColor(hex: UInt32(user.num))))

							VStack(alignment: .leading) {
								HStack {
									if user.pkiEncrypted {
										if !user.keyMatch {
											/// Public Key on the User and the Public Key on the Last Message don't match
											Image(systemName: "key.slash")
												.foregroundColor(.red)
										} else {
											Image(systemName: "lock.fill")
												.foregroundColor(.green)
										}
									} else {
										Image(systemName: "lock.open.fill")
											.foregroundColor(.yellow)
									}
									Text(user.longName ?? "Unknown".localized)
										.font(.headline)
										.allowsTightening(true)
									Spacer()
									if user.userNode?.favorite ?? false {
										Image(systemName: "star.fill")
											.foregroundColor(.yellow)
									}
									if user.messageList.count > 0 {
										if lastMessageDay == currentDay {
											Text(lastMessageTime, style: .time )
												.font(.footnote)
												.foregroundColor(.secondary)
										} else if lastMessageDay == (currentDay - 1) {
											Text("Yesterday")
												.font(.footnote)
												.foregroundColor(.secondary)
										} else if lastMessageDay < (currentDay - 1) && lastMessageDay > (currentDay - 5) {
											Text(lastMessageTime.formattedDate(format: dateFormatString))
												.font(.footnote)
												.foregroundColor(.secondary)
										} else if lastMessageDay < (currentDay - 1800) {
											Text(lastMessageTime.formattedDate(format: dateFormatString))
												.font(.footnote)
												.foregroundColor(.secondary)
										}
									}
								}

								if user.messageList.count > 0 {
									HStack(alignment: .top) {
										Text("\(mostRecent != nil ? mostRecent!.messagePayload! : " ")")
											.font(.footnote)
											.foregroundColor(.secondary)
									}
								}
							}
						}
						.frame(height: 62)
						.contextMenu {
							Button {
								if node != nil && !(user.userNode?.favorite ?? false) {
									let success = bleManager.setFavoriteNode(node: user.userNode!, connectedNodeNum: Int64(node!.num))
									if success {
										user.userNode?.favorite = !(user.userNode?.favorite ?? false)
										Logger.data.info("Favorited a node")
									}
								} else {
									let success = bleManager.removeFavoriteNode(node: user.userNode!, connectedNodeNum: Int64(node!.num))
									if success {
										user.userNode?.favorite = !(user.userNode?.favorite ?? false)
										Logger.data.info("Unfavorited a node")
									}
								}
								context.refresh(user, mergeChanges: true)
								do {
									try context.save()
								} catch {
									context.rollback()
									Logger.data.error("Save Node Favorite Error")
								}
							} label: {
								Label((user.userNode?.favorite ?? false) ? "Un-Favorite" : "Favorite", systemImage: (user.userNode?.favorite ?? false) ? "star.slash.fill" : "star.fill")
							}
							Button {
								user.mute = !user.mute
								do {
									try context.save()
								} catch {
									context.rollback()
									Logger.data.error("Save User Mute Error")
								}
							} label: {
								Label(user.mute ? "Show Alerts" : "Hide Alerts", systemImage: user.mute ? "bell" : "bell.slash")
							}
							if user.messageList.count > 0 {
								Button(role: .destructive) {
									isPresentingDeleteUserMessagesConfirm = true
									userSelection = user
								} label: {
									Label("Delete Messages", systemImage: "trash")
								}
							}
						}
						.confirmationDialog(
							"This conversation will be deleted.",
							isPresented: $isPresentingDeleteUserMessagesConfirm,
							titleVisibility: .visible
						) {
							Button(role: .destructive) {
								deleteUserMessages(user: userSelection!, context: context)
								context.refresh(node!.user!, mergeChanges: true)
							} label: {
								Text("Delete")
							}
						}
					}
				}
				.listStyle(.plain)
				.navigationTitle(String.localizedStringWithFormat("Contacts (%@)", String(users.count)))
			}
			.sheet(isPresented: $editingFilters) {
				NodeListFilter(filterTitle: "Contact Filters", viaLora: $viaLora, viaMqtt: $viaMqtt, isOnline: $isOnline, isPkiEncrypted: $isPkiEncrypted, isFavorite: $isFavorite, isIgnored: $isIgnored, isEnvironment: $isEnvironment, distanceFilter: $distanceFilter, maximumDistance: $maxDistance, hopsAway: $hopsAway, roleFilter: $roleFilter, deviceRoles: $deviceRoles)
			}
			.sheet(isPresented: $showingHelp) {
				DirectMessagesHelp()
			}
			.safeAreaInset(edge: .bottom, alignment: .leading) {
				HStack {
					Button(action: {
						withAnimation {
							showingHelp = !showingHelp
						}
					}) {
						Image(systemName: !editingFilters ? "questionmark.circle" : "questionmark.circle.fill")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
					Spacer()
					Button(action: {
						withAnimation {
							editingFilters = !editingFilters
						}
					}) {
						Image(systemName: !editingFilters ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
							.padding(.vertical, 5)
					}
					.tint(Color(UIColor.secondarySystemBackground))
					.foregroundColor(.accentColor)
					.buttonStyle(.borderedProminent)
				}
				.controlSize(.regular)
				.padding(5)
			}
			.padding(.bottom, 5)
			.searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a contact")
				.disableAutocorrection(true)
				.scrollDismissesKeyboard(.immediately)
		}
	}
}

struct FilteredUserList<Content: View>: View {
	@FetchRequest var fetchRequest: FetchedResults<UserEntity>
	let content: (FetchedResults<UserEntity>) -> Content

	var body: some View {
		content(fetchRequest)
	}

	init(
		searchText: String,
		viaLora: Bool,
		viaMqtt: Bool,
		isOnline: Bool,
		isPkiEncrypted: Bool,
		isFavorite: Bool,
		isIgnored: Bool,
		isEnvironment: Bool,
		distanceFilter: Bool,
		maxDistance: Double,
		hopsAway: Double,
		roleFilter: Bool,
		deviceRoles: Set<Int>,
		userSelection: Binding<UserEntity?>,
		@ViewBuilder content: @escaping (FetchedResults<UserEntity>) -> Content
	) {
		self.content = content
		// Build predicates based on filter variables
		var predicates: [NSPredicate] = []
		// Search text predicates
		if !searchText.isEmpty {
			let searchPredicates = ["userId", "numString", "hwModel", "hwDisplayName", "longName", "shortName"].map { property in
				return NSPredicate(format: "%K CONTAINS[c] %@", property, searchText)
			}
			let textSearchPredicate = NSCompoundPredicate(type: .or, subpredicates: searchPredicates)
			predicates.append(textSearchPredicate)
		}
		// Mqtt and lora
		if !(viaLora && viaMqtt) {
			if viaLora {
				let loraPredicate = NSPredicate(format: "userNode.viaMqtt == NO")
				predicates.append(loraPredicate)
			} else {
				let mqttPredicate = NSPredicate(format: "userNode.viaMqtt == YES")
				predicates.append(mqttPredicate)
			}
		}
		// Roles
		if roleFilter && deviceRoles.count > 0 {
			var rolesArray: [NSPredicate] = []
			for dr in deviceRoles {
				let deviceRolePredicate = NSPredicate(format: "role == %i", Int32(dr))
				rolesArray.append(deviceRolePredicate)
			}
			let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: rolesArray)
			predicates.append(compoundPredicate)
		}
		// Hops Away
		if hopsAway == 0 {
			let hopsAwayPredicate = NSPredicate(format: "userNode.hopsAway == %i", Int32(hopsAway))
			predicates.append(hopsAwayPredicate)
		} else if hopsAway > -1.0 {
			let hopsAwayPredicate = NSPredicate(format: "userNode.hopsAway > 0 AND userNode.hopsAway <= %i", Int32(hopsAway))
			predicates.append(hopsAwayPredicate)
		}
		// Online
		if isOnline {
			let isOnlinePredicate = NSPredicate(format: "userNode.lastHeard >= %@", Calendar.current.date(byAdding: .minute, value: -120, to: Date())! as NSDate)
			predicates.append(isOnlinePredicate)
		}
		// Encrypted
		if isPkiEncrypted {
			let isPkiEncryptedPredicate = NSPredicate(format: "pkiEncrypted == YES")
			predicates.append(isPkiEncryptedPredicate)
		}
		// Favorites
		if isFavorite {
			let isFavoritePredicate = NSPredicate(format: "userNode.favorite == YES")
			predicates.append(isFavoritePredicate)
		}
		// Distance
		if distanceFilter {
			let pointOfInterest = LocationsHandler.currentLocation
			if pointOfInterest.latitude != LocationsHandler.DefaultLocation.latitude && pointOfInterest.longitude != LocationsHandler.DefaultLocation.longitude {
				let d: Double = maxDistance * 1.1
				let r: Double = 6371009
				let meanLatitidue = pointOfInterest.latitude * .pi / 180
				let deltaLatitude = d / r * 180 / .pi
				let deltaLongitude = d / (r * cos(meanLatitidue)) * 180 / .pi
				let minLatitude: Double = pointOfInterest.latitude - deltaLatitude
				let maxLatitude: Double = pointOfInterest.latitude + deltaLatitude
				let minLongitude: Double = pointOfInterest.longitude - deltaLongitude
				let maxLongitude: Double = pointOfInterest.longitude + deltaLongitude
				let distancePredicate = NSPredicate(format: "(SUBQUERY(userNode.positions, $position, $position.latest == TRUE && (%lf <= ($position.longitudeI / 1e7)) AND (($position.longitudeI / 1e7) <= %lf) AND (%lf <= ($position.latitudeI / 1e7)) AND (($position.latitudeI / 1e7) <= %lf))).@count > 0", minLongitude, maxLongitude, minLatitude, maxLatitude)
				predicates.append(distancePredicate)
			}
		}
		// Always apply unmessagable and connected node filters
		// Show unmessagable nodes only if they have messages, otherwise hide them
		let unmessagablePredicate = NSPredicate(format: "unmessagable == NO")
		let hasMessagesPredicate = NSPredicate(format: "receivedMessages.@count > 0 OR sentMessages.@count > 0")
		let isUnmessagablePredicate = NSCompoundPredicate(type: .or, subpredicates: [unmessagablePredicate, hasMessagesPredicate])
		predicates.append(isUnmessagablePredicate)
		let isIgnoredPredicate = NSPredicate(format: "userNode.ignored == NO")
		predicates.append(isIgnoredPredicate)
		let isConnectedNodePredicate = NSPredicate(format: "NOT (numString CONTAINS %@)", String(UserDefaults.preferredPeripheralNum))
		predicates.append(isConnectedNodePredicate)
		// Combine all predicates
		let finalPredicate = predicates.isEmpty ? NSPredicate(value: true) : NSCompoundPredicate(type: .and, subpredicates: predicates)
		// Initialize the fetch request with the combined predicate
		_fetchRequest = FetchRequest<UserEntity>(
			sortDescriptors: [
				NSSortDescriptor(key: "lastMessage", ascending: false),
				NSSortDescriptor(key: "userNode.favorite", ascending: false),
				NSSortDescriptor(key: "pkiEncrypted", ascending: false),
				NSSortDescriptor(key: "userNode.lastHeard", ascending: false),
				NSSortDescriptor(key: "longName", ascending: true)
			],
			predicate: finalPredicate,
			animation: .spring
		)
	}
}
