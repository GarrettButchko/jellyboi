//
//  JellyfinQueryHelper.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 10/29/26.
//

import Foundation
import Get
import JellyfinAPI

// MARK: - Paths.GetItemsParameters Presets & Builders

nonisolated extension Paths.GetItemsParameters {

    /// Default standard fields requested across JellyBoi for card and detail display.
    public static var standardFields: [ItemFields] {
        [.genres, .tags, .overview, .primaryImageAspectRatio]
    }

    /// Additional fields for TV shows (child counts).
    public static var tvShowFields: [ItemFields] {
        standardFields + [.childCount, .recursiveItemCount]
    }

    /// Additional fields for playback items and collections.
    public static var playbackItemFields: [ItemFields] {
        standardFields + [.mediaSources, .mediaStreams]
    }

    /// Standard base parameter set with recursive querying and user data enabled.
    public static func standard(
        userID: String?,
        includeItemTypes: [BaseItemKind]? = nil,
        sortBy: [ItemSortBy] = [.sortName],
        sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        fields: [ItemFields] = standardFields,
        limit: Int? = nil,
        isRecursive: Bool = true,
        enableUserData: Bool = true
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            limit: limit,
            isRecursive: isRecursive,
            sortOrder: sortOrder,
            fields: fields,
            includeItemTypes: includeItemTypes,
            sortBy: sortBy,
            enableUserData: enableUserData
        )
    }

    /// Preset for fetching movies sorted alphabetically by default.
    public static func movies(
        userID: String?,
        sortBy: [ItemSortBy] = [.sortName],
        sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        limit: Int? = nil
    ) -> Paths.GetItemsParameters {
        standard(
            userID: userID,
            includeItemTypes: [.movie],
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: limit
        )
    }

    /// Preset for fetching TV series with series-specific fields.
    public static func tvShows(
        userID: String?,
        sortBy: [ItemSortBy] = [.sortName],
        sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        limit: Int? = nil
    ) -> Paths.GetItemsParameters {
        standard(
            userID: userID,
            includeItemTypes: [.series],
            sortBy: sortBy,
            sortOrder: sortOrder,
            fields: tvShowFields,
            limit: limit
        )
    }

    /// Preset for fetching episodes sorted by series and episode name.
    public static func episodes(
        userID: String?,
        sortBy: [ItemSortBy] = [.seriesSortName, .sortName],
        sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        limit: Int? = nil
    ) -> Paths.GetItemsParameters {
        standard(
            userID: userID,
            includeItemTypes: [.episode],
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: limit
        )
    }

    /// Preset for fetching collections / box sets.
    public static func collections(
        userID: String?,
        sortBy: [ItemSortBy] = [.sortName],
        sortOrder: [JellyfinAPI.SortOrder] = [.ascending],
        limit: Int? = nil
    ) -> Paths.GetItemsParameters {
        standard(
            userID: userID,
            includeItemTypes: [.boxSet],
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: limit
        )
    }

    /// Preset for recommended / top rated items.
    public static func recommended(
        userID: String?,
        limit: Int = 20
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            fields: [],
            includeItemTypes: [.movie, .series],
            sortBy: [.communityRating],
            enableUserData: false,
            enableTotalRecordCount: false,
            enableImages: false
        )
    }

    /// Preset for recently added movies.
    public static func recentMovies(
        userID: String?,
        limit: Int = 20
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            fields: [],
            includeItemTypes: [.movie],
            sortBy: [.dateCreated],
            enableUserData: false,
            enableTotalRecordCount: false,
            enableImages: false
        )
    }

    /// Preset for recently added TV series.
    public static func recentShows(
        userID: String?,
        limit: Int = 20
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.descending],
            fields: [],
            includeItemTypes: [.series],
            sortBy: [.dateCreated],
            enableUserData: false,
            enableTotalRecordCount: false,
            enableImages: false
        )
    }

    /// Preset for collection / box set contents.
    public static func collectionItems(
        collectionID: String,
        userID: String?
    ) -> Paths.GetItemsParameters {
        var params = Paths.GetItemsParameters()
        params.userID = userID
        params.parentID = collectionID
        params.isRecursive = true
        params.isCollapseBoxSetItems = false
        params.fields = playbackItemFields
        params.enableUserData = userID != nil
        params.enableImages = true
        return params
    }

    /// Preset for items associated with a person / actor / director.
    public static func personItems(
        personID: String? = nil,
        personName: String? = nil,
        userID: String?,
        itemTypes: [BaseItemKind] = [.movie, .series]
    ) -> Paths.GetItemsParameters {
        var params = standard(
            userID: userID,
            includeItemTypes: itemTypes,
            sortBy: [.premiereDate, .productionYear, .sortName],
            sortOrder: [.descending]
        )
        if let personID, !personID.isEmpty {
            params.personIDs = [personID]
        } else if let personName, !personName.isEmpty {
            params.person = personName
        }
        return params
    }

    /// Preset configured for fast counting (limit 0, recursive).
    public static func countOnly(
        userID: String?,
        types: [BaseItemKind]? = nil,
        filters: [ItemFilter]? = nil
    ) -> Paths.GetItemsParameters {
        Paths.GetItemsParameters(
            userID: userID,
            limit: 0,
            isRecursive: true,
            includeItemTypes: types,
            filters: filters
        )
    }
}

// MARK: - Paths.GetNextUpParameters Presets

nonisolated extension Paths.GetNextUpParameters {
    public static func standard(userID: String? = nil, limit: Int = 20) -> Paths.GetNextUpParameters {
        Paths.GetNextUpParameters(userID: userID, limit: limit, enableResumable: true)
    }
}

// MARK: - Paths.GetSeasonsParameters Presets

nonisolated extension Paths.GetSeasonsParameters {
    public static func standard(
        userID: String?,
        fields: [ItemFields] = [.primaryImageAspectRatio]
    ) -> Paths.GetSeasonsParameters {
        Paths.GetSeasonsParameters(
            userID: userID,
            fields: fields,
            enableImages: true,
            enableUserData: false
        )
    }
}

// MARK: - Paths.GetEpisodesParameters Presets

nonisolated extension Paths.GetEpisodesParameters {
    /// Preset for fetching all episodes of a series across all seasons.
    public static func series(
        userID: String?,
        fields: [ItemFields] = [.primaryImageAspectRatio, .mediaSources, .mediaStreams]
    ) -> Paths.GetEpisodesParameters {
        Paths.GetEpisodesParameters(
            userID: userID,
            fields: fields,
            enableImages: true,
            enableUserData: true
        )
    }

    /// Preset for fetching episodes for a specific season.
    public static func season(
        _ seasonNumber: Int?,
        userID: String?,
        fields: [ItemFields] = [.primaryImageAspectRatio, .mediaSources, .mediaStreams]
    ) -> Paths.GetEpisodesParameters {
        Paths.GetEpisodesParameters(
            userID: userID,
            fields: fields,
            season: seasonNumber,
            enableImages: true,
            enableUserData: true
        )
    }
}

// MARK: - Paths.GetItemImageParameters Presets

nonisolated extension Paths.GetItemImageParameters {
    /// Standard card poster artwork (e.g., library grids, download cards).
    public static func poster(
        maxWidth: Int = 280,
        quality: Int = 65,
        tag: String? = nil
    ) -> Paths.GetItemImageParameters {
        Paths.GetItemImageParameters(maxWidth: maxWidth, quality: quality, tag: tag)
    }

    /// High-resolution detail page poster.
    public static func detailPoster(
        maxWidth: Int = 500,
        quality: Int = 80,
        tag: String? = nil
    ) -> Paths.GetItemImageParameters {
        Paths.GetItemImageParameters(maxWidth: maxWidth, quality: quality, tag: tag)
    }

    /// Episode or video wide thumbnail (16:9).
    public static func thumbnail(
        maxWidth: Int = 360,
        quality: Int = 65,
        tag: String? = nil
    ) -> Paths.GetItemImageParameters {
        Paths.GetItemImageParameters(maxWidth: maxWidth, quality: quality, tag: tag)
    }

    /// Backdrop / fanart image.
    public static func backdrop(
        maxWidth: Int = 800,
        quality: Int = 70,
        tag: String? = nil
    ) -> Paths.GetItemImageParameters {
        Paths.GetItemImageParameters(maxWidth: maxWidth, quality: quality, tag: tag)
    }

    /// Cast & crew / avatar circular image.
    public static func avatar(
        maxWidth: Int = 160,
        quality: Int = 70,
        tag: String? = nil
    ) -> Paths.GetItemImageParameters {
        Paths.GetItemImageParameters(maxWidth: maxWidth, quality: quality, tag: tag)
    }
}

// MARK: - Paths.GetPersonImageParameters Presets

nonisolated extension Paths.GetPersonImageParameters {
    public static func standard(
        maxWidth: Int = 280,
        quality: Int = 70,
        tag: String? = nil
    ) -> Paths.GetPersonImageParameters {
        Paths.GetPersonImageParameters(tag: tag, maxWidth: maxWidth, quality: quality)
    }
}

// MARK: - Paths.GetUserImageParameters Presets

nonisolated extension Paths.GetUserImageParameters {
    public static func standard(
        userID: String?,
        tag: String? = nil
    ) -> Paths.GetUserImageParameters {
        Paths.GetUserImageParameters(userID: userID, tag: tag)
    }
}

// MARK: - Paths.GetSimilarItemsParameters Presets

nonisolated extension Paths.GetSimilarItemsParameters {
    public static func standard(
        userID: String?,
        limit: Int = 12,
        fields: [ItemFields] = [.primaryImageAspectRatio]
    ) -> Paths.GetSimilarItemsParameters {
        Paths.GetSimilarItemsParameters(userID: userID, limit: limit, fields: fields)
    }
}

// MARK: - Paths.GetVideoStreamParameters Presets

nonisolated extension Paths.GetVideoStreamParameters {
    /// Static direct-play stream parameters.
    public static func directStatic(
        sessionID: String?,
        mediaSourceID: String?
    ) -> Paths.GetVideoStreamParameters {
        var params = Paths.GetVideoStreamParameters()
        params.isStatic = true
        params.playSessionID = sessionID
        params.mediaSourceID = mediaSourceID
        return params
    }
}

// MARK: - JellyfinClient Convenience API Extensions

extension JellyfinClient {

    // MARK: Items & Details

    /// Fetches items using the given parameters and unwraps the response's `items` array.
    public func fetchItems(parameters: Paths.GetItemsParameters) async throws -> [BaseItemDto] {
        let response = try await send(Paths.getItems(parameters: parameters)).value
        return response.items ?? []
    }

    /// Safely fetches items using the given parameters, returning an empty array on error.
    public func fetchItemsOrEmpty(parameters: Paths.GetItemsParameters) async -> [BaseItemDto] {
        (try? await fetchItems(parameters: parameters)) ?? []
    }

    /// Fetches a single item by ID.
    public func fetchItem(itemID: String, userID: String? = nil) async throws -> BaseItemDto {
        try await send(Paths.getItem(itemID: itemID, userID: userID)).value
    }

    /// Safely fetches a single item by ID, returning nil on error.
    public func fetchItemOrNil(itemID: String, userID: String? = nil) async -> BaseItemDto? {
        try? await fetchItem(itemID: itemID, userID: userID)
    }

    /// Fetches a person / actor by name.
    public func fetchPerson(name: String, userID: String? = nil) async throws -> BaseItemDto {
        try await send(Paths.getPerson(name: name, userID: userID)).value
    }

    /// Safely fetches a person / actor by name, returning nil on error.
    public func fetchPersonOrNil(name: String, userID: String? = nil) async -> BaseItemDto? {
        try? await fetchPerson(name: name, userID: userID)
    }

    /// Fetches similar items for a given item.
    public func fetchSimilarItems(itemID: String, userID: String?, limit: Int = 12) async -> [BaseItemDto] {
        let params = Paths.GetSimilarItemsParameters.standard(userID: userID, limit: limit)
        let response = try? await send(Paths.getSimilarItems(itemID: itemID, parameters: params)).value
        return response?.items ?? []
    }

    /// Fetches special features / extras for a given item.
    public func fetchSpecialFeatures(itemID: String, userID: String?) async -> [BaseItemDto] {
        (try? await send(Paths.getSpecialFeatures(itemID: itemID, userID: userID)).value) ?? []
    }

    // MARK: Seasons & Episodes

    /// Fetches seasons for a given series.
    public func fetchSeasons(seriesID: String, userID: String?) async throws -> [BaseItemDto] {
        let response = try await send(Paths.getSeasons(seriesID: seriesID, parameters: .standard(userID: userID))).value
        return response.items ?? []
    }

    /// Safely fetches seasons for a given series, returning an empty array on error.
    public func fetchSeasonsOrEmpty(seriesID: String, userID: String?) async -> [BaseItemDto] {
        (try? await fetchSeasons(seriesID: seriesID, userID: userID)) ?? []
    }

    /// Fetches episodes for a given series and optional season number.
    public func fetchEpisodes(seriesID: String, seasonNumber: Int? = nil, userID: String?) async throws -> [BaseItemDto] {
        let params: Paths.GetEpisodesParameters = seasonNumber == nil
            ? .series(userID: userID)
            : .season(seasonNumber, userID: userID)
        let response = try await send(Paths.getEpisodes(seriesID: seriesID, parameters: params)).value
        return response.items ?? []
    }

    /// Safely fetches episodes for a given series and optional season number, returning an empty array on error.
    public func fetchEpisodesOrEmpty(seriesID: String, seasonNumber: Int? = nil, userID: String?) async -> [BaseItemDto] {
        (try? await fetchEpisodes(seriesID: seriesID, seasonNumber: seasonNumber, userID: userID)) ?? []
    }

    // MARK: User & Item User Data

    /// Fetches current authenticated user.
    public func fetchCurrentUser() async throws -> UserDto {
        try await send(Paths.getCurrentUser).value
    }

    /// Marks an item as unplayed.
    @discardableResult
    public func markUnplayed(itemID: String, userID: String?) async throws -> UserItemDataDto {
        try await send(Paths.markUnplayedItem(itemID: itemID, userID: userID)).value
    }

    /// Updates favorite state for an item.
    @discardableResult
    public func setFavorite(_ isFavorite: Bool, itemID: String, userID: String?) async throws -> UserItemDataDto {
        let request = isFavorite
            ? Paths.markFavoriteItem(itemID: itemID, userID: userID)
            : Paths.unmarkFavoriteItem(itemID: itemID, userID: userID)
        return try await send(request).value
    }

    // MARK: Playback & Reporting

    /// Fetches playback info for an item.
    public func fetchPlaybackInfo(itemID: String, userID: String?) async throws -> PlaybackInfoResponse {
        try await send(Paths.getPlaybackInfo(itemID: itemID, userID: userID)).value
    }

    /// Reports playback start to server.
    public func reportPlaybackStart(_ state: PlaybackStateInfo) async throws {
        _ = try await send(Paths.reportPlaybackStart(state))
    }

    /// Reports playback progress to server.
    public func reportPlaybackProgress(_ state: PlaybackStateInfo) async throws {
        _ = try await send(Paths.reportPlaybackProgress(state))
    }

    /// Reports playback stopped to server.
    public func reportPlaybackStopped(_ stopInfo: PlaybackStopInfo) async throws {
        _ = try await send(Paths.reportPlaybackStopped(stopInfo))
    }

    // MARK: Image & Stream URLs

    /// Builds a URL for an item's image.
    public func itemImageURL(
        itemID: String,
        imageType: String = "Primary",
        parameters: Paths.GetItemImageParameters = .poster()
    ) -> URL? {
        url(with: Paths.getItemImage(itemID: itemID, imageType: imageType, parameters: parameters))
    }

    /// Builds a URL for a person's image by name.
    public func personImageURL(
        name: String,
        imageType: String = "Primary",
        parameters: Paths.GetPersonImageParameters = .standard()
    ) -> URL? {
        url(with: Paths.getPersonImage(name: name, imageType: imageType, parameters: parameters))
    }

    /// Builds a URL for a user's avatar.
    public func userImageURL(
        userID: String,
        tag: String? = nil
    ) -> URL? {
        url(with: Paths.getUserImage(parameters: .standard(userID: userID, tag: tag)))
    }

    /// Builds a direct static video stream URL.
    ///
    /// Deliberately unauthenticated: the playback pipeline applies the access token in one place
    /// (`PlaybackURL.applyingAuthentication`) so every stream URL, direct or transcoded, is
    /// authenticated the same way. Downloads, which hand raw URLs to a downloader, still pass
    /// `queryAPIKey: true` at their own call site.
    public func directVideoStreamURL(
        itemID: String,
        sessionID: String?,
        mediaSourceID: String?
    ) -> URL? {
        url(
            with: Paths.getVideoStream(
                itemID: itemID,
                parameters: .directStatic(sessionID: sessionID, mediaSourceID: mediaSourceID)
            )
        )
    }
}
