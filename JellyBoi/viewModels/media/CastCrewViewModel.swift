//
//  CastCrewViewModel.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 9/22/26.
//

import Foundation
import Observation
import Get
import JellyfinAPI

@Observable
@MainActor
class CastCrewViewModel {

    let person: BaseItemPerson

    private(set) var detailedPerson: BaseItemDto?
    private(set) var mediaItems: [BaseItemDto] = []
    private(set) var episodeItems: [BaseItemDto] = []
    private(set) var isLoading: Bool = true

    private weak var serverViewModel: ServerViewModel?

    init(person: BaseItemPerson, serverViewModel: ServerViewModel? = nil) {
        self.person = person
        self.serverViewModel = serverViewModel
    }

    var personName: String {
        detailedPerson?.name ?? person.name ?? "Cast & Crew"
    }

    var personRole: String? {
        if let role = person.role, !role.isEmpty {
            return role
        }
        return person.type?.rawValue
    }

    var overview: String? {
        detailedPerson?.overview
    }

    var birthDateFormatted: String? {
        guard let date = detailedPerson?.premiereDate else {
            if let year = detailedPerson?.productionYear {
                return "\(year)"
            }
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: date)

        if let endDate = detailedPerson?.endDate {
            let endYear = Calendar.current.component(.year, from: endDate)
            let birthYear = Calendar.current.component(.year, from: date)
            let age = endYear - birthYear
            if age > 0 {
                return "\(dateString) (died at \(age))"
            }
            return dateString
        } else {
            let calendar = Calendar.current
            let ageComponents = calendar.dateComponents([.year], from: date, to: Date())
            if let age = ageComponents.year, age > 0 {
                return "\(dateString) (\(age) years old)"
            }
            return dateString
        }
    }

    var birthPlaceFormatted: String? {
        if let locations = detailedPerson?.productionLocations, !locations.isEmpty {
            return locations.joined(separator: ", ")
        }
        return nil
    }

    func mapsURL(for location: String) -> URL? {
        guard let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }

    func personImageURL(client: JellyfinClient? = nil) -> URL? {
        #if DEBUG
        if DebugSettings.shared.hidePersonImage { return nil }
        #endif
        let activeClient = client ?? serverViewModel?.client ?? ServerViewModel.shared.client
        guard let activeClient else { return nil }
        if let id = detailedPerson?.id ?? person.id {
            let tag = detailedPerson?.imageTags?["Primary"] ?? person.primaryImageTag
            return activeClient.itemImageURL(
                itemID: id,
                parameters: .poster(maxWidth: 400, quality: 85, tag: tag)
            )
        } else if let name = detailedPerson?.name ?? person.name {
            return activeClient.personImageURL(
                name: name,
                parameters: .standard(maxWidth: 400, quality: 85)
            )
        }
        return nil
    }

    func loadData(client: JellyfinClient? = nil, userID: String? = nil) async {
        let svm = serverViewModel ?? ServerViewModel.shared
        let activeClient = client ?? svm.client
        let activeUserID = userID ?? svm.currentUser?.id
        guard let activeClient else { return }

        isLoading = true
        defer { isLoading = false }

        // 1. Fetch detailed person info
        do {
            if let id = person.id, !id.isEmpty {
                detailedPerson = try await activeClient.fetchItem(itemID: id, userID: activeUserID)
            } else if let name = person.name, !name.isEmpty {
                detailedPerson = try await activeClient.fetchPerson(name: name, userID: activeUserID)
            }
        } catch {
            if detailedPerson == nil, let name = person.name, !name.isEmpty {
                detailedPerson = await activeClient.fetchPersonOrNil(name: name, userID: activeUserID)
            }
        }

        let personID = detailedPerson?.id ?? person.id
        let personName = detailedPerson?.name ?? person.name

        // 2. Fetch movies & TV shows, and episodes concurrently
        async let fetchedMedia = fetchItems(
            itemTypes: [.movie, .series],
            personID: personID,
            personName: personName,
            client: activeClient,
            userID: activeUserID
        )
        async let fetchedEpisodes = fetchItems(
            itemTypes: [.episode],
            personID: personID,
            personName: personName,
            client: activeClient,
            userID: activeUserID
        )

        let (items, episodes) = await (fetchedMedia, fetchedEpisodes)
        mediaItems = items
        episodeItems = episodes
    }

    private func fetchItems(
        itemTypes: [BaseItemKind],
        personID: String?,
        personName: String?,
        client: JellyfinClient,
        userID: String?
    ) async -> [BaseItemDto] {
        let params = Paths.GetItemsParameters.personItems(
            personID: personID,
            personName: personName,
            userID: userID,
            itemTypes: itemTypes
        )

        do {
            var items = try await client.fetchItems(parameters: params)

            // Fallback: If personIDs returned empty, try querying by person name
            if items.isEmpty, let name = personName, !name.isEmpty, params.personIDs != nil {
                var nameParams = params
                nameParams.personIDs = nil
                nameParams.person = name
                let nameItems = await client.fetchItemsOrEmpty(parameters: nameParams)
                if !nameItems.isEmpty {
                    items = nameItems
                }
            }

            var seen = Set<String>()
            return items.filter { item in
                guard let id = item.id else { return false }
                return seen.insert(id).inserted
            }
        } catch {
            // Fallback by name if error
            if let name = personName, !name.isEmpty {
                let fallbackParams = Paths.GetItemsParameters.personItems(
                    personName: name,
                    userID: userID,
                    itemTypes: itemTypes
                )
                let fallbackItems = await client.fetchItemsOrEmpty(parameters: fallbackParams)
                var seen = Set<String>()
                return fallbackItems.filter { item in
                    guard let id = item.id else { return false }
                    return seen.insert(id).inserted
                }
            }
            return []
        }
    }
}
