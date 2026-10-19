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

extension MediaDetailView {

    @ViewBuilder
    var castSection: some View {
        let actors = (displayItem.people ?? []).filter { $0.type == .actor }
        if !detailVM.isCastHidden && !actors.isEmpty {
            castContent(actors)
        }
    }

    private func castContent(_ people: [BaseItemPerson]) -> some View {
        var seen = Set<String>()
        let uniquePeople = people.filter { person in
            let key = person.id ?? person.name ?? ""
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(uniquePeople, id: \.id) { person in
                        Button {
                            selectedPerson = person
                        } label: {
                            CastCircle(
                                person: person,
                                imageURL: castImageURL(for: person)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    func castImageURL(for person: BaseItemPerson) -> URL? {
        detailVM.castImageURL(for: person, client: serverViewModel.client)
    }
}

// MARK: - CastCircle

struct CastCircle: View {
    let person: BaseItemPerson
    let imageURL: URL?
    var namespace: Namespace.ID? = nil

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
        let circleContent = ZStack {
            Circle()
                .fill(Color.sub)
                .frame(width: 70, height: 70)

            if let url = imageURL {
                WebImage(
                    url: url,
                    transaction: Transaction(animation: .easeInOut(duration: 0.3))
                ) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.fade(duration: 0.3))
                    } else {
                        placeholderIcon
                    }
                }
                .frame(width: 70, height: 70)
                .clipShape(Circle())
            } else {
                placeholderIcon
            }
        }
        .frame(width: 70, height: 70)

        if let namespace {
            circleContent
                .matchedTransitionSource(
                    id: person.id ?? person.name ?? "",
                    in: namespace
                )
        } else {
            circleContent
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 40))
            .foregroundStyle(Color.subFour)
    }
}
