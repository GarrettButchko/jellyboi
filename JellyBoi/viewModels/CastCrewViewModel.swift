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

    init(person: BaseItemPerson) {
        self.person = person
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

    func personImageURL(client: JellyfinClient?) -> URL? {
        guard let client else { return nil }
        if let id = detailedPerson?.id ?? person.id {
            let tag = detailedPerson?.imageTags?["Primary"] ?? person.primaryImageTag
            return client.url(with: Paths.getItemImage(
                itemID: id,
                imageType: "Primary",
                parameters: .init(maxWidth: 400, quality: 85, tag: tag)
            ))
        } else if let name = detailedPerson?.name ?? person.name {
            return client.url(with: Paths.getPersonImage(
                name: name,
                imageType: "Primary",
                parameters: .init(maxWidth: 400, quality: 85)
            ))
        }
        return nil
    }

    func loadData(client: JellyfinClient?, userID: String?) async {
        guard let client else { return }

        isLoading = true
        defer { isLoading = false }

        // 1. Fetch detailed person info
        do {
            if let id = person.id, !id.isEmpty {
                detailedPerson = try await client.send(Paths.getItem(itemID: id, userID: userID)).value
            } else if let name = person.name, !name.isEmpty {
                detailedPerson = try await client.send(Paths.getPerson(name: name, userID: userID)).value
            }
        } catch {
            if detailedPerson == nil, let name = person.name, !name.isEmpty {
                detailedPerson = try? await client.send(Paths.getPerson(name: name, userID: userID)).value
            }
        }

        let personID = detailedPerson?.id ?? person.id
        let personName = detailedPerson?.name ?? person.name

        // 2. Fetch movies & TV shows, and episodes concurrently
        async let fetchedMedia = fetchItems(
            itemTypes: [.movie, .series],
            personID: personID,
            personName: personName,
            client: client,
            userID: userID
        )
        async let fetchedEpisodes = fetchItems(
            itemTypes: [.episode],
            personID: personID,
            personName: personName,
            client: client,
            userID: userID
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
        var params = Paths.GetItemsParameters(
            userID: userID,
            isRecursive: true,
            sortOrder: [.descending],
            fields: [.primaryImageAspectRatio, .genres, .tags, .overview],
            includeItemTypes: itemTypes,
            sortBy: [.premiereDate, .productionYear, .sortName]
        )

        if let id = personID, !id.isEmpty {
            params.personIDs = [id]
        } else if let name = personName, !name.isEmpty {
            params.person = name
        }

        do {
            let response = try await client.send(Paths.getItems(parameters: params)).value
            var items = response.items ?? []

            // Fallback: If personIDs returned empty, try querying by person name
            if items.isEmpty, let name = personName, !name.isEmpty, params.personIDs != nil {
                var nameParams = params
                nameParams.personIDs = nil
                nameParams.person = name
                if let nameResponse = try? await client.send(Paths.getItems(parameters: nameParams)).value {
                    items = nameResponse.items ?? []
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
                let fallbackParams = Paths.GetItemsParameters(
                    userID: userID,
                    isRecursive: true,
                    sortOrder: [.descending],
                    fields: [.primaryImageAspectRatio, .genres, .tags],
                    includeItemTypes: itemTypes,
                    sortBy: [.premiereDate, .sortName],
                    person: name
                )
                if let fallbackRes = try? await client.send(Paths.getItems(parameters: fallbackParams)).value {
                    var seen = Set<String>()
                    return (fallbackRes.items ?? []).filter { item in
                        guard let id = item.id else { return false }
                        return seen.insert(id).inserted
                    }
                }
            }
            return []
        }
    }
}
