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

    func castSection(_ actors: [BaseItemPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.mainOpp)
                .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 16) {
                    ForEach(actors.prefix(20), id: \.id) { person in
                        CastCircle(
                            person: person,
                            imageURL: castImageURL(for: person)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    func castImageURL(for person: BaseItemPerson) -> URL? {
        guard let client = serverViewModel.client,
              let id = person.id else { return nil }
        return client.url(with: Paths.getItemImage(
            itemID: id,
            imageType: "Primary",
            parameters: .init(maxWidth: 200, quality: 80)
        ))
    }
}

// MARK: - CastCircle

struct CastCircle: View {
    let person: BaseItemPerson
    let imageURL: URL?

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
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
                            Color.sub
                        }
                    }
                    .frame(width: 70, height: 70)
                    .clipShape(Circle())
                }
            }

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
                }
            }
        }
    }
}
