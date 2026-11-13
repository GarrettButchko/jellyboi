//
//  MediaDetailCastSection.swift
//  JellyBoi
//
//  Created by Garrett Butchko on 8/23/26.
//

import SwiftUI
import BaseColors
import SDWebImageSwiftUI
import JellyfinAPI

// MARK: - Skeleton Default Items

private let defaultCastPerson = BaseItemPerson(
    id: "default-cast-person",
    name: "Cast Member",
    role: "Character Role",
    type: .actor
)

private let defaultCastPeople: [BaseItemPerson] = (0..<8).map { index in
    BaseItemPerson(
        id: "default-cast-\(index)",
        name: defaultCastPerson.name,
        role: defaultCastPerson.role,
        type: defaultCastPerson.type
    )
}

extension MediaDetailView {

    /// The cast placeholder is shown while the screen is still loading and the cast list is still
    /// empty — `primaryDetailsStatus` alone flips to `.loaded` as soon as the item has an overview,
    /// which used to hide the whole section (no skeleton, no content) until the cast arrived.
    private var isCastPlaceholderVisible: Bool {
        detailVM.cast.isEmpty
            && displayItem.type != .boxSet
            && (detailVM.isLoading || detailVM.primaryDetailsStatus.isLoading)
    }

    @ViewBuilder
    var castSection: some View {
        if !detailVM.isCastHidden, !detailVM.cast.isEmpty || isCastPlaceholderVisible {
            SectionRow(title: "Cast & Crew") {
                if detailVM.cast.isEmpty {
                    castSkeleton
                } else {
                    castContent(detailVM.cast)
                }
            }
            .skeleton(when: isCastPlaceholderVisible, value: detailVM.cast.count)
        }
    }
    
    private var castSkeleton: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(defaultCastPeople, id: \.id) { person in
                    CastCircle(person: person, imageURL: nil)
                        .frame(width: 74, alignment: .top)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }

    private func castContent(_ people: [BaseItemPerson]) -> some View {
        var seen = Set<String>()
        let uniquePeople = people.filter { person in
            let key = person.id ?? person.name ?? ""
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
        
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(uniquePeople, id: \.id) { person in
                    Button {
                        selectedPerson = person
                    } label: {
                        CastCircle(
                            person: person,
                            imageURL: person.avatarURL(client: serverViewModel.client)
                        )
                        .frame(width: 74, alignment: .top)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
    }
}

// MARK: - CastCircle

struct CastCircle: View {
    let person: BaseItemPerson
    let imageURL: URL?
    var namespace: Namespace.ID? = nil

    @Environment(\.redactionReasons) private var redactionReasons

    private var isRedacted: Bool {
        redactionReasons.contains(.placeholder)
    }

    var body: some View {
        VStack(spacing: 7) {
            avatarView

            VStack(spacing: 2) {
                Text(person.name ?? "")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.mainOpp)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 74)

                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 74)
                } else if let type = person.type?.rawValue, !type.isEmpty {
                    Text(type)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.mainOpp.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 74)
                }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View { 
        if isRedacted {
            Circle()
                .fill(Color.mainOpp.opacity(0.12))
                .frame(width: 72, height: 72)
        } else if let imageURL {
            WebImage(url: imageURL)
                .resizable()
                .indicator(.activity)
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.mainOpp.opacity(0.08))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.mainOpp.opacity(0.3))
                }
        }
    }
}
